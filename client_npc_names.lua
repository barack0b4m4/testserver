-- Draws NPC/Shopkeeper names above their heads with distance-based transparency

local MAX_DIST = 30 -- maximum draw distance in meters

addEventHandler("onClientRender", root, function()
    -- Player position for distance check
    local px, py, pz = getElementPosition(localPlayer)
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        local name = getElementData(ped, "npc.name") or getElementData(ped, "shop.name")
        if name and isElementOnScreen(ped) then
            local x, y, z = getElementPosition(ped)
            local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if dist < MAX_DIST then
                -- Fade alpha with distance (closer = more opaque)
                local alpha = 255 * (1 - (dist / MAX_DIST))
                alpha = math.max(60, math.min(alpha, 255)) -- clamp alpha (semi-visible at farthest)
                local sx, sy = getScreenFromWorldPosition(x, y, z + 1.0)
                if sx and sy then
                    dxDrawText(name, sx, sy, sx, sy, tocolor(255, 255, 200, alpha), 1.3, "default-bold", "center", "bottom")
                end
            end
        end
    end
end)