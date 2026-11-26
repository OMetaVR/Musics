import SwiftUI
import MusicsCore

/// Shared header for album / playlist / genre screens.
struct CollectionHeader<Accessory: View>: View {
    let artworkURL: URL?
    var round = false
    let title: String
    var subtitle: String?
    var subtitleAction: (() -> Void)?
    var meta: String
    var note: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 14) {
            ArtworkView(url: artworkURL, cornerRadius: round ? 110 : 8)
                .frame(width: 220, height: 220)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                .padding(.top, 8)
            VStack(spacing: 4) {
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.inkHi)
                    .multilineTextAlignment(.center).lineLimit(3)
                if let subtitle {
                    Button { subtitleAction?() } label: {
                        Text(subtitle).font(.system(size: 18)).foregroundStyle(Theme.accent).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(subtitleAction == nil)
                }
                Text(meta).font(.system(size: 13)).foregroundStyle(Theme.ink3)
                if let note {
                    Text(note).font(.system(size: 12)).foregroundStyle(Theme.ink3).multilineTextAlignment(.center).padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
            HStack(spacing: 12) { accessory }
                .padding(.horizontal, Theme.gutter)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }
}

// MARK: Album

struct AlbumView: View {
    @Environment(AppModel.self) private var model
    let albumID: AlbumID

    var body: some View {
        let index = model.library.index
        if let album = index.albums[albumID] {
            let tracks = index.albumTracks(albumID)
            let ctx = PlaybackContext(kind: .album, id: album.id, title: album.title)
            let discs = Set(tracks.map(\.discNumber)).count > 1
            List {
                CollectionHeader(artworkURL: model.artworkURL(album: album, size: 640), title: album.title, subtitle: album.artist,
                                 subtitleAction: { model.open(.artist(TextNormalizer.key(album.artist))) },
                                 meta: meta(album, tracks)) {
                    PlayShuffleButtons(play: { model.play(tracks, context: ctx) },
                                       shuffle: { model.play(tracks, context: ctx, shuffle: true) })
                    CollectionDownloadButton(tracks: tracks)
                }
                .bareRow()
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                    if discs, i == 0 || tracks[i - 1].discNumber != t.discNumber {
                        Text("Disc \(t.discNumber)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3)
                            .padding(.top, 12).plainRow()
                    }
                    TrackRow(track: t, leading: .number,
                             subtitleOverride: t.artists == [album.artist] ? (t.duration > 0 ? Format.time(t.duration) : "") : t.artistLine) {
                        model.play(tracks, startAt: i, context: ctx)
                    }
                    .plainRow()
                }
                moreByArtist(album).bareRow()
            }
            .appList()
            .navigationTitle(album.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu { AlbumMenuItems(album: album) } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        } else {
            EmptyStateView(icon: "questionmark.square.dashed", title: "Album not found", message: "It may have been removed from the server.")
        }
    }

    private func meta(_ a: Album, _ tracks: [Track]) -> String {
        var parts: [String] = []
        if a.year > 0 { parts.append(String(a.year)) }
        parts.append(Format.songs(tracks.count))
        let total = tracks.reduce(0) { $0 + $1.duration }
        if total > 0 { parts.append(Format.duration(total)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func moreByArtist(_ album: Album) -> some View {
        let index = model.library.index
        let others = (index.artist(named: album.artist)?.albumIDs ?? []).filter { $0 != album.id }.compactMap { index.albums[$0] }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "More by \(album.artist)")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) { ForEach(others.prefix(12)) { AlbumTile(album: $0, width: 140) } }
                        .padding(.horizontal, Theme.gutter)
                }
            }
            .padding(.vertical, 20)
        }
    }
}

// MARK: Artist

struct ArtistView: View {
    @Environment(AppModel.self) private var model
    let artistID: String
    @State private var showAllSongs = false

    var body: some View {
        let index = model.library.index
        if let artist = index.artists[artistID] {
            let all = index.tracks(artist.trackIDs)
            let top = topSongs(artist, all)
            let disc = index.discography(artist)
            let appears = artist.appearsOnAlbumIDs.compactMap { index.albums[$0] }
            let ctx = PlaybackContext(kind: .artist, id: artist.id, title: artist.name)
            List {
                CollectionHeader(artworkURL: (artist.albumIDs.first ?? artist.appearsOnAlbumIDs.first).flatMap { model.artworkURL(albumID: $0, size: 640) },
                                 round: true, title: artist.name,
                                 meta: [disc.albums.count + disc.singles.count > 0 ? "\(disc.albums.count + disc.singles.count) releases" : nil,
                                        Format.songs(all.count)].compactMap { $0 }.joined(separator: " · ")) {
                    PlayShuffleButtons(play: { model.play(top.isEmpty ? all : top + all.filter { !top.contains($0) }, context: ctx) },
                                       shuffle: { model.play(all, context: ctx, shuffle: true) })
                    if model.capabilities.contains(.radio) {
                        Button { model.startRadio(.artist(artist.name), title: "\(artist.name) Radio") } label: {
                            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 18)).frame(width: 44, height: 44)
                        }
                        .buttonStyle(FilledButtonStyle(primary: false))
                        .accessibilityLabel("Start radio")
                    }
                }
                .bareRow()

                Section {
                    let shown = showAllSongs ? all : top
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, t in
                        TrackRow(track: t, showAlbum: true) { model.play(shown, startAt: i, context: ctx) }.plainRow()
                    }
                    if all.count > top.count {
                        Button(showAllSongs ? "Show Top Songs" : "Show All \(all.count) Songs") { withAnimation { showAllSongs.toggle() } }
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.accent).plainRow(top: 10, bottom: 10)
                    }
                } header: { header(showAllSongs ? "All Songs" : "Top Songs") }

                shelf("Albums", disc.albums)
                shelf("Singles & EPs", disc.singles)
                shelf("Appears On", appears)
            }
            .appList()
            .navigationTitle(artist.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            EmptyStateView(icon: "music.mic", title: "Artist not found", message: "")
        }
    }

    /// Most played by you; otherwise liked songs, then the newest.
    private func topSongs(_ artist: Artist, _ all: [Track]) -> [Track] {
        let stats = model.stats.stats
        var ids = stats.topTracks(among: artist.trackIDs, limit: 5)
        if ids.count < 5 {
            let liked = artist.trackIDs.filter { model.library.isLiked($0) && !ids.contains($0) }
            ids += liked.prefix(5 - ids.count)
        }
        if ids.count < 5 {
            let newest = all.sorted { ($0.year, $0.addedAt) > ($1.year, $1.addedAt) }.map(\.id).filter { !ids.contains($0) }
            ids += newest.prefix(5 - ids.count)
        }
        return model.library.index.tracks(ids)
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.inkHi).textCase(nil)
    }

    @ViewBuilder private func shelf(_ title: String, _ albums: [Album]) -> some View {
        if !albums.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(albums) { AlbumTile(album: $0, width: 140, subtitle: $0.year > 0 ? String($0.year) : $0.artist) }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, 6)
                }
                .bareRow()
            } header: { header(title) }
        }
    }
}

