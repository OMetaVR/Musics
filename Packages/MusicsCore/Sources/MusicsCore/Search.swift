import Foundation

public enum TextNormalizer {
    /// Lower-case, accent-free, punctuation turned into spaces, whitespace collapsed.
    public static func normalize(_ s: String) -> String {
        // Folding is the expensive part; plain ASCII only needs lower-casing.
        let ascii = s.utf8.allSatisfy { $0 < 128 }
        let folded = ascii ? s.lowercased()
            : s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var out = ""
        out.reserveCapacity(folded.utf8.count)
        var lastSpace = true
        for ch in folded.unicodeScalars {
            let v = ch.value
            let isAlnum = v < 128 ? ((v >= 97 && v <= 122) || (v >= 48 && v <= 57) || (v >= 65 && v <= 90))
                                  : CharacterSet.alphanumerics.contains(ch)
            if isAlnum {
                out.unicodeScalars.append(ch)
                lastSpace = false
            } else if ch == "&" {
                if !lastSpace { out.append(" ") }
                out.append("and ")
                lastSpace = true
            } else if ch == "'" || ch == "’" || ch == "." {
                continue  // "don't" → "dont", "m.i.a" → "mia"
            } else if !lastSpace {
                out.append(" ")
                lastSpace = true
            }
        }
        if out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    /// Key used to merge artist spellings ("The Weeknd" == "the weeknd").
    public static func key(_ s: String) -> String {
        let n = normalize(s)
        return n.isEmpty ? s.lowercased() : n
    }

    /// Sort key that ignores leading articles and symbols, so "The Beatles" sorts under B.
    public static func sortKey(_ s: String) -> String {
        var n = normalize(s)
        for article in ["the ", "a ", "an "] where n.hasPrefix(article) && n.count > article.count {
            n.removeFirst(article.count)
            break
        }
        return n
    }

    /// The A–Z section a title belongs to ("#" for digits and symbols).
    public static func sectionLetter(_ s: String) -> String {
        guard let first = sortKey(s).unicodeScalars.first else { return "#" }
        if first.value >= 97 && first.value <= 122 { return String(first).uppercased() }
        return "#"
    }
}

/// Memoizes normalization while building an index; artist and album names repeat a lot.
public final class NormalizeCache {
    private var normalized = [String: String]()
    private var sortKeys = [String: String]()
    public init() {}

    public func normalize(_ s: String) -> String {
        if let n = normalized[s] { return n }
        let n = TextNormalizer.normalize(s)
        normalized[s] = n
        return n
    }

    public func key(_ s: String) -> String {
        let n = normalize(s)
        return n.isEmpty ? s.lowercased() : n
    }

    public func sortKey(_ s: String) -> String {
        if let k = sortKeys[s] { return k }
        var n = normalize(s)
        for article in ["the ", "a ", "an "] where n.hasPrefix(article) && n.count > article.count {
            n.removeFirst(article.count)
            break
        }
        sortKeys[s] = n
        return n
    }
}

public struct SearchResults: Sendable {
    public enum Top: Sendable, Hashable {
        case track(TrackID), album(AlbumID), artist(String), playlist(PlaylistID), genre(String)
    }

    public var query: String
    public var top: Top?
    public var tracks: [TrackID] = []
    public var albums: [AlbumID] = []
    public var artists: [String] = []
    public var playlists: [PlaylistID] = []
    public var genres: [String] = []

    public var isEmpty: Bool { tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty && genres.isEmpty }
}

/// In-memory search over the whole library. Typo tolerant, accent and punctuation insensitive.
public final class SearchIndex: @unchecked Sendable {
    struct Entry {
        let id: String
        /// Words of the primary field (title / name).
        let primary: [String]
        let primaryJoined: String
        /// Words of secondary fields (artist, album).
        let secondary: [String]
    }

    private let tracks: [Entry]
    private let albums: [Entry]
    private let artists: [Entry]
    private let playlists: [Entry]
    private let genres: [Entry]

    public init(tracks: [Track], albums: [Album], artists: [Artist], playlists: [Playlist], genres: [Genre],
                cache: NormalizeCache = NormalizeCache()) {
        func entry(_ id: String, _ primary: String, _ secondary: [String]) -> Entry {
            let p = cache.normalize(primary)
            let s = secondary.map(cache.normalize).joined(separator: " ")
            return Entry(id: id, primary: p.split(separator: " ").map(String.init), primaryJoined: p,
                         secondary: s.split(separator: " ").map(String.init))
        }
        self.tracks = tracks.map { entry($0.id, $0.title, $0.artists + [$0.albumTitle]) }
        self.albums = albums.map { entry($0.id, $0.title, [$0.artist]) }
        self.artists = artists.map { entry($0.id, $0.name, []) }
        self.playlists = playlists.map { entry($0.id, $0.name, []) }
        self.genres = genres.map { entry($0.name, $0.name, []) }
    }

