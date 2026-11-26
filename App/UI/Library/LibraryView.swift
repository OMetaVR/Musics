import SwiftUI
import MusicsCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    private var index: LibraryIndex { model.library.index }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ConnectionBanner().bareRow().id("top")
                Section {
                    row(.playlists, "music.note.list", "Playlists", index.playlists.count)
                    row(.artists, "music.mic", "Artists", index.artists.count)
                    row(.albums, "square.stack", "Albums", index.albums.count)
                    row(.songs, "music.note", "Songs", index.tracks.count)
                    row(.genres, "guitars", "Genres", index.genres.count)
                    row(.liked, "heart", "Liked Songs", model.library.likes.count)
                    row(.downloads, "arrow.down.circle", "Downloaded", model.downloads.downloaded.count)
                    row(.history, "clock.arrow.circlepath", "Recently Played", nil)
                }
                if !index.albumsByAdded.isEmpty {
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 18) {
                            ForEach(index.albumsByAdded.prefix(12)) { AlbumTile(album: $0, width: nil) }
                        }
                        .padding(.horizontal, Theme.gutter)
                        .padding(.bottom, 16)
                        .bareRow()
                    } header: {
                        HStack {
                            Text("Recently Added").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.inkHi)
                            Spacer()
                            Button("See All") { model.open(.recentlyAdded) }.font(.system(size: 15)).foregroundStyle(Theme.accent)
                        }
                        .textCase(nil)
                    }
                }
                if model.library.isRefreshing {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Updating library…") }
                        .font(.system(size: 13)).foregroundStyle(Theme.ink3).bareRow().padding(.vertical, 8).frame(maxWidth: .infinity)
                }
            }
            .appList()
            .refreshable { if let s = model.session { await model.library.refresh(session: s, force: true) } }
            .onChange(of: model.scrollToTopToken[.library]) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
            }
        }
    }

    private func row(_ route: Route, _ icon: String, _ title: String, _ count: Int?) -> some View {
        Button { model.open(route) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.accent).frame(width: 28)
                Text(title).font(.system(size: 17)).foregroundStyle(Theme.ink)
                Spacer()
                if let count { Text(count.formatted()).font(.system(size: 15)).foregroundStyle(Theme.ink3) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.edge)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plainRow(top: 12, bottom: 12)
    }
}

/// A–Z index along the right edge; drag or tap to jump. Haptic tick per letter.
struct SectionIndexBar: View {
    let letters: [String]
    let onSelect: (String) -> Void
    @State private var last: String?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { l in
                    Text(l).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard !letters.isEmpty else { return }
                        let i = min(max(Int(v.location.y / geo.size.height * CGFloat(letters.count)), 0), letters.count - 1)
                        let l = letters[i]
                        if l != last {
                            last = l
                            UISelectionFeedbackGenerator().selectionChanged()
                            onSelect(l)
                        }
                    }
                    .onEnded { _ in last = nil }
            )
        }
        .frame(width: 18)
        .frame(maxHeight: min(CGFloat(letters.count) * 16, 440))
        .accessibilityHidden(true)
    }
}

struct LetterSection<Item>: Identifiable {
    let letter: String
    let items: [Item]
    var id: String { letter }
}

/// Groups items into A–Z sections by a title.
struct LetterSections<Item> {
    let letters: [String]
    let sections: [LetterSection<Item>]

    init(_ items: [Item], title: (Item) -> String) {
        var order: [String] = []
        var map: [String: [Item]] = [:]
        for item in items {
            let l = TextNormalizer.sectionLetter(title(item))
            if map[l] == nil { order.append(l) }
            map[l, default: []].append(item)
        }
        // "#" last, like Contacts and Apple Music.
        order.sort { a, b in a == "#" ? false : b == "#" ? true : a < b }
        letters = order
        sections = order.map { LetterSection(letter: $0, items: map[$0] ?? []) }
    }
}
