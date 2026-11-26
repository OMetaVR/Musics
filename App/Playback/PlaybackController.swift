import Foundation
import MusicsCore
import Observation

/// Owns the queue and drives the player: gapless preloading, autoplay radio, stats, sleep timer,
/// undo for queue edits, restoring the session, and telling the server what's playing.
@MainActor
@Observable
final class PlaybackController {
    enum SleepTimer: Equatable {
        case at(Date)
        case endOfTrack
    }

    struct SavedState: Codable {
        var queue: PlaybackQueue
        var position: Double
    }

    private(set) var queue = PlaybackQueue()
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var sleepTimer: SleepTimer?
    private(set) var canUndo = false
    private(set) var isFetchingAutoplay = false

    @ObservationIgnored let engine = PlayerEngine()
    @ObservationIgnored let center = NowPlayingCenter()
    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored private var undoStack: [PlaybackQueue] = []
    @ObservationIgnored private var listened: Double = 0
    @ObservationIgnored private var lastTick: Double = 0
    @ObservationIgnored private var lastReport = Date.distantPast
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var pauseAfterAdvance = false
    @ObservationIgnored private var userVolume: Float = 1
    @ObservationIgnored private var restoredServer: UUID?

    init() {
        center.controller = self
        center.configureSession()
        center.configureCommands()
        engine.onTick = { [weak self] t in self?.tick(t) }
        engine.onEnded = { [weak self] id in self?.itemEnded(id) }
        engine.onCurrentChanged = { [weak self] id in self?.engineMoved(to: id) }
        engine.onFailed = { [weak self] id, msg in self?.itemFailed(id, msg) }
        engine.onPlayingChanged = { [weak self] playing in self?.playingChanged(playing) }
        engine.onBufferingChanged = { [weak self] b in self?.isBuffering = b }
    }

    // MARK: Lookups

    private var index: LibraryIndex { app?.library.index ?? .empty }

    var currentTrack: Track? { queue.current.flatMap { index.tracks[$0.trackID] } }
    func track(_ item: QueueItem) -> Track? { index.tracks[item.trackID] }
    var hasQueue: Bool { queue.current != nil }

    func upcomingTrackIDs(limit: Int) -> [TrackID] { queue.upcoming.prefix(limit).map(\.trackID) }

    /// Groups songs by artist for spread shuffle. A plain closure over the current index, so it can be
    /// passed to the (nonisolated) queue methods.
    private var artistKey: (TrackID) -> String {
        let tracks = index.tracks
        return { TextNormalizer.key(tracks[$0]?.primaryArtist ?? $0) }
    }

    // MARK: Starting playback

    func play(_ tracks: [Track], startAt: Int? = nil, context: PlaybackContext, shuffle: Bool = false) {
        guard !tracks.isEmpty else { return }
        accountOutgoing(skipped: true)
        pushUndo()
        var q = queue
        q.play(tracks.map(\.id), startAt: startAt, context: context, shuffle: shuffle, groupKey: artistKey)
        queue = q
        app?.stats.update { $0.recordContext(context) }
        loadCurrent(play: true)
    }

    /// Starts a radio station from a seed: the seed song first (for song radio), then suggestions.
    func startRadio(_ seed: RadioSeed, title: String) async {
        guard let app, let session = app.session, let base = session.baseURL else {
            app?.toast("Radio needs a connection to the server.")
            return
        }
        do {
            let ids = try await session.provider.radio(base: base, seed: seed, count: 50, exclude: [])
            var tracks = index.tracks(ids)
            if case let .track(id) = seed, let seedTrack = index.tracks[id] {
                tracks.removeAll { $0.id == id }
                tracks.insert(seedTrack, at: 0)
            }
            guard !tracks.isEmpty else {
                app.toast("Not enough similar songs yet. The server may still be analysing the library.")
                return
            }
            play(tracks, startAt: 0, context: PlaybackContext(kind: .radio, id: nil, title: title))
        } catch {
            app.toast((error as? LocalizedError)?.errorDescription ?? "Couldn't start radio.")
            session.reportFailure()
        }
    }

