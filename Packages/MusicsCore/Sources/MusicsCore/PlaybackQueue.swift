import Foundation

/// Where a run of songs came from; shown as "Playing from …" and used for "Jump back in".
public struct PlaybackContext: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case album, playlist, artist, genre, liked, songs, search, radio, adventure, downloads, queue
    }

    public var kind: Kind
    public var id: String?
    public var title: String

    public init(kind: Kind, id: String? = nil, title: String) {
        self.kind = kind
        self.id = id
        self.title = title
    }
}

public struct QueueItem: Codable, Hashable, Identifiable, Sendable {
    public enum Origin: String, Codable, Sendable {
        /// Part of the album/playlist/list the user started.
        case context
        /// Added with Play Next / Add to Queue.
        case user
        /// Suggested by radio once the context ran out.
        case autoplay
    }

    public let id: UUID
    public let trackID: TrackID
    public var origin: Origin

    public init(trackID: TrackID, origin: Origin, id: UUID = UUID()) {
        self.id = id
        self.trackID = trackID
        self.origin = origin
    }
}

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one

    public var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// The play order, as a value type so every edit can be undone by keeping the previous copy.
///
/// Order of play: `current`, then `upNext` (user queue), then `context` (rest of the album or
/// playlist, shuffled or not), then `autoplay` (radio). `history` holds what already played.
public struct PlaybackQueue: Codable, Sendable, Equatable {
    public enum Section: String, Codable, Sendable { case upNext, context, autoplay }

    public private(set) var history: [QueueItem] = []
    public private(set) var current: QueueItem?
    public private(set) var upNext: [QueueItem] = []
    public private(set) var context: [QueueItem] = []
    public private(set) var autoplay: [QueueItem] = []
    /// The whole context in its original order, for un-shuffling and repeat-all.
    public private(set) var contextOrder: [QueueItem] = []
    public private(set) var contextInfo: PlaybackContext?
    public private(set) var shuffle = false
    public var repeatMode: RepeatMode = .off

    public static let historyLimit = 200

    public init() {}

    public var isEmpty: Bool { current == nil }

    /// Everything that will play after the current item, in order.
    public var upcoming: [QueueItem] { upNext + context + autoplay }

    /// The item that plays when the current one ends on its own, for gapless preloading.
    /// nil when it can't be known in advance (repeat-all wrapping into a fresh shuffle).
    public var nextItemOnEnd: QueueItem? {
        if repeatMode == .one { return current }
        if let n = upNext.first ?? context.first { return n }
        if repeatMode == .all, !contextOrder.isEmpty { return shuffle ? nil : contextOrder.first }
        return autoplay.first
    }

    /// True when the queue is about to run dry and radio should top it up.
    public var wantsAutoplay: Bool {
        repeatMode == .off && upNext.isEmpty && context.count < 2 && autoplay.count < 5
    }

    /// Track ids already queued or played, so radio doesn't suggest them again.
    public var knownTrackIDs: Set<TrackID> {
        var s = Set(history.suffix(100).map(\.trackID))
        if let c = current { s.insert(c.trackID) }
        for i in upcoming { s.insert(i.trackID) }
        return s
    }

    // MARK: Starting playback

    /// Replaces the context with `tracks` and starts at `startIndex` (or a random song when shuffling
    /// without one). The user's Play Next queue is kept, as in Spotify.
    public mutating func play(_ tracks: [TrackID], startAt startIndex: Int? = nil, context info: PlaybackContext,
                              shuffle: Bool, groupKey: (TrackID) -> String = { $0 }) {
        guard !tracks.isEmpty else { return }
        var rng = SystemRandomNumberGenerator()
        play(tracks, startAt: startIndex, context: info, shuffle: shuffle, groupKey: groupKey, using: &rng)
    }