    /// `boost` lets the caller favour liked or often-played songs (added to the score).
    public func search(_ query: String, limit: Int = 50, boost: ((TrackID) -> Double)? = nil) -> SearchResults {
        let q = TextNormalizer.normalize(query)
        var results = SearchResults(query: query)
        let tokens = q.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return results }

        func run(_ entries: [Entry], limit: Int, boost: ((String) -> Double)? = nil) -> [(String, Double)] {
            var hits: [(String, Double)] = []
            for e in entries {
                if var s = Self.score(e, q: q, tokens: tokens, fuzzy: false) {
                    if let boost { s += boost(e.id) }
                    hits.append((e.id, s))
                }
            }
            if hits.count < 5 {
                // Nothing (or little) matched exactly: allow one typo per word.
                let have = Set(hits.map(\.0))
                for e in entries where !have.contains(e.id) {
                    if let s = Self.score(e, q: q, tokens: tokens, fuzzy: true) { hits.append((e.id, s)) }
                }
            }
            hits.sort { $0.1 > $1.1 }
            return Array(hits.prefix(limit))
        }

        let t = run(tracks, limit: limit, boost: boost)
        let al = run(albums, limit: 24)
        let ar = run(artists, limit: 24)
        let pl = run(playlists, limit: 24)
        let g = run(genres, limit: 12)
        results.tracks = t.map(\.0)
        results.albums = al.map(\.0)
        results.artists = ar.map(\.0)
        results.playlists = pl.map(\.0)
        results.genres = g.map(\.0)

        // Top result: the best exact-ish match across kinds, with a small bias toward artists and albums
        // (searching an artist's name should surface the artist, not their song of the same name).
        var best: (SearchResults.Top, Double)?
        func consider(_ top: SearchResults.Top, _ score: Double?) {
            guard let score else { return }
            if best == nil || score > best!.1 { best = (top, score) }
        }
        consider(ar.first.map { .artist($0.0) } ?? .artist(""), ar.first.map { $0.1 + 6 })
        consider(al.first.map { .album($0.0) } ?? .album(""), al.first.map { $0.1 + 2 })
        consider(pl.first.map { .playlist($0.0) } ?? .playlist(""), pl.first.map { $0.1 + 1 })
        consider(t.first.map { .track($0.0) } ?? .track(""), t.first?.1)
        consider(g.first.map { .genre($0.0) } ?? .genre(""), g.first.map { $0.1 - 4 })
        results.top = best?.0
        return results
    }

    static func score(_ e: Entry, q: String, tokens: [String], fuzzy: Bool) -> Double? {
        if !fuzzy {
            if e.primaryJoined == q { return 100 }
            if e.primaryJoined.hasPrefix(q) { return 85 - Double(min(e.primaryJoined.count - q.count, 20)) * 0.3 }
        }
        var score = 0.0
        var primaryHits = 0
        for (i, tok) in tokens.enumerated() {
            let isLast = i == tokens.count - 1
            if let s = match(tok, in: e.primary, prefixOK: isLast || tok.count >= 3, fuzzy: fuzzy) {
                score += s
                primaryHits += 1
            } else if let s = match(tok, in: e.secondary, prefixOK: isLast || tok.count >= 3, fuzzy: fuzzy) {
                score += s * 0.6
            } else {
                return nil
            }
        }
        var total = score / Double(tokens.count) * 60
        if primaryHits == tokens.count { total += 10 }
        if fuzzy { total *= 0.5 }
        return total
    }

    /// 1.0 for an exact word, 0.8 for a prefix, 0.5 for a one-edit typo.
    static func match(_ tok: String, in words: [String], prefixOK: Bool, fuzzy: Bool) -> Double? {
        var best: Double?
        for w in words {
            if w == tok { return 1 }
            if prefixOK, w.hasPrefix(tok) { best = max(best ?? 0, 0.8) }
            if fuzzy, best == nil, tok.count >= 4 {
                let prefix = String(w.prefix(tok.count))
                if abs(prefix.count - tok.count) <= 1, editDistance(tok, prefix, max: 1) <= 1 { best = 0.5 }
            }
        }
        return best
    }

    /// Damerau–Levenshtein (optimal string alignment), bailing out above `max`.
    static func editDistance(_ a: String, _ b: String, max: Int) -> Int {
        let a = Array(a.unicodeScalars), b = Array(b.unicodeScalars)
        if abs(a.count - b.count) > max { return max + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev2 = [Int](repeating: 0, count: b.count + 1)
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    cur[j] = Swift.min(cur[j], prev2[j - 2] + 1)
                }
                rowMin = Swift.min(rowMin, cur[j])
            }
            if rowMin > max { return max + 1 }
            (prev2, prev, cur) = (prev, cur, prev2)
        }
        return prev[b.count]
    }
}
