Ares Open Theater
================
Synced outdoor cinema screen using DUI + DrawSpritePoly.
Standalone resource, no framework dependency.

Author: roroleroh (Ares Studio)
Resource: ares-open-theater
Version: 1.0.0


FILES
-----
  fxmanifest.lua   resource manifest
  config.lua       screen definitions, ACE permission, video sources
  server/main.lua  state authority, ACE gate, timestamp calc, late-join sync
  client/utils.lua DrawSpritePoly wrapper + coord math
  client/main.lua  DUI lifecycle, render loop, interaction prompt
  html/index.html  DUI page shell
  html/style.css   fullscreen black background, no scrollbars
  html/player.js   YouTube IFrame + HTML5 <video> postMessage bridge


INSTALL
-------
1. Drop the ares-open-theater folder into your server's resources/[standalone]
   directory (or wherever you keep resources).
2. Ensure server.cfg has:
       ensure ares-open-theater
3. Grant yourself control:
       add_ace group.admin opentheater.control allow
       add_principal identifier.steam:YOURHEXHERE group.admin

   With Config.debug = true the ACE check is bypassed entirely (see
   "DEBUG-MODE ACE BYPASS" below). Useful while you set up screens,
   but remember to flip it off before going live.

4. Set the screen corners and interaction point in config.lua
   (see "SETUP COMMANDS" below for the wizard that grabs them).


HOW IT WORKS
------------
- Server holds source-of-truth state per screen:
    theaterStates[id] = { url, playing, startedAt, pausedAt, timestamp, ... }
- Every control event goes through ACE check on the server.
- Server broadcasts opentheater:syncState with the *current* playback
  position (timestamp + elapsed since startedAt) so every player — including
  late joiners — starts at the right second.
- Each client mounts a DUI per screen, renders it onto the screen corners
  with DrawSpritePoly every frame (only while the player is in stream range).
- When out of range, the render thread throttles to Config.proximityInterval.


VIDEO SOURCES
-------------
The DUI player auto-detects:

  YouTube URLs    ->  https://www.youtube.com/watch?v=...
                     https://youtu.be/...
                     Mounted via YouTube IFrame API, loops on end.

  Direct video    ->  *.mp4, *.m3u8, *.webm, *.ogg
                     Mounted via HTML5 <video>, loops on end.

Mix freely per play command. Toggle sources in Config.videoSources.


GETTING COORDS (KIVO)
---------------------
1. Boot the server with Config.debug = true.
2. In-game, walk to each corner of the screen mesh.
3. At each corner, type:    /getscreencoords
4. The current coords and heading print to F8 console AND chat.
5. Copy the printed vec3() into config.lua under the matching corner.
   Order is: topLeft, topRight, bottomRight, bottomLeft.
6. Stand at the spot players should approach the screen and run
   /getscreencoords again — paste into interactCoords.
7. Set Config.debug = false when you're done.

To get screen corners without booting the server, use CodeWalker:
  - Open the MLO in CodeWalker.
  - Select each corner vertex of the screen mesh.
  - Note the world coordinates from the vertex inspector.
  - Paste into config.lua.

The recommended way is the wizard — see SETUP COMMANDS below.


SETUP COMMANDS (debug only — Config.debug must be true)
-------------------------------------------------------
Three register-only-when-debug commands live in client/main.lua:

  /setupscreen [id] [label...]
    Starts a corner-pick wizard. For each of the four corners, aim at
    the surface and press E — the command grabs the world coord via a
    camera raycast. For the interaction point it grabs your player
    position. After all 5 points are captured, a paste-ready
    Config.screens block is printed to F8.

    Examples:
      /setupscreen
      /setupscreen beach_theater_main
      /setupscreen beach_theater_main Beach Open Theater

    The wizard walks you through, in order:
      1. topLeft     (camera raycast)
      2. topRight    (camera raycast)
      3. bottomRight (camera raycast)
      4. bottomLeft  (camera raycast)
      5. interactCoords (player position)
    A raycast that hits nothing prompts you to aim at a surface and
    try again.

  /setupcancel
    Aborts an in-progress wizard.

  /getscreencoords
    Legacy quick-grab. Prints the player's current world position and
    heading. Still useful for interactCoords or any non-screen coord.
    Prefer /setupscreen for screen corners — it uses the camera raycast
    so you don't have to walk into the wall.


