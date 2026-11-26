import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Looks at the device's network interfaces. The Tailscale iOS app runs as a VPN whose `utun`
/// interface carries an address in 100.64.0.0/10.
public enum NetworkInterfaces {
    public struct Address: Hashable, Sendable {
        public var interface: String
        public var address: String
    }

    public static func ipv4Addresses() -> [Address] {
        var out: [Address] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return out }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let sa = ifa.pointee.ifa_addr, Int32(sa.pointee.sa_family) == AF_INET else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            #if canImport(Darwin)
            let len = socklen_t(sa.pointee.sa_len)
            #else
            let len = socklen_t(MemoryLayout<sockaddr_in>.size)
            #endif
            if getnameinfo(sa, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                out.append(Address(interface: String(cString: ifa.pointee.ifa_name), address: String(cString: host)))
            }
        }
        return out
    }

    /// True when an interface holds a Tailscale (CGNAT 100.64/10) address.
    public static func tailscaleActive() -> Bool {
        ipv4Addresses().contains { EndpointClassifier.parseIPv4($0.address).map(EndpointClassifier.isTailscale) ?? false }
    }

    public static func tailscaleAddress() -> String? {
        ipv4Addresses().first { EndpointClassifier.parseIPv4($0.address).map(EndpointClassifier.isTailscale) ?? false }?.address
    }
}

public enum HostResolver {
    /// Numeric addresses for a host name (blocking; call off the main thread). Literal IPs return themselves.
    public static func addresses(for host: String) -> [String] {
        if host.isEmpty { return [] }
        if EndpointClassifier.parseIPv4(host) != nil || host.contains(":") { return [host] }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        #if canImport(Darwin)
        hints.ai_socktype = SOCK_STREAM
        #else
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #endif
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return [] }
        defer { freeaddrinfo(res) }
        var out: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let ai = cursor {
            defer { cursor = ai.pointee.ai_next }
            guard let sa = ai.pointee.ai_addr else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, ai.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                let s = String(cString: buf)
                if !out.contains(s) { out.append(s) }
            }
        }
        return out
    }
}
