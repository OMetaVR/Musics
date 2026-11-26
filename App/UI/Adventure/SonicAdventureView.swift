import SwiftUI
import MusicsCore

/// Pick two songs; the server walks its audio-embedding space between them and returns a path of
/// songs that morphs from one to the other.
struct SonicAdventureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State var start: Track?
    @State private var end: Track?
    @State private var steps = 14.0
    @State private var path: [Track] = []
    @State private var loading = false
    @State private var error: String?
    @State private var picking: Slot?

    enum Slot: String, Identifiable { case start, end; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    slotRow(.start, start)
                    slotRow(.end, end)
                    VStack(alignment: .leading) {
                        Text("\(Int(steps)) songs").font(.system(size: 14)).foregroundStyle(Theme.ink2)
                        Slider(value: $steps, in: 4...40, step: 1)
                    }
                    .plainRow(top: 8, bottom: 8)
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack { Text("Find the Path"); Spacer(); if loading { ProgressView() } }
                    }
                    .disabled(start == nil || end == nil || loading)
                    .plainRow(top: 12, bottom: 12)
                } footer: {
                    Text("Songs are chosen by how they sound, stepping gradually from the first song to the second.")
                        .foregroundStyle(Theme.ink3)
                }
                if let error {
                    Text(error).foregroundStyle(Theme.danger).plainRow(top: 8, bottom: 8)
                }
                if !path.isEmpty {
                    Section {
                        PlayShuffleButtons(play: { play() }, shuffle: { play(shuffle: true) })
                            .padding(.vertical, 8).plainRow()
                        ForEach(Array(path.enumerated()), id: \.element.id) { i, t in
                            TrackRow(track: t, showAlbum: true) { play(at: i) }.plainRow()
                        }
                    } header: {
                        Text("The Path").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.inkHi).textCase(nil)
                    }
                }
            }
            .appList()
            .navigationTitle("Sonic Adventure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $picking) { slot in
                TrackPicker { t in
                    if slot == .start { start = t } else { end = t }
                    path = []
                    picking = nil
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func slotRow(_ slot: Slot, _ track: Track?) -> some View {
        Button { picking = slot } label: {
            HStack(spacing: 12) {
                Text(slot == .start ? "From" : "To").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3).frame(width: 40, alignment: .leading)
                if let track {
                    ArtworkView(url: model.artworkURL(track: track, size: 128), cornerRadius: 4).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title).foregroundStyle(Theme.ink).lineLimit(1)
                        Text(track.artistLine).font(.system(size: 13)).foregroundStyle(Theme.ink3).lineLimit(1)
                    }
                } else {
                    Text("Choose a song").foregroundStyle(Theme.accent)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .plainRow(top: 8, bottom: 8)
    }

    private func generate() async {
        guard let start, let end, let session = model.session, let base = session.baseURL else {
            error = "Sonic Adventure needs a connection to the server."
            return
        }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let ids = try await session.provider.adventure(base: base, from: start.id, to: end.id, steps: Int(steps))
            path = model.library.index.tracks(ids)
            if path.isEmpty { error = "No path found between these songs." }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach the server."
        }
    }

    private func play(at i: Int = 0, shuffle: Bool = false) {
        guard let start, let end else { return }
        model.play(path, startAt: i, context: PlaybackContext(kind: .adventure, title: "\(start.title) → \(end.title)"), shuffle: shuffle)
        dismiss()
        model.showPlayer = true
    }
}

/// Searchable song picker.
struct TrackPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onPick: (Track) -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let index = model.library.index
                let tracks: [Track] = query.isEmpty
                    ? index.tracks(model.stats.stats.recentlyPlayedTracks.prefix(30).map { $0 })
                    : index.tracks(index.search.search(query, limit: 60).tracks)
                if query.isEmpty, !tracks.isEmpty {
                    Text("Recently played").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3).plainRow(top: 8, bottom: 4)
                }
                ForEach(tracks) { t in
                    Button { onPick(t) } label: {
                        HStack(spacing: 12) {
                            ArtworkView(url: model.artworkURL(track: t, size: 128), cornerRadius: 4).frame(width: 42, height: 42)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title).foregroundStyle(Theme.ink).lineLimit(1)
                                Text(t.artistLine).font(.system(size: 13)).foregroundStyle(Theme.ink3).lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .plainRow(top: 5, bottom: 5)
                }
            }
            .appList()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search songs")
            .navigationTitle("Choose a Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
