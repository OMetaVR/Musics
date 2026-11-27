import SwiftUI
import MusicsCore

// MARK: Songs

struct SongsView: View {
    enum Sort: String, CaseIterable { case title = "Title", artist = "Artist", added = "Recently Added", plays = "Most Played" }

    @Environment(AppModel.self) private var model
    @State private var sort: Sort = .title
    @State private var filter = ""
    @State private var sorted: [Track] = []
    @State private var groups = LetterSections<Track>([], title: { $0.title })

    var body: some View {
        let ctx = PlaybackContext(kind: .songs, title: "Songs")
        ScrollViewReader { proxy in
            List {
                PlayShuffleButtons(play: { model.play(sorted, context: ctx) },
                                   shuffle: { model.play(sorted, context: ctx, shuffle: true) })
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 8).bareRow()
                if sort == .title && filter.isEmpty {
                    ForEach(groups.sections) { section in
                        Section {
                            ForEach(section.items) { t in
                                TrackRow(track: t) { playFrom(t, ctx) }.plainRow()
                            }
                        } header: { letterHeader(section.letter) }
                        .id("sec-\(section.letter)")
                    }
                } else {
                    ForEach(sorted) { t in TrackRow(track: t, subtitleOverride: subtitle(t)) { playFrom(t, ctx) }.plainRow() }
                }
            }
            .appList()
            .overlay(alignment: .trailing) {
                if sort == .title && filter.isEmpty {
                    SectionIndexBar(letters: groups.letters) { l in
                        proxy.scrollTo("sec-\(l)", anchor: .top)
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .navigationTitle("Songs")
        .searchable(text: $filter, prompt: "Filter songs")
        .toolbar { sortMenu }
        .task(id: "\(sort.rawValue)|\(filter)|\(model.library.index.snapshot.version)") { resort() }
    }

    private func subtitle(_ t: Track) -> String? {
        switch sort {
        case .plays:
            let n = model.stats.stats.plays(t.id)
            return "\(t.artistLine), \(n) play\(n == 1 ? "" : "s")"
        case .added: return "\(t.artistLine), \(t.addedAt.formatted(date: .abbreviated, time: .omitted))"
        default: return nil
        }
    }

    private func playFrom(_ t: Track, _ ctx: PlaybackContext) {
        model.play(sorted, startAt: sorted.firstIndex { $0.id == t.id }, context: ctx)
    }

    private func resort() {
        let index = model.library.index
        var base = index.tracksByTitle
        if !filter.isEmpty {
            let hits = Set(index.search.search(filter, limit: 2000).tracks)
            base = base.filter { hits.contains($0.id) }
        }
        defer { groups = sort == .title && filter.isEmpty ? LetterSections(sorted) { $0.title } : LetterSections([], title: { $0.title }) }
        switch sort {
        case .title: sorted = base
        case .artist: sorted = base.sorted { (TextNormalizer.sortKey($0.primaryArtist), $0.albumTitle, $0.discNumber, $0.trackNumber) <
                                             (TextNormalizer.sortKey($1.primaryArtist), $1.albumTitle, $1.discNumber, $1.trackNumber) }
        case .added: sorted = base.sorted { $0.addedAt > $1.addedAt }
        case .plays:
            let stats = model.stats.stats
            sorted = base.filter { stats.plays($0.id) > 0 }.sorted { stats.plays($0.id) > stats.plays($1.id) }
        }
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) } }
            } label: { Image(systemName: "arrow.up.arrow.down") }
            .accessibilityLabel("Sort")
        }
    }
}

func letterHeader(_ letter: String) -> some View {
    Text(letter).font(Typeface.condensed(19, .extraBold)).foregroundStyle(Theme.dust).textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
}

// MARK: Albums

struct AlbumsView: View {
    enum Sort: String, CaseIterable { case added = "Recently Added", title = "Title", artist = "Artist", year = "Year" }

    @Environment(AppModel.self) private var model
    @State private var sort: Sort
    @State private var filter = ""
    @State private var albums: [Album] = []

