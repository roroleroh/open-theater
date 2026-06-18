-- client/main.lua
--
-- For each configured screen: resolves the networked entity the server
-- spawned, then creates/destroys a DUI + runtime texture based on player
-- distance (each DUI is its own CEF instance - don't keep them alive when
-- nobody's nearby).
--
-- Statebag changes (videoUrl/videoType/playing/startTime) on the entity are
-- pushed into the DUI via SendDuiMessage, where html/screen/script.js
-- actually sets the <video> src.

local activeScreens = {} -- [screenId] = { config, netId, entity, dui, runtimeTxd, runtimeTexture }

local function createScreenDui(screenConfig)
    local pagePath = ('nui://%s/html/screen/index.html'):format(GetCurrentResourceName())

    local dui = CreateDui(pagePath, screenConfig.renderTargetWidth, screenConfig.renderTargetHeight)
    local duiHandle = GetDuiHandle(dui)

    local runtimeTxdName = screenConfig.textureDict .. '_rt'
    local runtimeTxd = CreateRuntimeTxd(runtimeTxdName)
    local runtimeTexture = CreateRuntimeTextureFromDuiHandle(runtimeTxd, screenConfig.textureName, duiHandle)

    AddReplaceTexture(screenConfig.textureDict, screenConfig.textureName, runtimeTxdName, screenConfig.textureName)

    if Config.debug then
        print(('[OpenTheater] Created DUI for screen "%s"'):format(screenConfig.id))
    end

    return dui, runtimeTxd, runtimeTexture
end

local function destroyScreenDui(screenId)
    local active = activeScreens[screenId]
    if not active or not active.dui then return end

    DestroyDui(active.dui)
    RemoveReplaceTexture(active.config.textureDict, active.config.textureName)

    active.dui = nil
    active.runtimeTxd = nil
    active.runtimeTexture = nil

    if Config.debug then
        print(('[OpenTheater] Destroyed DUI for screen "%s"'):format(screenId))
    end
end

-- Pushes the entity's current statebag into the DUI page
local function pushStateToDui(screenId)
    local active = activeScreens[screenId]
    if not active or not active.dui or not active.entity then return end

    local state = Entity(active.entity).state

    if not state.playing or not state.videoUrl then
        SendDuiMessage(active.dui, json.encode({ type = 'stop' }))
        return
    end

    -- For VOD this lets a client that joins/returns mid-playback seek to
    -- roughly the right spot. Live HLS streams should ignore seekTo and just
    -- play from the live edge - that's handled in html/screen/script.js.
    local elapsed = GetCloudTimeAsInt() - (state.startTime or 0)
    if elapsed < 0 then elapsed = 0 end

    SendDuiMessage(active.dui, json.encode({
        type = 'play',
        url = state.videoUrl,
        videoType = state.videoType,
        seekTo = elapsed
    }))
end

CreateThread(function()
    -- Give the server a moment to finish spawning screen entities
    Wait(1000)

    local screenNetIds = lib.callback.await('ares_opentheater:getScreens', false)

    for screenId, netId in pairs(screenNetIds or {}) do
        local screenConfig

        for _, cfg in pairs(Config.screens) do
            if cfg.id == screenId then
                screenConfig = cfg
                break
            end
        end

        if screenConfig then
            activeScreens[screenId] = { config = screenConfig, netId = netId }
        end
    end

    while true do
        for screenId, active in pairs(activeScreens) do
            local entity = NetworkGetEntityFromNetworkId(active.netId)

            if DoesEntityExist(entity) then
                active.entity = entity

                local playerCoords = GetEntityCoords(cache.ped or PlayerPedId())
                local distance = #(playerCoords - GetEntityCoords(entity))

                if distance <= active.config.streamDistance then
                    if not active.dui then
                        active.dui, active.runtimeTxd, active.runtimeTexture = createScreenDui(active.config)
                        pushStateToDui(screenId)
                    end
                elseif active.dui then
                    destroyScreenDui(screenId)
                end
            end
        end

        Wait(Config.distanceCheckInterval)
    end
end)

-- Re-push state whenever the server updates playback on a screen entity
local function onPlaybackStateChanged(bagName)
    local entity = GetEntityFromStateBagName(bagName)

    for screenId, active in pairs(activeScreens) do
        if active.entity == entity then
            pushStateToDui(screenId)
        end
    end
end

AddStateBagChangeHandler('videoUrl', '', function(bagName) onPlaybackStateChanged(bagName) end)
AddStateBagChangeHandler('playing', '', function(bagName) onPlaybackStateChanged(bagName) end)

-- Basic player-facing control: stand within 5m of a screen and run /theater
-- to load or stop a video. Swap this for an ox_target option / lib.points
-- zone in a real build - this is just enough to exercise the statebag flow.
RegisterCommand('theater', function()
    local playerCoords = GetEntityCoords(cache.ped or PlayerPedId())

    for screenId, active in pairs(activeScreens) do
        if active.entity and DoesEntityExist(active.entity) then
            local distance = #(playerCoords - GetEntityCoords(active.entity))

            if distance <= 5.0 then
                local input = lib.inputDialog('Open Theater', {
                    {
                        type = 'input',
                        label = 'Video URL (.mp4 or .m3u8)',
                        description = 'Leave empty + submit to stop playback',
                        required = false
                    },
                    {
                        type = 'select',
                        label = 'Type',
                        options = {
                            { value = 'mp4', label = 'MP4 (file, VOD)' },
                            { value = 'hls', label = 'HLS (.m3u8, live or VOD)' }
                        },
                        default = 'mp4'
                    }
                })

                if not input then return end

                if not input[1] or input[1] == '' then
                    local success = lib.callback.await('ares_opentheater:stopVideo', false, { screenId = screenId })

                    if success then
                        lib.notify({ description = 'Screen stopped', type = 'success' })
                    end

                    return
                end

                local success, err = lib.callback.await('ares_opentheater:setVideo', false, {
                    screenId = screenId,
                    url = input[1],
                    videoType = input[2]
                })

                if success then
                    lib.notify({ description = 'Video loaded', type = 'success' })
                else
                    lib.notify({ description = err or 'Failed to load video', type = 'error' })
                end

                return
            end
        end
    end

    lib.notify({ description = 'No screen nearby', type = 'error' })
end, false)
