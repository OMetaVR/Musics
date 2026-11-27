import SwiftUI
import MusicsCore

/// Synced lyrics: follows the song, highlights word by word when the source has word timing,
/// pauses following for a few seconds after the user scrolls, and seeks when a line is tapped.
struct LyricsView: View {
    @Environment(AppModel.self) private var model
    let track: Track

    enum LoadState { case loading, loaded(Lyrics), none, failed(String) }
    @State private var state: LoadState = .loading
    @State private var active: Int?
    @State private var userScrolledAt = Date.distantPast

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .none:
                message("No lyrics for this song.")
            case let .failed(why):
                message(why)
            case let .loaded(lyrics):
                if lyrics.isSynced { synced(lyrics) } else { plain(lyrics) }
            }
        }
        .task(id: track.id) { await load() }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(Typeface.condensed(22, .bold)).foregroundStyle(Theme.paper.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        state = .loading
        guard let session = model.session, let base = session.baseURL else {
            state = .failed("Lyrics need a connection to the server.")
            return
        }
        do {
            if let l = try await session.provider.lyrics(base: base, track: track), !l.lines.isEmpty {
                state = .loaded(l)
            } else {
                state = .none
            }
        } catch {
            state = .failed("Couldn't load lyrics.")
        }
    }

    private func plain(_ lyrics: Lyrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lyrics.lines) { line in
                    Text(line.text).font(Typeface.condensed(24, .bold)).foregroundStyle(Theme.paper.opacity(0.85))
                }
                source(lyrics)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func source(_ lyrics: Lyrics) -> some View {
        Text(lyrics.source.map { "Lyrics from \($0)" } ?? "")
            .font(.system(size: 12)).foregroundStyle(Theme.paper.opacity(0.4)).padding(.top, 20)
    }

    private func synced(_ lyrics: Lyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Color.clear.frame(height: 40)
                    ForEach(lyrics.lines) { line in
                        LyricLine(lyrics: lyrics, line: line, isActive: line.id == active, isPast: (active ?? -1) > line.id)
                            .id(line.id)
                            .onTapGesture {
                                model.player.seek(to: line.start)
                                if !model.player.isPlaying { model.player.play() }
                                userScrolledAt = .distantPast
                            }
                    }
                    source(lyrics)
                    Color.clear.frame(height: 200)
                }
                .padding(.horizontal, Theme.gutter)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 5).onChanged { _ in userScrolledAt = Date() })
            .background {
                // Drives `active` ten times a second without re-rendering the whole list.
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    let idx = lyrics.activeLineIndex(at: model.player.engine.currentTime + 0.2)
                    Color.clear.onChange(of: idx, initial: true) { _, new in active = new }
                }
            }
            .onChange(of: active) { _, new in
                guard let new, Date().timeIntervalSince(userScrolledAt) > 4 else { return }
                withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(new, anchor: UnitPoint(x: 0.5, y: 0.35)) }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                         .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
    }
}

struct LyricLine: View {
    @Environment(AppModel.self) private var model
    let lyrics: Lyrics
    let line: Lyrics.Line
    let isActive: Bool
    let isPast: Bool

    var body: some View {
        Group {
            if line.isInstrumentalGap {
                Text("♪").font(Typeface.condensed(32, .extraBold, relativeTo: .title))
                    .foregroundStyle(Theme.paper.opacity(isActive ? 0.9 : 0.35))
            } else if isActive, lyrics.kind == .word, !line.words.isEmpty {
                // Karaoke: sung words bright, the rest dim. Only the active line re-renders on the timeline.
                TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
                    let t = model.player.engine.currentTime + 0.05
                    line.words.reduce(Text("")) { acc, w in
                        acc + Text(w.text).foregroundColor(t >= w.start ? Theme.paper : Theme.paper.opacity(0.4))
                    }
                    .font(Typeface.condensed(32, .extraBold, relativeTo: .title))
                }
            } else {
                Text(line.text)
                    .font(Typeface.condensed(32, .extraBold, relativeTo: .title))
                    .foregroundStyle(Theme.paper.opacity(isActive ? 1 : isPast ? 0.45 : 0.35))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(isActive ? 1 : 0.97, anchor: .leading)
        .animation(.easeOut(duration: 0.25), value: isActive)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Plays from this line")
    }
}
