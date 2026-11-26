import XCTest
@testable import MusicsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Runs against a real music.lan when MUSICLAN_URL is set, e.g.
/// `MUSICLAN_URL=http://127.0.0.1:3791 swift test --filter LiveServerTests`.
final class LiveServerTests: XCTestCase {
    var base: URL? { ProcessInfo.processInfo.environment["MUSICLAN_URL"].flatMap(URL.init(string:)) }

    func testFetchLibraryAndFeatures() async throws {
        guard let base else { throw XCTSkip("MUSICLAN_URL not set") }
        let p = MusicLanProvider(http: HTTPClient())
        let version = try await p.libraryVersion(base: base)
        XCTAssertFalse(version.isEmpty)

        let start = Date()
        let snap = try await p.fetchLibrary(base: base)
        let fetched = Date().timeIntervalSince(start)
        let indexStart = Date()
        let index = LibraryIndex(snap)
        let indexed = Date().timeIntervalSince(indexStart)
        print("live: \(snap.tracks.count) tracks, \(snap.albums.count) albums, \(snap.playlists.count) playlists, " +
              "\(index.artists.count) artists, \(index.genres.count) genres; fetch \(String(format: "%.2f", fetched))s, " +
              "index \(String(format: "%.2f", indexed))s")
        XCTAssertGreaterThan(snap.tracks.count, 0)

        let searchStart = Date()
        for q in ["a", "lo", "love", "the weeknd", "radiohaed", "moon stars"] { _ = index.search.search(q) }
        print("live: 6 searches in \(String(format: "%.3f", Date().timeIntervalSince(searchStart)))s")

        let track = try XCTUnwrap(snap.tracks.first)
        _ = try await p.lyrics(base: base, track: track)
        let radio = try await p.radio(base: base, seed: .track(track.id), count: 5, exclude: [])
        XCTAssertFalse(radio.contains(track.id), "append mode excludes the seed")
        let semantic = try? await p.semanticSearch(base: base, query: "calm piano", limit: 3)
        print("live: radio \(radio.count), semantic \(semantic?.count ?? -1)")

        let resolution = await EndpointResolver(prober: HTTPEndpointProber(provider: p))
            .resolve([Endpoint(url: base)], network: NetworkState())
        XCTAssertNotNil(resolution.active)
    }
}
