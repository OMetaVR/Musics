import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct NetworkState: Sendable, Hashable {
    public var isConnected: Bool
    public var isExpensive: Bool
    /// A Tailscale tunnel interface with a 100.64.0.0/10 address is up.
    public var tailscaleActive: Bool

    public init(isConnected: Bool = true, isExpensive: Bool = false, tailscaleActive: Bool = false) {
        self.isConnected = isConnected
        self.isExpensive = isExpensive
        self.tailscaleActive = tailscaleActive
    }
}

public struct ProbeResult: Sendable, Hashable, Identifiable {
    public var endpoint: Endpoint
    public var reachable: Bool
    public var latency: TimeInterval?
    /// Kind after DNS (a `.lan` name served over Tailscale split DNS counts as Tailscale).
    public var kind: EndpointKind
    public var error: String?
    public var id: UUID { endpoint.id }

    public init(endpoint: Endpoint, reachable: Bool, latency: TimeInterval?, kind: EndpointKind, error: String?) {
        self.endpoint = endpoint
        self.reachable = reachable
        self.latency = latency
        self.kind = kind
        self.error = error
    }
}

public enum UnreachableReason: Sendable, Hashable {
    case noEndpoints
    case offline
    /// Only tailnet addresses are configured and the Tailscale tunnel isn't up.
    case tailscaleOff
    case allFailed(String)

    public var message: String {
        switch self {
        case .noEndpoints: return "This server has no addresses."
        case .offline: return "You're offline."
        case .tailscaleOff: return "Tailscale is off. Turn it on to reach this server."
        case let .allFailed(why): return why
        }
    }
}

public struct Resolution: Sendable, Hashable {
    public var active: ProbeResult?
    public var results: [ProbeResult]
    public var failure: UnreachableReason?
    public var resolvedAt: Date

    public init(active: ProbeResult?, results: [ProbeResult], failure: UnreachableReason?, resolvedAt: Date = Date()) {
        self.active = active
        self.results = results
        self.failure = failure
        self.resolvedAt = resolvedAt
    }
}

public protocol EndpointProber: Sendable {
    func probe(_ endpoint: Endpoint) async -> ProbeResult
}

/// Probes with the provider's ping request, timing the round trip and resolving the host to detect
/// Tailscale split-DNS names.
public struct HTTPEndpointProber: EndpointProber {
    public let provider: MusicProvider
    public let session: URLSession
    public let timeout: TimeInterval

    public init(provider: MusicProvider, session: URLSession = .shared, timeout: TimeInterval = 3) {
        self.provider = provider
        self.session = session
        self.timeout = timeout
    }

    public func probe(_ endpoint: Endpoint) async -> ProbeResult {
        let host = endpoint.url.host ?? ""
        let kind = EndpointClassifier.classify(host: host, resolvedAddresses: HostResolver.addresses(for: host))
        var req = provider.probeRequest(base: endpoint.url)
        req.timeoutInterval = timeout
        let start = Date()
        do {
            let (data, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                return ProbeResult(endpoint: endpoint, reachable: false, latency: nil, kind: kind,
                                   error: MusicsError.http(code, nil).errorDescription)
            }
            if provider.kind == .subsonic, let s = String(data: data, encoding: .utf8), s.contains("\"failed\"") {
                return ProbeResult(endpoint: endpoint, reachable: false, latency: nil, kind: kind,
                                   error: "Wrong username or password.")
            }
            return ProbeResult(endpoint: endpoint, reachable: true, latency: Date().timeIntervalSince(start), kind: kind, error: nil)
        } catch {
            return ProbeResult(endpoint: endpoint, reachable: false, latency: nil, kind: kind,
                               error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

public enum EndpointRanking {
    /// Best first: local network beats Tailscale beats public; then the user's order; then latency.
    public static func rank(_ results: [ProbeResult], order: [UUID]) -> [ProbeResult] {
        results.filter(\.reachable).sorted { a, b in
            if a.kind.rank != b.kind.rank { return a.kind.rank < b.kind.rank }
            let ia = order.firstIndex(of: a.endpoint.id) ?? .max, ib = order.firstIndex(of: b.endpoint.id) ?? .max
            if ia != ib { return ia < ib }
            return (a.latency ?? .infinity) < (b.latency ?? .infinity)
        }
    }

    public static func failure(for results: [ProbeResult], network: NetworkState) -> UnreachableReason {
        if results.isEmpty { return .noEndpoints }
        if !network.isConnected { return .offline }
        if !network.tailscaleActive, results.allSatisfy({ $0.kind == .tailscale }) { return .tailscaleOff }
        let errors = Set(results.compactMap(\.error))
        if errors.count == 1, let e = errors.first { return .allFailed(e) }
        if !network.tailscaleActive, results.contains(where: { $0.kind == .tailscale }) {
            return .allFailed("No address answered. Tailscale is off, so tailnet addresses can't be reached.")
        }
        return .allFailed("No address answered.")
    }
}

public actor EndpointResolver {
    private let prober: EndpointProber

    public init(prober: EndpointProber) { self.prober = prober }

    /// Probes every enabled endpoint in parallel and picks the best reachable one. Returns early as soon as
    /// a local-network address answers, since nothing can beat it.
    public func resolve(_ endpoints: [Endpoint], network: NetworkState) async -> Resolution {
        let enabled = endpoints.filter(\.enabled)
        guard !enabled.isEmpty else { return Resolution(active: nil, results: [], failure: .noEndpoints) }
        let prober = self.prober
        var results: [ProbeResult] = []
        await withTaskGroup(of: ProbeResult.self) { group in
            for e in enabled { group.addTask { await prober.probe(e) } }
            for await r in group {
                results.append(r)
                if r.reachable, r.kind == .lan {
                    group.cancelAll()
                    break
                }
            }
        }
        // Report endpoints cancelled by the early exit as not probed rather than dropping them.
        for e in enabled where !results.contains(where: { $0.endpoint.id == e.id }) {
            results.append(ProbeResult(endpoint: e, reachable: false, latency: nil, kind: e.guessedKind, error: "Not checked"))
        }
        let order = endpoints.map(\.id)
        results.sort { (order.firstIndex(of: $0.endpoint.id) ?? 0) < (order.firstIndex(of: $1.endpoint.id) ?? 0) }
        if let best = EndpointRanking.rank(results, order: order).first {
            return Resolution(active: best, results: results, failure: nil)
        }
        return Resolution(active: nil, results: results, failure: EndpointRanking.failure(for: results, network: network))
    }
}
