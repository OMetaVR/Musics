import Foundation

/// Lookups and derived collections over a `LibrarySnapshot`. Built once per snapshot, off the main thread.
public final class LibraryIndex: @unchecked Sendable {
    public let snapshot: LibrarySnapshot
    public let tracks: [TrackID: Track]
    public let albums: [AlbumID: Album]
    public let playlists: [PlaylistID: Playlist]
    public let artists: [String: Artist]
    public let genres: [Genre]
    public let genreTracks: [String: [TrackID]]

    /// Albums newest first.
    public let albumsByAdded: [Album]
    /// Albums A–Z by title.
    public let albumsByTitle: [Album]
    /// Artists A–Z, only those that are an album artist or have at least one track.
    public let artistsByName: [Artist]
    /// All songs A–Z by title.
    public let tracksByTitle: [Track]
    public let playlistsByName: [Playlist]
    public let search: SearchIndex

    public init(_ snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
        var tracks = [TrackID: Track](minimumCapacity: snapshot.tracks.count)
        for t in snapshot.tracks { tracks[t.id] = t }
        var albums = [AlbumID: Album](minimumCapacity: snapshot.albums.count)
        for a in snapshot.albums { albums[a.id] = a }
        var playlists = [PlaylistID: Playlist]()
        for p in snapshot.playlists {
            var p = p
            p.trackIDs = p.trackIDs.filter { tracks[$0] != nil }
            playlists[p.id] = p
        }
        self.tracks = tracks
        self.albums = albums
        self.playlists = playlists

        // Artists: keyed by normalized name; display name is the first spelling seen.
        let norm = NormalizeCache()
        var artists = [String: Artist]()
        func touch(_ name: String) -> String {
            let key = norm.key(name)
            if artists[key] == nil {
                artists[key] = Artist(id: key, name: name, albumIDs: [], appearsOnAlbumIDs: [], trackIDs: [])
            }
            return key
        }
        for album in snapshot.albums {
            let key = touch(album.artist)
            artists[key]?.albumIDs.append(album.id)
        }
        var appears = [String: Set<AlbumID>]()
        for t in snapshot.tracks {
            for name in t.artists {
                let key = touch(name)
                artists[key]?.trackIDs.append(t.id)
                if norm.key(t.albumArtist) != key {
                    appears[key, default: []].insert(t.albumID)
                }
            }
        }
        for (key, set) in appears {
            artists[key]?.appearsOnAlbumIDs = set.compactMap { albums[$0] }
                .sorted { ($0.year, $0.title) > ($1.year, $1.title) }.map(\.id)
        }
        for key in Array(artists.keys) {
            artists[key]?.albumIDs.sort { (albums[$0]?.year ?? 0, albums[$0]?.title ?? "") > (albums[$1]?.year ?? 0, albums[$1]?.title ?? "") }
        }
        // "Unknown artist" style placeholders stay, but drop entries with nothing to show.
        artists = artists.filter { !$0.value.albumIDs.isEmpty || !$0.value.trackIDs.isEmpty }
        self.artists = artists

        // Genres: prefer what the server sent, else count from tracks.
        var gTracks = [String: [TrackID]]()
        for t in snapshot.tracks { for g in t.genres { gTracks[g, default: []].append(t.id) } }
        self.genreTracks = gTracks
        if !snapshot.genres.isEmpty {
            genres = snapshot.genres.sorted { $0.trackCount > $1.trackCount }
        } else {
            genres = gTracks.map { name, ids in
                Genre(name: name, trackCount: ids.count, coverAlbumID: ids.first.flatMap { tracks[$0]?.albumID })
            }.filter { $0.trackCount >= 3 }.sorted { $0.trackCount > $1.trackCount }
        }

        albumsByAdded = snapshot.albums.sorted { $0.addedAt > $1.addedAt }
        // Sort keys computed once per item, not once per comparison.
        func sorted<T>(_ items: [T], by text: (T) -> String) -> [T] {
            items.map { (norm.sortKey(text($0)), $0) }.sorted { $0.0 < $1.0 }.map(\.1)
        }
        albumsByTitle = sorted(snapshot.albums) { $0.title }
        artistsByName = sorted(Array(artists.values)) { $0.name }
        tracksByTitle = sorted(snapshot.tracks) { $0.title }
        playlistsByName = playlists.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        search = SearchIndex(tracks: snapshot.tracks, albums: snapshot.albums, artists: Array(artists.values),
                             playlists: Array(playlists.values), genres: genres, cache: norm)
    }

    public static let empty = LibraryIndex(.empty)

    public func tracks(_ ids: [TrackID]) -> [Track] { ids.compactMap { tracks[$0] } }

    public func albumTracks(_ albumID: AlbumID) -> [Track] {
        tracks(albums[albumID]?.trackIDs ?? [])
    }

    public func artist(named name: String) -> Artist? { artists[TextNormalizer.key(name)] }

    /// Album ids for an artist split into full albums (3+ songs) and singles/EPs.
    public func discography(_ artist: Artist) -> (albums: [Album], singles: [Album]) {
        let all = artist.albumIDs.compactMap { albums[$0] }
        return (all.filter { $0.trackIDs.count >= 4 }, all.filter { $0.trackIDs.count < 4 })
    }

    public var totalDuration: Double { snapshot.tracks.reduce(0) { $0 + $1.duration } }
}
