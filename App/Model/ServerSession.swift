import Foundation
import MusicsCore
import Network
import Observation

/// A connection to one server: its provider plus whichever of its addresses works on the current network.
/// Re-resolves when the network changes (Wi-Fi ↔ cellular, Tailscale on/off) and after request failures.
@MainActor
@Observable
final class ServerSession {
    enum Status: Equatable {
        case connecting
        case online(EndpointKind, latency: TimeInterval?)
        case offline(UnreachableReason)
    }

    let profile: ServerProfile
    let provider: MusicProvider
    private(set) var status: Status = .connecting
    private(set) var resolution: Resolution?
    private(set) var network = NetworkState()
    private(set) var isResolving = false
    /// Called after the active address changes (e.g. to refresh the library or rebuild stream URLs).
    var onBaseURLChange: (@MainActor (URL?) -> Void)?

    @ObservationIgnored private let resolver: EndpointResolver
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var lastResolve = Date.distantPast
    @ObservationIgnored private var pendingResolve: Task<Void, Never>?

    init(profile: ServerProfile, credentials: ServerCredentials?) {
        self.profile = profile
        let provider = ProviderFactory.make(profile, credentials: credentials)
        self.provider = provider
        resolver = EndpointResolver(prober: HTTPEndpointProber(provider: provider))
    }

    var baseURL: URL? { resolution?.active?.endpoint.url }
    var isOnline: Bool { if case .online = status { return true } else { return false } }
    var capabilities: ProviderCapabilities { provider.capabilities }
    var isExpensiveNetwork: Bool { network.isExpensive }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let state = NetworkState(isConnected: path.status == .satisfied, isExpensive: path.isExpensive || path.isConstrained,
                                     tailscaleActive: NetworkInterfaces.tailscaleActive())
            Task { @MainActor [weak self] in self?.networkChanged(state) }
        }
        monitor.start(queue: DispatchQueue(label: "musics.path"))
        Task { await resolve() }
    }

    func stop() {
        monitor.cancel()
        pendingResolve?.cancel()
    }

    private func networkChanged(_ state: NetworkState) {
        guard state != network else { return }
        network = state
        // Debounce: interfaces flap while switching networks.
        pendingResolve?.cancel()
        pendingResolve = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.resolve()
        }
    }

    /// Probes all addresses and picks the best one.
    func resolve() async {
        guard !isResolving else { return }
        isResolving = true
        defer { isResolving = false }
        if resolution == nil { status = .connecting }
        let old = baseURL
        lastResolve = Date()
        var net = network
        net.tailscaleActive = NetworkInterfaces.tailscaleActive()
        network = net
        let r = await resolver.resolve(profile.endpoints, network: net)
        resolution = r
        if let a = r.active {
            status = .online(a.kind, latency: a.latency)
        } else {
            status = .offline(r.failure ?? .allFailed("No address answered."))
        }
        if baseURL != old { onBaseURLChange?(baseURL) }
    }

    /// A request failed: re-check addresses, at most every 10 s.
    func reportFailure() {
        guard Date().timeIntervalSince(lastResolve) > 10 else { return }
        Task { await resolve() }
    }

    /// Streaming quality for the current network.
    func quality(_ settings: AppSettings) -> StreamQuality {
        network.isExpensive ? settings.cellularQuality : settings.wifiQuality
    }

    var statusText: String {
        switch status {
        case .connecting: return "Connecting…"
        case let .online(kind, latency):
            let ms = latency.map { " · \(Int($0 * 1000)) ms" } ?? ""
            return "\(kind.displayName)\(ms)"
        case let .offline(reason): return reason.message
        }
    }
}