    // MARK: Transport

    func play() {
        guard queue.current != nil else { return }
        if engine.currentItemID != queue.current?.id {
            loadCurrent(play: true, at: position)
            return
        }
        center.activate()
        engine.volume = userVolume
        engine.play()
        report(force: true)
    }

    func pause() {
        engine.pause()
        save()
        report(force: true)
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func next() {
        guard queue.current != nil else { return }
        accountOutgoing(skipped: true)
        var q = queue
        if q.advance(auto: false, groupKey: artistKey) != nil {
            queue = q
            loadCurrent(play: true)
        } else if wantsAutoplay {
            Task { await fetchAutoplay(thenAdvance: true) }
        }
    }

    func previous() {
        if position > 3 || queue.history.isEmpty {
            seek(to: 0)
            return
        }
        accountOutgoing(skipped: true)
        var q = queue
        if q.previous() != nil {
            queue = q
            loadCurrent(play: true)
        }
    }

    func seek(to seconds: Double) {
        let target = min(max(0, seconds), max(duration - 0.5, 0))
        position = target
        lastTick = target
        engine.seek(to: target) { [weak self] in
            guard let self else { return }
            self.center.updateProgress(position: self.engine.currentTime, duration: self.duration, playing: self.isPlaying)
        }
        report(force: true)
    }

    func setRepeat(_ mode: RepeatMode) {
        queue.repeatMode = mode
        syncNext()
        save()
        refreshNowPlaying()
    }

    func cycleRepeat() { setRepeat(queue.repeatMode.next) }

    func setShuffle(_ on: Bool) {
        var q = queue
        q.setShuffle(on, groupKey: artistKey)
        queue = q
        syncNext()
        save()
        refreshNowPlaying()
    }

    func toggleLikeCurrent() {
        guard let t = currentTrack else { return }
        app?.toggleLike(t)
    }

    // MARK: Queue editing (undoable)

    func playNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        let wasEmpty = queue.current == nil
        edit { $0.playNext(tracks.map(\.id)) }
        if wasEmpty { loadCurrent(play: true) }
        app?.toast(tracks.count == 1 ? "“\(tracks[0].title)” plays next" : "\(tracks.count) songs play next", undo: wasEmpty ? nil : { [weak self] in self?.undo() })
    }

