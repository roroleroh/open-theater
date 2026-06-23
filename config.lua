Config = {}
Config.debug = true

-- ACE permission required to control the theater (play/pause/stop/seek)
Config.acePermission = 'opentheater.control'

-- Stream distance check interval (ms) when player is outside range
Config.proximityInterval = 500

-- Proximity audio. The DUI volume is driven by the player's distance to the
-- screen centre: full volume within minDistance, silent at the screen's reach,
-- with a gentle rolloff in between.
--
-- The reach scales with the physical screen size:
--     reach = screenDiagonal (m) * reachPerMeter, clamped to [minReach, maxReach]
-- so bigger screens are heard from further away, while minReach guarantees even
-- small screens are still audible from a fair distance.
--
-- Per-screen overrides win over all of this: set audioMinDistance and/or
-- audioMaxDistance on a screen entry to pin exact values for that screen.
Config.audio = {
    minDistance = 4.0,      -- within this many metres: full volume
    reachPerMeter = 2.5,    -- reach = screen diagonal * this
    minReach = 18.0,        -- floor: smallest screens are still heard this far
    maxReach = 60.0,        -- ceiling: huge screens don't blast the whole map
    updateInterval = 200,   -- how often (ms) the volume is recalculated
}

-- YouTube IFrame API will be loaded async. If you proxy it, change this URL.
Config.youtubeApiUrl = 'https://www.youtube.com/iframe_api'

-- Allowed video sources. 'youtube' = IFrame API, 'mp4' = HTML5 <video>
Config.videoSources = {
    youtube = true,
    mp4 = true,
}

-- Available prop flags. The model name is what gets loaded via GetHashKey
-- (the .ydr extension is implied). Order here is the order operators see in
-- the flag-picker context menu. Add or remove entries freely; the resource
-- only knows about flags you list here.
Config.flags = {
    { model = 'kivo_bs_flags_us', label = 'United States' },
    { model = 'kivo_bs_flags_en', label = 'England' },
    { model = 'kivo_bs_flags_sc', label = 'Scotland' },
    { model = 'kivo_bs_flags_fr', label = 'France' },
    { model = 'kivo_bs_flags_ge', label = 'Germany' },
    { model = 'kivo_bs_flags_sp', label = 'Spain' },
    { model = 'kivo_bs_flags_it', label = 'Italy' },
    { model = 'kivo_bs_flags_po', label = 'Poland' },
    { model = 'kivo_bs_flags_nl', label = 'Netherlands' },
    { model = 'kivo_bs_flags_be', label = 'Belgium' },
    { model = 'kivo_bs_flags_sw', label = 'Sweden' },
    { model = 'kivo_bs_flags_no', label = 'Norway' },
    { model = 'kivo_bs_flags_sz', label = 'Switzerland' },
    { model = 'kivo_bs_flags_tr', label = 'Turkey' },
    { model = 'kivo_bs_flags_sa', label = 'Saudi Arabia' },
    { model = 'kivo_bs_flags_jp', label = 'Japan' },
    { model = 'kivo_bs_flags_sk', label = 'South Korea' },
    { model = 'kivo_bs_flags_ar', label = 'Argentina' },
    { model = 'kivo_bs_flags_br', label = 'Brazil' },
    { model = 'kivo_bs_flags_ca', label = 'Canada' },
    { model = 'kivo_bs_flags_cl', label = 'Chile' },
    { model = 'kivo_bs_flags_ec', label = 'Ecuador' },
    { model = 'kivo_bs_flags_me', label = 'Mexico' },
    { model = 'kivo_bs_flags_au', label = 'Australia' },
    { model = 'kivo_bs_flags_mo', label = 'Morocco' },
}

-- Screen definitions.
-- corners order MUST be: topLeft, topRight, bottomRight, bottomLeft
-- interactCoords is the player stand-point (where the prompt is shown).
-- duiWidth / duiHeight should match the on-screen aspect ratio.
-- useProp = true enables a physical prop (flag) spawned at prop.pos / prop.rot
-- when a player enters the screen's stream range. The displayed model is read
-- from the statebag (defaulted to prop.model if none is set).
-- prop.rot is a QUATERNION (x, y, z, w) consumed by SetEntityQuaternion.
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
    useProp = true,
    prop = {
        model = 'kivo_bs_flags_us',
        pos = vec3(-1751.22009, -843.4657, 6.288247),
        rot = vec4(0.0, 0.0, 0.8874134, 0.4609744),
    },
},
    -- Add more screens by copying the block above.
    -- Each screen needs a UNIQUE id, a unique runtime TXD will be created
    -- with the name 'theater_<id>'.
}