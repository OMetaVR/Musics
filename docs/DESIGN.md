# Musics: product and UX design

Musics is a native iOS player for music you host yourself. Its first server is music.lan; it also works
with OpenSubsonic servers (Navidrome, Gonic, Airsonic and similar). It replaces the music.lan web player
on the phone, and Spotify and Apple Music set the minimum it has to match.

## What the user wants from it

Someone who hosts their own library has already given up Spotify's catalogue for control over their music.
They want:

1. **Playback that always starts.** The phone moves between home Wi-Fi, Tailscale on cellular, a public
   address and no signal. Musics picks the working address on its own. Something you have played before, or
   that the queue has prefetched, keeps playing without signal.
2. **The fastest way to their own songs.** Search runs on the phone and returns results as each letter is typed,
   tolerating typos and ignoring accents. Every list is a single swipe from playing next.
3. **Discovery from their own library.** Radio, genre stations, audio-similarity search ("rainy late-night
   piano") and Sonic Adventure (a smooth path between two songs) come from the server's audio embeddings,
   not someone else's catalogue.
4. **No loss of control.** Every queue edit can be undone. Shuffle avoids playing an artist twice in a row.
   The app restores exactly where you were, paused. It reports what is missing, for example "212 of 240 songs
   available" on a Spotify-exported playlist, instead of hiding it.
5. **Respect for the library's size.** 15,000 songs and 10,000 albums must scroll, sort and index
   (A–Z scrubber) smoothly. The library is cached on the phone, so the app opens to content immediately.

## Baseline features (parity with Spotify and Apple Music)

| Area | Included |
| --- | --- |
| Library | Songs, albums, artists, playlists, genres, liked songs, downloads; sort and filter; A–Z index |
| Playback | Gapless (preloaded next item), shuffle, repeat one/all, lock screen, Control Center, headphone and AirPods controls, AirPlay picker, interruptions and route changes |
| Queue | Play next, add to queue, reorder, remove, clear, history, "continue playing from", autoplay |
| Now Playing | Large artwork, scrubber, volume, artwork-tinted background, swipe-down dismissal, like button |
| Lyrics | Line-synced and word-synced, auto-follow, tap a line to seek, plain-text fallback |
| Offline | Download a song, album or playlist; downloads tab; offline mode that greys out songs it can't play |
| Personal | Likes synced with the server, recently played, recently added, top songs per artist |
| Extras | Sleep timer (time or end of song, with fade), song info |

## Beyond the baseline

| Feature | Why it matters |
| --- | --- |
| **Multiple addresses per server** (LAN, Tailscale, public) chosen by network, latency and priority, rechecked when the network changes | One server profile works at home, on a tailnet and over the internet |
| **Tailscale awareness**: detects the tailnet tunnel, says when a tailnet address is unreachable because Tailscale is off, understands MagicDNS and `.ts.net` names | Explains failures that other players report as "server unreachable" |
| **Smart cache**: the next tracks are prefetched to disk and kept in a size-capped LRU cache | No gap or buffering at track changes on poor cellular; recent songs replay offline |
| **Audio-similarity search** ("Sounds like…") added below text results | Find music by mood or sound, not only by its tags |
| **Sonic Adventure**: choose two songs and get a smooth path between them | Not available in any mainstream player |
| **Artist-spread shuffle** | Avoids clusters such as three songs from the same album in a row |
| **Undo for queue edits** | Removing or clearing is safe |
| **Honest playlist availability** (resolved/total) | Spotify-exported lists show what is missing |
| **Discord presence** through music.lan's now-playing endpoint | The server's existing Discord RPC daemon also shows the phone |
| **Instant cold start** from the cached library, updated in the background when the server's version changes | No spinner on launch |
| **Word-level karaoke lyrics** | music.lan already supplies Musixmatch/Netease word timing |

## Navigation

```
Tab bar:   Home · Search · Library            (mini player docked above the tab bar)
Home       Quick actions · Jump back in · Recently added · Your playlists · Genres · Stations · Rediscover
Search     Field → instant local results (Top, Songs, Artists, Albums, Playlists, Genres) + "Sounds like…"
           Empty state: recent searches and genre grid
Library    Playlists · Artists · Albums · Songs · Liked · Downloaded · Genres  (rows pushed on a stack)
Detail     Album · Artist · Playlist · Genre: push onto the tab's own NavigationStack
Player     Mini player → full Now Playing (drag down to close) → Lyrics / Queue panes
Settings   From the Home toolbar: Servers, Playback, Downloads & cache, Integrations, About
```

Each tab keeps its own navigation stack. Tapping the current tab returns it to the top of its stack. The
mini player stays visible above every tab, and the full player covers the screen without replacing the
navigation underneath it.

## Interaction rules

- **Rows**: tap plays the row in its context (the album, playlist or list that row belongs to). A leading
  swipe plays next, a trailing swipe adds to the end of the queue. A long press opens the context menu.
- **Context menu (every song)**: Play Next, Add to Queue, Start Radio, Like/Unlike, Download/Remove,
  Go to Album, Go to Artist, Song Info.
- **Mini player**: tap or swipe up opens Now Playing; horizontal swipes skip; the play button pauses.
- **Now Playing**: drag down dismisses it. Artwork shrinks while paused. Tapping the artwork toggles lyrics.
  The scrubber follows the finger and seeks when released. Previous restarts the song if more than 3 s has
  played, otherwise it goes to the previous song.
- **Lyrics**: the view follows the current line. Scrolling by hand pauses following for 4 s. Tapping a line seeks there.
- **Haptics**: light feedback on like, queue changes and seek release; nothing on ordinary taps.
- **Every destructive queue action** shows a toast with Undo for 4 s.
- **Restore**: on launch, the last queue and position return paused. Nothing plays until the user presses play.

## Visual language

The look follows music.lan's own: solid near-black surfaces (`#0A0A0B`, `#0F1012`, `#121316`), subtle 1 px
edges, the green accent `#5CCB8A`, compact corner radii, and artwork used for information rather than decoration.
Now Playing is tinted with the album's accent colour (from the server's `c` field, or sampled from the artwork
for Subsonic servers). It does not use decorative gradients, uppercase eyebrows or greeting banners.

