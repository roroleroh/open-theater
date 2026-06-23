-- Ares Open Theater — server authority (statebag model)
-- Each screen's playback state lives in a global statebag entry:
--     GlobalState['opentheater:<screenId>'] = {
--         url        = string|false,   -- false = stopped/idle
--         playing    = bool,
--         baseTime   = number,         -- video position (s) at startedAt
--         startedAt  = number,         -- server os.time() (epoch s) of baseTime
--         lastCommand= string,
--         flag       = string|false,   -- model name of the prop flag, or false
--     }
-- Statebags replicate to every client automatically, including late joiners,
-- so clients just read the bag and compute the current position — no manual
-- broadcast or request/response handshake needed.
--
-- The selected flag is ALSO persisted to KV storage (SetResourceKvp) so it
-- survives a full server restart. Statebags live in RAM only; KV is the only
-- store that crosses process restarts. On resource start we rehydrate the
-- statebag's flag from KV if the statebag entry is missing.

local RESOURCE_NAME = GetCurrentResourceName()

local function stateKey(screenId)
    return ('opentheater:%s'):format(screenId)
end

local function getState(screenId)
    return GlobalState[stateKey(screenId)]
end

-- Merge `partial` over the existing statebag entry (if any), falling back to
-- sane defaults for a brand-new screen. Fields not mentioned in `partial`
-- survive the update — so e.g. `flag` is preserved across play/pause/seek
-- without each handler having to remember to copy it forward.
local function setState(screenId, partial)
    local current = getState(screenId)
    local merged
    if current then
        merged = {}
        for k, v in pairs(current) do merged[k] = v end
        for k, v in pairs(partial) do merged[k] = v end
    else
        merged = {
            url = false,
            playing = false,
            baseTime = 0,
            startedAt = os.time(),
            lastCommand = 'init',
            flag = false,
        }
        for k, v in pairs(partial) do merged[k] = v end
    end
    GlobalState[stateKey(screenId)] = merged
end

-- ---------- KV storage (reboot-proof flag selection) ----------
-- Resource-scoped key/value store, persisted to disk. Used only for the
-- flag selection because that's the one piece of operator state we want to
-- survive a full server restart; video state is intentionally session-only.

local function flagKvKey(screenId)
    return ('opentheater:flag:%s'):format(screenId)
end

local function loadFlagFromKv(screenId)
    return GetResourceKvp(flagKvKey(screenId))
end

local function saveFlagToKv(screenId, model)
    if model then
        SetResourceKvp(flagKvKey(screenId), model)
    else
        DeleteResourceKvp(flagKvKey(screenId))
    end
end

-- Current playback position (seconds) for a state. Server-authoritative:
-- baseTime plus however long it's been playing since startedAt.
local function currentPosition(st)
    if not st then return 0 end
    if st.playing and st.startedAt then
        local elapsed = os.time() - st.startedAt
        if elapsed < 0 then elapsed = 0 end
        return (st.baseTime or 0) + elapsed
    end
    return st.baseTime or 0
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

-- Clients use this once at startup to cancel out client/server clock skew, so
-- the epoch-based position maths stays accurate regardless of local clocks.
lib.callback.register('opentheater:serverTime', function(_)
    return os.time()
end)

-- ---------- Control events from clients ----------

RegisterNetEvent('opentheater:play', function(screenId, url)
    local src = source
    if not hasControl(src) then return end
    if type(screenId) ~= 'string' or type(url) ~= 'string' then return end
    if not screenExists(screenId) then return end

    setState(screenId, {
        url = url,
        playing = true,
        baseTime = 0,
        startedAt = os.time(),
        lastCommand = 'play',
    })

    if Config.debug then
        print(('[%s] play screen=%s url=%s by=%d'):format(RESOURCE_NAME, screenId, url, src))
    end
end)