    public mutating func play<G: RandomNumberGenerator>(_ tracks: [TrackID], startAt startIndex: Int?, context info: PlaybackContext,
                                                       shuffle: Bool, groupKey: (TrackID) -> String, using rng: inout G) {
        guard !tracks.isEmpty else { return }
        pushHistory()
        let items = tracks.map { QueueItem(trackID: $0, origin: .context) }
        contextOrder = items
        contextInfo = info
        autoplay = []
        self.shuffle = shuffle
        if shuffle {
            let first = startIndex.flatMap { items.indices.contains($0) ? items[$0] : nil }
            var rest = items
            if let first { rest.removeAll { $0.id == first.id } }
            rest = SpreadShuffle.shuffle(rest, groupKey: { groupKey($0.trackID) }, using: &rng)
            current = first ?? rest.removeFirst()
            context = rest
        } else {
            let start = min(max(startIndex ?? 0, 0), items.count - 1)
            current = items[start]
            context = Array(items[(start + 1)...])
        }
    }

    // MARK: Moving through the queue

    /// Moves to the next item. `auto` is true when the previous one finished by itself, which
    /// matters for repeat-one. Returns nil (and stays put) at the end of the queue.
    @discardableResult
    public mutating func advance(auto: Bool, groupKey: (TrackID) -> String = { $0 }) -> QueueItem? {
        if auto, repeatMode == .one, let current { return current }
        let previous = current
        let next: QueueItem?
        if !upNext.isEmpty {
            next = upNext.removeFirst()
        } else if !context.isEmpty {
            next = context.removeFirst()
        } else if repeatMode != .off, !contextOrder.isEmpty {
            // Repeat-all (or a manual skip in repeat-one): start the context again, with fresh ids
            // so the new round doesn't collide with history.
            contextOrder = contextOrder.map { QueueItem(trackID: $0.trackID, origin: .context) }
            context = shuffle ? SpreadShuffle.shuffle(contextOrder, groupKey: { groupKey($0.trackID) }) : contextOrder
            next = context.removeFirst()
        } else if !autoplay.isEmpty {
            next = autoplay.removeFirst()
        } else {
            next = nil
        }
        guard let next else { return nil }
        if let previous { appendHistory(previous) }
        current = next
        return next
    }

    /// Steps back to the most recent history item, returning the current one to the front of its section.
    @discardableResult
    public mutating func previous() -> QueueItem? {
        guard let prev = history.popLast() else { return nil }
        if let cur = current { insertFront(cur) }
        current = prev
        return prev
    }

    /// Plays an upcoming item now. Items between the current one and the target in the same
    /// section are skipped (dropped), like tapping further down a queue in Spotify.
    @discardableResult
    public mutating func jump(to id: UUID) -> QueueItem? {
        if let i = upNext.firstIndex(where: { $0.id == id }) {
            let target = upNext[i]
            upNext.removeFirst(i + 1)
            return setCurrent(target)
        }
        if let i = context.firstIndex(where: { $0.id == id }) {
            let target = context[i]
            context.removeFirst(i + 1)
            return setCurrent(target)
        }
        if let i = autoplay.firstIndex(where: { $0.id == id }) {
            let target = autoplay[i]
            autoplay.removeFirst(i + 1)
            context = []
            return setCurrent(target)
        }
        if history.contains(where: { $0.id == id }) {
            while let c = current, c.id != id, previous() != nil {}
            return current
        }
        return nil
    }

    // MARK: Editing

    public mutating func playNext(_ tracks: [TrackID]) {
        let items = tracks.map { QueueItem(trackID: $0, origin: .user) }
        if current == nil {
            guard let first = items.first else { return }
            current = first
            upNext.insert(contentsOf: items.dropFirst(), at: 0)
        } else {
            upNext.insert(contentsOf: items, at: 0)
        }
    }

    public mutating func addToQueue(_ tracks: [TrackID]) {
        let items = tracks.map { QueueItem(trackID: $0, origin: .user) }
        if current == nil {
            guard let first = items.first else { return }
            current = first
            upNext.append(contentsOf: items.dropFirst())
        } else {
            upNext.append(contentsOf: items)
        }
    }

