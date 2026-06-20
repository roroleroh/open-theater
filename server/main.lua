-- Ares Open Theater — server authority
-- Source of truth: per-screen playback state. Clients request sync on join
-- so late arrivals land at the correct timestamp.

local RESOURCE_NAME = GetCurrentResourceName()

-- theaterStates[screenId] = {
--     url           = string,         -- last URL (kept for /stop & resume UX)
--     playing       = bool,
--     startedAt     = number,         -- GetGameTimer() ms when last play/seek began
--     pausedAt      = number|nil,     -- GetGameTimer() ms when paused (nil if playing)
--     timestamp     = number,         -- seconds into the video at startedAt
--     lastCommand   = string,         -- last action type for debugging
--     source        = number|nil,     -- server source that issued last command
-- }
local theaterStates = {}

local function getState(screenId)
    return theaterStates[screenId]
end

-- Compute current playback position (seconds) given a state object.
-- Server-authoritative: every client uses the same formula, no client drift.
local function currentTimestamp(state)
    if not state or not state.playing then
        return state and state.timestamp or 0
    end
    local elapsedMs = GetGameTimer() - state.startedAt
    if elapsedMs < 0 then elapsedMs = 0 end
    return state.timestamp + (elapsedMs / 1000.0)
end

local function broadcastState(screenId)
    local state = theaterStates[screenId]
    if not state then return end
    TriggerClientEvent('opentheater:syncState', -1, screenId, {
        url = state.url,
        playing = state.playing,
        timestamp = currentTimestamp(state),
        lastCommand = state.lastCommand,
    })
end

local function hasControl(source)
    if Config.debug then
        return true
    end
    if not IsPlayerAceAllowed(source, Config.acePermission) then
        if Config.debug then
            print(('[%s] source=%d denied: missing ace %q'):format(
                RESOURCE_NAME, source, Config.acePermission))
        end
        return false
    end
    return true
end

local function screenExists(screenId)
    for _, screen in ipairs(Config.screens) do
        if screen.id == screenId then return true end
    end
    return false
end

-- ---------- Control events from clients ----------

RegisterNetEvent('opentheater:play', function(screenId, url)
    local src = source
    if not hasControl(src) then return end
    if type(screenId) ~= 'string' or type(url) ~= 'string' then return end
    if not screenExists(screenId) then return end

    theaterStates[screenId] = {
        url = url,
        playing = true,
        startedAt = GetGameTimer(),
        pausedAt = nil,
        timestamp = 0,
        lastCommand = 'play',
        source = src,
    }

    if Config.debug then
        print(('[%s] play screen=%s url=%s by=%d'):format(
            RESOURCE_NAME, screenId, url, src))
    end

    broadcastState(screenId)
end)

RegisterNetEvent('opentheater:pause', function(screenId)
    local src = source
    if not hasControl(src) then return end
    if type(screenId) ~= 'string' then return end

    local state = theaterStates[screenId]
    if not state or not state.playing then return end

    state.timestamp = currentTimestamp(state)
    state.playing = false
    state.pausedAt = GetGameTimer()
    state.lastCommand = 'pause'
    state.source = src

    if Config.debug then
        print(('[%s] pause screen=%s at=%.2fs'):format(
            RESOURCE_NAME, screenId, state.timestamp))
    end

    broadcastState(screenId)
end)

RegisterNetEvent('opentheater:stop', function(screenId)
    local src = source
    if not hasControl(src) then return end
    if type(screenId) ~= 'string' then return end

    local state = theaterStates[screenId]
    if not state then return end

    state.playing = false
    state.pausedAt = GetGameTimer()
    state.timestamp = 0
    state.lastCommand = 'stop'
    state.source = src

    if Config.debug then
        print(('[%s] stop screen=%s'):format(RESOURCE_NAME, screenId))
    end

    broadcastState(screenId)
end)

RegisterNetEvent('opentheater:seek', function(screenId, timestamp)
    local src = source
    if not hasControl(src) then return end
    if type(screenId) ~= 'string' then return end
    timestamp = tonumber(timestamp)
    if not timestamp or timestamp < 0 then return end

    local state = theaterStates[screenId]
    if not state then return end

    state.timestamp = timestamp
    state.startedAt = GetGameTimer()
    state.playing = state.playing and true or false
    state.pausedAt = state.playing and nil or GetGameTimer()
    state.lastCommand = 'seek'
    state.source = src

    if Config.debug then
        print(('[%s] seek screen=%s to=%.2fs'):format(
            RESOURCE_NAME, screenId, timestamp))
    end

    broadcastState(screenId)
end)

-- ---------- Late join / reconnect ----------

RegisterNetEvent('opentheater:requestState', function()
    local src = source
    if Config.debug then
        print(('[%s] requestState from=%d'):format(RESOURCE_NAME, src))
    end
    for screenId, _ in pairs(theaterStates) do
        local state = theaterStates[screenId]
        TriggerClientEvent('opentheater:syncState', src, screenId, {
            url = state.url,
            playing = state.playing,
            timestamp = currentTimestamp(state),
            lastCommand = state.lastCommand,
        })
    end
end)

-- ---------- Admin: force-clear all state on resource stop ----------

AddEventHandler('onResourceStop', function(name)
    if name ~= RESOURCE_NAME then return end
    theaterStates = {}
end)