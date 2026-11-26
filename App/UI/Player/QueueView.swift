import SwiftUI
import MusicsCore

/// Playing Next (user queue), Continue Playing (rest of the context) and Autoplay. Tap to jump,
/// long-press and drag to reorder, swipe to remove; every edit can be undone from the toast.
struct QueueView: View {
    @Environment(AppModel.self) private var model
    @State private var showHistory = false

    private var player: PlaybackController { model.player }

    var body: some View {
        let q = player.queue
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                toggle("shuffle", on: q.shuffle, label: "Shuffle") { player.setShuffle(!q.shuffle) }
                toggle(q.repeatMode == .one ? "repeat.1" : "repeat", on: q.repeatMode != .off, label: "Repeat") { player.cycleRepeat() }
                if model.capabilities.contains(.radio) {
                    toggle("infinity", on: model.settings.autoplay, label: "Autoplay") {
                        model.settings.autoplay.toggle()
                        if !model.settings.autoplay { player.clearAutoplay() }
                    }
                }
                Spacer()
                if !q.upcoming.isEmpty {
                    Button("Clear") { player.clearUpcoming() }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)

            List {
                if !q.history.isEmpty {
                    Section {
                        if showHistory {
                            ForEach(q.history.suffix(50)) { item in row(item, dim: true) }
                        }
                    } header: {
                        Button { withAnimation { showHistory.toggle() } } label: {
                            HStack {
                                Text("History").queueHeader()
                                Image(systemName: showHistory ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.6))
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !q.upNext.isEmpty {
                    Section {
                        ForEach(q.upNext) { item in row(item) }
                            .onMove { player.move(in: .upNext, from: $0, to: $1) }
                            .onDelete { idx in idx.map { q.upNext[$0] }.forEach(player.remove) }
                    } header: { Text("Playing Next").queueHeader() }
                }
                if !q.context.isEmpty {
                    Section {
                        ForEach(q.context.prefix(300)) { item in row(item) }
                            .onMove { player.move(in: .context, from: $0, to: $1) }
                            .onDelete { idx in idx.map { q.context[$0] }.forEach(player.remove) }
                    } header: {
                        Text("Continue Playing" + (q.contextInfo.map { " from \($0.title)" } ?? "")).queueHeader()
                    }
                }
                if !q.autoplay.isEmpty || player.isFetchingAutoplay {
                    Section {
                        ForEach(q.autoplay) { item in row(item) }
                            .onMove { player.move(in: .autoplay, from: $0, to: $1) }
                            .onDelete { idx in idx.map { q.autoplay[$0] }.forEach(player.remove) }
                        if player.isFetchingAutoplay {
                            ProgressView().tint(.white).frame(maxWidth: .infinity).listRowBackground(Color.clear)
                        }
                    } header: {
                        HStack {
                            Text("Autoplay").queueHeader()
                            Text("Similar songs").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5))
                        }
                    }
                }
                if q.upcoming.isEmpty && !player.isFetchingAutoplay {
                    Text("Nothing up next.").font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.5))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
        }
    }

    private func toggle(_ icon: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Color.black : Color.white.opacity(0.85))
                .frame(width: 46, height: 32)
                .background(on ? Theme.accent : Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "On" : "Off")
    }

    @ViewBuilder private func row(_ item: QueueItem, dim: Bool = false) -> some View {
        if let t = player.track(item) {
            Button { player.jump(to: item) } label: {
                HStack(spacing: 12) {
                    ArtworkView(url: model.artworkURL(track: t, size: 128), cornerRadius: 4).frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 15)).foregroundStyle(.white).lineLimit(1)
                        Text(t.artistLine).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if model.downloads.isAvailableOffline(t.id) {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                .opacity(dim ? 0.55 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 16))
            .contextMenu { TrackMenuItems(track: t) }
        }
    }
}

private extension Text {
    func queueHeader() -> some View {
        font(.system(size: 15, weight: .bold)).foregroundStyle(.white).textCase(nil)
    }
}
