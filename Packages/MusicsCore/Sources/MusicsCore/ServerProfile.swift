import Foundation

public enum ServerKind: String, Codable, CaseIterable, Sendable {
    /// music.lan (this project's own server).
    case musicLan
    /// Subsonic / OpenSubsonic: Navidrome, Gonic, Airsonic, Ampache…
    case subsonic

    public var displayName: String {
        switch self {
        case .musicLan: return "music.lan"
        case .subsonic: return "Subsonic / Navidrome"
        }
    }
}

public enum EndpointKind: String, Codable, CaseIterable, Sendable {
    case lan, tailscale, publicInternet

    public var displayName: String {
        switch self {
        case .lan: return "Local network"
        case .tailscale: return "Tailscale"
        case .publicInternet: return "Public"
        }
    }

    /// Lower is tried first when several addresses answer.
    var rank: Int {
        switch self {
        case .lan: return 0
        case .tailscale: return 1
        case .publicInternet: return 2
        }
    }
}

public struct Endpoint: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL
    public var enabled: Bool

    public init(url: URL, enabled: Bool = true, id: UUID = UUID()) {
        self.id = id
        self.url = url
        self.enabled = enabled
    }

    /// What kind of address this looks like from its host name alone.
    public var guessedKind: EndpointKind { EndpointClassifier.classify(host: url.host ?? "") }
}

public enum AuthMethod: String, Codable, CaseIterable, Sendable {
    case none
    /// HTTP Basic, e.g. Caddy `basic_auth` in front of music.lan on a public address.
    case basic
    /// A custom header, e.g. `Authorization: Bearer …` or Cloudflare Access service tokens.
    case header
    /// Subsonic token auth (salted MD5 of the password).
    case subsonic
}

/// A music server the user added. Secrets (password / header value) live in the Keychain, keyed by `id`.
public struct ServerProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ServerKind
    public var endpoints: [Endpoint]
    public var auth: AuthMethod
    public var username: String
    public var headerName: String

    public init(id: UUID = UUID(), name: String, kind: ServerKind, endpoints: [Endpoint],
                auth: AuthMethod = .none, username: String = "", headerName: String = "Authorization") {
        self.id = id
        self.name = name
        self.kind = kind
        self.endpoints = endpoints
        self.auth = auth
        self.username = username
        self.headerName = headerName
    }
}

public struct ServerCredentials: Sendable, Hashable {
    public var secret: String
    public init(secret: String) { self.secret = secret }
}

public enum EndpointClassifier {
    public static func classify(host rawHost: String) -> EndpointKind {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.hasSuffix(".ts.net") { return .tailscale }
        if let v4 = parseIPv4(host) {
            if isTailscale(v4) { return .tailscale }
            if isPrivate(v4) { return .lan }
            return .publicInternet
        }
        if host.contains(":") {
            if host.hasPrefix("fd7a:115c:a1e0") { return .tailscale }
            if host.hasPrefix("fe80") || host.hasPrefix("fc") || host.hasPrefix("fd") || host == "::1" { return .lan }
            return .publicInternet
        }
        if !host.contains(".") { return .lan }  // single-label names: MagicDNS short names or LAN hosts
        for suffix in [".local", ".lan", ".home", ".home.arpa", ".internal", ".localdomain", ".intranet", ".corp"]
        where host.hasSuffix(suffix) {
            return .lan
        }
        return .publicInternet
    }

    /// Classification after DNS: a `.lan` name that resolves into 100.64.0.0/10 is reached over Tailscale
    /// (split DNS), not the local network.
    public static func classify(host: String, resolvedAddresses: [String]) -> EndpointKind {
        if resolvedAddresses.contains(where: { parseIPv4($0).map(isTailscale) ?? $0.lowercased().hasPrefix("fd7a:115c:a1e0") }) {
            return .tailscale
        }
        return classify(host: host)
    }

    public static func parseIPv4(_ s: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var b: [UInt8] = []
        for p in parts {
            guard let v = UInt8(p) else { return nil }
            b.append(v)
        }
        return (b[0], b[1], b[2], b[3])
    }

    /// CGNAT range Tailscale assigns: 100.64.0.0/10.
    public static func isTailscale(_ ip: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        ip.0 == 100 && (ip.1 & 0xC0) == 64
    }

    public static func isPrivate(_ ip: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        switch ip.0 {
        case 10, 127: return true
        case 172: return (16...31).contains(ip.1)
        case 192: return ip.1 == 168
        case 169: return ip.1 == 254
        default: return false
        }
    }

    /// Accepts what people type ("music.lan", "100.101.102.103:3791", "https://x.ts.net") and returns a URL
    /// with a scheme and no trailing slash. Bare hosts default to http for private/tailnet names, https otherwise.
    public static func normalizeURL(_ input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") {
            let host = String(s.split(separator: "/").first ?? "").split(separator: ":").first.map(String.init) ?? s
            let kind = classify(host: host)
            // Public names and Tailscale's own *.ts.net names (which get real certificates) use https.
            let secure = kind == .publicInternet || host.lowercased().hasSuffix(".ts.net")
            s = (secure ? "https://" : "http://") + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
