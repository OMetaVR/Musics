import SwiftUI
import MusicsCore

struct HomeView: View {
    @Environment(AppModel.self) private var model

    private var index: LibraryIndex { model.library.index }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Color.clear.frame(height: 0).id("top")
                    ConnectionBanner()
                    if model.library.isEmpty {
                        loadingOrEmpty
                    } else {
                        quickActions
                        jumpBackIn
                        recentlyAdded
                        playlists
                        stations
                        genres
                        rediscover
                    }
                }
                .padding(.vertical, 12)
            }
            .refreshable {
                if let s = model.session {
                    await s.resolve()
                    await model.library.refresh(session: s, force: true)
                }
            }
            .onChange(of: model.scrollToTopToken[.home]) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
        }
        .background(Theme.bg)
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.showSettings = true } label: {
                    HStack(spacing: 6) {
                        StatusDot()
                        Image(systemName: "gearshape")
                    }
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    @ViewBuilder private var loadingOrEmpty: some View {
        if model.library.isRefreshing || model.session?.status == .connecting {
            VStack(spacing: 12) {
                ProgressView().tint(Theme.accent)
                Text("Loading your library…").font(.system(size: 15)).foregroundStyle(Theme.ink3)
            }
            .frame(maxWidth: .infinity).padding(.top, 80)
        } else if let err = model.library.lastError {
            EmptyStateView(icon: "exclamationmark.triangle", title: "Couldn't load the library", message: err,
                           actionTitle: "Try Again") {
                Task { if let s = model.session { await model.library.refresh(session: s, force: true) } }
            }
        } else if model.session?.isOnline == true {
            EmptyStateView(icon: "music.note.list", title: "No music yet", message: "This server's library is empty.")
        }
    }

    // MARK: Sections

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            QuickTile(icon: "heart.fill", title: "Liked Songs", subtitle: Format.songs(model.library.likes.count)) { model.open(.liked) }
            QuickTile(icon: "shuffle", title: "Shuffle All", subtitle: Format.songs(index.snapshot.tracks.count)) {
                model.play(index.snapshot.tracks, context: PlaybackContext(kind: .songs, title: "All songs"), shuffle: true)
            }
            QuickTile(icon: "arrow.down.circle.fill", title: "Downloads", subtitle: Format.songs(model.downloads.downloaded.count)) {
                model.open(.downloads)
            }
            if model.capabilities.contains(.adventure) {
                QuickTile(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "Sonic Adventure", subtitle: "Song to song") {
                    model.adventureStart = model.player.currentTrack
                    model.showAdventure = true
                }
            } else {
                QuickTile(icon: "clock.arrow.circlepath", title: "History", subtitle: "Recently played") { model.open(.history) }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }

    @ViewBuilder private var jumpBackIn: some View {
        let recents = model.stats.stats.recentContexts.filter { resolvable($0.context) }.prefix(12)
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Jump Back In", action: { model.open(.history) }, actionTitle: "History")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(recents)) { recent in contextTile(recent.context) }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }

    private func resolvable(_ c: PlaybackContext) -> Bool {
        switch c.kind {
        case .album: return c.id.flatMap { index.albums[$0] } != nil
        case .playlist: return c.id.flatMap { index.playlists[$0] } != nil
        case .artist: return c.id.flatMap { index.artists[$0] } != nil
        case .genre, .liked, .downloads: return true
        default: return false
        }
    }

    @ViewBuilder private func contextTile(_ c: PlaybackContext) -> some View {
        switch c.kind {
        case .album:
            if let a = c.id.flatMap({ index.albums[$0] }) { AlbumTile(album: a, width: 140) }
        case .playlist:
            if let p = c.id.flatMap({ index.playlists[$0] }) { PlaylistTile(playlist: p, width: 140) }
        case .artist:
            if let a = c.id.flatMap({ index.artists[$0] }) { ArtistTile(artist: a, size: 140) }
        case .genre:
            GenreTile(name: c.id ?? c.title, width: 140)
        case .liked:
            IconTile(icon: "heart.fill", title: "Liked Songs", width: 140) { model.open(.liked) }
        case .downloads:
            IconTile(icon: "arrow.down.circle.fill", title: "Downloads", width: 140) { model.open(.downloads) }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var recentlyAdded: some View {
        let albums = index.albumsByAdded.prefix(16)
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recently Added") { model.open(.recentlyAdded) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(albums)) { AlbumTile(album: $0, width: 150) }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }

    @ViewBuilder private var playlists: some View {
        let lists = index.snapshot.playlists.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(16)
        if !lists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Your Playlists") { model.open(.playlists) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(lists)) { p in
                            if let full = index.playlists[p.id] { PlaylistTile(playlist: full, width: 150) }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
            }
        }
    }

    /// Radio stations seeded from the artists you play most (or have most of).
    @ViewBuilder private var stations: some View {
        if model.capabilities.contains(.radio) {
            let artists = topArtists(8)
            if !artists.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Stations")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(artists) { a in
                                StationTile(title: "\(a.name) Radio",
                                            artworkURL: a.albumIDs.first.flatMap { model.artworkURL(albumID: $0, size: 300) }) {
                                    model.startRadio(.artist(a.name), title: "\(a.name) Radio")
                                }
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                }
            }
        }
    }

    private func topArtists(_ n: Int) -> [Artist] {
        let stats = model.stats.stats
        var playsByArtist: [String: Int] = [:]
        for (id, s) in stats.tracks where s.plays > 0 {
            if let t = index.tracks[id] { playsByArtist[TextNormalizer.key(t.primaryArtist), default: 0] += s.plays }
        }
        if playsByArtist.count >= 3 {
            return playsByArtist.sorted { $0.value > $1.value }.prefix(n).compactMap { index.artists[$0.key] }
        }
        return index.artistsByName.filter { !$0.albumIDs.isEmpty }.sorted { $0.trackIDs.count > $1.trackIDs.count }.prefix(n).map { $0 }
    }

    @ViewBuilder private var genres: some View {
        let top = index.genres.prefix(8)
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Genres") { model.open(.genres) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(top)) { g in GenreChip(genre: g) }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }

    @ViewBuilder private var rediscover: some View {
        let ids = model.stats.stats.rediscover(limit: 30).filter { index.tracks[$0] != nil }
        if ids.count >= 3 {
            let tracks = index.tracks(ids)
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Rediscover", action: {
                    model.play(tracks, context: PlaybackContext(kind: .songs, title: "Rediscover"), shuffle: true)
                }, actionTitle: "Shuffle")
                Text("Songs you used to play a lot.").font(.system(size: 14)).foregroundStyle(Theme.ink3).padding(.horizontal, Theme.gutter)
                VStack(spacing: 0) {
                    ForEach(Array(tracks.prefix(5).enumerated()), id: \.element.id) { i, t in
                        TrackRow(track: t) { model.play(tracks, startAt: i, context: PlaybackContext(kind: .songs, title: "Rediscover")) }
                            .padding(.horizontal, Theme.gutter)
                    }
                }
            }
        }
    }
}

