import Foundation
import MusicsCore
import Observation

/// The active server's library: loaded from the on-disk cache at launch, refreshed from the server when
/// its version changes. Index building happens off the main thread.
@MainActor
@Observable
final class LibraryStore {
    private(set) var index: LibraryIndex = .empty
    private(set) var likes: [TrackID] = []
    private(set) var likeSet: Set<TrackID> = []
    private(set) var isLoaded = false
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    private(set) var serverID: UUID?

    @ObservationIgnored private var lastVersionCheck = Date.distantPast

    var isEmpty: Bool { index.snapshot.tracks.isEmpty }
    var fetchedAt: Date { index.snapshot.fetchedAt }

    private func cacheURL(_ id: UUID) -> URL { Paths.server(id).appendingPathComponent("library.json") }

    func reset() {
        index = .empty
        likes = []
        likeSet = []
        isLoaded = false
        serverID = nil
        lastError = nil
    }

    /// Instant start: the last library seen for this server.
    func loadCached(serverID id: UUID) async {
        serverID = id
        let url = cacheURL(id)
        let built: LibraryIndex? = await Task.detached(priority: .userInitiated) {
            guard let snap = Store.load(LibrarySnapshot.self, from: url) else { return nil }
            return LibraryIndex(snap)
        }.value
        guard serverID == id else { return }
        if let built { apply(built) }
        isLoaded = built != nil
    }

    /// Re-downloads the library when the server reports a different version (or when forced).
    /// music.lan bumps its version on every rescan, so unforced checks re-download at most every 10 minutes.
    func refresh(session: ServerSession, force: Bool = false) async {
        guard let base = session.baseURL, !isRefreshing else { return }
        let id = session.profile.id
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if !force, !isEmpty {
                guard Date().timeIntervalSince(lastVersionCheck) > 60 else { return }
                lastVersionCheck = Date()
                let version = try await session.provider.libraryVersion(base: base)
                let stale = Date().timeIntervalSince(fetchedAt) > 600
                if version == index.snapshot.version || (!stale && session.profile.kind == .musicLan) { return }
            }
            let provider = session.provider
            let url = cacheURL(id)
            let (built, saveURL) = try await Task.detached(priority: .userInitiated) {
                let snap = try await provider.fetchLibrary(base: base)
                return (LibraryIndex(snap), url)
            }.value
            guard serverID == id else { return }
            // A server whose music drive is unmounted reports an empty library. Keep the songs we
            // already know about (downloads and the smart cache still play) instead of wiping them.
            if built.snapshot.tracks.isEmpty, !isEmpty {
                lastError = "\(session.profile.name) reports an empty library, so its music drive may be unmounted. Showing the last library this phone saw."
                return
            }
            apply(built)
            isLoaded = true
            lastError = nil
            let snapshot = built.snapshot
            Task.detached(priority: .utility) { Store.save(snapshot, to: saveURL) }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            session.reportFailure()
        }
    }

    private func apply(_ built: LibraryIndex) {
        index = built
        likes = built.snapshot.likes.filter { built.tracks[$0] != nil }
        likeSet = Set(likes)
    }

    func isLiked(_ id: TrackID) -> Bool { likeSet.contains(id) }

    /// Optimistic: flips immediately, rolls back if the server refuses.
    func setLiked(_ id: TrackID, _ liked: Bool, session: ServerSession?) async -> Bool {
        let before = likes
        if liked { likes.removeAll { $0 == id }; likes.insert(id, at: 0) } else { likes.removeAll { $0 == id } }
        likeSet = Set(likes)
        guard let session, let base = session.baseURL else {
            likes = before
            likeSet = Set(before)
            return false
        }
        do {
            if let server = try await session.provider.setLiked(base: base, trackID: id, liked: liked) {
                likes = server.filter { index.tracks[$0] != nil }
                likeSet = Set(likes)
            }
            persistLikes()
            return true
        } catch {
            likes = before
            likeSet = Set(before)
            session.reportFailure()
            return false
        }
    }

    private func persistLikes() {
        guard let id = serverID else { return }
        var snap = index.snapshot
        snap.likes = likes
        let url = cacheURL(id)
        Task.detached(priority: .utility) { Store.save(snap, to: url) }
    }

    var likedTracks: [Track] { index.tracks(likes) }
}
