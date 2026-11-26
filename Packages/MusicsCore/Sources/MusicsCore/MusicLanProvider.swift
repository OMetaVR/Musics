import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// music.lan's JSON API (the music-library server.py backend).
public struct MusicLanProvider: MusicProvider {
    public let http: HTTPClient
    public var kind: ServerKind { .musicLan }
    public var capabilities: ProviderCapabilities {
        [.likes, .lyrics, .radio, .genreRadio, .semanticSearch, .adventure, .nowPlaying, .transcoding]
    }
    public var mediaHeaders: [String: String] { http.headers }

    public init(http: HTTPClient) { self.http = http }

    // MARK: Wire format

    struct WireLibrary: Decodable {
        let tracks: [WireTrack]
        let albums: [WireAlbum]
        let playlists: [WirePlaylist]?
        let likes: [String]?
        let version: LossyString?
        let gn: [String]?
    }

    struct WireTrack: Decodable {
        let id: String
        let t: String?
        let ar: [String]?
        let al: String
        let n: LossyInt?
        let dk: LossyInt?
        let dur: Double?
        let y: LossyInt?
        let add: Double?
        let ext: String?
        let ly: Bool?
        let g: [Int]?
    }

    struct WireAlbum: Decodable {
        let id: String
        let name: String?
        let artist: String?
        let year: LossyInt?
        let tracks: [String]?
        let added: Double?
        let c: String?
        let cv: LossyString?
    }

    struct WirePlaylist: Decodable {
        let id: String
        let name: String?
        let tracks: [String]?
        let total: Int?
        let src: String?
        let url: String?
        let mtime: Double?
    }

    struct WireVersion: Decodable {
        let version: LossyString
        let scanning: Bool?
    }

    struct WireLyrics: Decodable {
        struct W: Decodable { let t: Double?; let e: Double?; let s: String? }
        struct L: Decodable { let t: Double?; let e: Double?; let text: String?; let w: [W]? }
        let source: String?
        let kind: String?
        let lines: [L]?
    }

    struct IDList: Decodable { let tracks: [String]? }
    struct ScoredList: Decodable {
        struct S: Decodable { let id: String; let score: Double? }
        let tracks: [S]?
        let error: String?
    }
    struct LikesResponse: Decodable { let likes: [String]? }

    // MARK: Library

    public func probeRequest(base: URL) -> URLRequest {
        http.request(base.appendingAPIPath("/api/version"), timeout: 4)
    }

    public func libraryVersion(base: URL) async throws -> String {
        let v: WireVersion = try await http.get(base.appendingAPIPath("/api/version"), timeout: 8)
        return v.version.value
    }

    public func fetchLibrary(base: URL) async throws -> LibrarySnapshot {
        let data = try await http.data(http.request(base.appendingAPIPath("/api/library"), timeout: 90))
        return try Self.decodeLibrary(data, decoder: http)
    }

    static func decodeLibrary(_ data: Data, decoder http: HTTPClient = HTTPClient()) throws -> LibrarySnapshot {
        let wire = try http.decode(WireLibrary.self, from: data)
        let genreNames = wire.gn ?? []
        var albums: [Album] = []
        albums.reserveCapacity(wire.albums.count)
        var albumByID = [String: WireAlbum]()
        for a in wire.albums { albumByID[a.id] = a }
        var tracks: [Track] = []
        tracks.reserveCapacity(wire.tracks.count)
        var durations = [String: Double]()
        for t in wire.tracks {
            let alb = albumByID[t.al]
            let artists = (t.ar ?? []).isEmpty ? [alb?.artist ?? "Unknown artist"] : t.ar!
            let genres = (t.g ?? []).compactMap { genreNames.indices.contains($0) ? genreNames[$0] : nil }
            tracks.append(Track(id: t.id, title: t.t ?? "Untitled", artists: artists, albumID: t.al,
                                albumTitle: alb?.name ?? "", albumArtist: alb?.artist ?? artists[0],
                                trackNumber: t.n?.value ?? 0, discNumber: max(1, t.dk?.value ?? 1), duration: t.dur ?? 0,
                                year: t.y?.value ?? 0, addedAt: Date(timeIntervalSince1970: t.add ?? 0),
                                format: (t.ext ?? "").lowercased(), hasEmbeddedLyrics: t.ly ?? false, genres: genres,
                                coverID: t.al))
            durations[t.al, default: 0] += t.dur ?? 0
        }
        for a in wire.albums {
            albums.append(Album(id: a.id, title: a.name ?? "Unknown album", artist: a.artist ?? "Unknown artist",
                                year: a.year?.value ?? 0, trackIDs: a.tracks ?? [],
                                addedAt: Date(timeIntervalSince1970: a.added ?? 0), accentHex: a.c,
                                coverRevision: a.cv?.value, coverID: a.id, duration: durations[a.id] ?? 0))
        }
        let playlists = (wire.playlists ?? []).map { p in
            Playlist(id: p.id, name: p.name ?? "Playlist", trackIDs: p.tracks ?? [], total: p.total,
                     source: PlaylistSource(rawValue: p.src ?? "") ?? .unknown,
                     externalURL: (p.url ?? "").isEmpty ? nil : p.url,
                     modifiedAt: Date(timeIntervalSince1970: p.mtime ?? 0))
        }
        return LibrarySnapshot(version: wire.version?.value ?? "", tracks: tracks, albums: albums,
                               playlists: playlists, likes: wire.likes ?? [], genres: [])
    }

