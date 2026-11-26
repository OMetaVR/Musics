import Foundation

/// Shuffle that spreads each artist's songs evenly through the list, so the same artist
/// (or album) rarely plays twice in a row. Each artist's songs get evenly spaced slots with
/// a random offset and jitter, then everything is sorted by slot.
public enum SpreadShuffle {
    public static func shuffle<T, G: RandomNumberGenerator>(_ items: [T], groupKey: (T) -> String,
                                                             using rng: inout G) -> [T] {
        guard items.count > 2 else { return items.shuffled(using: &rng) }
        var groups = [String: [T]]()
        var order: [String] = []
        for item in items {
            let k = groupKey(item)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(item)
        }
        if groups.count == 1 { return items.shuffled(using: &rng) }
        var slotted: [(Double, T)] = []
        slotted.reserveCapacity(items.count)
        for k in order {
            let members = groups[k]!.shuffled(using: &rng)
            let n = Double(members.count)
            let spacing = 1.0 / n
            let offset = Double.random(in: 0..<spacing, using: &rng)
            for (i, m) in members.enumerated() {
                let jitter = Double.random(in: -0.1...0.1, using: &rng) * spacing
                slotted.append((offset + Double(i) * spacing + jitter, m))
            }
        }
        slotted.sort { $0.0 < $1.0 }
        return slotted.map(\.1)
    }

    public static func shuffle<T>(_ items: [T], groupKey: (T) -> String) -> [T] {
        var rng = SystemRandomNumberGenerator()
        return shuffle(items, groupKey: groupKey, using: &rng)
    }
}

/// Deterministic generator for tests and reproducible shuffles.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