struct StatusDot: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let color: Color = {
            switch model.session?.status {
            case .online: return Theme.accent
            case .connecting, .none: return Theme.ink3
            case .offline: return Theme.danger
            }
        }()
        Circle().fill(color).frame(width: 7, height: 7)
            .accessibilityLabel(model.session?.statusText ?? "No server")
    }
}

struct QuickTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36).background(Theme.accentBg, in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.ink3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }
}

struct IconTile: View {
    let icon: String
    let title: String
    var width: CGFloat = 140
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Theme.accentBg
                    Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Theme.accent)
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
    }
}

struct StationTile: View {
    let title: String
    let artworkURL: URL?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkView(url: artworkURL, cornerRadius: 6)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.black)
                        .padding(6).background(Theme.accent, in: Circle()).padding(8)
                }
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            .frame(width: 140)
        }
        .buttonStyle(.plain)
    }
}

struct GenreChip: View {
    @Environment(AppModel.self) private var model
    let genre: Genre

    var body: some View {
        Button { model.open(.genre(genre.name)) } label: {
            HStack(spacing: 10) {
                ArtworkView(url: genre.coverAlbumID.flatMap { model.artworkURL(albumID: $0, size: 128) }, cornerRadius: 4)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(genre.name.capitalized).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(Format.songs(genre.trackCount)).font(.system(size: 12)).foregroundStyle(Theme.ink3)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }
}

struct GenreTile: View {
    @Environment(AppModel.self) private var model
    let name: String
    var width: CGFloat = 140

    var body: some View {
        let genre = model.library.index.genres.first { $0.name == name }
        Button { model.open(.genre(name)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkView(url: genre?.coverAlbumID.flatMap { model.artworkURL(albumID: $0, size: 300) }, cornerRadius: 6)
                Text(name.capitalized).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
    }
}