INTERACTION ZONES & URL ENTRY
-----------------------------
Every entry in Config.screens gets a 4m sphere zone (ox_lib
lib.zones.sphere) centered on its interactCoords. Standing inside
shows "Press E to set screen URL"; pressing E opens an ox_lib input
dialog. Whatever you paste is normalized client-side and forwarded to
the server as opentheater:play.

Accepted URL forms (auto-detected):

  YouTube (any of these works, all collapse to watch?v=ID):
    https://www.youtube.com/watch?v=ID
    https://youtu.be/ID
    https://www.youtube.com/shorts/ID
    https://www.youtube.com/embed/ID
    https://www.youtube.com/live/ID
    (bare 11-char ID also works)

  Stream / direct video (passthrough, query string preserved):
    http(s)://*.m3u8
    http(s)://*.mp4
    http(s)://*.webm
    http(s)://*.ogg

Anything else is rejected client-side with a red notification. The
server re-validates the URL on opentheater:play, so a tampered client
can't smuggle garbage past the gate.

Set hidePrompt = true on a screen entry to suppress its zone and
prompt entirely (useful for background/decorative screens).


DEBUG-MODE ACE BYPASS
---------------------
With Config.debug = true, hasControl() on the server short-circuits
to true. Every player — not just ACE holders — can drive the theater
via the zone's input dialog (play URL) and via the underlying
opentheater:play / pause / stop / seek server events.

This is intentional and exists so you can place and test screens
without first setting up ACE groups. Remember to flip
Config.debug = false before going live, otherwise anyone in a zone
can hijack playback.


SYNC MODEL
----------
            Lua client                    Server                     DUI
              |                            |                          |
   play(url)-->|---- opentheater:play --->|-- validates ACE,         |
              |                            |   stores state,          |
              |                            |   broadcasts ------------>|-- play(url, ts)
              |                            |                          |
   join ----->|---- opentheater:requestState ->|-- computes current ts ->|-- play(url, ts)
              |                            |                          |
   pause ---->|---- opentheater:pause --->|-- updates state,         |
              |                            |   broadcasts ------------>|-- pause
              |                            |                          |


DUI vs NUI — TWO DIFFERENT THINGS
---------------------------------
- DUI: the html/* page mounted as a runtime texture, projected onto the
  screen in the world. This is what the players see.
- NUI: the html/* page also serves as the browser overlay (ui_page).
  Currently unused by the operator flow — the URL entry goes through
  an ox_lib inputDialog instead. The 'close' NUI callback is kept as
  a defensive fallback in case anything ever opens NUI focus.

The operator's flow today:
  Operator (in zone)
                  ->  Press E
                  ->  lib.inputDialog (URL)
                  ->  Client normalizes URL
                  ->  TriggerServerEvent('opentheater:play')
                  ->  Server validates ACE + URL, broadcasts
                  ->  All clients' DUIs receive via opentheater:syncState


ADDING MORE SCREENS
-------------------
Copy the block under Config.screens and give it a new unique id. Each screen
creates its own runtime TXD ('theater_<id>') so they won't collide. The
server iterates Config.screens to validate screenIds — adding to config.lua
is the only step required.


KNOWN LIMITATIONS
-----------------
- YouTube IFrame API requires outbound HTTPS to youtube.com. If your server
  blocks outbound traffic, proxy the API URL in Config.youtubeApiUrl.
- M3U8 streams require CORS to allow embedding. Some CDNs won't.
- Each screen's interaction prompt only fires inside its own 4m zone,
  so operators must stand at the screen they want to drive.


CREDITS
-------
Built by roroleroh for Ares Studio.
FiveM DUI / DrawSpritePoly pattern is well-documented in the FiveM native
reference; this resource packages it with server-authoritative sync.