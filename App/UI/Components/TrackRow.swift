import SwiftUI
import MusicsCore

/// A song row. Tap plays it in its context (handled by the caller); a leading swipe plays it next,
/// a trailing swipe adds it to the queue; long-press shows every action.
struct TrackRow: View {
    enum Leading { case artwork, number, none }

    @Environment(AppModel.self) private var model
    let track: Track
    var leading: Leading = .artwork
    var showAlbum = false
    var subtitleOverride: String?
    var action: () -> Void

    private var isCurrent: Bool { model.player.currentTrack?.id == track.id }
    private var unavailable: Bool {
        !(model.session?.isOnline ?? false) && !model.downloads.isAvailableOffline(track.id)
    }

    var body: some View {
        // Two independent controls in the row: the row itself and the "…" menu. Both need explicit
        // styles, or a List treats a tap anywhere as a tap on both.
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    leadingView
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(isCurrent ? Theme.accent : Theme.ink)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if model.downloads.isDownloaded(track.id) {
                                Image(systemName: "arrow.down.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.accent)
                                    .accessibilityLabel("Downloaded")
                            } else if model.downloads.state(track.id) == .downloading || model.downloads.state(track.id) == .queued {
                                ProgressView().controlSize(.mini).tint(Theme.ink3)
                            }
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.ink3).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if model.library.isLiked(track.id) {
                        Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(Theme.accent)
                            .accessibilityLabel("Liked")
                    }
                }
                .contentShape(Rectangle())
                .opacity(unavailable ? 0.4 : 1)
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityHint("Plays this song. Swipe right to play next, left to add to the queue.")

            Menu {
                TrackMenuItems(track: track)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("More actions for \(track.title)")
        }
        .contextMenu {
            TrackMenuItems(track: track)
        } preview: {
            TrackPreview(track: track)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { model.player.playNext([track]) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                .tint(Theme.accentEdge)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { model.player.addToQueue([track]) } label: { Label("Add to Queue", systemImage: "text.append") }
                .tint(Color(hex: "#3A4A5C")!)
        }
    }

    private var subtitle: String {
        if let subtitleOverride { return subtitleOverride }
        return showAlbum ? "\(track.artistLine) · \(track.albumTitle)" : track.artistLine
    }

    @ViewBuilder private var leadingView: some View {
        switch leading {
        case .artwork:
            ZStack {
                ArtworkView(url: model.artworkURL(track: track, size: 128), cornerRadius: 4).frame(width: 46, height: 46)
                if isCurrent {
                    Color.black.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 4))
                    PlayingBars(animating: model.player.isPlaying).frame(width: 16, height: 14)
                }
            }
            .frame(width: 46, height: 46)
        case .number:
            ZStack {
                if isCurrent {
                    PlayingBars(animating: model.player.isPlaying).frame(width: 14, height: 12)
                } else {
                    Text(track.trackNumber > 0 ? "\(track.trackNumber)" : "–")
                        .font(.system(size: 15, weight: .regular).monospacedDigit())
                        .foregroundStyle(Theme.ink3)
                }
            }
            .frame(width: 26)
        case .none:
            EmptyView()
        }
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Theme.cellHi : Color.clear)
    }
}

/// Every action for a song; used by context menus and the "…" button.
struct TrackMenuItems: View {
    @Environment(AppModel.self) private var model
    let track: Track

    var body: some View {
        Section {
            Button { model.player.playNext([track]) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { model.player.addToQueue([track]) } label: { Label("Add to Queue", systemImage: "text.append") }
            if model.capabilities.contains(.radio) {
                Button { model.startRadio(.track(track.id), title: "\(track.title) Radio") } label: {
                    Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
                }
            }
            if model.capabilities.contains(.adventure) {
                Button {
                    model.adventureStart = track
                    model.showAdventure = true
                } label: { Label("Sonic Adventure from Here", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            }
        }
        Section {
            let liked = model.library.isLiked(track.id)
            Button { model.toggleLike(track) } label: {
                Label(liked ? "Unlike" : "Like", systemImage: liked ? "heart.slash" : "heart")
            }
            if model.downloads.isDownloaded(track.id) {
                Button(role: .destructive) { model.removeDownloads([track]) } label: { Label("Remove Download", systemImage: "trash") }
            } else {
                Button { model.download([track]) } label: { Label("Download", systemImage: "arrow.down.circle") }
            }
        }
        Section {
            Button { model.open(.album(track.albumID)) } label: { Label("Go to Album", systemImage: "square.stack") }
            ForEach(track.artists.prefix(3), id: \.self) { name in
                Button { model.open(.artist(TextNormalizer.key(name))) } label: {
                    Label(track.artists.count > 1 ? "Go to \(name)" : "Go to Artist", systemImage: "music.mic")
                }
            }
            Button { model.infoTrack = track } label: { Label("Song Info", systemImage: "info.circle") }
        }
    }
}

struct TrackPreview: View {
    @Environment(AppModel.self) private var model
    let track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArtworkView(url: model.artworkURL(track: track, size: 640), cornerRadius: 8).frame(width: 260, height: 260)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.headline).foregroundStyle(Theme.inkHi).lineLimit(2)
                Text(track.artistLine).font(.subheadline).foregroundStyle(Theme.ink2).lineLimit(1)
                Text([track.albumTitle, track.year > 0 ? String(track.year) : nil, Format.time(track.duration)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.ink3).lineLimit(1)
            }
        }
        .padding(14)
        .background(Theme.panel)
    }
}

/// Three bars that bounce while playing.
struct PlayingBars: View {
    var animating: Bool
    var color: Color = Theme.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animating)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = animating ? (sin(t * (5 + Double(i) * 1.7) + Double(i)) + 1) / 2 : 0.35
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .scaleEffect(x: 1, y: 0.25 + 0.75 * phase, anchor: .bottom)
                }
            }
        }
        .accessibilityLabel(animating ? "Now playing" : "Paused")
    }
}
