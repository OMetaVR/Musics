import SwiftUI
import MusicsCore

/// Instant on-device search over the whole library, plus "Sounds like…" audio matches from the server.
struct SearchView: View {
    enum Scope: String, CaseIterable { case all = "All", songs = "Songs", artists = "Artists", albums = "Albums", playlists = "Playlists" }

    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var results: SearchResults?
    @State private var semantic: [Track] = []
    @State private var semanticState: SemanticState = .idle

    enum SemanticState { case idle, loading, done, unavailable }

    private var index: LibraryIndex { model.library.index }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                browse
            } else if let results {
                scopePicker
                resultSections(results)
            }
        }
        .appList()
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Songs, artists, albums, moods")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onSubmit(of: .search) { model.stats.update { $0.recordSearch(query) } }
        .task(id: query) { await runSearch() }
        .task(id: query) { await runSemantic() }
    }

    // MARK: Search

    private func runSearch() async {
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { results = nil; return }
        let idx = index
        let stats = model.stats.stats
        let likes = model.library.likeSet
        let r = await Task.detached(priority: .userInitiated) {
            idx.search.search(q, limit: 60) { stats.searchBoost($0, liked: likes.contains($0)) }
        }.value
        if !Task.isCancelled, q == query { results = r }
    }

    private func runSemantic() async {
        semantic = []
        let q = query.trimmingCharacters(in: .whitespaces)
        guard model.settings.showAudioSearch, model.capabilities.contains(.semanticSearch), q.count >= 3,
              let session = model.session, let base = session.baseURL else {
            semanticState = .idle
            return
        }
        // Wait for typing to settle; the embedding search costs the server real work.
        try? await Task.sleep(nanoseconds: 550_000_000)
        guard !Task.isCancelled else { return }
        semanticState = .loading
        do {
            let hits = try await session.provider.semanticSearch(base: base, query: q, limit: 20)
            guard !Task.isCancelled else { return }
            let textIDs = Set(results?.tracks.prefix(10) ?? [])
            semantic = hits.compactMap { index.tracks[$0.id] }.filter { !textIDs.contains($0.id) }
            semanticState = .done
        } catch {
            if !Task.isCancelled { semanticState = .unavailable }
        }
    }

    // MARK: Empty state

    @ViewBuilder private var browse: some View {
        let recent = model.stats.stats.recentSearches
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.self) { s in
                    Button { query = s } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.ink3)
                            Text(s).foregroundStyle(Theme.ink)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .plainRow(top: 10, bottom: 10)
                }
                .onDelete { idx in model.stats.update { s in for i in idx.sorted(by: >) { s.recentSearches.remove(at: i) } } }
            } header: { header("Recent") }
        }
        if !index.genres.isEmpty {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(index.genres.prefix(24)) { GenreChip(genre: $0) }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 8)
                .bareRow()
            } header: { header("Browse Genres") }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.inkHi).textCase(nil)
    }

    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Scope.allCases, id: \.self) { s in
                    Button { scope = s } label: {
                        Text(s.rawValue).font(.system(size: 14, weight: .medium))
                            .foregroundStyle(scope == s ? Color.black : Theme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(scope == s ? Theme.accent : Theme.cellHi, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .padding(.vertical, 6)
        .bareRow()
    }

    // MARK: Results

    @ViewBuilder private func resultSections(_ r: SearchResults) -> some View {
        let tracks = index.tracks(r.tracks)
        if r.isEmpty && semantic.isEmpty && semanticState != .loading {
            EmptyStateView(icon: "magnifyingglass", title: "No results", message: "Nothing in your library matches “\(query)”.")
                .bareRow()
        }
        if scope == .all, let top = r.top {
            Section { topResult(top).bareRow() } header: { header("Top Result") }
        }
        if (scope == .all || scope == .songs), !tracks.isEmpty {
            Section {
                ForEach(Array(tracks.prefix(scope == .songs ? 60 : 6).enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, showAlbum: true) { playSearch(tracks, at: i) }.plainRow()
                }
            } header: { header("Songs") }
        }
        if scope == .all || scope == .artists {
            let artists = r.artists.compactMap { index.artists[$0] }
            if !artists.isEmpty {
                Section {
                    if scope == .all {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) { ForEach(artists.prefix(12)) { ArtistTile(artist: $0, size: 96) } }
                                .padding(.horizontal, Theme.gutter)
                        }
                        .bareRow()
                    } else {
                        ForEach(artists) { a in
                            Button { model.open(.artist(a.id)) } label: {
                                CollectionRow(artworkURL: a.albumIDs.first.flatMap { model.artworkURL(albumID: $0, size: 128) },
                                              title: a.name, subtitle: Format.songs(a.trackIDs.count), round: true)
                            }
                            .buttonStyle(.plain).plainRow(top: 6, bottom: 6)
                        }
                    }
                } header: { header("Artists") }
            }
        }
        if scope == .all || scope == .albums {
            let albums = r.albums.compactMap { index.albums[$0] }
            if !albums.isEmpty {
                Section {
                    if scope == .all {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) { ForEach(albums.prefix(12)) { AlbumTile(album: $0, width: 130) } }
                                .padding(.horizontal, Theme.gutter)
                        }
                        .bareRow()
                    } else {
                        ForEach(albums) { a in
                            Button { model.open(.album(a.id)) } label: {
                                CollectionRow(artworkURL: model.artworkURL(album: a, size: 128), title: a.title,
                                              subtitle: "\(a.artist)\(a.year > 0 ? " · \(a.year)" : "")")
                            }
                            .buttonStyle(.plain).plainRow(top: 6, bottom: 6)
                        }
                    }
                } header: { header("Albums") }
            }
        }
        if scope == .all || scope == .playlists {
            let lists = r.playlists.compactMap { index.playlists[$0] }
            if !lists.isEmpty {
                Section {
                    ForEach(lists) { p in
                        Button { model.open(.playlist(p.id)) } label: {
                            CollectionRow(artworkURL: model.artworkURL(playlist: p, size: 128), title: p.name, subtitle: Format.songs(p.trackIDs.count))
                        }
                        .buttonStyle(.plain).plainRow(top: 6, bottom: 6)
                    }
                } header: { header("Playlists") }
            }
        }
        if scope == .all, !r.genres.isEmpty {
            Section {
                ForEach(r.genres, id: \.self) { g in
                    Button { model.open(.genre(g)) } label: {
                        CollectionRow(artworkURL: index.genres.first { $0.name == g }?.coverAlbumID.flatMap { model.artworkURL(albumID: $0, size: 128) },
                                      title: g.capitalized, subtitle: "Genre")
                    }
                    .buttonStyle(.plain).plainRow(top: 6, bottom: 6)
                }
            } header: { header("Genres") }
        }
        if scope == .all || scope == .songs { semanticSection }
    }

    @ViewBuilder private var semanticSection: some View {
        switch semanticState {
        case .loading:
            Section {
                HStack(spacing: 10) { ProgressView().tint(Theme.ink3); Text("Listening for matches…").foregroundStyle(Theme.ink3) }
                    .font(.system(size: 14)).plainRow(top: 10, bottom: 10)
            } header: { semanticHeader }
        case .done where !semantic.isEmpty:
            Section {
                ForEach(Array(semantic.enumerated()), id: \.element.id) { i, t in
                    TrackRow(track: t, showAlbum: true) {
                        model.play(semantic, startAt: i, context: PlaybackContext(kind: .search, title: "Sounds like “\(query)”"))
                    }
                    .plainRow()
                }
            } header: { semanticHeader }
        default:
            EmptyView()
        }
    }

    private var semanticHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            header("Sounds Like “\(query)”")
            Text("Matched by listening to the audio, not the tags.").font(.system(size: 12)).foregroundStyle(Theme.ink3).textCase(nil)
        }
    }

    private func playSearch(_ tracks: [Track], at i: Int) {
        model.stats.update { $0.recordSearch(query) }
        model.play(tracks, startAt: i, context: PlaybackContext(kind: .search, title: "“\(query)”"))
    }

    @ViewBuilder private func topResult(_ top: SearchResults.Top) -> some View {
        Group {
            switch top {
            case let .track(id):
                if let t = index.tracks[id] {
                    topCard(url: model.artworkURL(track: t, size: 300), title: t.title, subtitle: "Song · \(t.artistLine)", round: false) {
                        playSearch(index.tracks(results?.tracks ?? [id]), at: max(0, results?.tracks.firstIndex(of: id) ?? 0))
                    }
                }
            case let .album(id):
                if let a = index.albums[id] {
                    topCard(url: model.artworkURL(album: a, size: 300), title: a.title, subtitle: "Album · \(a.artist)", round: false) {
                        model.open(.album(id))
                    }
                }
            case let .artist(id):
                if let a = index.artists[id] {
                    topCard(url: a.albumIDs.first.flatMap { model.artworkURL(albumID: $0, size: 300) }, title: a.name,
                            subtitle: "Artist · \(Format.songs(a.trackIDs.count))", round: true) { model.open(.artist(id)) }
                }
            case let .playlist(id):
                if let p = index.playlists[id] {
                    topCard(url: model.artworkURL(playlist: p, size: 300), title: p.name, subtitle: "Playlist", round: false) {
                        model.open(.playlist(id))
                    }
                }
            case let .genre(name):
                topCard(url: index.genres.first { $0.name == name }?.coverAlbumID.flatMap { model.artworkURL(albumID: $0, size: 300) },
                        title: name.capitalized, subtitle: "Genre", round: false) { model.open(.genre(name)) }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 6)
    }

    private func topCard(url: URL?, title: String, subtitle: String, round: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ArtworkView(url: url, cornerRadius: round ? 40 : 6).frame(width: 80, height: 80)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.inkHi).lineLimit(2)
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.ink3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }
}