    // MARK: Media

    func needsTranscode(_ track: Track, _ quality: StreamQuality) -> Bool {
        switch quality {
        case .original: return !AudioFormats.isNative(track.format)
        case .efficient: return !AudioFormats.efficient.contains(track.format)
        }
    }

    public func streamURL(base: URL, track: Track, quality: StreamQuality) -> URL {
        base.appendingAPIPath("/api/tracks/\(track.id)/audio",
                              query: needsTranscode(track, quality) ? [URLQueryItem(name: "fmt", value: "aac")] : [])
    }

    public func downloadURL(base: URL, track: Track, quality: StreamQuality) -> URL {
        streamURL(base: base, track: track, quality: quality)
    }

    public func downloadExtension(track: Track, quality: StreamQuality) -> String {
        needsTranscode(track, quality) ? "m4a" : track.format
    }

    public func artworkURL(base: URL, album: Album, size: Int) -> URL? {
        var q = [URLQueryItem(name: "s", value: String(Self.artSize(size)))]
        if let rev = album.coverRevision, !rev.isEmpty { q.append(URLQueryItem(name: "v", value: rev)) }
        return base.appendingAPIPath("/api/albums/\(album.id)/cover.jpg", query: q)
    }

    public func artworkURL(base: URL, playlist: Playlist, size: Int) -> URL? {
        base.appendingAPIPath("/api/playlists/\(playlist.id)/cover.jpg",
                              query: [URLQueryItem(name: "s", value: String(Self.artSize(size))),
                                      URLQueryItem(name: "v", value: String(Int(playlist.modifiedAt.timeIntervalSince1970)))])
    }

    /// The server renders 128, 300 and 640 px.
    static func artSize(_ px: Int) -> Int {
        px <= 160 ? 128 : px <= 360 ? 300 : 640
    }

    // MARK: Features

    public func setLiked(base: URL, trackID: TrackID, liked: Bool) async throws -> [TrackID]? {
        let r: LikesResponse = try await http.post(base.appendingAPIPath("/api/tracks/\(trackID)/like"), json: ["liked": liked])
        return r.likes
    }

    public func lyrics(base: URL, track: Track) async throws -> Lyrics? {
        let w: WireLyrics = try await http.get(base.appendingAPIPath("/api/tracks/\(track.id)/lyrics"), timeout: 25)
        return Self.convert(w)
    }

    static func convert(_ w: WireLyrics) -> Lyrics? {
        guard let kindRaw = w.kind, let kind = Lyrics.Kind(rawValue: kindRaw), let raw = w.lines, !raw.isEmpty else { return nil }
        let lines = raw.enumerated().map { i, l in
            Lyrics.Line(id: i, start: l.t ?? 0, end: l.e, text: l.text ?? "",
                        words: (l.w ?? []).map { Lyrics.Word(start: $0.t ?? 0, end: $0.e ?? 0, text: $0.s ?? "") })
        }
        return Lyrics(kind: kind, source: w.source, lines: lines)
    }

    public func radio(base: URL, seed: RadioSeed, count: Int, exclude: [TrackID]) async throws -> [TrackID] {
        var body: [String: Any] = ["n": count, "exclude": Array(exclude.suffix(300)), "append": true]
        switch seed {
        case let .track(id): body["type"] = "track"; body["id"] = id
        case let .artist(name): body["type"] = "artist"; body["id"] = name
        case let .genre(name): body["type"] = "genre"; body["id"] = name
        }
        let r: IDList = try await http.post(base.appendingAPIPath("/api/radio"), json: body, timeout: 20)
        return r.tracks ?? []
    }

    public func semanticSearch(base: URL, query: String, limit: Int) async throws -> [ScoredTrack] {
        let url = base.appendingAPIPath("/api/search/semantic",
                                        query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))])
        let r: ScoredList = try await http.get(url, timeout: 25)
        return (r.tracks ?? []).map { ScoredTrack(id: $0.id, score: $0.score ?? 0) }
    }

    public func adventure(base: URL, from: TrackID, to: TrackID, steps: Int) async throws -> [TrackID] {
        let r: IDList = try await http.post(base.appendingAPIPath("/api/adventure"),
                                            json: ["start": from, "end": to, "steps": steps], timeout: 30)
        return r.tracks ?? []
    }

    public func reportNowPlaying(base: URL, _ report: NowPlayingReport) async {
        let body: [String: Any] = ["client_id": report.clientID, "client": "ios", "track_id": report.trackID ?? "",
                                   "playing": report.playing, "position": report.position, "duration": report.duration]
        _ = try? await http.data(http.request(base.appendingAPIPath("/api/now-playing"), method: "POST", json: body, timeout: 8))
    }

    public func prepare(base: URL, track: Track, quality: StreamQuality) async {
        let q = needsTranscode(track, quality) ? [URLQueryItem(name: "fmt", value: "aac")] : []
        _ = try? await http.data(http.request(base.appendingAPIPath("/api/tracks/\(track.id)/prepare", query: q),
                                              method: "POST", json: [String: String](), timeout: 8))
    }
}