    init(sortByAdded: Bool) { _sort = State(initialValue: sortByAdded ? .added : .title) }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], alignment: .leading, spacing: 20) {
                ForEach(albums) { a in
                    AlbumTile(album: a, width: nil, subtitle: sort == .year && a.year > 0 ? "\(a.artist), \(a.year)" : nil)
                }
            }
            .padding(Theme.gutter)
        }
        .background(Theme.bg)
        .navigationTitle(sort == .added ? "Recently Added" : "Albums")
        .searchable(text: $filter, prompt: "Filter albums")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) } }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
        }
        .task(id: "\(sort.rawValue)|\(filter)|\(model.library.index.snapshot.version)") { resort() }
    }

    private func resort() {
        let index = model.library.index
        var base: [Album]
        switch sort {
        case .added: base = index.albumsByAdded
        case .title: base = index.albumsByTitle
        case .artist: base = index.albumsByTitle.sorted { (TextNormalizer.sortKey($0.artist), $0.year) < (TextNormalizer.sortKey($1.artist), $1.year) }
        case .year: base = index.albumsByAdded.sorted { $0.year > $1.year }
        }
        if !filter.isEmpty {
            let hits = Set(index.search.search(filter, limit: 500).albums)
            let byArtist = Set(index.search.search(filter, limit: 50).artists)
            base = base.filter { hits.contains($0.id) || byArtist.contains(TextNormalizer.key($0.artist)) }
        }
        albums = base
    }
}

// MARK: Artists

struct ArtistsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var albumArtistsOnly = true

    var body: some View {
        let all = model.library.index.artistsByName.filter { !albumArtistsOnly || !$0.albumIDs.isEmpty }
        let shown = filter.isEmpty ? all : {
            let hits = Set(model.library.index.search.search(filter, limit: 300).artists)
            return all.filter { hits.contains($0.id) }
        }()
        let groups = LetterSections(shown) { $0.name }
        ScrollViewReader { proxy in
            List {
                ForEach(groups.sections) { section in
                    Section {
                        ForEach(section.items) { a in
                            Button { model.open(.artist(a.id)) } label: {
                                CollectionRow(artworkURL: (a.albumIDs.first ?? a.appearsOnAlbumIDs.first).flatMap { model.artworkURL(albumID: $0, size: 128) },
                                              title: a.name, subtitle: artistSubtitle(a), round: true)
                            }
                            .buttonStyle(.plain).plainRow(top: 5, bottom: 5)
                        }
                    } header: { letterHeader(section.letter) }
                    .id("sec-\(section.letter)")
                }
            }
            .appList()
            .overlay(alignment: .trailing) {
                if filter.isEmpty {
                    SectionIndexBar(letters: groups.letters) { proxy.scrollTo("sec-\($0)", anchor: .top) }.padding(.trailing, 2)
                }
            }
        }
        .navigationTitle("Artists")
        .searchable(text: $filter, prompt: "Filter artists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Album Artists Only", isOn: $albumArtistsOnly)
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            }
        }
    }

    private func artistSubtitle(_ a: Artist) -> String {
        let albums = a.albumIDs.count
        return albums > 0 ? "\(albums) album\(albums == 1 ? "" : "s"), \(Format.songs(a.trackIDs.count))" : Format.songs(a.trackIDs.count)
    }
}

// MARK: Playlists

struct PlaylistsView: View {
    @Environment(AppModel.self) private var model
    @State private var byRecent = false

    var body: some View {
        let lists = byRecent ? model.library.index.playlistsByName.sorted { $0.modifiedAt > $1.modifiedAt } : model.library.index.playlistsByName
        List {
            if lists.isEmpty {
                EmptyStateView(icon: "music.note.list", title: "No playlists",
                               message: model.session?.profile.kind == .musicLan
                                   ? "Put .m3u8 files or spotDL exports in the music folder and they appear here."
                                   : "Playlists made on the server appear here.")
                    .bareRow()
            }
            ForEach(lists) { p in
                Button { model.open(.playlist(p.id)) } label: {
                    CollectionRow(artworkURL: model.artworkURL(playlist: p, size: 128), title: p.name,
                                  subtitle: p.missingCount > 0 ? "\(p.trackIDs.count) of \(p.total) songs" : Format.songs(p.trackIDs.count),
                                  badge: p.source == .spotify ? "Spotify" : p.source == .m3u ? "M3U" : nil)
                }
                .buttonStyle(.plain).plainRow(top: 5, bottom: 5)
            }
        }
        .appList()
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $byRecent) {
                        Text("Name").tag(false)
                        Text("Recently Updated").tag(true)
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
        }
    }
}