## Connectivity model

```
ServerProfile
  kind: musicLan | subsonic
  endpoints: [Endpoint(url, label, kind: lan | tailscale | public, priority)]
  auth: none | basic(user, password) | header(name, value) | subsonic(user, password)  (secrets in Keychain)

EndpointResolver
  on launch, network change and request failure:
    probe every endpoint in parallel (2.5 s timeout)
    rank reachable ones: user priority, then the network's preference (Wi-Fi → LAN, tunnel → Tailscale), then latency
  publishes the active base URL and a reason when none respond ("Tailscale is off", "No network")
```

If nothing responds, the app goes into offline mode: it shows the cached library and plays downloaded and
cached songs only.

## Roadmap

1. **Foundation (this commit)**: core library and providers, endpoint resolver, queue engine, playback,
   the full UI described above, downloads, smart cache, lyrics, radio, Sonic Adventure, settings and CI IPA build.
2. **Polish**: crossfade (dual-player), ReplayGain/normalisation, a home-screen widget, Live Activity,
   App Intents/Siri ("play my liked songs"), Handoff with the web player, playlist editing on music.lan
   (needs server endpoints), and play counts synced to the server.
3. **Reach**: CarPlay (needs the audio entitlement), embedded Tailscale (tsnet userspace, so the Tailscale app
   isn't needed), Jellyfin native API, iPad sidebar layout, Mac Catalyst.

## Server-side additions that would help (music.lan)

- `POST /api/playlists` and related endpoints for creating and editing playlists from the app.
- `POST /api/scrobble`, so play counts and history are shared between the web player and the app.
- Optional bearer-token check when served on a public address. The app already sends a configurable header.
