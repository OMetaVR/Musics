import SwiftUI
import MusicsCore

struct SongInfoView: View {
    @Environment(AppModel.self) private var model
    let track: Track

    var body: some View {
        let stats = model.stats.stats.tracks[track.id]
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ArtworkView(url: model.artworkURL(track: track, size: 300), cornerRadius: Theme.artRadius).frame(width: 84, height: 84)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.inkHi)
                            Text(track.artistLine).foregroundStyle(Theme.ink2)
                        }
                    }
                    .listRowBackground(Theme.panel)
                }
                Section("Details") {
                    row("Album", track.albumTitle)
                    row("Album artist", track.albumArtist)
                    if track.trackNumber > 0 { row("Track", track.discNumber > 1 ? "\(track.discNumber)-\(track.trackNumber)" : "\(track.trackNumber)") }
                    if track.year > 0 { row("Year", String(track.year)) }
                    row("Length", Format.time(track.duration))
                    if !track.genres.isEmpty { row("Genres", track.genres.map(\.capitalized).joined(separator: ", ")) }
                    row("Format", [track.format.uppercased(), track.bitRate.map { "\($0) kbit/s" }].compactMap { $0 }.joined(separator: ", "))
                    if track.addedAt.timeIntervalSince1970 > 0 { row("Added", track.addedAt.formatted(date: .abbreviated, time: .omitted)) }
                }
                Section("You") {
                    row("Plays", "\(stats?.plays ?? 0)")
                    if let last = stats?.lastPlayed { row("Last played", last.formatted(.relative(presentation: .named))) }
                    if let skips = stats?.skips, skips > 0 { row("Skipped early", "\(skips)") }
                    row("Liked", model.library.isLiked(track.id) ? "Yes" : "No")
                    row("Offline", model.downloads.isDownloaded(track.id) ? "Downloaded"
                        : model.downloads.isAvailableOffline(track.id) ? "In smart cache" : "No")
                }
                Section {
                    row("ID", track.id)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Song Info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).foregroundStyle(Theme.ink2).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .listRowBackground(Theme.panel)
    }
}
