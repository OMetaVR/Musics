import Foundation

/// Local listening history: per-song counters and recently played contexts. Drives "Jump back in",
/// "Rediscover", search boosting and an artist's top songs.
public struct ListeningStats: Codable, Sendable {
    public struct TrackStats: Codable, Sendable, Hashable {
        public var plays: Int = 0
        public var skips: Int = 0
        public var lastPlayed: Date?
        public var firstPlayed: Date?
    }

    public struct RecentContext: Codable, Sendable, Hashable, Identifiable {
        public var context: PlaybackContext
        public var playedAt: Date
        public var id: String { "\(context.kind.rawValue):\(context.id ?? context.title)" }
    }

    public var tracks: [TrackID: TrackStats] = [:]
    public var recentContexts: [RecentContext] = []
    public var recentSearches: [String] = []

    public init() {}

    /// A play counts once the song has played for half its length or four minutes (Last.fm's rule).
    public static func countsAsPlay(listened: Double, duration: Double) -> Bool {
        listened >= min(240, max(duration, 30) / 2)
    }

    public mutating func recordPlay(_ id: TrackID, at date: Date = Date()) {
        var s = tracks[id] ?? TrackStats()
        s.plays += 1
        s.lastPlayed = date
        if s.firstPlayed == nil { s.firstPlayed = date }
        tracks[id] = s
    }

    /// Skipped within the first 30 seconds.
    public mutating func recordSkip(_ id: TrackID) {
        tracks[id, default: TrackStats()].skips += 1
    }

    public mutating func recordContext(_ context: PlaybackContext, at date: Date = Date()) {
        // Queue / search contexts aren't places you'd jump back into.
        guard ![.queue, .search].contains(context.kind) else { return }
        let entry = RecentContext(context: context, playedAt: date)
        recentContexts.removeAll { $0.id == entry.id }
        recentContexts.insert(entry, at: 0)
        if recentContexts.count > 40 { recentContexts.removeLast(recentContexts.count - 40) }
    }

    public mutating func recordSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        recentSearches.insert(q, at: 0)
        if recentSearches.count > 15 { recentSearches.removeLast(recentSearches.count - 15) }
    }

    public func plays(_ id: TrackID) -> Int { tracks[id]?.plays ?? 0 }

    /// Search boost: a little for liked songs, a little more for often-played ones.
    public func searchBoost(_ id: TrackID, liked: Bool) -> Double {
        (liked ? 6 : 0) + min(10, log2(Double(plays(id)) + 1) * 2.5)
    }

    /// Most played first, ties broken by recency.
    public func topTracks(among ids: [TrackID], limit: Int) -> [TrackID] {
        ids.filter { plays($0) > 0 }.sorted {
            let a = tracks[$0]!, b = tracks[$1]!
            if a.plays != b.plays { return a.plays > b.plays }
            return (a.lastPlayed ?? .distantPast) > (b.lastPlayed ?? .distantPast)
        }.prefix(limit).map { $0 }
    }

    /// Songs played at least three times but not in the last `days` days.
    public func rediscover(days: Int = 45, limit: Int = 50, now: Date = Date()) -> [TrackID] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        return tracks.filter { $0.value.plays >= 3 && ($0.value.lastPlayed ?? .distantPast) < cutoff }
            .sorted { $0.value.plays > $1.value.plays }
            .prefix(limit).map(\.key)
    }

    public var recentlyPlayedTracks: [TrackID] {
        tracks.filter { $0.value.lastPlayed != nil }.sorted { $0.value.lastPlayed! > $1.value.lastPlayed! }.prefix(50).map(\.key)
    }
}
