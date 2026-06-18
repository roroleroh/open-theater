# Ares Open Theater (scaffold)

In-world video screens (DUI + runtime texture on a prop) synced across
players via entity statebags, plus a standalone NUI test bench for checking
whether a given URL will actually play in CEF before wiring it into a screen.

## Layout

```
fxmanifest.lua
config.lua              -- screen definitions, validation rules, tuning
client/main.lua          -- DUI lifecycle, statebag listeners, /theater command
client/testbench.lua     -- /theatertest command (opens the NUI test bench)
server/main.lua          -- spawns screen entities, validates + writes statebags
html/screen/              -- DUI page rendered onto the prop (just <video> + hls.js)
html/testbench/           -- NUI overlay test bench
```

## Statebag design

Each screen is one **networked prop**, spawned server-side. The prop's
entity statebag is the single source of truth for what's playing:

| key         | type            | set by | meaning                                                        |
|-------------|-----------------|--------|-----------------------------------------------------------------|
| `screenId`  | string          | server | matches `Config.screens[].id`, set once at spawn                |
| `videoUrl`  | string \| nil   | server | direct `.mp4`/`.webm` or `.m3u8` URL currently assigned          |
| `videoType` | `'mp4'\|'hls'`  | server | tells the DUI page which player path to use                     |
| `startTime` | number (unix s) | server | `GetCloudTimeAsInt()` at the moment playback was (re)started     |
| `playing`   | boolean         | server | whether the screen should currently be showing anything          |

**Why server-writes-only:** clients call `ares_opentheater:setVideo` /
`ares_opentheater:stopVideo` callbacks. The server validates the URL
(scheme, extension vs. declared type, length) and is the only thing that
calls `Entity(entity):setState(...)`. This keeps the statebag itself
trustworthy and gives you one place to add permission checks (job, item,
admin-only, etc.) later.

**Sync model:**
- *VOD (`mp4`)*: `startTime` is the server's clock at load time. Every
  client computes `elapsed = now - startTime` and seeks the `<video>` to
  that offset on load (`html/screen/script.js`). Good enough for "everyone's
  within a couple seconds of each other," not frame-accurate.
- *Live (`hls`)*: `startTime`/`seekTo` are ignored. Every client just loads
  the same `.m3u8` and hls.js syncs to the live edge on its own - this is
  the path you'd use for a relayed live broadcast once you have an
  unencrypted HLS source on your own media server.

**DUI lifecycle:** each client runs a distance check (`Config.screens[].streamDistance`,
every `Config.distanceCheckInterval` ms). A DUI + runtime texture is only
created while a player is near that specific screen, and destroyed when they
walk away - each DUI is a full CEF instance, don't leave them running for
empty screens.

## Test bench (`/theatertest`)

Opens a full-screen NUI overlay with a URL input, MP4/HLS type selector, and
a live `<video>` + hls.js player. Use this to validate candidate URLs:

- **MP4**: if `play()` resolves and you see `playing (WxH)` in the status
  line, it'll work on a screen.
- **HLS**: watch for `Hls.Events.ERROR` - fatal `bufferStaleError` /
  `manifestLoadError` etc. usually means the source is DRM-protected or
  unreachable from the FiveM client's network context.
- Every status change is also mirrored to `f8` console via
  `client/testbench.lua` (`[OpenTheater:TestBench] ...`) for when you're
  testing without a visible NUI (e.g. headless dev client).

`Esc` or the Close button exits the test bench.

## Still TODO before this is a real product

- Verify `textureDict`/`textureName` for whatever prop you actually use as
  the screen (current `config.lua` values are placeholders for
  `prop_tv_flat_01` and almost certainly need correcting).
- Replace the `/theater` command with a proper interaction (ox_target /
  `lib.points` zone) and add permission checks in `setVideo`/`stopVideo`.
- Confirm server-side `CreateObject` behaves as expected on your build - if
  entities don't appear, fall back to spawning client-side on first resource
  start and broadcasting the netId.
- The MP4 path assumes you've already run content through the
  download → ffmpeg re-encode (H.264/AAC, `+faststart`) → host pipeline
  discussed earlier. This resource doesn't do any of that itself, it just
  plays whatever URL it's given.
