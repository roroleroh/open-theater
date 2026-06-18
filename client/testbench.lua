-- client/testbench.lua
--
-- Standalone NUI overlay for devs to throw a URL at and see whether it plays
-- in CEF before wiring it into a screen. Same renderer/codec/DRM behaviour
-- as the in-world DUI screens - if it doesn't play here, it won't play there.

RegisterCommand('theatertest', function()
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open' })
end, false)

RegisterNUICallback('close', function(_data, cb)
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback('log', function(data, cb)
    if Config.debug then
        print(('[OpenTheater:TestBench] %s'):format(data.message))
    end

    cb({})
end)
