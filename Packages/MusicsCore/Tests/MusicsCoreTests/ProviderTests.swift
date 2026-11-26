import XCTest
@testable import MusicsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MusicLanTests: XCTestCase {
    let json = """
    {"tracks":[
      {"id":"t1","t":"Song One","ar":["Artist A","Guest"],"al":"al1","n":1,"dk":1,"dur":180.5,"y":2020,"add":1700000000,"ext":"opus","ly":false,"g":[0,1]},
      {"id":"t2","t":"Song Two","ar":["Artist A"],"al":"al1","n":2,"dk":1,"dur":200,"y":2020,"add":1700000100,"ext":"mp3","ly":true},
      {"id":"t3","t":"Beyoncé Cover","ar":[],"al":"al2","n":"3/12","dur":100,"add":1600000000,"ext":"flac"}
    ],
    "albums":[
      {"id":"al1","name":"First","artist":"Artist A","year":2020,"tracks":["t1","t2"],"added":1700000100,"c":"#3b3b3b","cv":2},
      {"id":"al2","name":"Second","artist":"Artist B","year":0,"tracks":["t3"],"added":1600000000,"c":null}
    ],
    "playlists":[{"id":"p1","name":"Mix","tracks":["t2","t1","gone"],"resolved":2,"total":5,"src":"spotify","url":"https://open.spotify.com/playlist/x","mtime":1700000000}],
    "likes":["t2"],"scanning":false,"version":5546,"gn":["pop","trap"]}
    """

    func testDecodeLibrary() throws {
        let snap = try MusicLanProvider.decodeLibrary(Data(json.utf8))
        XCTAssertEqual(snap.version, "5546")
        XCTAssertEqual(snap.tracks.count, 3)
        let t1 = snap.tracks[0]
        XCTAssertEqual(t1.genres, ["pop", "trap"])
        XCTAssertEqual(t1.albumTitle, "First")
        XCTAssertEqual(t1.format, "opus")
        let t3 = snap.tracks[2]
        XCTAssertEqual(t3.trackNumber, 3, "\"3/12\" parses as 3")
        XCTAssertEqual(t3.artists, ["Artist B"], "empty artist list falls back to album artist")
        XCTAssertEqual(snap.albums[0].coverRevision, "2")
        XCTAssertEqual(snap.albums[0].accentHex, "#3b3b3b")
        XCTAssertEqual(snap.albums[0].duration, 380.5, accuracy: 0.01)
        XCTAssertEqual(snap.playlists[0].source, .spotify)
        XCTAssertEqual(snap.playlists[0].total, 5)
        XCTAssertEqual(snap.likes, ["t2"])

        let index = LibraryIndex(snap)
        XCTAssertEqual(index.playlists["p1"]?.trackIDs, ["t2", "t1"], "unknown ids dropped")
        XCTAssertEqual(index.playlists["p1"]?.missingCount, 3)
        let a = index.artist(named: "artist a")
        XCTAssertEqual(a?.albumIDs, ["al1"])
        XCTAssertEqual(index.artist(named: "Guest")?.appearsOnAlbumIDs, ["al1"])
        XCTAssertEqual(index.albumsByAdded.first?.id, "al1")
    }

    func testStreamURLsTranscodeOnlyWhatIOSCantPlay() throws {
        let p = MusicLanProvider(http: HTTPClient())
        let base = URL(string: "http://music.lan")!
        let snap = try MusicLanProvider.decodeLibrary(Data(json.utf8))
        XCTAssertEqual(p.streamURL(base: base, track: snap.tracks[0], quality: .original).absoluteString,
                       "http://music.lan/api/tracks/t1/audio?fmt=aac")
        XCTAssertEqual(p.streamURL(base: base, track: snap.tracks[1], quality: .original).absoluteString,
                       "http://music.lan/api/tracks/t2/audio")
        XCTAssertEqual(p.streamURL(base: base, track: snap.tracks[2], quality: .original).absoluteString,
                       "http://music.lan/api/tracks/t3/audio")
        XCTAssertEqual(p.streamURL(base: base, track: snap.tracks[2], quality: .efficient).absoluteString,
                       "http://music.lan/api/tracks/t3/audio?fmt=aac")
        XCTAssertEqual(p.downloadExtension(track: snap.tracks[0], quality: .original), "m4a")
        XCTAssertEqual(p.artworkURL(base: base, album: snap.albums[0], size: 600)?.absoluteString,
                       "http://music.lan/api/albums/al1/cover.jpg?s=640&v=2")
    }

    func testBaseURLWithSubpath() {
        let base = URL(string: "https://example.com/music")!
        XCTAssertEqual(base.appendingAPIPath("/api/version").absoluteString, "https://example.com/music/api/version")
        XCTAssertEqual(base.appendingAPIPath("/api/genre/hip hop").absoluteString, "https://example.com/music/api/genre/hip%20hop")
    }

    func testLyricsConversion() throws {
        let w = """
        {"source":"Musixmatch","kind":"word","lines":[
          {"t":0.16,"e":0.95,"text":"Hello there","w":[{"t":0.16,"e":0.6,"s":"Hello "},{"t":0.6,"e":0.95,"s":"there"}]},
          {"t":1.2,"e":3.0,"text":"Second"}]}
        """
        let wire = try JSONDecoder().decode(MusicLanProvider.WireLyrics.self, from: Data(w.utf8))
        let l = try XCTUnwrap(MusicLanProvider.convert(wire))
        XCTAssertEqual(l.kind, .word)
        XCTAssertEqual(l.lines[0].words.count, 2)
        XCTAssertNil(l.activeLineIndex(at: 0.1))
        XCTAssertEqual(l.activeLineIndex(at: 0.5), 0)
        XCTAssertEqual(l.activeLineIndex(at: 9), 1)
        let none = try JSONDecoder().decode(MusicLanProvider.WireLyrics.self, from: Data(#"{"source":null,"kind":null,"lines":[]}"#.utf8))
        XCTAssertNil(MusicLanProvider.convert(none))
    }
}

final class SubsonicTests: XCTestCase {
    func testMD5() {
        XCTAssertEqual(MD5.hex(""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(MD5.hex("The quick brown fox jumps over the lazy dog"), "9e107d9d372bb6826bd81d3542a419d6")
        // Example from the Subsonic API documentation.
        XCTAssertEqual(MD5.hex("sesame" + "c19b2d"), "26719a1196d2a940705a59634eb18eab")
        XCTAssertEqual(MD5.hex(String(repeating: "a", count: 200)).count, 32)
    }

    func testEnvelopeAndAssemble() throws {
        let body = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,"searchResult3":{"song":[
          {"id":"s2","title":"B","album":"Alb","albumId":"a1","artist":"X","track":2,"discNumber":1,"year":2001,"duration":100,"suffix":"flac","created":"2024-01-02T03:04:05.000Z","coverArt":"al-a1","genres":[{"name":"Rock"}]},
          {"id":"s1","title":"A","album":"Alb","albumId":"a1","artist":"X","artists":[{"id":"1","name":"X"},{"id":"2","name":"Y"}],"track":1,"duration":90,"suffix":"opus","created":"2024-01-01T00:00:00Z"},
          {"id":"s3","title":"Loose","album":"Orphan","albumId":"a9","artist":"Z","duration":60,"suffix":"mp3"}
        ]}}}
        """
        let r = try HTTPClient().decode(SubsonicProvider.Envelope<SubsonicProvider.SearchResponse>.self, from: Data(body.utf8))
        let songs = r.response.searchResult3?.song ?? []
        let albums = try HTTPClient().decode(SubsonicProvider.Envelope<SubsonicProvider.AlbumListResponse>.self, from: Data("""
        {"subsonic-response":{"status":"ok","albumList2":{"album":[{"id":"a1","name":"Alb","artist":"X","coverArt":"al-a1","songCount":2,"year":2001}]}}}
        """.utf8)).response.albumList2?.album ?? []
        let snap = SubsonicProvider.assemble(version: "2|x", albums: albums, songs: songs, starred: ["s1"],
                                             genres: [], playlists: [])
        XCTAssertEqual(snap.tracks.count, 3)
        let a1 = try XCTUnwrap(snap.albums.first { $0.id == "a1" })
        XCTAssertEqual(a1.trackIDs, ["s1", "s2"], "sorted by track number")
        XCTAssertEqual(snap.tracks.first { $0.id == "s1" }?.artists, ["X", "Y"])
        XCTAssertEqual(snap.tracks.first { $0.id == "s2" }?.genres, ["rock"])
        XCTAssertNotNil(snap.albums.first { $0.id == "a9" }, "orphan album synthesized")
        XCTAssertEqual(snap.likes, ["s1"])
    }

    func testErrorEnvelope() throws {
        let body = #"{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":40,"message":"Wrong username or password"}}}"#
        let s = try HTTPClient().decode(SubsonicProvider.Envelope<SubsonicProvider.Status>.self, from: Data(body.utf8)).response
        XCTAssertEqual(s.status, "failed")
        XCTAssertEqual(s.error?.code, 40)
    }

    func testStreamAndArtworkURLs() {
        let p = SubsonicProvider(username: "me", password: "pw", http: HTTPClient())
        let base = URL(string: "https://nd.example.com")!
        let flac = Track(id: "1", title: "", artists: ["a"], albumID: "x", albumTitle: "", albumArtist: "", format: "flac")
        let opus = Track(id: "2", title: "", artists: ["a"], albumID: "x", albumTitle: "", albumArtist: "", format: "opus")
        XCTAssertTrue(p.streamURL(base: base, track: flac, quality: .original).absoluteString.contains("format=raw"))
        XCTAssertTrue(p.streamURL(base: base, track: opus, quality: .original).absoluteString.contains("format=mp3"))
        XCTAssertEqual(p.downloadExtension(track: opus, quality: .original), "mp3")
        let album = Album(id: "x", title: "", artist: "", coverID: "al-x")
        let u1 = p.artworkURL(base: base, album: album, size: 300)
        XCTAssertEqual(u1, p.artworkURL(base: base, album: album, size: 300), "artwork URLs are stable cache keys")
        XCTAssertNotEqual(u1, p.artworkURL(base: base, album: album, size: 600))
    }
}

final class SearchTests: XCTestCase {
    func makeIndex() -> LibraryIndex {
        let tracks = [
            Track(id: "1", title: "Halo", artists: ["Beyoncé"], albumID: "a", albumTitle: "I Am... Sasha Fierce", albumArtist: "Beyoncé"),
            Track(id: "2", title: "Crazy in Love", artists: ["Beyoncé", "JAY-Z"], albumID: "b", albumTitle: "Dangerously in Love", albumArtist: "Beyoncé"),
            Track(id: "3", title: "Radiohead Song", artists: ["Someone"], albumID: "c", albumTitle: "X", albumArtist: "Someone"),
            Track(id: "4", title: "Karma Police", artists: ["Radiohead"], albumID: "d", albumTitle: "OK Computer", albumArtist: "Radiohead"),
            Track(id: "5", title: "Don't Stop Me Now", artists: ["Queen"], albumID: "e", albumTitle: "Jazz", albumArtist: "Queen"),
        ]
        let albums = [
            Album(id: "a", title: "I Am... Sasha Fierce", artist: "Beyoncé", trackIDs: ["1"]),
            Album(id: "b", title: "Dangerously in Love", artist: "Beyoncé", trackIDs: ["2"]),
            Album(id: "c", title: "X", artist: "Someone", trackIDs: ["3"]),
            Album(id: "d", title: "OK Computer", artist: "Radiohead", trackIDs: ["4"]),
            Album(id: "e", title: "Jazz", artist: "Queen", trackIDs: ["5"]),
        ]
        return LibraryIndex(LibrarySnapshot(version: "1", tracks: tracks, albums: albums, playlists: [], likes: [], genres: []))
    }

    func testAccentInsensitiveAndArtistFieldMatch() {
        let r = makeIndex().search.search("beyonce")
        XCTAssertEqual(Set(r.tracks), ["1", "2"])
        XCTAssertEqual(r.top, .artist("beyonce"))
    }

    func testMultiTokenAcrossFields() {
        let r = makeIndex().search.search("crazy jay")
        XCTAssertEqual(r.tracks.first, "2")
    }

    func testTypoTolerance() {
        let r = makeIndex().search.search("radiohaed")
        XCTAssertTrue(r.artists.contains("radiohead"))
    }

    func testApostropheAndPrefix() {
        XCTAssertEqual(makeIndex().search.search("dont sto").tracks.first, "5")
    }

    func testArtistBeatsSameNamedSong() {
        let r = makeIndex().search.search("radiohead")
        XCTAssertEqual(r.top, .artist("radiohead"))
        XCTAssertEqual(Set(r.tracks), ["3", "4"])
    }

    func testNormalizeAndSortKeys() {
        XCTAssertEqual(TextNormalizer.normalize("  Beyoncé & JAY-Z!! "), "beyonce and jay z")
        XCTAssertEqual(TextNormalizer.sectionLetter("The Beatles"), "B")
        XCTAssertEqual(TextNormalizer.sectionLetter("$NOT"), "N")
        XCTAssertEqual(TextNormalizer.sectionLetter("21 Savage"), "#")
        XCTAssertEqual(SearchIndex.editDistance("radiohaed", "radiohead", max: 1), 1)
        XCTAssertEqual(SearchIndex.editDistance("abc", "xyz", max: 1), 2)
    }
}

final class EndpointTests: XCTestCase {
    func testClassify() {
        XCTAssertEqual(EndpointClassifier.classify(host: "100.101.102.103"), .tailscale)
        XCTAssertEqual(EndpointClassifier.classify(host: "100.128.0.1"), .publicInternet)
        XCTAssertEqual(EndpointClassifier.classify(host: "box.tail1234.ts.net"), .tailscale)
        XCTAssertEqual(EndpointClassifier.classify(host: "music.lan"), .lan)
        XCTAssertEqual(EndpointClassifier.classify(host: "192.168.1.20"), .lan)
        XCTAssertEqual(EndpointClassifier.classify(host: "nas"), .lan)
        XCTAssertEqual(EndpointClassifier.classify(host: "music.example.com"), .publicInternet)
        XCTAssertEqual(EndpointClassifier.classify(host: "music.lan", resolvedAddresses: ["100.101.102.103"]), .tailscale)
    }

    func testNormalizeURL() {
        XCTAssertEqual(EndpointClassifier.normalizeURL("music.lan")?.absoluteString, "http://music.lan")
        XCTAssertEqual(EndpointClassifier.normalizeURL("100.101.102.103:3791/")?.absoluteString, "http://100.101.102.103:3791")
        XCTAssertEqual(EndpointClassifier.normalizeURL("box.tail1.ts.net")?.absoluteString, "https://box.tail1.ts.net")
        XCTAssertEqual(EndpointClassifier.normalizeURL("music.example.com")?.absoluteString, "https://music.example.com")
        XCTAssertEqual(EndpointClassifier.normalizeURL("http://x.com/sub/")?.absoluteString, "http://x.com/sub")
        XCTAssertNil(EndpointClassifier.normalizeURL("ftp://x"))
        XCTAssertNil(EndpointClassifier.normalizeURL("  "))
    }

    struct FakeProber: EndpointProber {
        let answers: [String: (Bool, Double, EndpointKind)]
        func probe(_ e: Endpoint) async -> ProbeResult {
            let a = answers[e.url.host!] ?? (false, 0, e.guessedKind)
            return ProbeResult(endpoint: e, reachable: a.0, latency: a.0 ? a.1 : nil, kind: a.2, error: a.0 ? nil : "timed out")
        }
    }

    func testResolverPrefersLanThenTailscaleThenPublic() async {
        let eps = ["pub.example.com", "100.101.102.103", "192.168.1.2"].map { Endpoint(url: URL(string: "http://\($0)")!) }
        let r1 = await EndpointResolver(prober: FakeProber(answers: [
            "pub.example.com": (true, 0.05, .publicInternet), "100.101.102.103": (true, 0.2, .tailscale), "192.168.1.2": (false, 0, .lan),
        ])).resolve(eps, network: NetworkState(tailscaleActive: true))
        XCTAssertEqual(r1.active?.endpoint.url.host, "100.101.102.103")

        let r2 = await EndpointResolver(prober: FakeProber(answers: [
            "pub.example.com": (true, 0.05, .publicInternet), "100.101.102.103": (false, 0, .tailscale),
        ])).resolve(eps, network: NetworkState())
        XCTAssertEqual(r2.active?.endpoint.url.host, "pub.example.com")
    }

    func testTailscaleOffReason() async {
        let eps = [Endpoint(url: URL(string: "http://music.lan")!)]
        let r = await EndpointResolver(prober: FakeProber(answers: ["music.lan": (false, 0, .tailscale)]))
            .resolve(eps, network: NetworkState(tailscaleActive: false))
        XCTAssertNil(r.active)
        XCTAssertEqual(r.failure, .tailscaleOff)
        let offline = await EndpointResolver(prober: FakeProber(answers: [:])).resolve(eps, network: NetworkState(isConnected: false))
        XCTAssertEqual(offline.failure, .offline)
    }
}

final class LyricsAndStatsTests: XCTestCase {
    func testLRC() {
        let l = Lyrics.parseLRC("[ar:Someone]\n[00:01.00]First\n[00:05.50][01:00.00]Chorus\n\n[00:03.25]Second")
        XCTAssertEqual(l.kind, .line)
        XCTAssertEqual(l.lines.map(\.text), ["First", "Second", "Chorus", "Chorus"])
        XCTAssertEqual(l.lines[1].start, 3.25, accuracy: 0.001)
        XCTAssertEqual(l.activeLineIndex(at: 4), 1)
        XCTAssertEqual(Lyrics.parseLRC("just text\nmore").kind, .plain)
    }

    func testStats() {
        var s = ListeningStats()
        XCTAssertFalse(ListeningStats.countsAsPlay(listened: 20, duration: 200))
        XCTAssertTrue(ListeningStats.countsAsPlay(listened: 100, duration: 200))
        XCTAssertTrue(ListeningStats.countsAsPlay(listened: 240, duration: 1200))
        let old = Date(timeIntervalSinceNow: -100 * 86400)
        for _ in 0..<3 { s.recordPlay("a", at: old) }
        s.recordPlay("b")
        XCTAssertEqual(s.topTracks(among: ["a", "b", "c"], limit: 5), ["a", "b"])
        XCTAssertEqual(s.rediscover(), ["a"])
        s.recordContext(PlaybackContext(kind: .album, id: "x", title: "X"))
        s.recordContext(PlaybackContext(kind: .search, title: "q"))
        s.recordContext(PlaybackContext(kind: .album, id: "x", title: "X"))
        XCTAssertEqual(s.recentContexts.count, 1)
    }
}