// MARK: Genres

struct GenresView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach(model.library.index.genres) { GenreChip(genre: $0) }
            }
            .padding(Theme.gutter)
        }
        .background(Theme.bg)
        .navigationTitle("Genres")
    }
}

// MARK: Liked / Downloads / History

struct LikedSongsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tracks = model.library.likedTracks
        let ctx = PlaybackContext(kind: .liked, title: "Liked Songs")
        List {
            if tracks.isEmpty {
                EmptyStateView(icon: "heart", title: "No liked songs", message: "Tap the heart on any song to keep it here.").bareRow()
            } else {
                HStack(spacing: 12) {
                    PlayShuffleButtons(play: { model.play(tracks, context: ctx) }, shuffle: { model.play(tracks, context: ctx, shuffle: true) })
                    CollectionDownloadButton(tracks: tracks)
                }
                .padding(.horizontal, Theme.gutter).padding(.vertical, 8).bareRow()
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t) { model.play(tracks, startAt: i, context: ctx) }.plainRow()
                }
            }
        }
        .appList()
        .navigationTitle("Liked Songs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Download Liked Songs Automatically", isOn: Bindable(model.settings).autoDownloadLiked)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }
}

struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmRemoveAll = false

    var body: some View {
        let index = model.library.index
        let tracks = model.downloads.downloaded.sorted { $0.value.date > $1.value.date }.compactMap { index.tracks[$0.key] }
        let ctx = PlaybackContext(kind: .downloads, title: "Downloads")
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Format.songs(tracks.count)), \(Format.bytes(model.downloads.downloadedBytes))")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                        Text("Smart cache: \(Format.bytes(model.downloads.cachedBytes)) of recently played and upcoming songs")
                            .font(.system(size: 12)).foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    if model.downloads.pendingCount > 0 {
                        Label("\(model.downloads.pendingCount)", systemImage: "arrow.down").font(.system(size: 13)).foregroundStyle(Theme.accent)
                    }
                }
                .plainRow(top: 10, bottom: 10)
            }
            if tracks.isEmpty {
                EmptyStateView(icon: "arrow.down.circle", title: "No downloads",
                               message: "Download songs, albums or playlists to play them without a connection.").bareRow()
            } else {
                PlayShuffleButtons(play: { model.play(tracks, context: ctx) }, shuffle: { model.play(tracks, context: ctx, shuffle: true) })
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 8).bareRow()
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, showAlbum: true) { model.play(tracks, startAt: i, context: ctx) }.plainRow()
                }
                .onDelete { idx in model.removeDownloads(idx.map { tracks[$0] }) }
            }
        }
        .appList()
        .navigationTitle("Downloaded")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { model.downloads.retryFailed() } label: { Label("Retry Failed", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { confirmRemoveAll = true } label: { Label("Remove All Downloads", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Remove all \(tracks.count) downloads?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Remove All", role: .destructive) { model.downloads.removeAllDownloads() }
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.stats.stats
        let tracks = model.library.index.tracks(stats.recentlyPlayedTracks)
        List {
            if tracks.isEmpty {
                EmptyStateView(icon: "clock", title: "Nothing played yet", message: "Songs you listen to show up here.").bareRow()
            }
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                TrackRow(track: t, subtitleOverride: "\(t.artistLine), \(relative(stats.tracks[t.id]?.lastPlayed))") {
                    model.play(tracks, startAt: i, context: PlaybackContext(kind: .songs, title: "Recently Played"))
                }
                .plainRow()
            }
        }
        .appList()
        .navigationTitle("Recently Played")
    }

    private func relative(_ d: Date?) -> String {
        guard let d else { return "" }
        return d.formatted(.relative(presentation: .named))
    }
}
