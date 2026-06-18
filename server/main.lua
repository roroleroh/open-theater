-- server/main.lua
--
-- Spawns one networked prop per configured screen and exposes callbacks for
-- setting/clearing what's playing on it. All URL validation happens here -
-- clients only ever request a change, the server decides whether it's valid
-- and writes the statebag.

local screenEntities = {} -- [screenId] = netId

CreateThread(function()
    for _, screen in pairs(Config.screens) do
        local obj = CreateObject(screen.model, screen.coords.x, screen.coords.y, screen.coords.z, true, true, false)
        SetEntityHeading(obj, screen.coords.w)
        FreezeEntityPosition(obj, true)

        local netId = NetworkGetNetworkIdFromEntity(obj)
        screenEntities[screen.id] = netId

        -- Initialize statebag defaults so clients have something sane to read
        -- before anyone has loaded a video yet.
        Entity(obj):setState('screenId', screen.id, true)
        Entity(obj):setState('videoUrl', nil, true)
        Entity(obj):setState('videoType', nil, true)
        Entity(obj):setState('startTime', 0, true)
        Entity(obj):setState('playing', false, true)

        if Config.debug then
            print(('[OpenTheater] Spawned screen "%s" (netId %s) at %.2f, %.2f, %.2f')
                :format(screen.id, netId, screen.coords.x, screen.coords.y, screen.coords.z))
        end
    end
end)

-- Returns { [screenId] = netId } so clients can resolve the actual entity
lib.callback.register('ares_opentheater:getScreens', function(_source)
    local result = {}

    for screenId, netId in pairs(screenEntities) do
        result[screenId] = netId
    end

    return result
end)

-- Validates and applies a video to a screen's statebag
lib.callback.register('ares_opentheater:setVideo', function(source, data)
    if type(data) ~= 'table' then
        return false, 'Malformed request'
    end

    local screenId = data.screenId
    local url = data.url
    local videoType = data.videoType

    if type(url) ~= 'string' or #url == 0 or #url > Config.maxUrlLength then
        return false, 'Invalid URL'
    end

    if videoType ~= 'mp4' and videoType ~= 'hls' then
        return false, 'Invalid video type'
    end

    if not url:match('^https?://') then
        return false, 'URL must start with http:// or https://'
    end

    local validExtension = false
    local lowered = url:lower()

    for _, ext in pairs(Config.allowedExtensions[videoType]) do
        -- match the extension either at the end of the URL or right before a query string
        if lowered:find(ext .. '$') or lowered:find(ext .. '?', 1, true) then
            validExtension = true
            break
        end
    end

    if not validExtension then
        return false, ('URL does not look like a .%s file for type "%s"')
            :format(table.concat(Config.allowedExtensions[videoType], '/.'), videoType)
    end

    local netId = screenEntities[screenId]
    if not netId then
        return false, 'Unknown screen'
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) then
        return false, 'Screen entity missing'
    end

    Entity(entity):setState('videoUrl', url, true)
    Entity(entity):setState('videoType', videoType, true)
    Entity(entity):setState('startTime', GetCloudTimeAsInt(), true)
    Entity(entity):setState('playing', true, true)

    if Config.debug then
        print(('[OpenTheater] %s set screen "%s" -> [%s] %s'):format(GetPlayerName(source), screenId, videoType, url))
    end

    return true
end)

-- Clears a screen back to idle
lib.callback.register('ares_opentheater:stopVideo', function(source, data)
    if type(data) ~= 'table' then
        return false, 'Malformed request'
    end

    local netId = screenEntities[data.screenId]
    if not netId then
        return false, 'Unknown screen'
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(entity) then
        return false, 'Screen entity missing'
    end

    Entity(entity):setState('playing', false, true)
    Entity(entity):setState('videoUrl', nil, true)
    Entity(entity):setState('videoType', nil, true)
    Entity(entity):setState('startTime', 0, true)

    if Config.debug then
        print(('[OpenTheater] %s stopped screen "%s"'):format(GetPlayerName(source), data.screenId))
    end

    return true
end)
