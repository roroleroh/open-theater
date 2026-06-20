Config = {}
Config.debug = true

-- ACE permission required to control the theater (play/pause/stop/seek)
Config.acePermission = 'opentheater.control'

-- Stream distance check interval (ms) when player is outside range
Config.proximityInterval = 500

-- Proximity audio. The DUI volume is driven by the player's distance to the
-- screen centre: full volume within minDistance, silent past maxDistance, with
-- a gentle rolloff in between. Per-screen overrides are supported via
-- audioMinDistance / audioMaxDistance on a screen entry.
Config.audio = {
    minDistance = 4.0,      -- within this many metres: full volume
    maxDistance = 30.0,     -- beyond this many metres: silent
    updateInterval = 200,   -- how often (ms) the volume is recalculated
}

-- YouTube IFrame API will be loaded async. If you proxy it, change this URL.
Config.youtubeApiUrl = 'https://www.youtube.com/iframe_api'

-- Allowed video sources. 'youtube' = IFrame API, 'mp4' = HTML5 <video>
Config.videoSources = {
    youtube = true,
    mp4 = true,
}

-- Screen definitions.
-- corners order MUST be: topLeft, topRight, bottomRight, bottomLeft
-- interactCoords is the player stand-point (where the prompt is shown).
-- duiWidth / duiHeight should match the on-screen aspect ratio.
Config.screens = {
    {
    id = 'screen_430072',
    label = 'New Theater Screen',
    corners = {
        topLeft     = vec3(-1747.6044, -850.1349, 18.7815),
        topRight    = vec3(-1756.2386, -837.8496, 18.6306),
        bottomRight = vec3(-1756.2363, -837.8528, 10.3434),
        bottomLeft  = vec3(-1747.6036, -850.1359, 10.3410),
    },
    duiWidth = 1280,
    duiHeight = 720,
    interactCoords = vec3(-1756.0884, -848.8927, 8.6466),
    interactHeading = 324.80,
    streamDistance = 100.0,
    hidePrompt = false,
},
    -- Add more screens by copying the block above.
    -- Each screen needs a UNIQUE id, a unique runtime TXD will be created
    -- with the name 'theater_<id>'.
}