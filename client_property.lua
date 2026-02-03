-- client_property.lua (CLIENT)
-- Property system client-side interactions

local currentProperty = nil

-- Handle blip clicks
addEventHandler("onClientClick", root, function(button, state, x, y, worldX, worldY, worldZ, clickedElement)
    if button ~= "left" or state ~= "down" then return end
    if not clickedElement or getElementType(clickedElement) ~= "blip" then return end
    
    local propertyID = getElementData(clickedElement, "property.id")
    if not propertyID then return end
    
    outputChatBox("Interacting with property...", 200, 200, 200)
    triggerServerEvent("property:waypoint:clicked", localPlayer, propertyID)
end)

-- Handle marker hit
addEventHandler("onClientMarkerHit", root, function()
    local propertyID = getElementData(source, "property.id")
    if propertyID then
        currentProperty = propertyID
        outputChatBox("Press G to interact with " .. getElementData(source, "property.name"), 0, 255, 0)
    end
end)

addEventHandler("onClientMarkerLeave", root, function()
    currentProperty = nil
end)

-- Handle G key at marker
addEventHandler("onClientKey", root, function(key, state)
    if key ~= "g" or state == false then return end
    if not currentProperty then return end
    
    triggerServerEvent("property:marker:interact", localPlayer, currentProperty)
end)