RegisterNetEvent('opentheater:pause', function(screenId)
    local src = source
    if not hasControl(src) then return end
    if type(screenId) ~= 'string' then return end

    local st = getState(screenId)
    if not st or not st.url or not st.playing then return end

    setState(screenId, {
        url = st.url,
        playing = false,
        baseTime = currentPosition(st),
        startedAt = os.time(),
        lastCommand = 'pause',
    })

    if Config.debug then
        print(('[%s] pause screen=%s'):format(RESOURCE_NAME, screenId))
    end
end)

RegisterNetEvent('opentheater:resume', function(screenId)
    local src = source
    if not hasControl(src) then return end
    if type(screenId) ~= 'string' then return end

    local st = getState(screenId)
    if not st or not st.url or st.playing then return end

    setState(screenId, {
        url = st.url,
        playing = true,
        baseTime = st.baseTime or 0,
        startedAt = os.time(),
        lastCommand = 'resume',
    })

    if Config.debug then
        print(('[%s] resume screen=%s'):format(RESOURCE_NAME, screenId))
    end
end)

RegisterNetEvent('opentheater:stop', function(screenId)
    local src = source
    if not hasControl(src) then return end
    if type(screenId) ~= 'string' then return end
    if not screenExists(screenId) then return end

    setState(screenId, {
        url = false,
        playing = false,
        baseTime = 0,
        startedAt = os.time(),
        lastCommand = 'stop',
    })

    if Config.debug then
        print(('[%s] stop screen=%s'):format(RESOURCE_NAME, screenId))
    end
end)

RegisterNetEvent('opentheater:seek', function(screenId, timestamp)
    local src = source
    if not hasControl(src) then return end
    if type(screenId) ~= 'string' then return end
    timestamp = tonumber(timestamp)
    if not timestamp or timestamp < 0 then return end

    local st = getState(screenId)
    if not st or not st.url then return end

    setState(screenId, {
        url = st.url,
        playing = st.playing and true or false,
        baseTime = timestamp,
        startedAt = os.time(),
        lastCommand = 'seek',
    })

    if Config.debug then
        print(('[%s] seek screen=%s to=%.2fs'):format(RESOURCE_NAME, screenId, timestamp))
    end
end)

-- ---------- Flag (prop) selection ----------

-- Validate that a flag model name is one we know about. Used to reject
-- arbitrary strings sent by a compromised client.
local function isKnownFlag(model)
    if type(model) ~= 'string' then return false end
    for _, f in ipairs(Config.flags or {}) do
        if f.model == model then return true end
    end
    return false
end

RegisterNetEvent('opentheater:setFlag', function(screenId, model)
    local src = source
    if not hasControl(src) then return end
    if type(screenId) ~= 'string' then return end
    if not screenExists(screenId) then return end

    -- Normalise: accept a known model, or anything falsy to clear the flag.
    local normalized = false
    if model and model ~= '' then
        if not isKnownFlag(model) then
            if Config.debug then
                print(('[%s] setFlag rejected: unknown model %q for screen %s'):format(
                    RESOURCE_NAME, tostring(model), screenId))
            end
            return
        end
        normalized = model
    end

    setState(screenId, { flag = normalized, lastCommand = 'flag' })

    -- Persist the selection so it survives a full server restart. Statebag is
    -- RAM-only and gets wiped on process restart; KV is the durable store.
    saveFlagToKv(screenId, normalized or nil)

    if Config.debug then
        print(('[%s] setFlag screen=%s flag=%s by=%d'):format(
            RESOURCE_NAME, screenId, tostring(normalized), src))
    end
end)

-- ---------- Init: give every configured screen a defined idle state ----------
-- Existing state is preserved across resource restarts (the server keeps
-- running), so a movie survives a script restart. On a full server restart
-- the statebag is wiped — we rehydrate `flag` from KV (the only store that
-- crosses process restarts) and seed everything else to idle defaults.

AddEventHandler('onResourceStart', function(name)
    if name ~= RESOURCE_NAME then return end
    for _, screen in ipairs(Config.screens) do
        if getState(screen.id) == nil then
            setState(screen.id, {
                url = false,
                playing = false,
                baseTime = 0,
                startedAt = os.time(),
                lastCommand = 'init',
                flag = loadFlagFromKv(screen.id) or false,
            })
        end
    end
end)
