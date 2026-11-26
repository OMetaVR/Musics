import Foundation

public typealias TrackID = String
public typealias AlbumID = String
public typealias PlaylistID = String

/// A song, normalized across server kinds.
public struct Track: Codable, Hashable, Identifiable, Sendable {
    public var id: TrackID
    public var title: String
    public var artists: [String]
    public var albumID: AlbumID
    public var albumTitle: String
    public var albumArtist: String
    public var trackNumber: Int
    public var discNumber: Int
    public var duration: Double
    public var year: Int
    public var addedAt: Date
    /// File extension / codec suffix as reported by the server ("opus", "mp3", "flac", ...).
    public var format: String
    public var hasEmbeddedLyrics: Bool
    public var genres: [String]
    /// Server-specific artwork key (Subsonic coverArt id). music.lan uses the album id.
    public var coverID: String?
    public var bitRate: Int?

    public init(id: TrackID, title: String, artists: [String], albumID: AlbumID, albumTitle: String,
                albumArtist: String, trackNumber: Int = 0, discNumber: Int = 1, duration: Double = 0,
                year: Int = 0, addedAt: Date = Date(timeIntervalSince1970: 0), format: String = "",
                hasEmbeddedLyrics: Bool = false, genres: [String] = [], coverID: String? = nil, bitRate: Int? = nil) {
        self.id = id
        self.title = title
        self.artists = artists
        self.albumID = albumID
        self.albumTitle = albumTitle
        self.albumArtist = albumArtist
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.duration = duration
        self.year = year
        self.addedAt = addedAt
        self.format = format
        self.hasEmbeddedLyrics = hasEmbeddedLyrics
        self.genres = genres
        self.coverID = coverID
        self.bitRate = bitRate
    }

    public var artistLine: String { artists.joined(separator: ", ") }
    public var primaryArtist: String { artists.first ?? albumArtist }
}

public struct Album: Codable, Hashable, Identifiable, Sendable {
    public var id: AlbumID
    public var title: String
    public var artist: String
    public var year: Int
    public var trackIDs: [TrackID]
    public var addedAt: Date
    /// Accent colour as "#rrggbb", when the server supplies one.
    public var accentHex: String?
    /// Changes when the server replaces the artwork; used to bust image caches.
    public var coverRevision: String?
    public var coverID: String?
    public var duration: Double

    public init(id: AlbumID, title: String, artist: String, year: Int = 0, trackIDs: [TrackID] = [],
                addedAt: Date = Date(timeIntervalSince1970: 0), accentHex: String? = nil,
                coverRevision: String? = nil, coverID: String? = nil, duration: Double = 0) {
        self.id = id
        self.title = title
        self.artist = artist
        self.year = year
        self.trackIDs = trackIDs
        self.addedAt = addedAt
        self.accentHex = accentHex
        self.coverRevision = coverRevision
        self.coverID = coverID
        self.duration = duration
    }
}

public enum PlaylistSource: String, Codable, Sendable {
    case spotify, m3u, server, unknown
}

public struct Playlist: Codable, Hashable, Identifiable, Sendable {
    public var id: PlaylistID
    public var name: String
    public var trackIDs: [TrackID]
    /// Number of entries in the source list, including ones the server couldn't match to a file.
    public var total: Int
    public var source: PlaylistSource
    public var externalURL: String?
    public var modifiedAt: Date
    public var coverID: String?
    public var comment: String?

    public init(id: PlaylistID, name: String, trackIDs: [TrackID], total: Int? = nil, source: PlaylistSource = .server,
                externalURL: String? = nil, modifiedAt: Date = Date(timeIntervalSince1970: 0),
                coverID: String? = nil, comment: String? = nil) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.total = max(total ?? trackIDs.count, trackIDs.count)
        self.source = source
        self.externalURL = externalURL
        self.modifiedAt = modifiedAt
        self.coverID = coverID
        self.comment = comment
    }

    public var missingCount: Int { max(0, total - trackIDs.count) }
}

public struct Genre: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var trackCount: Int
    public var coverAlbumID: AlbumID?
    public var id: String { name }

    public init(name: String, trackCount: Int, coverAlbumID: AlbumID? = nil) {
        self.name = name
        self.trackCount = trackCount
        self.coverAlbumID = coverAlbumID
    }
}

/// Derived from tracks and albums; not sent by servers.
public struct Artist: Hashable, Identifiable, Sendable {
    /// Normalized name, stable across casing differences.
    public var id: String
    public var name: String
    /// Albums whose album artist is this artist.
    public var albumIDs: [AlbumID]
    /// Albums by other album artists that contain a track by this artist.
    public var appearsOnAlbumIDs: [AlbumID]
    public var trackIDs: [TrackID]
}

/// Everything fetched from a server in one go, cached on disk between launches.
public struct LibrarySnapshot: Codable, Sendable {
    public var version: String
    public var fetchedAt: Date
    public var tracks: [Track]
    public var albums: [Album]
    public var playlists: [Playlist]
    public var likes: [TrackID]
    public var genres: [Genre]

    public init(version: String, fetchedAt: Date = Date(), tracks: [Track], albums: [Album],
                playlists: [Playlist], likes: [TrackID], genres: [Genre]) {
        self.version = version
        self.fetchedAt = fetchedAt
        self.tracks = tracks
        self.albums = albums
        self.playlists = playlists
        self.likes = likes
        self.genres = genres
    }

    public static let empty = LibrarySnapshot(version: "", fetchedAt: Date(timeIntervalSince1970: 0),
                                              tracks: [], albums: [], playlists: [], likes: [], genres: [])
}

public struct ScoredTrack: Codable, Hashable, Sendable {
    public var id: TrackID
    public var score: Double
    public init(id: TrackID, score: Double) {
        self.id = id
        self.score = score
    }
}

public enum StreamQuality: String, Codable, CaseIterable, Sendable {
    /// The file as stored, transcoded only when iOS can't decode it.
    case original
    /// AAC/MP3 around 160 kbit/s for cellular.
    case efficient
}

/// Formats AVFoundation decodes without help.
public enum AudioFormats {
    public static let native: Set<String> = ["mp3", "m4a", "aac", "mp4", "m4b", "alac", "flac", "wav", "aif", "aiff", "caf"]
    public static func isNative(_ ext: String) -> Bool { native.contains(ext.lowercased()) }
    public static let efficient: Set<String> = ["mp3", "m4a", "aac", "mp4", "m4b"]
}
