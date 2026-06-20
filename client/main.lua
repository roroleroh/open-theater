-- Ares Open Theater — client main
-- DUI lifecycle, runtime TXD/texture, render loop, sync handler, dev tool.

local Utils = require('client.utils')
local RESOURCE_NAME = GetCurrentResourceName()

-- Per-screen state. Keyed by screen.id.
--   duiObj        : DUI instance handle
--   duiHandle     : GPU handle for runtime texture creation
--   txdName       : unique runtime TXD name
--   ready         : bool, true once the runtime texture exists
--   currentCmd    : last command sent to the DUI (debug)
local screens = {}

local function getScreenConfig(screenId)
    for _, s in ipairs(Config.screens) do
        if s.id == screenId then return s end
    end
    return nil
end

local function log(...)
    if Config.debug then
        print(('[%s:client]'):format(RESOURCE_NAME), ...)
    end
end

-- ---------- DUI bring-up ----------

local function initScreen(screenCfg)
    local key = screenCfg.id
    if screens[key] then return end

    local url = ('nui://%s/html/index.html'):format(RESOURCE_NAME)
    local duiObj = CreateDui(url, screenCfg.duiWidth, screenCfg.duiHeight)
    if not duiObj then
        log(('DUI creation failed for screen %s'):format(key))
        return
    end

    local duiHandle = GetDuiHandle(duiObj)
    if not duiHandle then
        log(('GetDuiHandle failed for screen %s'):format(key))
        DestroyDui(duiObj)
        return
    end

    local txdName = ('theater_%s'):format(key)
    local txd = CreateRuntimeTxd(txdName)
    CreateRuntimeTextureFromDuiHandle(txd, 'screen', duiHandle)

    screens[key] = {
        cfg = screenCfg,
        duiObj = duiObj,
        duiHandle = duiHandle,
        txdName = txdName,
        ready = true,
        currentCmd = nil,
    }

    log(('Screen %s ready (%dx%d)'):format(
        key, screenCfg.duiWidth, screenCfg.duiHeight))
end

local function destroyScreen(key)
    local s = screens[key]
    if not s then return end
    if s.duiObj then DestroyDui(s.duiObj) end
    screens[key] = nil
end

local function sendDui(screenKey, payload, quiet)
    local s = screens[screenKey]
    if not s or not s.duiObj then return end
    s.currentCmd = payload.type
    SendDuiMessage(s.duiObj, json.encode(payload))
    -- `quiet` suppresses the log line: the proximity audio loop sends a volume
    -- message several times a second, which would otherwise flood the console.
    if Config.debug and not quiet then
        log(('-> DUI %s: %s'):format(screenKey, json.encode(payload)))
    end
end

-- ---------- Sync handler (server -> client -> DUI) ----------

RegisterNetEvent('opentheater:syncState', function(screenId, state)
    if not state or type(screenId) ~= 'string' then return end
    if not screens[screenId] then return end

    if not state.url then
        -- Stop / blank: tell DUI to clear
        sendDui(screenId, { type = 'stop' })
        return
    end

    sendDui(screenId, {
        type = state.playing and 'play' or 'pause',
        url = state.url,
        timestamp = state.timestamp or 0,
    })
end)

-- ---------- Interaction zone + URL entry ----------
-- One ox_lib sphere zone per screen, centered on interactCoords.
-- Standing inside shows "Press E to set screen URL"; E opens a URL input
-- dialog whose value is normalized (YouTube -> watch?v=ID, m3u8/mp4
-- passthrough) and forwarded to the server as opentheater:play.

local zones = {}
local setupWizard = {
    active = false,
    id = '',
    label = '',
    points = {},
    current = 0,
}

