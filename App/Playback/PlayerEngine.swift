import AVFoundation
import Foundation

/// AVQueuePlayer holding the current item plus the next one, so tracks change without a gap.
/// Knows nothing about the queue; reports events to its owner by queue-item id.
@MainActor
final class PlayerEngine {
    struct Source: Equatable {
        var itemID: UUID
        var url: URL
        var headers: [String: String]
        var isLocal: Bool { url.isFileURL }
    }

    let player = AVQueuePlayer()
    private var sources: [ObjectIdentifier: Source] = [:]
    private var observers: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var pendingSeek: Double?

    var onEnded: ((UUID) -> Void)?
    var onCurrentChanged: ((UUID?) -> Void)?
    var onFailed: ((UUID, String) -> Void)?
    var onTick: ((Double) -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?
    var onBufferingChanged: ((Bool) -> Void)?

    init() {
        player.actionAtItemEnd = .advance
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.onTick?(t.seconds.isFinite ? t.seconds : 0) }
        }
        observers.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let status = p.timeControlStatus
            Task { @MainActor in
                self?.onPlayingChanged?(status == .playing)
                self?.onBufferingChanged?(status == .waitingToPlayAtSpecifiedRate)
            }
        })
        observers.append(player.observe(\.currentItem, options: [.new]) { [weak self] p, _ in
            let item = p.currentItem
            Task { @MainActor in
                guard let self else { return }
                self.onCurrentChanged?(item.flatMap { self.sources[ObjectIdentifier($0)]?.itemID })
            }
        })
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] n in
            guard let item = n.object as? AVPlayerItem else { return }
            let key = ObjectIdentifier(item)
            MainActor.assumeIsolated {
                guard let self, let src = self.sources[key] else { return }
                self.onEnded?(src.itemID)
            }
        }
        failObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] n in
            guard let item = n.object as? AVPlayerItem else { return }
            let key = ObjectIdentifier(item)
            let msg = (n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "Playback failed"
            MainActor.assumeIsolated {
                guard let self, let src = self.sources[key] else { return }
                self.onFailed?(src.itemID, msg)
            }
        }
    }

    var currentTime: Double {
        let t = player.currentTime().seconds
        return t.isFinite ? t : 0
    }

    var currentItemID: UUID? { player.currentItem.flatMap { sources[ObjectIdentifier($0)]?.itemID } }
    var queuedNextItemID: UUID? {
        let items = player.items()
        return items.count > 1 ? sources[ObjectIdentifier(items[1])]?.itemID : nil
    }
    var currentSource: Source? { player.currentItem.flatMap { sources[ObjectIdentifier($0)] } }
    var isPlaying: Bool { player.timeControlStatus == .playing || player.rate > 0 }

    private func makeItem(_ s: Source) -> AVPlayerItem {
        var options: [String: Any] = [:]
        if !s.headers.isEmpty, !s.isLocal { options["AVURLAssetHTTPHeaderFieldsKey"] = s.headers }
        let asset = AVURLAsset(url: s.url, options: options)
        let item = AVPlayerItem(asset: asset)
        // Enough buffer for a dead zone, not so much that skipping wastes data.
        item.preferredForwardBufferDuration = s.isLocal ? 0 : 60
        sources[ObjectIdentifier(item)] = s
        let id = ObjectIdentifier(item)
        observers.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let msg = item.error?.localizedDescription ?? "Couldn't play this song"
            Task { @MainActor in
                guard let self, let src = self.sources[id] else { return }
                self.onFailed?(src.itemID, msg)
            }
        })
        return item
    }

    /// Replaces everything with `current` (and optionally a preloaded `next`).
    func load(_ current: Source, next: Source?, at position: Double, play: Bool) {
        player.removeAllItems()
        pruneSources()
        let item = makeItem(current)
        player.insert(item, after: nil)
        if let next { player.insert(makeItem(next), after: item) }
        if position > 1 {
            pendingSeek = position
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if play { player.play() } else { player.pause() }
    }

    /// Sets the item that follows the current one, replacing a stale preload.
    func setNext(_ next: Source?) {
        let items = player.items()
        guard let current = items.first else { return }
        if items.count > 1, let existing = sources[ObjectIdentifier(items[1])], existing == next { return }
        for extra in items.dropFirst() { player.remove(extra) }
        if let next { player.insert(makeItem(next), after: current) }
        pruneSources()
    }

    /// After the queue advanced by itself: true if the player already moved to `itemID` (gapless path).
    func isCurrent(_ itemID: UUID) -> Bool { currentItemID == itemID }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: Double, completion: (() -> Void)? = nil) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in completion?() }
        }
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        pruneSources()
    }

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    var duration: Double? {
        guard let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 else { return nil }
        return d
    }

    private func pruneSources() {
        let live = Set(player.items().map(ObjectIdentifier.init))
        sources = sources.filter { live.contains($0.key) }
        // Item status observers for removed items are harmless (they look up by id), but don't let them pile up.
        if observers.count > 64 { observers = Array(observers.prefix(2)) + observers.suffix(12) }
    }
}
