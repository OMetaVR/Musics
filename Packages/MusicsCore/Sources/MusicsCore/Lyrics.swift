import Foundation

public struct Lyrics: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Every word has its own timing (karaoke).
        case word
        /// Every line has a start time.
        case line
        /// Unsynced text.
        case plain
    }

    public struct Word: Codable, Hashable, Sendable {
        public var start: Double
        public var end: Double
        public var text: String
        public init(start: Double, end: Double, text: String) {
            self.start = start
            self.end = end
            self.text = text
        }
    }

    public struct Line: Codable, Hashable, Identifiable, Sendable {
        public var id: Int
        public var start: Double
        public var end: Double?
        public var text: String
        public var words: [Word]
        public init(id: Int, start: Double, end: Double?, text: String, words: [Word] = []) {
            self.id = id
            self.start = start
            self.end = end
            self.text = text
            self.words = words
        }
        public var isInstrumentalGap: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty || text == "♪" }
    }

    public var kind: Kind
    public var source: String?
    public var lines: [Line]

    public init(kind: Kind, source: String?, lines: [Line]) {
        self.kind = kind
        self.source = source
        self.lines = lines
    }

    public var isSynced: Bool { kind != .plain }

    /// Index of the line being sung at `time`, or nil before the first line.
    public func activeLineIndex(at time: Double) -> Int? {
        guard isSynced, !lines.isEmpty else { return nil }
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].start <= time + 0.001 {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }

    /// 0...1 progress through a word-synced line, for karaoke fill.
    public func progress(ofLine index: Int, at time: Double) -> Double {
        guard lines.indices.contains(index) else { return 0 }
        let line = lines[index]
        let end = line.end ?? (lines.indices.contains(index + 1) ? lines[index + 1].start : line.start + 4)
        guard end > line.start else { return time >= line.start ? 1 : 0 }
        return min(1, max(0, (time - line.start) / (end - line.start)))
    }

    /// Parses LRC text ("[mm:ss.xx] line"). Lines without timestamps make it plain.
    public static func parseLRC(_ text: String, source: String? = nil) -> Lyrics {
        var timed: [(Double, String)] = []
        var plain: [String] = []
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var stamps: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let t = parseStamp(tag) { stamps.append(t) } else if stamps.isEmpty { rest = ""; break }
                rest = rest[rest.index(after: close)...]
            }
            let body = rest.trimmingCharacters(in: .whitespaces)
            if stamps.isEmpty {
                if !body.isEmpty { plain.append(body) }
            } else {
                for s in stamps { timed.append((s, body)) }
            }
        }
        if timed.isEmpty {
            return Lyrics(kind: .plain, source: source,
                          lines: plain.enumerated().map { Line(id: $0.offset, start: 0, end: nil, text: $0.element) })
        }
        timed.sort { $0.0 < $1.0 }
        let lines = timed.enumerated().map { i, item in
            Line(id: i, start: item.0, end: i + 1 < timed.count ? timed[i + 1].0 : nil, text: item.1)
        }
        return Lyrics(kind: .line, source: source, lines: lines)
    }

    static func parseStamp(_ tag: Substring) -> Double? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1].replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        return m * 60 + s
    }
}
