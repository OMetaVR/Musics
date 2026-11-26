import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MusicsError: Error, LocalizedError, Sendable, Equatable {
    case http(Int, String?)
    case decoding(String)
    case server(String)
    case unsupported(String)
    case unreachable(String)
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case let .http(code, msg):
            if code == 401 || code == 403 { return "The server refused the credentials (\(code))." }
            return msg.map { "Server error \(code): \($0)" } ?? "Server error \(code)."
        case let .decoding(msg): return "Unexpected response from the server (\(msg))."
        case let .server(msg): return msg
        case let .unsupported(what): return "This server doesn't support \(what)."
        case let .unreachable(why): return why
        case .notConfigured: return "No server is set up."
        }
    }
}

/// Thin async wrapper over URLSession that adds the profile's auth headers.
public struct HTTPClient: Sendable {
    public let session: URLSession
    public let headers: [String: String]
    public let timeout: TimeInterval

    public init(session: URLSession = .shared, headers: [String: String] = [:], timeout: TimeInterval = 30) {
        self.session = session
        self.headers = headers
        self.timeout = timeout
    }

    public func request(_ url: URL, method: String = "GET", json: Any? = nil, timeout: TimeInterval? = nil) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout ?? self.timeout)
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        if let json {
            r.httpBody = try? JSONSerialization.data(withJSONObject: json)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    public func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MusicsError.decoding("not HTTP") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw MusicsError.http(http.statusCode, msg)
        }
        return data
    }

    public func get<T: Decodable>(_ url: URL, as type: T.Type = T.self, timeout: TimeInterval? = nil) async throws -> T {
        try decode(T.self, from: try await data(request(url, timeout: timeout)))
    }

    public func post<T: Decodable>(_ url: URL, json: Any, as type: T.Type = T.self, timeout: TimeInterval? = nil) async throws -> T {
        try decode(T.self, from: try await data(request(url, method: "POST", json: json, timeout: timeout)))
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw MusicsError.decoding("missing \(key.stringValue) at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw MusicsError.decoding("wrong type at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch {
            throw MusicsError.decoding(String(describing: error).prefix(120).description)
        }
    }

    /// Basic auth header value.
    public static func basic(user: String, password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }
}

extension URL {
    /// Appends a path ("/api/x") to a base URL that may itself contain a path (reverse-proxy subfolder).
    public func appendingAPIPath(_ path: String, query: [URLQueryItem] = []) -> URL {
        var comps = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        let basePath = comps.percentEncodedPath.hasSuffix("/") ? String(comps.percentEncodedPath.dropLast()) : comps.percentEncodedPath
        let encoded = path.split(separator: "/", omittingEmptySubsequences: false).map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? String($0)
        }.joined(separator: "/")
        comps.percentEncodedPath = basePath + (encoded.hasPrefix("/") ? encoded : "/" + encoded)
        if !query.isEmpty { comps.queryItems = (comps.queryItems ?? []) + query }
        return comps.url!
    }
}

/// Decodes a value that some servers send as a number and others as a string.
struct LossyString: Decodable, Hashable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(d) }
        else if let b = try? c.decode(Bool.self) { value = String(b) }
        else { value = "" }
    }
}

struct LossyInt: Decodable, Hashable {
    let value: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = Int(d) }
        else if let s = try? c.decode(String.self) { value = Int(s.prefix { $0.isNumber }) ?? 0 }
        else { value = 0 }
    }
}
