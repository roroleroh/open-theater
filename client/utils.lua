-- Ares Open Theater — client utilities
-- DrawSpritePoly wrapper + coord math. No framework deps.

local Utils = {}

-- Average the four corners to get a screen-centre world position.
-- Used for range checks and for the interaction prompt placement.
function Utils.getCenterCoords(corners)
    local c = corners
    return vector3(
        (c.topLeft.x + c.topRight.x + c.bottomRight.x + c.bottomLeft.x) / 4.0,
        (c.topLeft.y + c.topRight.y + c.bottomRight.y + c.bottomLeft.y) / 4.0,
        (c.topLeft.z + c.topRight.z + c.bottomRight.z + c.bottomLeft.z) / 4.0
    )
end

-- Cheap squared distance; avoids sqrt in the hot path.
function Utils.distSq(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

function Utils.isInRange(coords, distance)
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local maxSq = distance * distance
    return Utils.distSq(pedCoords, coords) <= maxSq
end

-- Render the DUI texture onto the four world corners.
--
-- DrawSpritePoly draws ONE textured triangle: 3 vertices (9 floats), the
-- colour, the txd/txn, then per-vertex UVW (u, v, w) — 3 floats each. It does
-- NOT take a 4th vertex. A rectangle is therefore two triangles:
--   triangle 1: topLeft -> topRight    -> bottomRight
--   triangle 2: topLeft -> bottomRight -> bottomLeft
-- UV layout (w is unused for a flat texture, so it stays 0.0):
--   topLeft(0,0)  topRight(1,0)
--   bottomLeft(0,1)  bottomRight(1,1)
-- Triangles are single-sided (back-face culled), so we also draw the reverse
-- winding — that keeps the screen visible no matter which way the configured
-- corners are wound.
function Utils.drawScreenPoly(corners, txdName, textureName, opacity)
    opacity = opacity or 255
    if opacity < 0 then opacity = 0 end
    if opacity > 255 then opacity = 255 end

    local c = corners
    local tl, tr, br, bl = c.topLeft, c.topRight, c.bottomRight, c.bottomLeft

    local function tri(a, b, d, ua, va, ub, vb, ud, vd)
        DrawSpritePoly(
            a.x, a.y, a.z,
            b.x, b.y, b.z,
            d.x, d.y, d.z,
            255, 255, 255, opacity,
            txdName, textureName,
            ua, va, 0.0,
            ub, vb, 0.0,
            ud, vd, 0.0
        )
    end

    -- Front faces
    tri(tl, tr, br, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0)
    tri(tl, br, bl, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0)
    -- Back faces (reverse winding, same UV per vertex)
    tri(tl, br, tr, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0)
    tri(tl, bl, br, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0)
end

-- Format a vec3 as a ready-to-paste string for config.lua.
function Utils.formatVec3(v)
    return ('vector3(%.4f, %.4f, %.4f)'):format(v.x, v.y, v.z)
end

-- Cast a ray from the gameplay camera forward and return the first world hit.
-- Used by /setupscreen to grab screen corners: aim at a surface, hit is the
-- world coord. Returns the hit coords plus ray metadata, or nil if the ray
-- didn't hit anything within `distance`.
function Utils.raycastFromCamera(distance)
    distance = distance or 50.0
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local pitch = math.rad(camRot.x)
    local yaw = math.rad(camRot.z)
    local forward = vector3(
        -math.sin(yaw) * math.cos(pitch),
        math.cos(yaw) * math.cos(pitch),
        math.sin(pitch)
    )
    local endCoords = camCoords + forward * distance

    local handle = StartShapeTestLosProbe(
        camCoords.x, camCoords.y, camCoords.z,
        endCoords.x, endCoords.y, endCoords.z,
        511, PlayerPedId(), 7
    )

    local hit, hitCoords = 0, nil
    for _ = 1, 10 do
        local retval, hitResult, coords = GetShapeTestResult(handle)
        if retval == 2 then
            hit = hitResult
            hitCoords = coords
            break
        end
        Wait(0)
    end

    if hit == 1 and hitCoords then
        return {
            hitCoords = hitCoords,
            camCoords = camCoords,
            endCoords = endCoords,
        }
    end

    return {
        hitCoords = nil,
        camCoords = camCoords,
        endCoords = endCoords,
    }
end

return Utils