    func addToQueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        let wasEmpty = queue.current == nil
        edit { $0.addToQueue(tracks.map(\.id)) }
        if wasEmpty { loadCurrent(play: true) }
        app?.toast(tracks.count == 1 ? "Added “\(tracks[0].title)” to the queue" : "Added \(tracks.count) songs to the queue",
                   undo: wasEmpty ? nil : { [weak self] in self?.undo() })
    }

    func remove(_ item: QueueItem) {
        let title = track(item)?.title ?? "Song"
        edit { $0.remove(item.id) }
        app?.toast("Removed “\(title)”", undo: { [weak self] in self?.undo() })
    }

    func move(in section: PlaybackQueue.Section, from: IndexSet, to: Int) {
        edit { $0.move(in: section, from: from, to: to) }
    }

    func clearUpcoming() {
        edit { $0.clearUpcoming() }
        app?.toast("Cleared the queue", undo: { [weak self] in self?.undo() })
    }

    func clearAutoplay() { edit { $0.clearAutoplay() } }

    func jump(to item: QueueItem) {
        accountOutgoing(skipped: true)
        pushUndo()
        var q = queue
        guard q.jump(to: item.id) != nil else { return }
        queue = q
        loadCurrent(play: true)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        canUndo = !undoStack.isEmpty
        let changedCurrent = previous.current?.id != queue.current?.id
        queue = previous
        if changedCurrent { loadCurrent(play: isPlaying) } else { syncNext() }
        save()
    }

    private func edit(_ change: (inout PlaybackQueue) -> Void) {
        pushUndo()
        var q = queue
        change(&q)
        queue = q
        syncNext()
        save()
        maybeAutoplay()
        prefetchUpcoming()
    }

    private func pushUndo() {
        undoStack.append(queue)
        if undoStack.count > 30 { undoStack.removeFirst() }
        canUndo = true
    }

    // MARK: Sleep timer

    func setSleepTimer(minutes: Int?) {
        engine.volume = userVolume
        pauseAfterAdvance = false
        if let minutes {
            sleepTimer = .at(Date().addingTimeInterval(Double(minutes) * 60))
            app?.toast("Music stops in \(minutes) minutes")
        } else {
            sleepTimer = nil
        }
    }

    func sleepAtEndOfTrack() {
        sleepTimer = .endOfTrack
        app?.toast("Music stops after this song")
    }

    var sleepRemaining: TimeInterval? {
        if case let .at(date) = sleepTimer { return max(0, date.timeIntervalSinceNow) }
        return nil
    }

    // MARK: Loading

    /// Loads the queue's current item into the player (and the next one for gapless playback).
    private func loadCurrent(play shouldPlay: Bool, at start: Double = 0) {
        guard let item = queue.current, let track = track(item) else {
            engine.stop()
            isPlaying = false
            refreshNowPlaying()
            return
        }
        guard let source = source(for: item) else {
            // Offline and not downloaded: skip ahead to something that's available, or stop.
            if let playable = queue.upcoming.first(where: { app?.downloads.isAvailableOffline($0.trackID) == true }) {
                app?.toast("“\(track.title)” isn't available offline. Skipping.")
                var q = queue
                q.jump(to: playable.id)
                queue = q
                loadCurrent(play: shouldPlay)
            } else {
                engine.stop()
                app?.toast("“\(track.title)” isn't available offline.")
                refreshNowPlaying()
            }
            return
        }
        listened = 0
        lastTick = start
        position = start
        duration = track.duration
        if shouldPlay {
            center.activate()
            engine.volume = userVolume
        }
        engine.load(source, next: nextSource(), at: start, play: shouldPlay)
        refreshNowPlaying()
        report(force: true)
        save()
        maybeAutoplay()
        prefetchUpcoming()
    }

    private func source(for item: QueueItem) -> PlayerEngine.Source? {
        guard let app, let track = track(item) else { return nil }
        if let file = app.downloads.localFile(for: track.id) {
            return PlayerEngine.Source(itemID: item.id, url: file, headers: [:])
        }
        guard let session = app.session, let base = session.baseURL else { return nil }
        let url = session.provider.streamURL(base: base, track: track, quality: session.quality(app.settings))
        return PlayerEngine.Source(itemID: item.id, url: url, headers: session.provider.mediaHeaders)
    }

    private func nextSource() -> PlayerEngine.Source? {
        queue.nextItemOnEnd.flatMap(source(for:))
    }

    /// Re-points the preloaded next item after any queue change.
    private func syncNext() {
        guard engine.currentItemID != nil, engine.currentItemID == queue.current?.id else { return }
        engine.setNext(nextSource())
    }

    func localFileBecameAvailable(_ id: TrackID) {
        if queue.nextItemOnEnd?.trackID == id { syncNext() }
    }

    /// The server came back or moved to another address.
    func connectionChanged() {
        if let src = engine.currentSource, !src.isLocal, let item = queue.current, let fresh = source(for: item), fresh.url != src.url {
            // Stream from the new address, continuing where we were.
            loadCurrent(play: isPlaying, at: engine.currentTime)
        } else {
            syncNext()
        }
        prefetchUpcoming()
    }

    // MARK: Engine events

    private func itemEnded(_ itemID: UUID) {
        guard itemID == queue.current?.id else { return }
        accountOutgoing(skipped: false)
        if sleepTimer == .endOfTrack {
            sleepTimer = nil
            pauseAfterAdvance = true
        }
        var q = queue
        guard let next = q.advance(auto: true, groupKey: artistKey) else {
            // End of the queue.
            if wantsAutoplay {
                Task { await fetchAutoplay(thenAdvance: true) }
            } else {
                engine.pause()
                engine.seek(to: 0)
                position = 0
                report(force: true)
            }
            return
        }
        queue = q
        listened = 0
        lastTick = 0
        position = 0
        if let t = currentTrack { duration = t.duration }
        if engine.queuedNextItemID == next.id || (engine.currentItemID == next.id && next.id != itemID) {
            // Gapless: AVQueuePlayer moves (or has moved) to the preloaded item by itself.
            if pauseAfterAdvance {
                pauseAfterAdvance = false
                engine.pause()
            }
            // If the player already moved before this notification arrived, its currentItem change was
            // ignored (the queue hadn't advanced yet), so preload the following song now. No-op otherwise.
            syncNext()
        } else {
            loadCurrent(play: !pauseAfterAdvance)
            pauseAfterAdvance = false
        }
        refreshNowPlaying()
        save()
        report(force: true)
        maybeAutoplay()
        prefetchUpcoming()
    }

    private func engineMoved(to itemID: UUID?) {
        guard let itemID, itemID == queue.current?.id else { return }
        if let d = engine.duration { duration = d }
        consecutiveFailures = 0
        syncNext()
    }

    private func itemFailed(_ itemID: UUID, _ message: String) {
        guard itemID == queue.current?.id else {
            // The preloaded item failed: drop it; it will be retried when it becomes current.
            if itemID == engine.queuedNextItemID { engine.setNext(nil) }
            return
        }
        consecutiveFailures += 1
        app?.session?.reportFailure()
        let title = currentTrack?.title ?? "This song"
        if consecutiveFailures <= 3, !queue.upcoming.isEmpty {
            app?.toast("Couldn't play “\(title)”. Skipping.")
            var q = queue
            q.advance(auto: false, groupKey: artistKey)
            queue = q
            loadCurrent(play: true)
        } else {
            engine.pause()
            app?.toast("Couldn't play “\(title)”: \(message)")
        }
    }

    private func playingChanged(_ playing: Bool) {
        guard playing != isPlaying else { return }
        isPlaying = playing
        center.updateProgress(position: engine.currentTime, duration: duration, playing: playing)
    }

    private func tick(_ t: Double) {
        position = t
        if let d = engine.duration, abs(d - duration) > 1 { duration = d }
        if isPlaying {
            let delta = t - lastTick
            if delta > 0, delta < 1.5 { listened += delta }
        }
        lastTick = t
        if isPlaying, case let .at(date) = sleepTimer {
            let remaining = date.timeIntervalSinceNow
            if remaining <= 0 {
                sleepTimer = nil
                pause()
                engine.volume = userVolume
            } else if remaining < 12 {
                engine.volume = userVolume * Float(remaining / 12)  // fade out
            }
        }
        if isPlaying, Date().timeIntervalSince(lastReport) > 15 { report(force: false) }
        if Date().timeIntervalSince(lastSave) > 10 { save() }
    }

    func interruptionBegan() { isPlaying = false }

    func interruptionEnded(shouldResume: Bool) {
        if shouldResume { play() }
    }

    // MARK: Autoplay / prefetch

    private var wantsAutoplay: Bool {
        guard let app, app.settings.autoplay, app.session?.capabilities.contains(.radio) == true else { return false }
        return queue.wantsAutoplay
    }

    private func maybeAutoplay() {
        guard wantsAutoplay, !isFetchingAutoplay else { return }
        Task { await fetchAutoplay(thenAdvance: false) }
    }

    private func fetchAutoplay(thenAdvance: Bool) async {
        guard let app, let session = app.session, let base = session.baseURL, !isFetchingAutoplay,
              let seed = queue.current?.trackID ?? queue.history.last?.trackID else { return }
        isFetchingAutoplay = true
        defer { isFetchingAutoplay = false }
        // Seed from the recent context so suggestions follow the mood, not just the last song.
        let exclude = Array(queue.knownTrackIDs)
        guard let ids = try? await session.provider.radio(base: base, seed: .track(seed), count: 25, exclude: exclude) else { return }
        var q = queue
        q.appendAutoplay(ids.filter { index.tracks[$0] != nil })
        queue = q
        if thenAdvance {
            var q2 = queue
            if q2.advance(auto: false, groupKey: artistKey) != nil {
                queue = q2
                loadCurrent(play: true)
            }
        } else {
            syncNext()
        }
        save()
    }

    private func prefetchUpcoming() {
        guard let app, let session = app.session, session.isOnline else { return }
        let count = max(0, app.settings.prefetchCount)
        let upcoming = index.tracks(queue.upcoming.prefix(count).map(\.trackID))
        app.downloads.prefetch(upcoming)
        // Warm server-side transcodes for the very next song if it will be streamed.
        if let next = upcoming.first, !app.downloads.isAvailableOffline(next.id), let base = session.baseURL {
            let provider = session.provider
            let quality = session.quality(app.settings)
            Task.detached(priority: .utility) { await provider.prepare(base: base, track: next, quality: quality) }
        }
    }

    // MARK: Stats, reporting, persistence

    /// Called when the current song stops being current: counts it as a play, a skip, or neither.
    private func accountOutgoing(skipped: Bool) {
        guard let app, let track = currentTrack else { return }
        let heard = listened
        listened = 0
        if ListeningStats.countsAsPlay(listened: heard, duration: track.duration) || (!skipped && heard > 5) {
            app.stats.update { $0.recordPlay(track.id) }
            if app.settings.scrobble, let session = app.session, session.capabilities.contains(.scrobble), let base = session.baseURL {
                let provider = session.provider
                let id = track.id
                Task.detached(priority: .utility) { await provider.scrobble(base: base, trackID: id, at: Date()) }
            }
        } else if skipped, heard < 30, heard > 0.5 {
            app.stats.update { $0.recordSkip(track.id) }
        }
    }

    private func report(force: Bool) {
        guard let app, app.settings.reportNowPlaying, let session = app.session,
              session.capabilities.contains(.nowPlaying), let base = session.baseURL else { return }
        if !force, Date().timeIntervalSince(lastReport) < 15 { return }
        lastReport = Date()
        let r = NowPlayingReport(clientID: app.settings.clientID, trackID: queue.current?.trackID, playing: isPlaying || engine.isPlaying,
                                 position: engine.currentTime, duration: duration)
        let provider = session.provider
        Task.detached(priority: .utility) { await provider.reportNowPlaying(base: base, r) }
    }

    func refreshNowPlaying() {
        guard let app else { return }
        let t = currentTrack
        center.update(track: t, artworkURL: t.flatMap { app.artworkURL(track: $0, size: 640) }, position: engine.currentTime,
                      duration: duration, playing: engine.isPlaying, liked: t.map { app.library.isLiked($0.id) } ?? false,
                      repeatMode: queue.repeatMode, shuffle: queue.shuffle)
    }

    private func stateURL(_ id: UUID) -> URL { Paths.server(id).appendingPathComponent("playback.json") }

    func save() {
        guard let id = app?.session?.profile.id, restoredServer == id else { return }
        lastSave = Date()
        let state = SavedState(queue: queue, position: engine.currentItemID == nil ? position : engine.currentTime)
        let url = stateURL(id)
        Task.detached(priority: .utility) { Store.save(state, to: url) }
    }

    /// Brings back the last queue and position, paused (nothing plays until the user presses play).
    func restore(serverID id: UUID) {
        restoredServer = id
        guard let state = Store.load(SavedState.self, from: stateURL(id)) else {
            queue = PlaybackQueue()
            return
        }
        var q = state.queue
        let tracks = index.tracks
        if !tracks.isEmpty { q.prune { tracks[$0] != nil } }
        queue = q
        position = state.position
        duration = currentTrack?.duration ?? 0
        undoStack = []
        canUndo = false
        if queue.current != nil, source(for: queue.current!) != nil {
            loadCurrent(play: false, at: state.position)
        } else {
            refreshNowPlaying()
        }
    }

    /// Switching servers: stop and forget the old queue (it's saved per server).
    func detach() {
        save()
        engine.stop()
        isPlaying = false
        queue = PlaybackQueue()
        position = 0
        duration = 0
        restoredServer = nil
        undoStack = []
        canUndo = false
        refreshNowPlaying()
    }
}
