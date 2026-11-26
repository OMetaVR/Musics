import SwiftUI
import MusicsCore

/// Docked above the tab bar. Tap or swipe up opens Now Playing; swipe sideways to skip.
struct MiniPlayer: View {
    @Environment(AppModel.self) private var model
    @State private var dragX: CGFloat = 0

    var body: some View {
        let player = model.player
        let track = player.currentTrack
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ArtworkView(url: track.flatMap { model.artworkURL(track: $0, size: 128) }, cornerRadius: 4)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track?.title ?? "Not playing").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.inkHi).lineLimit(1)
                    Text(track?.artistLine ?? "").font(.system(size: 13)).foregroundStyle(Theme.ink3).lineLimit(1)
                }
                .offset(x: dragX * 0.6)
                .opacity(1 - min(abs(dragX) / 160, 0.6))
                Spacer(minLength: 4)
                if player.isBuffering {
                    ProgressView().controlSize(.small).tint(Theme.ink2).frame(width: 28)
                }
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22)).foregroundStyle(Theme.inkHi).frame(width: 44, height: 44)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 18)).foregroundStyle(Theme.ink).frame(width: 40, height: 44)
                }
                .accessibilityLabel("Next")
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
            .buttonStyle(.plain)

            GeometryReader { geo in
                Rectangle().fill(Theme.accent)
                    .frame(width: geo.size.width * CGFloat(player.duration > 0 ? min(player.position / player.duration, 1) : 0))
            }
            .frame(height: 2)
            .background(Theme.line)
        }
        .background(model.accentColor(albumID: track?.albumID).map { $0.opacity(0.55) } ?? Theme.cellHi)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing: \(track?.title ?? ""), \(track?.artistLine ?? "")")
        .accessibilityAction(named: "Open player") { model.showPlayer = true }
    }
}
