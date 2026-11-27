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
        .tint(Theme.paper)
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
                        MiniPlayer()
                            .padding(.horizontal, 8)
                            .padding(.bottom, 4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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

/// Text-only tabs in the condensed face. The active tab gets paper-coloured type and a short rule above it.
struct TabBar: View {
    @Environment(AppModel.self) private var model
    @Namespace private var marker

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let active = model.tab == tab
                Button { model.selectTab(tab) } label: {
                    VStack(spacing: 7) {
                        ZStack {
                            if active {
                                Capsule().fill(Theme.paper).frame(width: 22, height: 3)
                                    .matchedGeometryEffect(id: "marker", in: marker)
                            }
                        }
                        .frame(height: 3)
                        Text(tab.title)
                            .font(Typeface.condensed(18, active ? .bold : .semibold))
                            .foregroundStyle(active ? Theme.paper : Theme.ash)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.25), value: model.tab)
        .background(Theme.night.ignoresSafeArea(edges: .bottom))
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.night).lineLimit(2)
            Spacer(minLength: 0)
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    model.toastItem = nil
                }
                .font(Typeface.condensed(16, .bold))
                .foregroundStyle(Theme.night)
                .underline()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .environment(\.colorScheme, .light)
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
