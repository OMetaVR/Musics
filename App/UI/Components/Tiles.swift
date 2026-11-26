import SwiftUI
import MusicsCore

struct AlbumTile: View {
    @Environment(AppModel.self) private var model
    let album: Album
    var width: CGFloat? = 150
    var subtitle: String?

    var body: some View {
        Button { model.open(.album(album.id)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkView(url: model.artworkURL(album: album, size: 300), cornerRadius: 6,
                            placeholder: model.accentColor(albumID: album.id) ?? Theme.cell)
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(subtitle ?? album.artist).font(.system(size: 13)).foregroundStyle(Theme.ink3).lineLimit(1)
                }
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { AlbumMenuItems(album: album) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.title), \(album.artist)")
    }
}

struct AlbumMenuItems: View {
    @Environment(AppModel.self) private var model
    let album: Album

    var body: some View {
        let tracks = model.library.index.albumTracks(album.id)
        Button { model.play(tracks, context: PlaybackContext(kind: .album, id: album.id, title: album.title)) } label: {
            Label("Play", systemImage: "play")
        }
        Button { model.play(tracks, context: PlaybackContext(kind: .album, id: album.id, title: album.title), shuffle: true) } label: {
            Label("Shuffle", systemImage: "shuffle")
        }
        Button { model.player.playNext(tracks) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { model.player.addToQueue(tracks) } label: { Label("Add to Queue", systemImage: "text.append") }
        Button { model.download(tracks) } label: { Label("Download", systemImage: "arrow.down.circle") }
        Button { model.open(.artist(TextNormalizer.key(album.artist))) } label: { Label("Go to Artist", systemImage: "music.mic") }
    }
}

struct PlaylistTile: View {
    @Environment(AppModel.self) private var model
    let playlist: Playlist
    var width: CGFloat? = 150

    var body: some View {
        Button { model.open(.playlist(playlist.id)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkView(url: model.artworkURL(playlist: playlist, size: 300), cornerRadius: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(playlist.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(Format.songs(playlist.trackIDs.count)).font(.system(size: 13)).foregroundStyle(Theme.ink3).lineLimit(1)
                }
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct ArtistTile: View {
    @Environment(AppModel.self) private var model
    let artist: Artist
    var size: CGFloat = 110

    var body: some View {
        Button { model.open(.artist(artist.id)) } label: {
            VStack(spacing: 6) {
                ArtworkView(url: (artist.albumIDs.first ?? artist.appearsOnAlbumIDs.first).flatMap { model.artworkURL(albumID: $0, size: 300) },
                            cornerRadius: size / 2)
                    .frame(width: size, height: size)
                Text(artist.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            .frame(width: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(artist.name)
    }
}

/// Row used in lists of albums, artists, playlists and genres.
struct CollectionRow: View {
    let artworkURL: URL?
    let title: String
    let subtitle: String
    var round = false
    var badge: String?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: artworkURL, cornerRadius: round ? 27 : 4).frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16)).foregroundStyle(Theme.ink).lineLimit(1)
                HStack(spacing: 6) {
                    if let badge {
                        Text(badge).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.cellHi, in: RoundedRectangle(cornerRadius: 3))
                    }
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.ink3).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.edge)
        }
        .contentShape(Rectangle())
    }
}

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?
    var actionTitle = "See All"

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).sectionTitle()
            Spacer()
            if let action {
                Button(actionTitle, action: action).font(.system(size: 15)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

/// The Play / Shuffle pair at the top of every collection.
struct PlayShuffleButtons: View {
    var play: () -> Void
    var shuffle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledButtonStyle(primary: true))
            Button(action: shuffle) {
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledButtonStyle(primary: false))
        }
    }
}

struct FilledButtonStyle: ButtonStyle {
    var primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(primary ? Color.black : Theme.accent)
            .padding(.vertical, 12)
            .background(primary ? Theme.accent : Theme.cellHi, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(primary ? Color.clear : Theme.line))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(Theme.ink3)
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(message).font(.system(size: 14)).foregroundStyle(Theme.ink3).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(FilledButtonStyle(primary: true)).frame(maxWidth: 220).padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Download state for a whole collection, as a toolbar-style button.
struct CollectionDownloadButton: View {
    @Environment(AppModel.self) private var model
    let tracks: [Track]

    var body: some View {
        let done = tracks.filter { model.downloads.isDownloaded($0.id) }.count
        let pending = tracks.filter { model.downloads.state($0.id) == .queued || model.downloads.state($0.id) == .downloading }.count
        Button {
            if done == tracks.count { model.removeDownloads(tracks) } else { model.download(tracks) }
        } label: {
            Group {
                if pending > 0 {
                    ProgressView(value: Double(done), total: Double(max(tracks.count, 1)))
                        .progressViewStyle(.circular).tint(Theme.accent).controlSize(.small)
                } else if done == tracks.count, !tracks.isEmpty {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
                } else {
                    Image(systemName: "arrow.down.circle").foregroundStyle(Theme.ink2)
                }
            }
            .font(.system(size: 22))
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel(done == tracks.count && !tracks.isEmpty ? "Remove downloads" : "Download all")
        .accessibilityValue(pending > 0 ? "\(done) of \(tracks.count) downloaded" : "")
    }
}

extension View {
    /// Standard list row styling on the app background.
    func plainRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: Theme.gutter, bottom: bottom, trailing: 8))
            .listRowBackground(Theme.bg)
            .listRowSeparatorTint(Theme.line)
    }

    func bareRow() -> some View {
        listRowInsets(EdgeInsets()).listRowBackground(Theme.bg).listRowSeparator(.hidden)
    }

    /// Applied to every List in the app.
    func appList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .environment(\.defaultMinListRowHeight, 1)
    }
}