// MARK: Playlist

struct PlaylistView: View {
    @Environment(AppModel.self) private var model
    let playlistID: PlaylistID
    @State private var filter = ""

    var body: some View {
        let index = model.library.index
        if let p = index.playlists[playlistID] {
            let tracks = index.tracks(p.trackIDs)
            let shown = filter.isEmpty ? tracks : {
                let hits = Set(index.search.search(filter, limit: 3000).tracks)
                return tracks.filter { hits.contains($0.id) }
            }()
            let ctx = PlaybackContext(kind: .playlist, id: p.id, title: p.name)
            List {
                CollectionHeader(artworkURL: model.artworkURL(playlist: p, size: 640), title: p.name,
                                 subtitle: p.source == .spotify ? "From Spotify" : p.source == .m3u ? "M3U playlist" : nil,
                                 meta: [Format.songs(tracks.count), Format.duration(tracks.reduce(0) { $0 + $1.duration })].joined(separator: " · "),
                                 note: p.missingCount > 0 ? "\(p.missingCount) of \(p.total) songs aren't in the library yet." : p.comment) {
                    PlayShuffleButtons(play: { model.play(tracks, context: ctx) },
                                       shuffle: { model.play(tracks, context: ctx, shuffle: true) })
                    CollectionDownloadButton(tracks: tracks)
                }
                .bareRow()
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t) {
                        if filter.isEmpty { model.play(tracks, startAt: i, context: ctx) }
                        else { model.play(tracks, startAt: tracks.firstIndex { $0.id == t.id }, context: ctx) }
                    }
                    .plainRow()
                }
            }
            .appList()
            .navigationTitle(p.name)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Find in playlist")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { model.player.playNext(tracks) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                        Button { model.player.addToQueue(tracks) } label: { Label("Add to Queue", systemImage: "text.append") }
                        if let s = p.externalURL, let url = URL(string: s) {
                            Link(destination: url) { Label("Open Original", systemImage: "arrow.up.right.square") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        } else {
            EmptyStateView(icon: "music.note.list", title: "Playlist not found", message: "")
        }
    }
}

// MARK: Genre

struct GenreView: View {
    @Environment(AppModel.self) private var model
    let name: String

    var body: some View {
        let index = model.library.index
        let tracks = index.tracks(index.genreTracks[name] ?? [])
        let genre = index.genres.first { $0.name == name }
        let ctx = PlaybackContext(kind: .genre, id: name, title: name.capitalized)
        let albums = Array(Set(tracks.map(\.albumID))).compactMap { index.albums[$0] }.sorted { $0.addedAt > $1.addedAt }
        List {
            CollectionHeader(artworkURL: genre?.coverAlbumID.flatMap { model.artworkURL(albumID: $0, size: 640) },
                             title: name.capitalized, meta: Format.songs(max(tracks.count, genre?.trackCount ?? 0))) {
                if model.capabilities.contains(.genreRadio) {
                    Button { model.startRadio(.genre(name), title: "\(name.capitalized) Radio") } label: {
                        Label("Genre Radio", systemImage: "dot.radiowaves.left.and.right").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledButtonStyle(primary: true))
                }
                Button { model.play(tracks, context: ctx, shuffle: true) } label: {
                    Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle(primary: !model.capabilities.contains(.genreRadio)))
                .disabled(tracks.isEmpty)
            }
            .bareRow()
            if !albums.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) { ForEach(albums.prefix(20)) { AlbumTile(album: $0, width: 140) } }
                            .padding(.horizontal, Theme.gutter)
                    }
                    .bareRow()
                } header: { Text("Albums").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.inkHi).textCase(nil) }
            }
            Section {
                ForEach(Array(tracks.prefix(200).enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, showAlbum: true) { model.play(tracks, startAt: i, context: ctx) }.plainRow()
                }
            } header: { Text("Songs").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.inkHi).textCase(nil) }
        }
        .appList()
        .navigationTitle(name.capitalized)
        .navigationBarTitleDisplayMode(.inline)
    }
}