-- Normalize whatever the operator pastes into a canonical URL the DUI player
-- understands: YouTube variants collapse to watch?v=ID, direct streams pass
-- through. Returns nil for anything unrecognized so the caller can reject it.
local function normalizeUrl(raw)
    if type(raw) ~= 'string' then return nil end
    local url = raw:gsub('^%s+', ''):gsub('%s+$', '')
    if url == '' then return nil end

    -- Direct stream / video — passthrough (query string preserved).
    if url:find('%.m3u8') or url:find('%.mp4') or url:find('%.webm') or url:find('%.ogg') then
        return url
    end

    -- Bare 11-char YouTube id.
    if #url == 11 and url:match('^[%w_-]+$') then
        return ('https://www.youtube.com/watch?v=%s'):format(url)
    end

    -- YouTube variants -> watch?v=ID
    local id = url:match('youtu%.be/([%w_-]+)')
        or url:match('[?&]v=([%w_-]+)')
        or url:match('youtube%.com/shorts/([%w_-]+)')
        or url:match('youtube%.com/embed/([%w_-]+)')
        or url:match('youtube%.com/live/([%w_-]+)')
        or url:match('youtube%.com/v/([%w_-]+)')
    if id then
        return ('https://www.youtube.com/watch?v=%s'):format(id)
    end

    return nil
end

local function openUrlInput(screenCfg)
    local input = lib.inputDialog(('Theater — %s'):format(screenCfg.label), {
        {
            type = 'input',
            label = 'YouTube or m3u8 URL',
            description = 'Paste a YouTube link (any format) or a .m3u8 / .mp4 / .webm / .ogg stream URL.',
            placeholder = 'https://www.youtube.com/watch?v=...',
            required = true,
        },
    })
    if not input or not input[1] then return end

    local url = normalizeUrl(input[1])
    if not url then
        lib.notify({
            type = 'error',
            description = 'Unrecognized URL. Use a YouTube link or a .mp4 / .m3u8 / .webm / .ogg stream.',
        })
        return
    end

    if Config.debug then
        log(('play %s url=%s'):format(screenCfg.id, url))
    end
    TriggerServerEvent('opentheater:play', screenCfg.id, url)
end

local function createScreenZone(screenCfg)
    if screenCfg.hidePrompt then return nil end

    local promptShown = false
    local zone = lib.zones.sphere({
        coords = screenCfg.interactCoords,
        radius = 4.0,
        debug = Config.debug,
        onEnter = function()
            log(('Entered interaction zone for screen %s'):format(screenCfg.id))
        end,
        inside = function()
            if setupWizard.active then return end
            if not promptShown then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to set screen URL')
                EndTextCommandDisplayHelp(0, false, true, -1)
                promptShown = true
            end
            if IsControlJustPressed(0, 38) then -- E
                openUrlInput(screenCfg)
            end
        end,
        onExit = function()
            promptShown = false
        end,
    })
    return zone
end

-- ---------- NUI control panel (placeholder) ----------
-- The NUI is separate from the DUI. The NUI is the operator's control
-- panel; the DUI is what's projected onto the screen. Two different things.
-- Currently the URL entry flow uses an ox_lib input dialog instead of the
-- NUI panel — this close callback stays as a defensive fallback in case
-- any future code (or external UI) opens NUI focus.

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

-- ---------- Render loop ----------

local function startRenderLoop(screenCfg)
    CreateThread(function()
        local key = screenCfg.id
        while screens[key] do
            local s = screens[key]
            if not s or not s.ready then
                Wait(100)
            elseif Utils.isInRange(screenCfg.interactCoords, screenCfg.streamDistance) then
                Utils.drawScreenPoly(
                    screenCfg.corners,
                    s.txdName,
                    'screen',
                    255
                )
                Wait(0)
            else
                -- Out of range: throttle hard, save frames.
                Wait(Config.proximityInterval)
            end
        end
    end)
end

-- ---------- Proximity audio ----------
-- The DUI plays its own audio; here we drive its volume from how close the
-- player is to the screen so it gets louder as you approach and fades to
-- silence past maxDistance. Volume 0..1 is forwarded to the DUI, which applies
-- it uniformly to YouTube and direct video via react-player's volume prop.

local function screenAudioBounds(screenCfg)
    local minD = screenCfg.audioMinDistance or Config.audio.minDistance
    local maxD = screenCfg.audioMaxDistance or Config.audio.maxDistance
    if maxD <= minD then maxD = minD + 0.01 end
    return minD, maxD
