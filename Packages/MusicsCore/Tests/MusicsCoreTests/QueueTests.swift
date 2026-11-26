import XCTest
@testable import MusicsCore

final class QueueTests: XCTestCase {
    let ctx = PlaybackContext(kind: .album, id: "a1", title: "Album")

    func ids(_ items: [QueueItem]) -> [String] { items.map(\.trackID) }

    func testPlayFromMiddleAndAdvance() {
        var q = PlaybackQueue()
        q.play(["1", "2", "3", "4"], startAt: 1, context: ctx, shuffle: false)
        XCTAssertEqual(q.current?.trackID, "2")
        XCTAssertEqual(ids(q.upcoming), ["3", "4"])
        XCTAssertEqual(q.advance(auto: true)?.trackID, "3")
        XCTAssertEqual(q.advance(auto: true)?.trackID, "4")
        XCTAssertNil(q.advance(auto: true), "end of queue stays put")
        XCTAssertEqual(q.current?.trackID, "4")
        XCTAssertEqual(ids(q.history), ["2", "3"])
    }

    func testPlayNextGoesBeforeContextAndAddToQueueAfterUserItems() {
        var q = PlaybackQueue()
        q.play(["1", "2", "3"], startAt: 0, context: ctx, shuffle: false)
        q.addToQueue(["x"])
        q.addToQueue(["y"])
        q.playNext(["n"])
        XCTAssertEqual(ids(q.upcoming), ["n", "x", "y", "2", "3"])
        XCTAssertEqual(q.advance(auto: true)?.trackID, "n")
    }

    func testPreviousReturnsItemsToTheirSections() {
        var q = PlaybackQueue()
        q.play(["1", "2", "3"], startAt: 0, context: ctx, shuffle: false)
        q.playNext(["u"])
        q.advance(auto: true)  // u
        q.advance(auto: true)  // 2
        XCTAssertEqual(q.current?.trackID, "2")
        q.previous()           // back to u, 2 returns to context front
        XCTAssertEqual(q.current?.trackID, "u")
        XCTAssertEqual(ids(q.upNext), [])
        XCTAssertEqual(ids(q.context), ["2", "3"])
        q.previous()
        XCTAssertEqual(q.current?.trackID, "1")
        XCTAssertEqual(ids(q.upNext), ["u"])
    }

    func testRepeatOneRepeatsOnlyOnAutoAdvance() {
        var q = PlaybackQueue()
        q.play(["1", "2"], startAt: 0, context: ctx, shuffle: false)
        q.repeatMode = .one
        XCTAssertEqual(q.advance(auto: true)?.trackID, "1")
        XCTAssertEqual(q.nextItemOnEnd?.trackID, "1")
        XCTAssertEqual(q.advance(auto: false)?.trackID, "2")
    }

    func testRepeatAllWrapsWithFreshIDs() {
        var q = PlaybackQueue()
        q.play(["1", "2"], startAt: 0, context: ctx, shuffle: false)
        q.repeatMode = .all
        q.advance(auto: true)
        let wrapped = q.advance(auto: true)
        XCTAssertEqual(wrapped?.trackID, "1")
        XCTAssertFalse(q.history.contains { $0.id == wrapped?.id }, "new round must not reuse history ids")
    }

    func testShuffleKeepsCurrentAndUnshuffleContinuesInOrder() {
        var q = PlaybackQueue()
        let tracks = (1...20).map(String.init)
        q.play(tracks, startAt: 4, context: ctx, shuffle: false)
        q.setShuffle(true)
        XCTAssertEqual(q.current?.trackID, "5")
        XCTAssertEqual(Set(ids(q.context)), Set(tracks).subtracting(["1", "2", "3", "4", "5"]))
        q.setShuffle(false)
        XCTAssertEqual(ids(q.context), (6...20).map(String.init))
    }

    func testShuffledStartWithoutIndexPlaysEverythingOnce() {
        var q = PlaybackQueue()
        var rng = SeededGenerator(seed: 7)
        q.play(["a", "b", "c", "d"], startAt: nil, context: ctx, shuffle: true, groupKey: { $0 }, using: &rng)
        XCTAssertEqual(Set(ids([q.current!] + q.context)), ["a", "b", "c", "d"])
        XCTAssertEqual(q.context.count, 3)
    }

