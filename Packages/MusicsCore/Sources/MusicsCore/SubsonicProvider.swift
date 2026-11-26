import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Subsonic / OpenSubsonic API (Navidrome, Gonic, Airsonic-Advanced, Ampache…).
public struct SubsonicProvider: MusicProvider {
    public let username: String
    public let password: String
    public let http: HTTPClient
    public static let clientName = "Musics"
    public static let apiVersion = "1.16.1"

    public var kind: ServerKind { .subsonic }
    public var capabilities: ProviderCapabilities { [.likes, .lyrics, .radio, .genreRadio, .scrobble, .nowPlaying, .transcoding] }
    public var mediaHeaders: [String: String] { http.headers }

    public init(username: String, password: String, http: HTTPClient) {
        self.username = username
        self.password = password
        self.http = http
    }

    // MARK: URLs

    /// `salt` is random per request unless given. Artwork uses a salt derived from the picture so the
    /// URL (the image cache key) stays the same between requests.
    func authQuery(salt fixedSalt: String? = nil) -> [URLQueryItem] {
        let salt = fixedSalt ?? String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
        return [URLQueryItem(name: "u", value: username),
                URLQueryItem(name: "t", value: MD5.hex(password + salt)),
                URLQueryItem(name: "s", value: salt),
                URLQueryItem(name: "v", value: Self.apiVersion),
                URLQueryItem(name: "c", value: Self.clientName),
                URLQueryItem(name: "f", value: "json")]
    }