end

local function computeVolume(centerCoords, minD, maxD)
    local pedCoords = GetEntityCoords(PlayerPedId())
    local dist = #(pedCoords - centerCoords)
    if dist <= minD then return 1.0 end
    if dist >= maxD then return 0.0 end
    local v = (maxD - dist) / (maxD - minD)
    return v * v -- gentle (quadratic) rolloff
end

local function startAudioLoop(screenCfg)
    CreateThread(function()
        local key = screenCfg.id
        local center = Utils.getCenterCoords(screenCfg.corners)
        local interval = (Config.audio and Config.audio.updateInterval) or 200
        local minD, maxD = screenAudioBounds(screenCfg)
        local lastSent = -1.0
        while screens[key] do
            local s = screens[key]
            if s and s.ready then
                local vol = computeVolume(center, minD, maxD)
                if math.abs(vol - lastSent) >= 0.01 then
                    lastSent = vol
                    sendDui(key, { type = 'volume', volume = vol }, true)
                end
            end
            Wait(interval)
        end
    end)
end

-- ---------- Dev tool: /setupscreen + /setupcancel ----------
-- Walks the player through picking the four screen corners (camera raycast)
-- and an interaction point, then prints a paste-ready Config.screens block
-- to the F8 console. Active only when Config.debug = true.

local setupStepNames = { 'topLeft', 'topRight', 'bottomRight', 'bottomLeft', 'interact' }

local function formatVec3Short(v)
    return ('vec3(%.4f, %.4f, %.4f)'):format(v.x, v.y, v.z)
end

local function drawWorldMarker(coords, r, g, b)
    DrawMarker(
        28,
        coords.x, coords.y, coords.z,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.06, 0.06, 0.06,
        r or 255, g or 255, b or 255, 220,
        false, false, 2, false, nil, nil, false
    )
end

local function showSetupHelp(message)
    lib.showTextUI(message)
end

local function hideSetupHelp()
    lib.hideTextUI()
end

local function outputSetupConfigBlock()
    local p = setupWizard.points
    local heading = GetEntityHeading(PlayerPedId())
    local block = ([[
{
    id = '%s',
    label = '%s',
    corners = {
        topLeft     = %s,
        topRight    = %s,
        bottomRight = %s,
        bottomLeft  = %s,
    },
    duiWidth = 1280,
    duiHeight = 720,
    interactCoords = %s,
    interactHeading = %.2f,
    streamDistance = 100.0,
    hidePrompt = false,
},
]]):format(
        setupWizard.id, setupWizard.label,
        formatVec3Short(p[1].coords),
        formatVec3Short(p[2].coords),
        formatVec3Short(p[3].coords),
        formatVec3Short(p[4].coords),
        formatVec3Short(p[5].coords),
        heading
    )

    print('========== COPY BELOW INTO Config.screens ==========')
    print(block)
    print('====================================================')
    TriggerEvent('chat:addMessage', {
        args = { '[OpenTheater]', 'Config block printed to F8 console. Paste into Config.screens.' }
    })
end

