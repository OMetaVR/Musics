import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ProviderCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let likes = ProviderCapabilities(rawValue: 1 << 0)
    public static let lyrics = ProviderCapabilities(rawValue: 1 << 1)
    public static let radio = ProviderCapabilities(rawValue: 1 << 2)
    public static let genreRadio = ProviderCapabilities(rawValue: 1 << 3)
    /// Search by sound / mood using audio embeddings.
    public static let semanticSearch = ProviderCapabilities(rawValue: 1 << 4)
    /// A path of songs morphing from one track to another.
    public static let adventure = ProviderCapabilities(rawValue: 1 << 5)
    /// Shares what's playing with the server (music.lan shows it on Discord).
    public static let nowPlaying = ProviderCapabilities(rawValue: 1 << 6)
    public static let scrobble = ProviderCapabilities(rawValue: 1 << 7)
    public static let transcoding = ProviderCapabilities(rawValue: 1 << 8)
}

public enum RadioSeed: Hashable, Sendable {
    case track(TrackID)
    case artist(String)
    case genre(String)
}

public struct NowPlayingReport: Sendable {
    public var clientID: String
    public var trackID: TrackID?
    public var playing: Bool
    public var position: Double
    public var duration: Double

    public init(clientID: String, trackID: TrackID?, playing: Bool, position: Double, duration: Double) {
        self.clientID = clientID
        self.trackID = trackID
        self.playing = playing
        self.position = position
        self.duration = duration
    }
}

/// One server API. Every call takes the base URL the endpoint resolver picked, so the same provider
/// works whichever address (LAN, Tailscale, public) is reachable right now.
public protocol MusicProvider: Sendable {
    var kind: ServerKind { get }
    var capabilities: ProviderCapabilities { get }
    /// Headers that must accompany media requests (AVURLAsset, downloads).
    var mediaHeaders: [String: String] { get }

    /// A cheap request that proves the server is there and the credentials work.
    func probeRequest(base: URL) -> URLRequest
    /// Changes whenever the library content changes; compared before downloading the whole library.
    func libraryVersion(base: URL) async throws -> String
    func fetchLibrary(base: URL) async throws -> LibrarySnapshot

    func streamURL(base: URL, track: Track, quality: StreamQuality) -> URL
    /// URL of a file to keep offline (always something AVFoundation can play).
    func downloadURL(base: URL, track: Track, quality: StreamQuality) -> URL
    /// File extension of what `downloadURL` returns.
    func downloadExtension(track: Track, quality: StreamQuality) -> String
    func artworkURL(base: URL, album: Album, size: Int) -> URL?
    func artworkURL(base: URL, playlist: Playlist, size: Int) -> URL?

    /// Returns the full new likes list when the server sends one, else nil.
    func setLiked(base: URL, trackID: TrackID, liked: Bool) async throws -> [TrackID]?
    func lyrics(base: URL, track: Track) async throws -> Lyrics?
    func radio(base: URL, seed: RadioSeed, count: Int, exclude: [TrackID]) async throws -> [TrackID]
    func semanticSearch(base: URL, query: String, limit: Int) async throws -> [ScoredTrack]
    func adventure(base: URL, from: TrackID, to: TrackID, steps: Int) async throws -> [TrackID]
    func reportNowPlaying(base: URL, _ report: NowPlayingReport) async
    /// Hints that a track will be played soon (server-side transcode / lyrics warm-up).
    func prepare(base: URL, track: Track, quality: StreamQuality) async
    func scrobble(base: URL, trackID: TrackID, at date: Date) async
}

public extension MusicProvider {
    func radio(base: URL, seed: RadioSeed, count: Int, exclude: [TrackID]) async throws -> [TrackID] {
        throw MusicsError.unsupported("radio")
    }
    func semanticSearch(base: URL, query: String, limit: Int) async throws -> [ScoredTrack] {
        throw MusicsError.unsupported("audio search")
    }
    func adventure(base: URL, from: TrackID, to: TrackID, steps: Int) async throws -> [TrackID] {
        throw MusicsError.unsupported("Sonic Adventure")
    }
    func reportNowPlaying(base: URL, _ report: NowPlayingReport) async {}
    func prepare(base: URL, track: Track, quality: StreamQuality) async {}
    func scrobble(base: URL, trackID: TrackID, at date: Date) async {}
}

public enum ProviderFactory {
    public static func make(_ profile: ServerProfile, credentials: ServerCredentials?, session: URLSession = .shared) -> MusicProvider {
        switch profile.kind {
        case .musicLan:
            return MusicLanProvider(http: HTTPClient(session: session, headers: authHeaders(profile, credentials)))
        case .subsonic:
            return SubsonicProvider(username: profile.username, password: credentials?.secret ?? "",
                                    http: HTTPClient(session: session, headers: authHeaders(profile, credentials)))
        }
    }

    public static func authHeaders(_ profile: ServerProfile, _ credentials: ServerCredentials?) -> [String: String] {
        guard let secret = credentials?.secret, !secret.isEmpty else { return [:] }
        switch profile.auth {
        case .basic: return ["Authorization": HTTPClient.basic(user: profile.username, password: secret)]
        case .header:
            let name = profile.headerName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? [:] : [name: secret]
        case .none, .subsonic: return [:]
        }
    }
}
