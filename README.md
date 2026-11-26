# Musics

A native iOS player for music you host yourself. It replaces the music.lan web player on the phone and also
works with Subsonic/OpenSubsonic servers (Navidrome, Gonic, Airsonic). It is written in SwiftUI for iOS 17+ and
is built as an unsigned IPA for sideloading.

[docs/DESIGN.md](docs/DESIGN.md) covers the product and UX reasoning, the navigation map, the interaction
rules and the roadmap.

## Features

- **One server, many addresses.** Each server can have LAN, Tailscale (MagicDNS name, `100.x` address or
  `*.ts.net`) and public URLs. Musics probes them in parallel and uses the best one that answers. It
  re-checks when the network changes, and recognises a `.lan` name that Tailscale split DNS serves
  (such as `music.lan → 100.101.102.103`) as a tailnet address.
- **Tailscale awareness.** It detects the Tailscale tunnel, explains when tailnet addresses fail because
  Tailscale is off, and offers to open the Tailscale app.
- **Public endpoints with sign-in.** Supports HTTP Basic (e.g. Caddy `basic_auth`), a custom header token
  (`Authorization: Bearer …`, Cloudflare Access) or a Subsonic account. Secrets are kept in the Keychain.
- **Instant library.** The whole library is cached on the phone and indexed off the main thread (0.24 s for
  15,638 songs on Linux, release build). Search is local, as-you-type, typo tolerant and ignores accents.
- **Playback.** Gapless (the next item is preloaded), artist-spread shuffle, repeat one/all, lock screen and
  Control Center (including like, shuffle and repeat), AirPlay, interruptions, pausing when headphones are
  unplugged, and a sleep timer with fade-out or end of song.
- **Queue.** Play Next, Add to Queue, reorder, swipe to remove, history, "Continue playing from…", and
  autoplay radio when the queue runs out. Every edit can be undone.
- **Offline.** Downloads (song, album, playlist, liked songs automatically), plus a **smart cache** that
  prefetches upcoming songs to disk and keeps recently played ones in a size-capped LRU store.
  The library stays browsable offline, and songs that can't play are dimmed.
- **music.lan extras.** Word-synced karaoke lyrics, song/artist/genre radio, **Search by Sound** (CLAP
  audio embeddings), **Sonic Adventure** (a path of songs between two tracks), playlist availability
  ("212 of 240 songs"), and now-playing reports, so the server's Discord presence also shows the phone.
- **Personal stats** on the device feed Jump Back In, Rediscover, Most Played sorting, artists' top songs
  and search ranking.

## Layout

```
App/                      iOS app (SwiftUI)
  Model/                  AppModel, server sessions, library store, settings, Keychain
  Playback/               AVQueuePlayer engine, queue controller, lock screen / remote commands
  Offline/                downloads + smart cache
  Artwork/                image cache and artwork view
  UI/                     Home, Search, Library, detail screens, player, settings, onboarding
Packages/MusicsCore/      platform-independent core (builds and tests on Linux)
  MusicLanProvider        music.lan JSON API
  SubsonicProvider        Subsonic / OpenSubsonic API
  EndpointResolver        address probing and ranking, Tailscale detection
  PlaybackQueue           queue engine (value type, so edits can be undone)
  Search / LibraryIndex   library index and fuzzy search
project.yml               XcodeGen spec
.github/workflows/        CI: core tests on Linux, unsigned IPA on macOS
```

## Building

The IPA is built by GitHub Actions. Every push to `main` uploads `Musics_<version>.ipa` as a workflow
artifact, and pushing a `v*` tag publishes it as a release. Sideload it with AltStore, SideStore, Feather
or TrollStore, which sign it during install.

On a Mac:

```sh
brew install xcodegen
xcodegen generate
open Musics.xcodeproj        # pick a team in Signing & Capabilities to run on a device
```

The core package can be tested on any machine with Swift, including Linux via Docker:

```sh
cd Packages/MusicsCore
docker run --rm -v "$PWD":/pkg -w /pkg swift:6.2-noble swift test
# against a running music.lan:
docker run --rm --network host -v "$PWD":/pkg -w /pkg -e MUSICLAN_URL=http://127.0.0.1:3791 \
  swift:6.2-noble swift test --filter LiveServerTests
```

## Connecting to music.lan

Add a server with the address `music.lan`. With Tailscale connected on the phone, split DNS resolves it to
the home server, and Musics labels it as Tailscale. To make it work without Tailscale, add a public URL as
a second address on the same server (behind Caddy `basic_auth` or a token header) and set the matching
sign-in.

## Suggested music.lan server changes

These would make the app better; none are required.

1. **Bump `version` only when the library content changes.** `Library._build` increments it on every
   90-second rescan, so clients can't tell when to re-download the 5 MB library. Musics currently limits
   music.lan refreshes to one every 10 minutes (or pull to refresh). A content hash compared before
   `self.version += 1` would fix this.
2. **Playlist editing endpoints** (`POST /api/playlists`, add/remove/reorder) for creating playlists in the app.
3. **`POST /api/scrobble`**, so play counts and history are shared between the web player and the app.
4. **Optional bearer-token check** for when music.lan is exposed on a public address.
