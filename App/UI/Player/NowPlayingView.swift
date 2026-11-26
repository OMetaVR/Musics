import AVKit
import MediaPlayer
import SwiftUI
import MusicsCore

struct NowPlayingView: View {
    enum Pane { case artwork, lyrics, queue }

    @Environment(AppModel.self) private var model
    @Binding var dragOffset: CGFloat
    @State private var pane: Pane = .artwork
    @State private var computedAccent: Color?

    private var player: PlaybackController { model.player }

    var body: some View {
        let track = player.currentTrack
        let bg = model.accentColor(albumID: track?.albumID) ?? computedAccent ?? Theme.nowPlayingFallback
        GeometryReader { geo in
            VStack(spacing: 0) {
                header(track)
                    .contentShape(Rectangle())
                    .gesture(dismissDrag)
                Group {
                    switch pane {
                    case .artwork:
                        artworkPane(track, width: geo.size.width)
                            .contentShape(Rectangle())
                            .gesture(dismissDrag)
                    case .lyrics:
                        compactHeader(track)
                        if let track { LyricsView(track: track).id(track.id) }
                    case .queue:
                        compactHeader(track)
                        QueueView()
                    }
                }
                .frame(maxHeight: .infinity)
                controls(track)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 12))
            }
            .padding(.top, geo.safeAreaInsets.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(bg.ignoresSafeArea())
            .background(Theme.bg.ignoresSafeArea())
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.25), value: pane)
        .task(id: track?.albumID) { await loadAccent(track) }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in if v.translation.height > 0 { dragOffset = v.translation.height } }
            .onEnded { v in
                if v.translation.height > 140 || v.predictedEndTranslation.height > 400 {
                    model.showPlayer = false
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { dragOffset = 0 }
            }
    }

    private func loadAccent(_ track: Track?) async {
        guard let track, model.accentColor(albumID: track.albumID) == nil, let url = model.artworkURL(track: track, size: 300),
              let img = await ArtworkLoader.shared.image(for: url) else { return }
        computedAccent = Color(uiColor: ArtworkLoader.shared.accentColor(for: url, image: img))
    }

    // MARK: Header

    @ViewBuilder private func header(_ track: Track?) -> some View {
        VStack(spacing: 6) {
            Capsule().fill(Color.white.opacity(0.35)).frame(width: 38, height: 5).padding(.top, 8)
            HStack {
                Button { model.showPlayer = false } label: {
                    Image(systemName: "chevron.down").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close player")
                Spacer()
                VStack(spacing: 1) {
                    if let ctx = player.queue.contextInfo {
                        Text(contextLabel(ctx)).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.65))
                        Text(ctx.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                }
                .onTapGesture { openContext() }
                Spacer()
                Menu { moreMenu(track) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("More")
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
        }
    }

    private func contextLabel(_ ctx: PlaybackContext) -> String {
        switch ctx.kind {
        case .album: return "Playing from album"
        case .playlist: return "Playing from playlist"
        case .artist: return "Playing from artist"
        case .genre: return "Playing from genre"
        case .radio: return "Playing radio"
        case .adventure: return "Sonic Adventure"
        case .liked: return "Playing from"
        case .downloads: return "Playing from"
        case .search: return "Playing from search"
        case .songs, .queue: return "Playing from"
        }
    }

    private func openContext() {
        guard let ctx = player.queue.contextInfo, let id = ctx.id else { return }
        switch ctx.kind {
        case .album: model.open(.album(id))
        case .playlist: model.open(.playlist(id))
        case .artist: model.open(.artist(id))
        case .genre: model.open(.genre(id))
        default: break
        }
    }

    @ViewBuilder private func moreMenu(_ track: Track?) -> some View {
        if let track {
            TrackMenuItems(track: track)
        }
        Section("Sleep timer") {
            if player.sleepTimer != nil {
                Button(role: .destructive) { player.setSleepTimer(minutes: nil) } label: { Label("Turn Off Sleep Timer", systemImage: "moon.zzz") }
            }
            ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                Button("\(m) minutes") { player.setSleepTimer(minutes: m) }
            }
            Button("End of song") { player.sleepAtEndOfTrack() }
        }
    }

    // MARK: Panes

    @ViewBuilder private func artworkPane(_ track: Track?, width: CGFloat) -> some View {
        let side = min(width - 48, 420)
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            ArtworkView(url: track.flatMap { model.artworkURL(track: $0, size: 640) }, cornerRadius: 10, placeholder: Color.black.opacity(0.2))
                .frame(width: side, height: side)
                .shadow(color: .black.opacity(0.35), radius: player.isPlaying ? 24 : 10, y: 12)
                .scaleEffect(player.isPlaying ? 1 : 0.86)
                .animation(.spring(response: 0.45, dampingFraction: 0.72), value: player.isPlaying)
                .onTapGesture { if track?.hasEmbeddedLyrics == true || model.capabilities.contains(.lyrics) { pane = .lyrics } }
                .accessibilityLabel("Artwork. Double-tap for lyrics.")
            Spacer(minLength: 16)
            titleRow(track).padding(.horizontal, 24)
        }
    }

    @ViewBuilder private func compactHeader(_ track: Track?) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.flatMap { model.artworkURL(track: $0, size: 128) }, cornerRadius: 5).frame(width: 54, height: 54)
                .onTapGesture { pane = .artwork }
            titleRow(track)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    @ViewBuilder private func titleRow(_ track: Track?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(track?.title ?? "").font(.system(size: 21, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Button {
                    if let a = track?.primaryArtist { model.open(.artist(TextNormalizer.key(a))) }
                } label: {
                    Text(track?.artistLine ?? "").font(.system(size: 17)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            if let track {
                let liked = model.library.isLiked(track.id)
                Button { model.toggleLike(track) } label: {
                    Image(systemName: liked ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundStyle(liked ? Theme.accent : Color.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .symbolEffect(.bounce, value: liked)
                }
                .accessibilityLabel(liked ? "Unlike" : "Like")
            }
        }
    }

    // MARK: Controls

    @ViewBuilder private func controls(_ track: Track?) -> some View {
        VStack(spacing: 14) {
            if pane == .artwork { Color.clear.frame(height: 0) }
            Scrubber(position: player.position, duration: player.duration) { player.seek(to: $0) }
                .padding(.horizontal, 24)
            HStack {
                Button { player.setShuffle(!player.queue.shuffle) } label: {
                    Image(systemName: "shuffle").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(player.queue.shuffle ? Theme.accent : Color.white.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Shuffle")
                .accessibilityValue(player.queue.shuffle ? "On" : "Off")
                Spacer()
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 28)).frame(width: 60, height: 60)
                }
                .accessibilityLabel("Previous")
                Spacer()
                Button { player.togglePlay() } label: {
                    ZStack {
                        Circle().fill(Color.white).frame(width: 72, height: 72)
                        if player.isBuffering {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 30)).foregroundStyle(Color.black)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Spacer()
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 28)).frame(width: 60, height: 60)
                }
                .accessibilityLabel("Next")
                Spacer()
                Button { player.cycleRepeat() } label: {
                    Image(systemName: player.queue.repeatMode == .one ? "repeat.1" : "repeat").font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(player.queue.repeatMode == .off ? Color.white.opacity(0.6) : Theme.accent)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Repeat")
                .accessibilityValue(player.queue.repeatMode.rawValue)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)

            if pane == .artwork {
                VolumeSlider().frame(height: 34).padding(.horizontal, 24)
            }

            HStack {
                paneButton(.lyrics, icon: "quote.bubble", label: "Lyrics")
                Spacer()
                AirPlayButton().frame(width: 44, height: 44)
                Spacer()
                if let remaining = player.sleepRemaining {
                    Text(Format.time(remaining)).font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Spacer()
                } else if player.sleepTimer == .endOfTrack {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.accent)
                    Spacer()
                }
                paneButton(.queue, icon: "list.bullet", label: "Queue")
            }
            .padding(.horizontal, 36)
        }
        .buttonStyle(.plain)
    }

    private func paneButton(_ target: Pane, icon: String, label: String) -> some View {
        Button { pane = pane == target ? .artwork : target } label: {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(pane == target ? Color.black : Color.white.opacity(0.8))
                .frame(width: 40, height: 34)
                .background(pane == target ? Color.white.opacity(0.85) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(pane == target ? .isSelected : [])
    }
}

/// Follows the finger while dragging and seeks on release; thickens while held.
struct Scrubber: View {
    let position: Double
    let duration: Double
    var onSeek: (Double) -> Void
    @State private var dragValue: Double?

    var body: some View {
        let shown = dragValue ?? position
        let fraction = duration > 0 ? min(max(shown / duration, 0), 1) : 0
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule().fill(Color.white.opacity(dragValue == nil ? 0.85 : 1))
                        .frame(width: geo.size.width * fraction)
                }
                .frame(height: dragValue == nil ? 5 : 9)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard duration > 0 else { return }
                            dragValue = min(max(v.location.x / geo.size.width, 0), 1) * duration
                        }
                        .onEnded { _ in
                            if let d = dragValue { onSeek(d) }
                            dragValue = nil
                        }
                )
                .animation(.easeOut(duration: 0.15), value: dragValue == nil)
            }
            .frame(height: 22)
            HStack {
                Text(Format.time(shown))
                Spacer()
                Text("-" + Format.time(max(0, duration - shown)))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.6))
        }
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(Format.time(position)) of \(Format.time(duration))")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: onSeek(position + 15)
            case .decrement: onSeek(position - 15)
            @unknown default: break
            }
        }
    }
}

struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        v.tintColor = .white
        v.setVolumeThumbImage(UIImage(systemName: "circle.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor.white.withAlphaComponent(0.8)
        v.activeTintColor = UIColor(Theme.accent)
        v.prioritizesVideoDevices = false
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
