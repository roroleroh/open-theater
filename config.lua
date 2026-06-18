Config = {}
Config.debug = true -- Always include in fresh projects

-- Each entry = one in-world screen. Each gets its own networked prop +
-- statebag, so multiple "open theaters" can exist independently.
--
-- IMPORTANT: textureDict / textureName are placeholders for prop_tv_flat_01.
-- Verify the actual texture dictionary + texture name for whatever prop you
-- end up using (dump it with a texture viewer / OpenIV) before relying on
-- AddReplaceTexture - wrong names will silently no-op.
Config.screens = {
    {
        id = 'theater_main',
        coords = vec4(0.0, 0.0, 0.0, 0.0), -- x, y, z, heading - set your real coords
        model = `prop_tv_flat_01`,
        textureDict = 'prop_tv_flat_01',
        textureName = 'screen_2',
        renderTargetWidth = 1920,
        renderTargetHeight = 1080,
        streamDistance = 25.0 -- DUI is created/destroyed based on player distance
    }
}

-- Server-side validation: only these extensions are accepted per video type.
-- This is a basic sanity filter, not a security boundary - the real
-- protection is that the page is just <video src="..."> / hls.js, no DRM,
-- no plugin execution.
Config.allowedExtensions = {
    mp4 = { '.mp4', '.m4v', '.webm' },
    hls = { '.m3u8' }
}

-- How often (ms) each client re-checks distance to every screen
Config.distanceCheckInterval = 2000

-- Max URL length accepted by the setVideo callback
Config.maxUrlLength = 1024
