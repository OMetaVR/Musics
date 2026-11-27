import AVKit
import SwiftUI
import MusicsCore

/// The sleeve: artwork edge to edge, melting into the album's colour, with the title set large in the
/// condensed face. Pausing dims the sleeve. Lyrics and Up next replace the artwork; the transport stays put.
struct NowPlayingView: View {
    enum Pane { case artwork, lyrics, queue }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var dragOffset: CGFloat
    @State private var pane: Pane = .artwork
    @State private var sampled: Color?

    private var player: PlaybackController { model.player }

    var body: some View {
        let track = player.currentTrack
        let tint = model.accentColor(albumID: track?.albumID) ?? sampled ?? Theme.sleeveFallback
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            let bottom = max(geo.safeAreaInsets.bottom, 14)
            let width = geo.size.width
            let fullHeight = geo.size.height + top + geo.safeAreaInsets.bottom
            // Leave room for the title, scrubber, transport and tabs; crop the art on short phones.
            let artHeight = min(width, max(fullHeight - 370, width * 0.7))
            VStack(spacing: 0) {
                if pane == .artwork {
                    sleeve(track, tint: tint, width: width, height: artHeight, top: top)
                    titleBlock(track)
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 2)
                        .contentShape(Rectangle())
                        .gesture(dismissDrag)
                    Spacer(minLength: 8)
                } else {
                    compactHeader(track, top: top)
                    Group {
                        if pane == .lyrics, let track { LyricsView(track: track).id(track.id) }
                        if pane == .queue { QueueView() }
                    }
                    .frame(maxHeight: .infinity)
                }
                controls(track)
                    .padding(.bottom, bottom)
            }
            .frame(width: width, height: fullHeight)
            .background(tint)
            .ignoresSafeArea()
        }
        .background(tint.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: tint)
        .animation(.snappy(duration: 0.3), value: pane)
        .task(id: track?.albumID) { sampled = await SleeveColor.sample(model, track) }
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

    // MARK: Sleeve

    @ViewBuilder private func sleeve(_ track: Track?, tint: Color, width: CGFloat, height: CGFloat, top: CGFloat) -> some View {
        let playing = player.isPlaying
        ZStack(alignment: .top) {
            ArtworkView(url: track.flatMap { model.artworkURL(track: $0, size: 640) }, cornerRadius: 0, placeholder: tint)
                .frame(width: width, height: width)
                .frame(width: width, height: height, alignment: .center)
                .clipped()
                // Paused: the sleeve goes quiet instead of shrinking.
                .saturation(playing ? 1 : 0.3)
                .brightness(playing ? 0 : -0.14)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: playing)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [tint.opacity(0), tint], startPoint: .top, endPoint: .bottom).frame(height: height * 0.32)
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: top + 70)
                }
                .onTapGesture { if model.capabilities.contains(.lyrics) { pane = .lyrics } }
                .accessibilityLabel(playing ? "Artwork" : "Artwork, paused")
                .accessibilityHint("Shows lyrics")
            topBar.padding(.top, top)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(dismissDrag)
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Button { model.showPlayer = false } label: {
                Image(systemName: "chevron.down").font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close player")
            Spacer(minLength: 8)
            if let ctx = player.queue.contextInfo {
                Button { openContext() } label: {
                    VStack(spacing: 0) {
                        Text(contextLabel(ctx)).font(.system(size: 12)).foregroundStyle(Theme.paper.opacity(0.7))
                        Text(ctx.title).font(Typeface.condensed(16, .bold)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Menu { moreMenu(player.currentTrack) } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("More")
        }
        .foregroundStyle(Theme.paper)
        .padding(.horizontal, 8)
    }

    @ViewBuilder private func titleBlock(_ track: Track?) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track?.title ?? "")
                    .font(Typeface.condensed(44, .extraBold, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.paper)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                Button {
                    if let a = track?.primaryArtist { model.open(.artist(TextNormalizer.key(a))) }
                } label: {
                    Text(track?.artistLine ?? "")
                        .font(Typeface.condensed(21, .semibold))
                        .foregroundStyle(Theme.paper.opacity(0.75))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            likeButton(track)
        }
    }

    @ViewBuilder private func likeButton(_ track: Track?) -> some View {
        if let track {
            let liked = model.library.isLiked(track.id)
            Button { model.toggleLike(track) } label: {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(liked ? Theme.lan : Theme.paper.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .symbolEffect(.bounce, value: liked)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(liked ? "Unlike" : "Like")
        }
    }

    @ViewBuilder private func compactHeader(_ track: Track?, top: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 12) {
                ArtworkView(url: track.flatMap { model.artworkURL(track: $0, size: 128) }, cornerRadius: Theme.artRadius)
                    .frame(width: 52, height: 52)
                    .onTapGesture { pane = .artwork }
                VStack(alignment: .leading, spacing: 0) {
                    Text(track?.title ?? "").font(Typeface.condensed(24, .extraBold)).foregroundStyle(Theme.paper).lineLimit(1)
                    Text(track?.artistLine ?? "").font(Typeface.condensed(17, .semibold)).foregroundStyle(Theme.paper.opacity(0.7)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                likeButton(track)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 8)
        }
        .padding(.top, top)
        .contentShape(Rectangle())
        .gesture(dismissDrag)
    }

    private func contextLabel(_ ctx: PlaybackContext) -> String {
        switch ctx.kind {
        case .album: return "Playing from album"
        case .playlist: return "Playing from playlist"
        case .artist: return "Playing from artist"
        case .genre: return "Playing from genre"
        case .radio: return "Radio"
        case .adventure: return "Sonic Adventure"
        case .search: return "Playing from search"
        case .liked, .downloads, .songs, .queue: return "Playing from"
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

    // MARK: Controls

    @ViewBuilder private func controls(_ track: Track?) -> some View {
        VStack(spacing: 16) {
            Scrubber(position: player.position, duration: player.duration) { player.seek(to: $0) }
                .padding(.horizontal, Theme.gutter)
            HStack(spacing: 0) {
                modeButton("shuffle", on: player.queue.shuffle, label: "Shuffle") { player.setShuffle(!player.queue.shuffle) }
                Spacer()
                Button { player.previous() } label: {
                    Image(systemName: "backward.end.fill").font(.system(size: 26)).frame(width: 60, height: 60)
                }
                .accessibilityLabel("Previous")
                Spacer()
                Button { player.togglePlay() } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.paper).frame(width: 80, height: 80)
                        if player.isBuffering {
                            ProgressView().tint(Theme.night)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.night)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Spacer()
                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill").font(.system(size: 26)).frame(width: 60, height: 60)
                }
                .accessibilityLabel("Next")
                Spacer()
                modeButton(player.queue.repeatMode == .one ? "repeat.1" : "repeat", on: player.queue.repeatMode != .off,
                           label: "Repeat") { player.cycleRepeat() }
                    .accessibilityValue(player.queue.repeatMode == .one ? "One" : player.queue.repeatMode == .all ? "All" : "Off")
            }
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, Theme.gutter - 4)

            HStack(spacing: 22) {
                paneTab(.lyrics, "Lyrics")
                paneTab(.queue, "Up next")
                Spacer()
                if let remaining = player.sleepRemaining {
                    Label(Format.time(remaining), systemImage: "moon.zzz.fill")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.paper.opacity(0.8))
                } else if player.sleepTimer == .endOfTrack {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.paper.opacity(0.8))
                        .accessibilityLabel("Stops after this song")
                }
                AirPlayButton().frame(width: 36, height: 36)
            }
            .padding(.horizontal, Theme.gutter)
        }
        .buttonStyle(.plain)
    }

    private func modeButton(_ icon: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(on ? Theme.night : Theme.paper.opacity(0.7))
                .frame(width: 38, height: 38)
                .background(on ? Theme.paper : Color.clear, in: Circle())
        }
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
    }

    private func paneTab(_ target: Pane, _ title: String) -> some View {
        let active = pane == target
        return Button { pane = active ? .artwork : target } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(Typeface.condensed(19, .bold))
                    .foregroundStyle(active ? Theme.paper : Theme.paper.opacity(0.55))
                Capsule().fill(active ? Theme.paper : Color.clear).frame(height: 2)
            }
            .fixedSize()
        }
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// A thin rule that follows the finger while dragging and seeks on release; it thickens while held.
struct Scrubber: View {
    let position: Double
    let duration: Double
    var onSeek: (Double) -> Void
    @State private var dragValue: Double?

    var body: some View {
        let shown = dragValue ?? position
        let fraction = duration > 0 ? min(max(shown / duration, 0), 1) : 0
        VStack(spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.paper.opacity(0.22))
                    Capsule().fill(Theme.paper).frame(width: max(geo.size.width * fraction, 3))
                }
                .frame(height: dragValue == nil ? 3 : 8)
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
            .frame(height: 20)
            HStack {
                Text(Format.time(shown))
                Spacer()
                Text("-" + Format.time(max(0, duration - shown)))
            }
            .font(Typeface.condensed(15, .semibold).monospacedDigit())
            .foregroundStyle(Theme.paper.opacity(dragValue == nil ? 0.6 : 0.95))
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

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(Theme.paper).withAlphaComponent(0.8)
        v.activeTintColor = UIColor(Theme.lan)
        v.prioritizesVideoDevices = false
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
