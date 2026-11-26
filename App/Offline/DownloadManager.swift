import Foundation
import MusicsCore
import Observation

/// Two kinds of offline audio:
/// - **Downloads**: songs the user asked to keep. Never evicted.
/// - **Smart cache**: upcoming songs prefetched while playing and songs played recently, kept in a
///   size-capped least-recently-used store. Makes track changes instant and survives dead zones.
@MainActor
@Observable
final class DownloadManager {
    struct Record: Codable, Hashable {
        var file: String
        var bytes: Int64
        var date: Date
    }

    enum State: Equatable { case queued, downloading, failed(String) }

    private(set) var downloaded: [TrackID: Record] = [:]
    private(set) var cached: [TrackID: Record] = [:]
    private(set) var active: [TrackID: State] = [:]

    @ObservationIgnored private var serverID: UUID?
    @ObservationIgnored private var queue: [(TrackID, Bool)] = []  // (id, isPrefetch)
    @ObservationIgnored private var running = 0
    @ObservationIgnored private let maxConcurrent = 3
    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 60 * 30
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    var downloadedBytes: Int64 { downloaded.values.reduce(0) { $0 + $1.bytes } }
    var cachedBytes: Int64 { cached.values.reduce(0) { $0 + $1.bytes } }
    var pendingCount: Int { active.values.filter { $0 == .queued || $0 == .downloading }.count }

    private var downloadsIndex: URL? { serverID.map { Paths.server($0).appendingPathComponent("downloads.json") } }
    private var cacheIndex: URL? { serverID.map { Paths.streamCache($0).appendingPathComponent("index.json") } }

    func load(serverID id: UUID) {
        serverID = id
        queue = []
        active = [:]
        downloaded = (downloadsIndex.flatMap { Store.load([TrackID: Record].self, from: $0) } ?? [:])
            .filter { FileManager.default.fileExists(atPath: Paths.downloads(id).appendingPathComponent($0.value.file).path) }
        cached = (cacheIndex.flatMap { Store.load([TrackID: Record].self, from: $0) } ?? [:])
            .filter { FileManager.default.fileExists(atPath: Paths.streamCache(id).appendingPathComponent($0.value.file).path) }
    }

    func isDownloaded(_ id: TrackID) -> Bool { downloaded[id] != nil }
    func state(_ id: TrackID) -> State? { active[id] }

    /// A local file to play instead of streaming, if there is one.
    func localFile(for id: TrackID) -> URL? {
        guard let sid = serverID else { return nil }
        if let r = downloaded[id] { return Paths.downloads(sid).appendingPathComponent(r.file) }
        if var r = cached[id] {
            r.date = Date()  // LRU touch
            cached[id] = r
            return Paths.streamCache(sid).appendingPathComponent(r.file)
        }
        return nil
    }

    func isAvailableOffline(_ id: TrackID) -> Bool { downloaded[id] != nil || cached[id] != nil }

    // MARK: Requests

    func download(_ tracks: [Track]) {
        for t in tracks where downloaded[t.id] == nil && active[t.id] == nil {
            active[t.id] = .queued
            queue.append((t.id, false))
        }
        pump()
    }

    func remove(_ ids: [TrackID]) {
        guard let sid = serverID else { return }
        for id in ids {
            queue.removeAll { $0.0 == id }
            if active[id] == .queued { active[id] = nil }
            if let r = downloaded.removeValue(forKey: id) {
                try? FileManager.default.removeItem(at: Paths.downloads(sid).appendingPathComponent(r.file))
            }
        }
        saveIndexes()
    }

    func removeAllDownloads() { remove(Array(downloaded.keys)) }

    /// Prefetch into the smart cache (called with the next songs in the queue).
    func prefetch(_ tracks: [Track]) {
        guard app?.settings.smartCache == true else { return }
        for t in tracks where downloaded[t.id] == nil && cached[t.id] == nil && active[t.id] == nil {
            active[t.id] = .queued
            // Prefetches jump the line: they're needed within minutes.
            queue.insert((t.id, true), at: 0)
        }
        pump()
    }