    func testJumpDropsSkippedItemsInSameSectionOnly() {
        var q = PlaybackQueue()
        q.play(["1", "2", "3", "4"], startAt: 0, context: ctx, shuffle: false)
        q.addToQueue(["u1", "u2"])
        let target = q.context[1]  // "3"
        q.jump(to: target.id)
        XCTAssertEqual(q.current?.trackID, "3")
        XCTAssertEqual(ids(q.upNext), ["u1", "u2"], "user queue survives a jump into the context")
        XCTAssertEqual(ids(q.context), ["4"])
    }

    func testJumpBackIntoHistory() {
        var q = PlaybackQueue()
        q.play(["1", "2", "3", "4"], startAt: 0, context: ctx, shuffle: false)
        q.advance(auto: true); q.advance(auto: true)
        let first = q.history[0]
        q.jump(to: first.id)
        XCTAssertEqual(q.current?.trackID, "1")
        XCTAssertEqual(ids(q.context), ["2", "3", "4"])
    }

    func testRemoveAndMove() {
        var q = PlaybackQueue()
        q.play(["1"], startAt: 0, context: ctx, shuffle: false)
        q.addToQueue(["a", "b", "c", "d"])
        q.move(in: .upNext, from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(ids(q.upNext), ["b", "c", "a", "d"])
        q.move(in: .upNext, from: IndexSet([2, 3]), to: 0)
        XCTAssertEqual(ids(q.upNext), ["a", "d", "b", "c"])
        XCTAssertTrue(q.remove(q.upNext[1].id))
        XCTAssertEqual(ids(q.upNext), ["a", "b", "c"])
    }

    func testAutoplayFillsAfterContextAndSkipsKnownTracks() {
        var q = PlaybackQueue()
        q.play(["1", "2"], startAt: 0, context: ctx, shuffle: false)
        XCTAssertTrue(q.wantsAutoplay)
        q.appendAutoplay(["2", "r1", "r1", "r2"])
        XCTAssertEqual(ids(q.autoplay), ["r1", "r2"])
        q.advance(auto: true)
        XCTAssertEqual(q.advance(auto: true)?.trackID, "r1")
        XCTAssertEqual(q.current?.origin, .autoplay)
    }

    func testNewContextKeepsUserQueueAndDropsAutoplay() {
        var q = PlaybackQueue()
        q.play(["1", "2"], startAt: 0, context: ctx, shuffle: false)
        q.addToQueue(["u"])
        q.appendAutoplay(["r"])
        q.play(["x", "y"], startAt: 0, context: PlaybackContext(kind: .playlist, id: "p", title: "P"), shuffle: false)
        XCTAssertEqual(q.current?.trackID, "x")
        XCTAssertEqual(ids(q.upcoming), ["u", "y"])
        XCTAssertEqual(q.history.last?.trackID, "1")
    }

    func testCodableRoundTrip() throws {
        var q = PlaybackQueue()
        q.play(["1", "2", "3"], startAt: 1, context: ctx, shuffle: true)
        q.repeatMode = .all
        let data = try JSONEncoder().encode(q)
        let back = try JSONDecoder().decode(PlaybackQueue.self, from: data)
        XCTAssertEqual(back, q)
    }

    func testPruneRemovesMissingTracksAndAdvancesPastMissingCurrent() {
        var q = PlaybackQueue()
        q.play(["1", "2", "3"], startAt: 0, context: ctx, shuffle: false)
        q.prune { $0 != "1" && $0 != "3" }
        XCTAssertEqual(q.current?.trackID, "2")
        XCTAssertTrue(q.upcoming.isEmpty)
    }
}

final class ShuffleTests: XCTestCase {
    func testSpreadAvoidsAdjacentSameArtistWhenPossible() {
        // 3 artists × 6 songs: a perfect spread exists; the algorithm should get close.
        let items = (0..<18).map { "\(["A", "B", "C"][$0 % 3])\($0)" }
        var adjacentTotal = 0
        for seed in 0..<50 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let out = SpreadShuffle.shuffle(items, groupKey: { String($0.prefix(1)) }, using: &rng)
            XCTAssertEqual(Set(out), Set(items))
            adjacentTotal += zip(out, out.dropFirst()).filter { $0.prefix(1) == $1.prefix(1) }.count
        }
        // A plain shuffle averages ~5.7 adjacent pairs per list here; spread should be far lower.
        XCTAssertLessThan(Double(adjacentTotal) / 50, 2.0)
    }
}
