import Foundation
import MusicsCore
import Observation
import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Hashable {
    case home, search, library

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .library: return "Library"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .library: return "square.stack"
        }
    }
}

enum Route: Hashable {
    case album(AlbumID)
    case artist(String)
    case playlist(PlaylistID)
    case genre(String)
    case liked
    case downloads
    case songs
    case albums
    case artists
    case playlists
    case genres
    case recentlyAdded
    case history
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var undo: (() -> Void)?
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Root state shared by every screen.
@MainActor
@Observable
final class AppModel {
    let settings = AppSettings()
    let servers = ServerStore()
    let library = LibraryStore()
    let stats = StatsStore()
    let downloads = DownloadManager()
    let player = PlaybackController()
    private(set) var session: ServerSession?

    var tab: AppTab = .home
    var paths: [AppTab: NavigationPath] = [.home: NavigationPath(), .search: NavigationPath(), .library: NavigationPath()]
    var showPlayer = false
    var showSettings = false
    var showAdventure = false
    var adventureStart: Track?
    var infoTrack: Track?
    var toastItem: Toast?
    /// Bumped when the user re-taps the active tab, so its root view scrolls to the top.
    var scrollToTopToken: [AppTab: Int] = [:]

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var lastForegroundRefresh = Date.distantPast

    init() {
        downloads.app = self
        player.app = self
    }

    // MARK: Lifecycle

    func startup() async {
        if let profile = servers.active { await activate(profile) }
    }

    func activate(_ profile: ServerProfile) async {
        player.detach()
        session?.stop()
        library.reset()
        servers.activeID = profile.id
        let s = ServerSession(profile: profile, credentials: servers.credentials(for: profile))
        ArtworkLoader.shared.headers = s.provider.mediaHeaders
        session = s
        stats.load(serverID: profile.id)
        downloads.load(serverID: profile.id)
        await library.loadCached(serverID: profile.id)
        player.restore(serverID: profile.id)
        s.onBaseURLChange = { @MainActor [weak self] url in
            guard let self, url != nil else { return }
            Task { @MainActor in
                await self.library.refresh(session: s)
                self.player.connectionChanged()
                self.downloads.resume()
            }
        }
        s.start()
    }

    func sceneBecameActive() {
        guard let session, Date().timeIntervalSince(lastForegroundRefresh) > 30 else { return }
        lastForegroundRefresh = Date()
        Task {
            if !session.isOnline { await session.resolve() }
            await library.refresh(session: session)
        }
    }

    func sceneEnteredBackground() {
        player.save()
        stats.flush()
        downloads.saveIndexes()
    }

    func removeServer(_ id: UUID) async {
        let wasActive = servers.activeID == id
        servers.remove(id)
        if wasActive {
            if let next = servers.active {
                await activate(next)
            } else {
                player.detach()
                session?.stop()
                session = nil
                library.reset()
            }
        }
    }

    // MARK: Navigation

    func open(_ route: Route) {
        showPlayer = false
        paths[tab, default: NavigationPath()].append(route)
    }

    func selectTab(_ t: AppTab) {
        if t == tab {
            if paths[t]?.isEmpty == false {
                paths[t] = NavigationPath()
            } else {
                scrollToTopToken[t, default: 0] += 1
            }
        } else {
            tab = t
        }
    }

    // MARK: Actions used across screens

    func play(_ tracks: [Track], startAt: Int? = nil, context: PlaybackContext, shuffle: Bool = false) {
        player.play(tracks, startAt: startAt, context: context, shuffle: shuffle)
    }

    func toggleLike(_ track: Track) {
        let liked = !library.isLiked(track.id)
        haptic(.light)
        Task {
            let ok = await library.setLiked(track.id, liked, session: session)
            if !ok { toast("Couldn't reach the server to save that like.") }
            else if liked, settings.autoDownloadLiked { downloads.download([track]) }
            player.refreshNowPlaying()
        }
    }

    func startRadio(_ seed: RadioSeed, title: String) {
        Task { await player.startRadio(seed, title: title) }
    }

    func download(_ tracks: [Track]) {
        let missing = tracks.filter { !downloads.isDownloaded($0.id) }
        guard !missing.isEmpty else { return }
        downloads.download(missing)
        toast(missing.count == 1 ? "Downloading “\(missing[0].title)”" : "Downloading \(missing.count) songs")
    }

    func removeDownloads(_ tracks: [Track]) {
        downloads.remove(tracks.map(\.id))
        toast(tracks.count == 1 ? "Removed download" : "Removed \(tracks.count) downloads")
    }

    func toast(_ text: String, undo: (() -> Void)? = nil) {
        toastTask?.cancel()
        withAnimation(.snappy(duration: 0.25)) { toastItem = Toast(text: text, undo: undo) }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: undo == nil ? 2_600_000_000 : 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toastItem = nil }
        }
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard settings.haptics else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    // MARK: Artwork

    func artworkURL(album: Album, size: Int) -> URL? {
        guard let session, let base = session.baseURL ?? session.profile.endpoints.first?.url else { return nil }
        return session.provider.artworkURL(base: base, album: album, size: size)
    }

    func artworkURL(albumID: AlbumID, size: Int) -> URL? {
        library.index.albums[albumID].flatMap { artworkURL(album: $0, size: size) }
    }

    func artworkURL(track: Track, size: Int) -> URL? {
        if let album = library.index.albums[track.albumID] { return artworkURL(album: album, size: size) }
        guard let session, let base = session.baseURL ?? session.profile.endpoints.first?.url, let cover = track.coverID else { return nil }
        return session.provider.artworkURL(base: base, album: Album(id: track.albumID, title: "", artist: "", coverID: cover), size: size)
    }

    func artworkURL(playlist: Playlist, size: Int) -> URL? {
        guard let session, let base = session.baseURL ?? session.profile.endpoints.first?.url else { return nil }
        if let url = session.provider.artworkURL(base: base, playlist: playlist, size: size) { return url }
        return playlist.trackIDs.first.flatMap { library.index.tracks[$0] }.flatMap { artworkURL(track: $0, size: size) }
    }

    func accentColor(albumID: AlbumID?) -> Color? {
        guard let id = albumID, let hex = library.index.albums[id]?.accentHex else { return nil }
        return Color(hex: hex)
    }

    var capabilities: ProviderCapabilities { session?.capabilities ?? [] }
}