    func clearCache() {
        guard let sid = serverID else { return }
        for r in cached.values { try? FileManager.default.removeItem(at: Paths.streamCache(sid).appendingPathComponent(r.file)) }
        cached = [:]
        saveIndexes()
    }

    func retryFailed() {
        let failed = active.compactMap { id, s -> TrackID? in if case .failed = s { return id } else { return nil } }
        for id in failed { active[id] = .queued; queue.append((id, false)) }
        pump()
    }

    // MARK: Worker

    private func pump() {
        guard let app, let sessionModel = app.session, let base = sessionModel.baseURL, let sid = serverID else { return }
        let onCellular = sessionModel.isExpensiveNetwork
        while running < maxConcurrent, !queue.isEmpty {
            let (id, isPrefetch) = queue.removeFirst()
            guard let track = app.library.index.tracks[id] else { active[id] = nil; continue }
            if !isPrefetch, onCellular, !app.settings.downloadOverCellular {
                active[id] = .failed("Waiting for Wi-Fi")
                continue
            }
            let quality = isPrefetch ? sessionModel.quality(app.settings) : app.settings.downloadQuality
            let provider = sessionModel.provider
            let url = provider.downloadURL(base: base, track: track, quality: quality)
            let ext = provider.downloadExtension(track: track, quality: quality)
            var request = URLRequest(url: url)
            for (k, v) in provider.mediaHeaders { request.setValue(v, forHTTPHeaderField: k) }
            let dir = isPrefetch ? Paths.streamCache(sid) : Paths.downloads(sid)
            let fileName = "\(id).\(ext.isEmpty ? "audio" : ext)"
            active[id] = .downloading
            running += 1
            let session = self.session
            Task { [weak self] in
                var outcome: Result<Int64, Error>
                do {
                    let (tmp, response) = try await session.download(for: request)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(code) else { throw MusicsError.http(code, nil) }
                    let dest = dir.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
                    outcome = .success((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
                } catch {
                    outcome = .failure(error)
                }
                self?.finish(id, fileName: fileName, isPrefetch: isPrefetch, outcome: outcome, serverID: sid)
            }
        }
    }

    private func finish(_ id: TrackID, fileName: String, isPrefetch: Bool, outcome: Result<Int64, Error>, serverID sid: UUID) {
        running -= 1
        guard sid == serverID else { return }
        switch outcome {
        case let .success(bytes):
            let record = Record(file: fileName, bytes: bytes, date: Date())
            if isPrefetch { cached[id] = record } else { downloaded[id] = record; removeFromCache(id) }
            active[id] = nil
            if isPrefetch { evictIfNeeded(); app?.player.localFileBecameAvailable(id) }
            saveIndexes()
        case let .failure(error):
            if isPrefetch {
                active[id] = nil
            } else {
                active[id] = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            app?.session?.reportFailure()
        }
        pump()
    }

    private func removeFromCache(_ id: TrackID) {
        guard let sid = serverID, let r = cached.removeValue(forKey: id) else { return }
        try? FileManager.default.removeItem(at: Paths.streamCache(sid).appendingPathComponent(r.file))
    }

    private func evictIfNeeded() {
        guard let sid = serverID, let app else { return }
        let limit = Int64(max(app.settings.cacheLimitMB, 100)) * 1_048_576
        var total = cachedBytes
        guard total > limit else { return }
        let protected = Set(app.player.upcomingTrackIDs(limit: 5) + [app.player.currentTrack?.id].compactMap { $0 })
        for (id, r) in cached.sorted(by: { $0.value.date < $1.value.date }) where total > limit && !protected.contains(id) {
            try? FileManager.default.removeItem(at: Paths.streamCache(sid).appendingPathComponent(r.file))
            cached[id] = nil
            total -= r.bytes
        }
    }

    func saveIndexes() {
        if let u = downloadsIndex { Store.save(downloaded, to: u) }
        if let u = cacheIndex { Store.save(cached, to: u) }
    }

    /// Network came back or the server changed address: resume waiting work.
    func resume() {
        let waiting = active.compactMap { id, s -> TrackID? in
            if case .failed("Waiting for Wi-Fi") = s { return id } else { return nil }
        }
        for id in waiting { active[id] = .queued; queue.append((id, false)) }
        pump()
    }
}
