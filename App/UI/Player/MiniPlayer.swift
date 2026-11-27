import SwiftUI
import MusicsCore

/// A strip of the current sleeve floating above the tabs, in the album's colour. Tap or swipe up opens
/// Now Playing; swipe sideways to skip.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    @State private var dragX: CGFloat = 0
    @State private var sampled: Color?

    var body: some View {
        let player = model.player
        let track = player.currentTrack
        let tint = model.accentColor(albumID: track?.albumID) ?? sampled ?? Theme.sleeveFallback
        HStack(spacing: 12) {
            ArtworkView(url: track.flatMap { model.artworkURL(track: $0, size: 128) }, cornerRadius: Theme.artRadius)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 0) {
                Text(track?.title ?? "Not playing")
                    .font(Typeface.condensed(18, .bold))
                    .foregroundStyle(Theme.paper)
                    .lineLimit(1)
                Text(track?.artistLine ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.paper.opacity(0.65))
                    .lineLimit(1)
            }
            .offset(x: dragX * 0.6)
            .opacity(1 - min(abs(dragX) / 160, 0.6))
            Spacer(minLength: 4)
            Button { player.togglePlay() } label: {
                ZStack {
                    if player.isBuffering {
                        ProgressView().tint(Theme.paper)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.paper)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 16)).foregroundStyle(Theme.paper.opacity(0.8))
                    .frame(width: 36, height: 44)
            }
            .accessibilityLabel("Next")
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .background(tint)
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Rectangle().fill(Theme.paper)
                    .frame(width: geo.size.width * CGFloat(player.duration > 0 ? min(player.position / player.duration, 1) : 0))
            }
            .frame(height: 2)
            .background(Theme.paper.opacity(0.18))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { model.showPlayer = true }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in
                    if abs(v.translation.width) > abs(v.translation.height) { dragX = v.translation.width }
                }
                .onEnded { v in
                    let dx = v.translation.width, dy = v.translation.height
                    withAnimation(.snappy) { dragX = 0 }
                    if dy < -40, abs(dy) > abs(dx) {
                        model.showPlayer = true
                    } else if dx < -70 {
                        model.haptic(.light)
                        player.next()
                    } else if dx > 70 {
                        model.haptic(.light)
                        player.previous()
                    }
                }
        )
        .animation(.easeInOut(duration: 0.4), value: track?.albumID)
        .task(id: track?.albumID) { sampled = await SleeveColor.sample(model, track) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing: \(track?.title ?? ""), \(track?.artistLine ?? "")")
        .accessibilityAction(named: "Open player") { model.showPlayer = true }
    }
}

/// The colour of a sleeve: the server's accent when it sends one, otherwise sampled from the artwork.
enum SleeveColor {
    @MainActor
    static func sample(_ model: AppModel, _ track: Track?) async -> Color? {
        guard let track, model.accentColor(albumID: track.albumID) == nil,
              let url = model.artworkURL(track: track, size: 300),
              let img = await ArtworkLoader.shared.image(for: url) else { return nil }
        return Color(uiColor: ArtworkLoader.shared.accentColor(for: url, image: img))
    }
}
