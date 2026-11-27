import SwiftUI
import MusicsCore

struct AlbumTile: View {
    @Environment(AppModel.self) private var model
    let album: Album
    var width: CGFloat? = 150
    var subtitle: String?

    var body: some View {
        Button { model.open(.album(album.id)) } label: {
            VStack(alignment: .leading, spacing: 7) {
                ArtworkView(url: model.artworkURL(album: album, size: 300), cornerRadius: Theme.artRadius,
                            placeholder: model.accentColor(albumID: album.id) ?? Theme.deck)
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.title).font(Typeface.cardTitle).foregroundStyle(Theme.paper).lineLimit(1)
                    Text(subtitle ?? album.artist).font(.system(size: 13)).foregroundStyle(Theme.dust).lineLimit(1)
                }
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
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
            VStack(alignment: .leading, spacing: 7) {
                ArtworkView(url: model.artworkURL(playlist: playlist, size: 300), cornerRadius: Theme.artRadius)
                VStack(alignment: .leading, spacing: 1) {
                    Text(playlist.name).font(Typeface.cardTitle).foregroundStyle(Theme.paper).lineLimit(1)
                    Text(Format.songs(playlist.trackIDs.count)).font(.system(size: 13)).foregroundStyle(Theme.dust).lineLimit(1)
                }
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
    }
}

struct ArtistTile: View {
    @Environment(AppModel.self) private var model
    let artist: Artist
    var size: CGFloat = 110

    var body: some View {
        Button { model.open(.artist(artist.id)) } label: {
            VStack(alignment: .leading, spacing: 7) {
                ArtworkView(url: (artist.albumIDs.first ?? artist.appearsOnAlbumIDs.first).flatMap { model.artworkURL(albumID: $0, size: 300) },
                            cornerRadius: size / 2)
                    .frame(width: size, height: size)
                Text(artist.name).font(Typeface.cardTitle).foregroundStyle(Theme.paper).lineLimit(1)
            }
            .frame(width: size, alignment: .leading)
        }
        .buttonStyle(PressStyle())
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
        HStack(spacing: 14) {
            ArtworkView(url: artworkURL, cornerRadius: round ? 27 : Theme.artRadius).frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16)).foregroundStyle(Theme.paper).lineLimit(1)
                HStack(spacing: 6) {
                    if let badge {
                        Text(badge).font(Typeface.condensed(12, .semibold)).foregroundStyle(Theme.dust)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(Theme.groove))
                    }
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.dust).lineLimit(1)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?
    var actionTitle = "See all"

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).sectionTitle()
            Spacer()
            if let action {
                Button(actionTitle, action: action).font(.system(size: 15)).foregroundStyle(Theme.dust)
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

/// Play / Shuffle pair at the top of every collection. Left aligned, sized to their labels.
struct PlayShuffleButtons: View {
    var play: () -> Void
    var shuffle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: play) { Label("Play", systemImage: "play.fill") }
                .buttonStyle(PillButtonStyle(primary: true))
            Button(action: shuffle) { Label("Shuffle", systemImage: "shuffle") }
                .buttonStyle(PillButtonStyle(primary: false))
        }
    }
}

/// Paper pill for the main action, deck pill for the secondary one.
struct PillButtonStyle: ButtonStyle {
    var primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.condensed(17, .bold))
            .foregroundStyle(primary ? Theme.night : Theme.paper)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(primary ? Theme.paper : Theme.deckHi, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Full-width variant, used in forms and onboarding.
struct FilledButtonStyle: ButtonStyle {
    var primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.condensed(18, .bold))
            .foregroundStyle(primary ? Theme.night : Theme.paper)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(primary ? Theme.paper : Theme.deckHi, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Slight dip on press for tiles; the only motion on browse screens.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.ash)
            Text(title).font(Typeface.condensed(26, .bold)).foregroundStyle(Theme.paper)
            if !message.isEmpty {
                Text(message).font(.system(size: 15)).foregroundStyle(Theme.dust)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(PillButtonStyle(primary: true)).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 40)
    }
}

/// Download state for a whole collection.
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
                        .progressViewStyle(.circular).tint(Theme.lan).controlSize(.small)
                } else if done == tracks.count, !tracks.isEmpty {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.lan)
                } else {
                    Image(systemName: "arrow.down.circle").foregroundStyle(Theme.dust)
                }
            }
            .font(.system(size: 24))
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel(done == tracks.count && !tracks.isEmpty ? "Remove downloads" : "Download all")
        .accessibilityValue(pending > 0 ? "\(done) of \(tracks.count) downloaded" : "")
    }
}

/// The top of album, playlist, artist and genre pages: artwork edge to edge, melting into the
/// album's own colour, with a large left-aligned condensed title.
struct SleeveHeader<Actions: View>: View {
    let artworkURL: URL?
    var tint: Color?
    var round = false
    let title: String
    var subtitle: String?
    var subtitleAction: (() -> Void)?
    var meta: String
    var note: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        let color = tint ?? Theme.sleeveFallback
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                if round {
                    color.frame(height: 260)
                    ArtworkView(url: artworkURL, cornerRadius: 110).frame(width: 220, height: 220).padding(.bottom, 20)
                } else {
                    ArtworkView(url: artworkURL, cornerRadius: 0, placeholder: color)
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [color.opacity(0), color], startPoint: .top, endPoint: .bottom)
                                .frame(height: 120)
                        }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Typeface.condensed(40, .extraBold, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.paper)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                if let subtitle {
                    Button { subtitleAction?() } label: {
                        Text(subtitle).font(Typeface.condensed(20, .semibold)).foregroundStyle(Theme.paper.opacity(0.85)).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(subtitleAction == nil)
                }
                Text(meta).font(.system(size: 14)).foregroundStyle(Theme.paper.opacity(0.6))
                if let note {
                    Text(note).font(.system(size: 13)).foregroundStyle(Theme.paper.opacity(0.6)).padding(.top, 2)
                }
                HStack(spacing: 10) { actions }.padding(.top, 12)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color)
            .overlay(alignment: .bottom) {
                // Fade the album colour back into the page so the list below doesn't sit on a hard edge.
                LinearGradient(colors: [color.opacity(0), Theme.night], startPoint: .top, endPoint: .bottom).frame(height: 18)
            }
        }
    }
}

/// Wrapping row layout (genre word cloud, chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

extension View {
    /// Standard list row styling on the app background.
    func plainRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: Theme.gutter, bottom: bottom, trailing: 8))
            .listRowBackground(Theme.night)
            .listRowSeparatorTint(Theme.groove)
    }

    func bareRow() -> some View {
        listRowInsets(EdgeInsets()).listRowBackground(Theme.night).listRowSeparator(.hidden)
    }

    /// Applied to every List in the app.
    func appList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .environment(\.defaultMinListRowHeight, 1)
    }
}