    func url(_ base: URL, _ method: String, _ params: [String: String?] = [:], stableSalt: Bool = false) -> URL {
        let extra = params.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }.sorted { $0.name < $1.name }
        let salt = stableSalt ? String(MD5.hex("musics|" + extra.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")).prefix(12)) : nil
        return base.appendingAPIPath("/rest/\(method).view", query: authQuery(salt: salt) + extra)
    }

    // MARK: Wire format

    struct Envelope<T: Decodable>: Decodable {
        let response: T
        enum CodingKeys: String, CodingKey { case response = "subsonic-response" }
    }

    struct Status: Decodable {
        struct Err: Decodable { let code: Int?; let message: String? }
        let status: String
        let error: Err?
        let openSubsonic: Bool?
    }

    struct NamedRef: Decodable { let id: String?; let name: String? }
    struct GenreRef: Decodable { let name: String? }

    struct Song: Decodable {
        let id: String
        let title: String?
        let album: String?
        let albumId: String?
        let artist: String?
        let artists: [NamedRef]?
        let displayAlbumArtist: String?
        let albumArtists: [NamedRef]?
        let track: LossyInt?
        let discNumber: LossyInt?
        let year: LossyInt?
        let genre: String?
        let genres: [GenreRef]?
        let coverArt: String?
        let duration: Double?
        let bitRate: Int?
        let suffix: String?
        let created: String?
        let starred: String?
        let isDir: Bool?
    }

    struct AlbumWire: Decodable {
        let id: String
        let name: String?
        let artist: String?
        let coverArt: String?
        let songCount: Int?
        let duration: Double?
        let created: String?
        let year: LossyInt?
        let song: [Song]?
    }

    struct PlaylistWire: Decodable {
        let id: String
        let name: String?
        let comment: String?
        let songCount: Int?
        let changed: String?
        let coverArt: String?
        let entry: [Song]?
    }

    struct SearchResponse: Decodable {
        struct R: Decodable { let song: [Song]? }
        let searchResult3: R?
    }
    struct AlbumListResponse: Decodable {
        struct R: Decodable { let album: [AlbumWire]? }
        let albumList2: R?
    }
    struct AlbumResponse: Decodable { let album: AlbumWire? }
    struct PlaylistsResponse: Decodable {
        struct R: Decodable { let playlist: [PlaylistWire]? }
        let playlists: R?
    }
    struct PlaylistResponse: Decodable { let playlist: PlaylistWire? }
    struct StarredResponse: Decodable {
        struct R: Decodable { let song: [Song]? }
        let starred2: R?
    }
    struct GenresResponse: Decodable {
        struct G: Decodable { let value: String?; let songCount: Int? }
        struct R: Decodable { let genre: [G]? }
        let genres: R?
    }
    struct ScanStatusResponse: Decodable {
        struct S: Decodable { let count: Int?; let lastScan: String?; let scanning: Bool? }
        let scanStatus: S?
    }
    struct SongsResponse: Decodable {
        struct R: Decodable { let song: [Song]? }
        let similarSongs2: R?
        let similarSongs: R?
        let randomSongs: R?
        let topSongs: R?
        let songsByGenre: R?
    }
    struct LyricsListResponse: Decodable {
        struct Line: Decodable { let start: Double?; let value: String? }
        struct Structured: Decodable { let synced: Bool?; let offset: Double?; let line: [Line]? }
        struct R: Decodable { let structuredLyrics: [Structured]? }
        let lyricsList: R?
    }
    struct LegacyLyricsResponse: Decodable {
        struct R: Decodable { let value: String? }
        let lyrics: R?
    }

    func call<T: Decodable>(_ base: URL, _ method: String, _ params: [String: String?] = [:], timeout: TimeInterval? = nil) async throws -> T {
        let data = try await http.data(http.request(url(base, method, params), timeout: timeout))
        let status = try http.decode(Envelope<Status>.self, from: data).response
        if status.status != "ok" {
            throw MusicsError.server(status.error?.message ?? "Subsonic error \(status.error?.code ?? 0)")
        }
        return try http.decode(Envelope<T>.self, from: data).response
    }

    // MARK: Library

    public func probeRequest(base: URL) -> URLRequest {
        http.request(url(base, "ping"), timeout: 4)
    }

    public func libraryVersion(base: URL) async throws -> String {
        let r: ScanStatusResponse = try await call(base, "getScanStatus", timeout: 8)
        guard let s = r.scanStatus else { return "" }
        return "\(s.count ?? 0)|\(s.lastScan ?? "")"
    }

    public func fetchLibrary(base: URL) async throws -> LibrarySnapshot {
        let version = (try? await libraryVersion(base: base)) ?? ""
        // Albums (for titles, dates and artwork ids).
        var albumWires: [AlbumWire] = []
        var offset = 0
        while true {
            let r: AlbumListResponse = try await call(base, "getAlbumList2", ["type": "alphabeticalByName", "size": "500",
                                                                              "offset": String(offset)], timeout: 60)
            let page = r.albumList2?.album ?? []
            albumWires += page
            if page.count < 500 { break }
            offset += 500
        }
        // Songs: an empty search3 query lists everything on Navidrome and most OpenSubsonic servers.
        var songs: [Song] = []
        offset = 0
        while true {
            let r: SearchResponse = try await call(base, "search3", ["query": "", "songCount": "500", "songOffset": String(offset),
                                                                     "albumCount": "0", "artistCount": "0"], timeout: 60)
            let page = r.searchResult3?.song ?? []
            songs += page
            if page.count < 500 { break }
            offset += 500
        }
        if songs.isEmpty, !albumWires.isEmpty {
            // Servers that need a non-empty query: walk albums instead.
            songs = try await withThrowingTaskGroup(of: [Song].self) { group in
                var out: [Song] = []
                var it = albumWires.makeIterator()
                for _ in 0..<6 { if let a = it.next() { group.addTask { try await albumSongs(base, a.id) } } }
                while let batch = try await group.next() {
                    out += batch
                    if let a = it.next() { group.addTask { try await albumSongs(base, a.id) } }
                }
                return out
            }
        }
        let starred: StarredResponse? = try? await call(base, "getStarred2")
        let genres: GenresResponse? = try? await call(base, "getGenres")
        let playlists = (try? await fetchPlaylists(base)) ?? []
        return Self.assemble(version: version, albums: albumWires, songs: songs,
                             starred: (starred?.starred2?.song ?? []).map(\.id),
                             genres: genres?.genres?.genre ?? [], playlists: playlists)
    }

    func albumSongs(_ base: URL, _ id: String) async throws -> [Song] {
        let r: AlbumResponse = try await call(base, "getAlbum", ["id": id])
        return r.album?.song ?? []
    }

    func fetchPlaylists(_ base: URL) async throws -> [Playlist] {
        let r: PlaylistsResponse = try await call(base, "getPlaylists")
        var out: [Playlist] = []
        for p in r.playlists?.playlist ?? [] {
            let full: PlaylistResponse? = try? await call(base, "getPlaylist", ["id": p.id])
            let entries = full?.playlist?.entry ?? []
            out.append(Playlist(id: p.id, name: p.name ?? "Playlist", trackIDs: entries.map(\.id), total: p.songCount,
                                source: .server, modifiedAt: Self.date(p.changed) ?? Date(timeIntervalSince1970: 0),
                                coverID: p.coverArt, comment: p.comment))
        }
        return out
    }

    static func track(_ s: Song) -> Track {
        let artists = (s.artists ?? []).compactMap(\.name).filter { !$0.isEmpty }
        let artistList = artists.isEmpty ? [s.artist ?? "Unknown artist"] : artists
        let albumArtist = s.displayAlbumArtist ?? s.albumArtists?.first?.name ?? s.artist ?? artistList[0]
        var genres = (s.genres ?? []).compactMap(\.name).map { $0.lowercased() }
        if genres.isEmpty, let g = s.genre, !g.isEmpty { genres = [g.lowercased()] }
        return Track(id: s.id, title: s.title ?? "Untitled", artists: artistList, albumID: s.albumId ?? "",
                     albumTitle: s.album ?? "", albumArtist: albumArtist, trackNumber: s.track?.value ?? 0,
                     discNumber: max(1, s.discNumber?.value ?? 1), duration: s.duration ?? 0, year: s.year?.value ?? 0,
                     addedAt: date(s.created) ?? Date(timeIntervalSince1970: 0), format: (s.suffix ?? "").lowercased(),
                     hasEmbeddedLyrics: false, genres: genres, coverID: s.coverArt, bitRate: s.bitRate)
    }

    static func assemble(version: String, albums wires: [AlbumWire], songs: [Song], starred: [String],
                         genres: [GenresResponse.G], playlists: [Playlist]) -> LibrarySnapshot {
        var seen = Set<String>()
        let tracks = songs.filter { $0.isDir != true && seen.insert($0.id).inserted }.map(track)
        var byAlbum = [String: [Track]]()
        for t in tracks { byAlbum[t.albumID, default: []].append(t) }
        var albums: [Album] = []
        var known = Set<String>()
        for a in wires {
            known.insert(a.id)
            let ts = (byAlbum[a.id] ?? []).sorted { ($0.discNumber, $0.trackNumber, $0.title) < ($1.discNumber, $1.trackNumber, $1.title) }
            guard !ts.isEmpty else { continue }
            albums.append(Album(id: a.id, title: a.name ?? "Unknown album", artist: a.artist ?? ts[0].albumArtist,
                                year: a.year?.value ?? ts[0].year, trackIDs: ts.map(\.id),
                                addedAt: date(a.created) ?? ts.map(\.addedAt).max() ?? Date(timeIntervalSince1970: 0),
                                coverID: a.coverArt ?? ts[0].coverID, duration: a.duration ?? ts.reduce(0) { $0 + $1.duration }))
        }
        // Songs whose album wasn't in the album list (rare): synthesize albums from tags.
        for (aid, ts) in byAlbum where !known.contains(aid) {
            let sorted = ts.sorted { ($0.discNumber, $0.trackNumber) < ($1.discNumber, $1.trackNumber) }
            albums.append(Album(id: aid, title: sorted[0].albumTitle, artist: sorted[0].albumArtist, year: sorted[0].year,
                                trackIDs: sorted.map(\.id), addedAt: sorted.map(\.addedAt).max()!, coverID: sorted[0].coverID,
                                duration: sorted.reduce(0) { $0 + $1.duration }))
        }
        let genreList = genres.compactMap { g -> Genre? in
            guard let name = g.value?.lowercased(), !name.isEmpty, (g.songCount ?? 0) > 0 else { return nil }
            return Genre(name: name, trackCount: g.songCount ?? 0)
        }
        return LibrarySnapshot(version: version, tracks: tracks, albums: albums, playlists: playlists, likes: starred,
                               genres: genreList)
    }

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: Media

    func transcodeFormat(_ track: Track, _ quality: StreamQuality) -> String? {
        switch quality {
        case .original: return AudioFormats.isNative(track.format) ? nil : "mp3"
        case .efficient: return AudioFormats.efficient.contains(track.format) && (track.bitRate ?? 0) <= 192 ? nil : "mp3"
        }
    }

    public func streamURL(base: URL, track: Track, quality: StreamQuality) -> URL {
        if let fmt = transcodeFormat(track, quality) {
            return url(base, "stream", ["id": track.id, "format": fmt, "maxBitRate": quality == .efficient ? "160" : "320"])
        }
        return url(base, "stream", ["id": track.id, "format": "raw"])
    }

    public func downloadURL(base: URL, track: Track, quality: StreamQuality) -> URL {
        transcodeFormat(track, quality) == nil ? url(base, "download", ["id": track.id]) : streamURL(base: base, track: track, quality: quality)
    }

    public func downloadExtension(track: Track, quality: StreamQuality) -> String {
        transcodeFormat(track, quality) ?? track.format
    }

    public func artworkURL(base: URL, album: Album, size: Int) -> URL? {
        guard let id = album.coverID else { return nil }
        return url(base, "getCoverArt", ["id": id, "size": String(size)], stableSalt: true)
    }

    public func artworkURL(base: URL, playlist: Playlist, size: Int) -> URL? {
        guard let id = playlist.coverID else { return nil }
        return url(base, "getCoverArt", ["id": id, "size": String(size)], stableSalt: true)
    }

    // MARK: Features

    public func setLiked(base: URL, trackID: TrackID, liked: Bool) async throws -> [TrackID]? {
        let _: Status = try await call(base, liked ? "star" : "unstar", ["id": trackID])
        return nil
    }

    public func lyrics(base: URL, track: Track) async throws -> Lyrics? {
        if let r: LyricsListResponse = try? await call(base, "getLyricsBySongId", ["id": track.id], timeout: 20),
           let list = r.lyricsList?.structuredLyrics, !list.isEmpty {
            let best = list.first { $0.synced == true } ?? list[0]
            let offset = (best.offset ?? 0) / 1000
            let raw = best.line ?? []
            let synced = best.synced == true
            let lines = raw.enumerated().map { i, l in
                Lyrics.Line(id: i, start: synced ? max(0, (l.start ?? 0) / 1000 - offset) : 0,
                            end: synced && i + 1 < raw.count ? (raw[i + 1].start ?? 0) / 1000 - offset : nil,
                            text: l.value ?? "")
            }
            if !lines.isEmpty { return Lyrics(kind: synced ? .line : .plain, source: "Server", lines: lines) }
        }
        let r: LegacyLyricsResponse = try await call(base, "getLyrics", ["artist": track.primaryArtist, "title": track.title], timeout: 20)
        guard let text = r.lyrics?.value, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Lyrics.parseLRC(text, source: "Server")
    }

    public func radio(base: URL, seed: RadioSeed, count: Int, exclude: [TrackID]) async throws -> [TrackID] {
        let ex = Set(exclude)
        let r: SongsResponse
        switch seed {
        case let .track(id):
            r = try await call(base, "getSimilarSongs2", ["id": id, "count": String(count)], timeout: 20)
        case let .artist(name):
            r = try await call(base, "getTopSongs", ["artist": name, "count": String(count)], timeout: 20)
        case let .genre(name):
            r = try await call(base, "getRandomSongs", ["genre": name, "size": String(count)], timeout: 20)
        }
        let songs = r.similarSongs2?.song ?? r.similarSongs?.song ?? r.topSongs?.song ?? r.randomSongs?.song ?? []
        return songs.map(\.id).filter { !ex.contains($0) }
    }

    public func reportNowPlaying(base: URL, _ report: NowPlayingReport) async {
        guard let id = report.trackID, report.playing, report.position < 5 else { return }
        _ = try? await http.data(http.request(url(base, "scrobble", ["id": id, "submission": "false"]), timeout: 8))
    }

    public func scrobble(base: URL, trackID: TrackID, at date: Date) async {
        let ms = String(Int(date.timeIntervalSince1970 * 1000))
        _ = try? await http.data(http.request(url(base, "scrobble", ["id": trackID, "time": ms, "submission": "true"]), timeout: 8))
    }
}