    public mutating func appendAutoplay(_ tracks: [TrackID]) {
        let known = knownTrackIDs
        var seen = Set<TrackID>()
        let fresh = tracks.filter { !known.contains($0) && seen.insert($0).inserted }
        autoplay.append(contentsOf: fresh.map { QueueItem(trackID: $0, origin: .autoplay) })
        if current == nil, !autoplay.isEmpty { current = autoplay.removeFirst() }
    }

    public mutating func clearAutoplay() { autoplay = [] }

    @discardableResult
    public mutating func remove(_ id: UUID) -> Bool {
        let before = upNext.count + context.count + autoplay.count
        upNext.removeAll { $0.id == id }
        context.removeAll { $0.id == id }
        autoplay.removeAll { $0.id == id }
        contextOrder.removeAll { $0.id == id }
        return upNext.count + context.count + autoplay.count != before
    }

    public mutating func move(in section: Section, from source: IndexSet, to destination: Int) {
        switch section {
        case .upNext: Self.move(&upNext, from: source, to: destination)
        case .context: Self.move(&context, from: source, to: destination)
        case .autoplay: Self.move(&autoplay, from: source, to: destination)
        }
    }

    public mutating func clearUpNext() { upNext = [] }

    /// Drops everything after the current item (the queue's "Clear" button).
    public mutating func clearUpcoming() {
        upNext = []
        context = []
        autoplay = []
        contextOrder = contextOrder.filter { $0.id == current?.id }
    }

    public mutating func reset() { self = PlaybackQueue() }

    public mutating func setShuffle(_ on: Bool, groupKey: (TrackID) -> String = { $0 }) {
        guard on != shuffle else { return }
        shuffle = on
        if on {
            context = SpreadShuffle.shuffle(context, groupKey: { groupKey($0.trackID) })
        } else if let cur = current, cur.origin == .context, let i = contextOrder.firstIndex(where: { $0.id == cur.id }) {
            // Continue the original order from the song that's playing (Apple Music behaviour).
            context = Array(contextOrder[(i + 1)...])
        } else {
            let remaining = Set(context.map(\.id))
            context = contextOrder.filter { remaining.contains($0.id) }
        }
    }

    /// Removes items whose track no longer exists (after a library refresh).
    public mutating func prune(keeping exists: (TrackID) -> Bool) {
        history.removeAll { !exists($0.trackID) }
        upNext.removeAll { !exists($0.trackID) }
        context.removeAll { !exists($0.trackID) }
        autoplay.removeAll { !exists($0.trackID) }
        contextOrder.removeAll { !exists($0.trackID) }
        if let c = current, !exists(c.trackID) {
            current = nil
            advance(auto: false)
        }
    }

    // MARK: Helpers

    private mutating func setCurrent(_ item: QueueItem) -> QueueItem {
        if let c = current { appendHistory(c) }
        current = item
        return item
    }

    private mutating func pushHistory() {
        if let c = current { appendHistory(c) }
        current = nil
    }

    private mutating func appendHistory(_ item: QueueItem) {
        history.append(item)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }

    private mutating func insertFront(_ item: QueueItem) {
        switch item.origin {
        case .user: upNext.insert(item, at: 0)
        case .context: context.insert(item, at: 0)
        case .autoplay: autoplay.insert(item, at: 0)
        }
    }

    static func move<T>(_ array: inout [T], from source: IndexSet, to destination: Int) {
        let moving = source.sorted().filter { array.indices.contains($0) }.map { array[$0] }
        let below = source.filter { $0 < destination }.count
        for i in source.sorted(by: >) where array.indices.contains(i) { array.remove(at: i) }
        let at = min(max(destination - below, 0), array.count)
        array.insert(contentsOf: moving, at: at)
    }
}
