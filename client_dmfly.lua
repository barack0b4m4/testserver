-- DM Flying movement handler

local flying = false
local flySpeed = 0.15
local keys = {}

addEventHandler("onClientKey", root, function(key, state)
    keys[key] = state
end)

function startFlying()
    flying = true
    addEventHandler("onClientRender", root, handleFlyMovement)
end

function stopFlying()
    flying = false
    removeEventHandler("onClientRender", root, handleFlyMovement)
end

function handleFlyMovement()
    if not flying then return end
    
    local player = localPlayer
    local x, y, z = getElementPosition(player)
    local camRot = getPedCameraRotation(player)
    
    -- Get camera direction for proper WASD movement
    local moveX = 0
    local moveY = 0
    
    -- Forward (W) - move in camera direction
    if keys["w"] then
        moveX = moveX + math.sin(math.rad(camRot)) * flySpeed
        moveY = moveY + math.cos(math.rad(camRot)) * flySpeed
    end
    
    -- Backward (S) - move opposite camera direction
    if keys["s"] then
        moveX = moveX - math.sin(math.rad(camRot)) * flySpeed
        moveY = moveY - math.cos(math.rad(camRot)) * flySpeed
    end
    
    -- Left strafe (A) - move left relative to camera
    if keys["a"] then
        moveX = moveX - math.sin(math.rad(camRot + 90)) * flySpeed
        moveY = moveY - math.cos(math.rad(camRot + 90)) * flySpeed
    end
    
    -- Right strafe (D) - move right relative to camera
    if keys["d"] then
        moveX = moveX + math.sin(math.rad(camRot + 90)) * flySpeed
        moveY = moveY + math.cos(math.rad(camRot + 90)) * flySpeed
    end
    
    -- Up (Space)
    if keys["space"] then
        z = z + flySpeed
    end
    
    -- Down (Z)
    if keys["z"] then
        z = z - flySpeed
    end
    
    -- Apply movement
    setElementPosition(player, x + moveX, y + moveY, z)
end

-- Listen for server events
addEvent("dmfly:start", true)
addEventHandler("dmfly:start", root, function()
    startFlying()
    outputChatBox("DM Fly Mode: ON", 0, 255, 0)
    outputChatBox("Use WASD to move, Space/Z to go up/down, F to land", 200, 200, 200)
end)

addEvent("dmfly:stop", true)
addEventHandler("dmfly:stop", root, function()
    stopFlying()
    outputChatBox("Landed. DM Fly Mode: OFF", 255, 0, 0)
end)

addEventHandler("onClientKey", root, function(key, state)
    if key == "f" and state == true then
        if flying then
            triggerServerEvent("dmfly:land", localPlayer)
        end
    end
end)