local function setupWizardThread()
    while setupWizard.active do
        local stepName = setupStepNames[setupWizard.current + 1]
        local hint
        local rayData = nil

        if stepName == 'interact' then
            hint = 'Stand at the interaction point and press [E] to capture'
            local coords = GetEntityCoords(PlayerPedId())
            drawWorldMarker(coords, 80, 200, 255)
        else
            hint = ('Aim at the %s corner and press [E] to capture'):format(stepName)
            rayData = Utils.raycastFromCamera(80.0)
            if rayData and rayData.hitCoords then
                drawWorldMarker(rayData.hitCoords, 0, 255, 120)
            elseif rayData and rayData.endCoords then
                drawWorldMarker(rayData.endCoords, 255, 80, 80)
            end
        end

        for index, point in ipairs(setupWizard.points) do
            local colorR, colorG, colorB = 255, 220, 0
            if point.name == 'interact' then
                colorR, colorG, colorB = 80, 200, 255
            end
            drawWorldMarker(point.coords, colorR, colorG, colorB)
        end

        showSetupHelp(('[%d/5] %s'):format(setupWizard.current + 1, hint))

        if IsControlJustPressed(0, 38) then -- E
            if stepName == 'interact' then
                local coords = GetEntityCoords(PlayerPedId())
                setupWizard.points[#setupWizard.points + 1] = { name = stepName, coords = coords }
                setupWizard.current = setupWizard.current + 1
                lib.notify({ type = 'success', description = 'Captured interactCoords' })
                log(('Captured interactCoords: %s'):format(formatVec3Short(coords)))
            else
                local hitCoords = rayData and rayData.hitCoords or nil
                if hitCoords then
                    setupWizard.points[#setupWizard.points + 1] = { name = stepName, coords = hitCoords }
                    setupWizard.current = setupWizard.current + 1
                    lib.notify({ type = 'success', description = ('Captured %s'):format(stepName) })
                    log(('Captured %s: %s'):format(stepName, formatVec3Short(hitCoords)))
                else
                    lib.notify({
                        type = 'error',
                        description = 'Raycast hit nothing. Aim at the screen surface and try again.',
                    })
                end
            end
        end

        if setupWizard.current >= 5 then
            hideSetupHelp()
            outputSetupConfigBlock()
            setupWizard.active = false
        end

        Wait(0)
    end

    hideSetupHelp()
end

local function startSetupScreen(id, label)
    if setupWizard.active then
        TriggerEvent('chat:addMessage', {
            args = { '[OpenTheater]', 'Setup already running. Type /setupcancel to abort.' }
        })
        return
    end
    setupWizard.active = true
    setupWizard.id = id or ('screen_' .. GetGameTimer())
    setupWizard.label = label or 'New Theater Screen'
    setupWizard.points = {}
    setupWizard.current = 0
    TriggerEvent('chat:addMessage', {
        args = { '[OpenTheater]',
            ('Setup started: id=%s label=%s. Aim at each corner, press E. Green marker = ray hit, red marker = max distance.'):format(setupWizard.id, setupWizard.label)
        }
    })
    setupWizardThread()
end

if Config.debug then
    RegisterCommand('setupscreen', function(_, args)
        local id = args[1]
        local label
        if #args >= 2 then
            label = table.concat(args, ' ', 2)
        end
        startSetupScreen(id, label)
    end, false)

    RegisterCommand('setupcancel', function()
        if setupWizard.active then
            setupWizard.active = false
            TriggerEvent('chat:addMessage', {
                args = { '[OpenTheater]', 'Setup cancelled.' }
            })
        end
    end, false)

    -- Legacy quick-grab fallback (player position, not raycast).
    RegisterCommand('getscreencoords', function(_, args)
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        print(('========================================'))
        print(('Current ped coords: %s'):format(Utils.formatVec3(coords)))
        print(('Current ped heading: %.2f'):format(heading))
        print(('========================================'))
        print('Usage: walk to each corner, type /getscreencoords, paste into config.lua')
        print('Corners order: topLeft, topRight, bottomRight, bottomLeft')

        TriggerEvent('chat:addMessage', {
            args = { '[OpenTheater]', ('Coords: %s'):format(Utils.formatVec3(coords)) }
        })
    end, false)
end

-- ---------- Boot / teardown ----------

CreateThread(function()
    -- Small delay to let the NUI page settle before the DUI mounts.
    Wait(500)
    for _, screenCfg in ipairs(Config.screens) do
        initScreen(screenCfg)
        startRenderLoop(screenCfg)
        startAudioLoop(screenCfg)
        local zone = createScreenZone(screenCfg)
        if zone then
            zones[screenCfg.id] = zone
        end
    end
    -- Ask the server for current state once we're up.
    TriggerServerEvent('opentheater:requestState')
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= RESOURCE_NAME then return end
    for key, _ in pairs(screens) do
        destroyScreen(key)
    end
    for key, zone in pairs(zones) do
        zone:remove()
        zones[key] = nil
    end
    SetNuiFocus(false, false)
end)