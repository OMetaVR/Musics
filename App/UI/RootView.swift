import SwiftUI
import MusicsCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if model.servers.profiles.isEmpty {
                WelcomeView()
            } else {
                MainShell()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .task { await model.startup() }
        .onChange(of: phase) { _, new in
            switch new {
            case .active: model.sceneBecameActive()
            case .background: model.sceneEnteredBackground()
            default: break
            }
        }
    }
}

/// Tabs that each keep their own navigation stack, with the mini player and tab bar docked at the bottom
/// and Now Playing sliding over everything.
struct MainShell: View {
    @Environment(AppModel.self) private var model
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        @Bindable var model = model
        ZStack {
            ZStack {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    TabStack(tab: tab)
                        .opacity(model.tab == tab ? 1 : 0)
                        .allowsHitTesting(model.tab == tab)
                        .accessibilityHidden(model.tab != tab)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let toast = model.toastItem {
                        ToastView(toast: toast).padding(.horizontal, 12).padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if model.player.hasQueue {
                        MiniPlayer().transition(.move(edge: .bottom))
                    }
                    TabBar()
                }
            }

            if model.showPlayer {
                NowPlayingView(dragOffset: $dragOffset)
                    .offset(y: max(0, dragOffset))
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: model.showPlayer)
        .sheet(isPresented: $model.showSettings) { SettingsView() }
        .sheet(isPresented: $model.showAdventure) { SonicAdventureView(start: model.adventureStart) }
        .sheet(item: $model.infoTrack) { track in SongInfoView(track: track).presentationDetents([.medium, .large]) }
    }
}

struct TabStack: View {
    @Environment(AppModel.self) private var model
    let tab: AppTab

    var body: some View {
        NavigationStack(path: Binding(get: { model.paths[tab] ?? NavigationPath() }, set: { model.paths[tab] = $0 })) {
            Group {
                switch tab {
                case .home: HomeView()
                case .search: SearchView()
                case .library: LibraryView()
                }
            }
            .navigationDestination(for: Route.self) { route in
                RouteView(route: route)
            }
        }
    }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case let .album(id): AlbumView(albumID: id)
        case let .artist(id): ArtistView(artistID: id)
        case let .playlist(id): PlaylistView(playlistID: id)
        case let .genre(name): GenreView(name: name)
        case .liked: LikedSongsView()
        case .downloads: DownloadsView()
        case .songs: SongsView()
        case .albums: AlbumsView(sortByAdded: false)
        case .recentlyAdded: AlbumsView(sortByAdded: true)
        case .artists: ArtistsView()
        case .playlists: PlaylistsView()
        case .genres: GenresView()
        case .history: HistoryView()
        }
    }
}

struct TabBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button { model.selectTab(tab) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: model.tab == tab ? tab.icon + ".fill" : tab.icon)
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 24)
                        Text(tab.title).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(model.tab == tab ? Theme.accent : Theme.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
                    .padding(.bottom, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
            }
        }
        .background(Theme.panel.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text).font(.system(size: 14)).foregroundStyle(Theme.ink).lineLimit(2)
            Spacer(minLength: 0)
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    model.toastItem = nil
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.cellHi, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.edge))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Shown at the top of Home and Library when the server can't be reached.
struct ConnectionBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.session, case let .offline(reason) = session.status {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: reason == .tailscaleOff ? "network.slash" : "wifi.slash").foregroundStyle(Theme.ink2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(reason == .offline ? "Offline" : "Can't reach \(session.profile.name)")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("\(reason.message) Downloaded and recently played songs still play.")
                        .font(.system(size: 13)).foregroundStyle(Theme.ink3)
                    HStack(spacing: 16) {
                        Button("Retry") { Task { await session.resolve() } }
                        if reason == .tailscaleOff, let url = URL(string: "tailscale://") {
                            Link("Open Tailscale", destination: url)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .cardBackground()
            .padding(.horizontal, Theme.gutter)
        }
    }
}
