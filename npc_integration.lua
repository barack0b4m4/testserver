-- npc_integration.lua (SERVER)
-- Integration layer between NPC-HLC-Enhanced and D&D RP gamemode

--------------------------------------------------------------------------------
-- DEBUG MESSAGE SUPPRESSION (MUST BE FIRST)
--------------------------------------------------------------------------------

-- Store originals IMMEDIATELY before anything else runs
local originalOutputChatBox = outputChatBox
local originalOutputDebugString = outputDebugString

-- Create suppression filter
local function shouldSuppressMessage(message)
    if type(message) ~= "string" then
        return false
    end
    
    local suppressPatterns = {
        "addNPCTask",
        "driveAlongLine",
        "walkAlongLine",
        "waitForGreenLight",
        "driveAroundBend",
        "crossRoad",
        "stopAtTrafficLight",
        "turnAround",
        "followPath",
        "NPC%-HLC",
        "pathfinding",
        "waypoint",
        "navigation",
        "ped movement",
        "traffic update",
        "route calculation"
    }
    
    for _, pattern in ipairs(suppressPatterns) do
        if message:find(pattern) then
            return true
        end
    end
    
    return false
end

-- Override outputChatBox globally
_G.outputChatBox = function(message, visibleTo, r, g, b, colorCoded)
    if shouldSuppressMessage(message) then
        return -- Suppress
    end
    return originalOutputChatBox(message, visibleTo, r, g, b, colorCoded)
end

-- Override outputDebugString globally
_G.outputDebugString = function(message, level, red, green, blue)
    if shouldSuppressMessage(message) then
        return -- Suppress
    end
    return originalOutputDebugString(message, level, red, green, blue)
end

outputServerLog("===== NPC_INTEGRATION.LUA LOADING =====")
outputServerLog("Chat/Debug suppression: ACTIVE")

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
    -- Debug settings
    suppressNPCDebug = true,      -- Suppress NPC-HLC debug messages
    showOwnDebug = false,         -- Show our own debug messages
    
    -- NPC spawning limits
    maxAmbientPeds = 30,          -- Max ambient pedestrians
    maxAmbientVehicles = 15,      -- Max ambient vehicles
    
    -- Spawn distances (meters)
    spawnDistance = 100,          -- How far from players to spawn
    despawnDistance = 150,        -- How far before despawning
    
    -- Update intervals (milliseconds)
    updateInterval = 1000,        -- How often to check spawning
    pathfindInterval = 500,       -- How often NPCs recalculate paths
    
    -- NPC behavior
    walkSpeed = 1.0,              -- Walking speed multiplier
    runSpeed = 1.5,               -- Running speed multiplier
    avoidanceRadius = 2.0,        -- How far NPCs avoid obstacles (meters)
    
    -- Integration with gamemode
    respectDMNPCs = true,         -- Don't spawn ambient NPCs near DM-controlled NPCs
    dmNPCClearRadius = 50,        -- Clear radius around DM NPCs (meters)
    
    -- Performance
    streamingDistance = 120,      -- MTA streaming distance
    tickRate = 50,                -- Physics tick rate (ms)
}

--------------------------------------------------------------------------------
-- GLOBAL TRACKING
--------------------------------------------------------------------------------

local AmbientPeds = {}        -- Spawned ambient pedestrians
local AmbientVehicles = {}    -- Spawned ambient vehicles
local PlayerSpawnZones = {}   -- Active spawn zones per player

-- Track DM-controlled NPCs to avoid conflicts
local DMControlledNPCs = {}

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

-- Check if position is clear of DM NPCs
local function isPositionClearOfDMNPCs(x, y, z)
    if not CONFIG.respectDMNPCs then return true end
    
    for _, npc in pairs(DMControlledNPCs) do
        if isElement(npc) then
            local nx, ny, nz = getElementPosition(npc)
            local distance = getDistanceBetweenPoints3D(x, y, z, nx, ny, nz)
            if distance < CONFIG.dmNPCClearRadius then
                return false
            end
        end
    end
    
    return true
end

-- Get random pedestrian model
local function getRandomPedModel()
    local pedModels = {
        7, 9, 10, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 43,
        44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
        60, 61, 62, 63, 64, 66, 67, 68, 69, 70, 71, 72, 73, 75, 76, 77,
        78, 79, 80, 81, 82, 83, 84, 85, 87, 88, 89, 90, 91, 92, 93, 94,
        95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108
    }
    return pedModels[math.random(1, #pedModels)]
end

-- Get random vehicle model
local function getRandomVehicleModel()
    local vehicleModels = {
        400, 401, 404, 405, 410, 411, 412, 419, 421, 422, 426, 436, 
        439, 445, 451, 458, 459, 466, 467, 474, 475, 479, 480, 482,
        489, 491, 492, 496, 500, 516, 517, 518, 526, 527, 529, 533,
        534, 535, 536, 540, 541, 542, 545, 546, 547, 549, 550, 551,
        558, 559, 560, 561, 562, 565, 566, 567, 575, 576, 579, 580,
        585, 587, 589, 596, 597, 598, 599, 600, 602, 603
    }
    return vehicleModels[math.random(1, #vehicleModels)]
end

-- Find nearest road node (simplified - in real implementation use NPC-HLC pathfinding)
local function findNearestRoadNode(x, y, z)
    -- This would integrate with NPC-HLC's pathfinding system
    -- For now, return the position slightly adjusted
    return x + math.random(-5, 5), y + math.random(-5, 5), z
end

-- Check if path is clear (obstacle detection)
local function isPathClear(startX, startY, startZ, endX, endY, endZ)
    -- Use isLineOfSightClear for collision check
    return isLineOfSightClear(
        startX, startY, startZ,
        endX, endY, endZ,
        true, true, false, true, false, false, false
    )
end

--------------------------------------------------------------------------------
-- AMBIENT PED SPAWNING
--------------------------------------------------------------------------------

local function spawnAmbientPed(x, y, z, dimension, interior)
    if #AmbientPeds >= CONFIG.maxAmbientPeds then
        return nil
    end
    
    if not isPositionClearOfDMNPCs(x, y, z) then
        return nil
    end
    
    local model = getRandomPedModel()
    local ped = createPed(model, x, y, z)
    
    if not ped then
        return nil
    end
    
    setElementDimension(ped, dimension)
    setElementInterior(ped, interior)
    
    -- Mark as ambient NPC
    setElementData(ped, "ambient.npc", true)
    setElementData(ped, "ambient.type", "pedestrian")
    setElementData(ped, "ambient.spawnTime", getRealTime().timestamp)
    
    -- Set initial behavior
    setPedAnimation(ped, "PED", "WALK_civi", -1, true, false, false, false)
    
    -- Store in tracking table
    table.insert(AmbientPeds, {
        element = ped,
        spawnTime = getRealTime().timestamp,
        targetX = nil,
        targetY = nil,
        targetZ = nil,
        state = "idle" -- idle, walking, running
    })
    
    outputServerLog("Spawned ambient ped at " .. x .. ", " .. y .. ", " .. z)
    
    if CONFIG.showOwnDebug then
        outputDebugString("[NPC Integration] Spawned ambient ped at " .. x .. ", " .. y .. ", " .. z)
    end
    
    return ped
end

local function despawnAmbientPed(ped)
    if not isElement(ped) then return end
    
    -- Remove from tracking
    for i, data in ipairs(AmbientPeds) do
        if data.element == ped then
            table.remove(AmbientPeds, i)
            break
        end
    end
    
    destroyElement(ped)
end

--------------------------------------------------------------------------------
-- AMBIENT VEHICLE SPAWNING
--------------------------------------------------------------------------------

local function spawnAmbientVehicle(x, y, z, dimension, interior)
    if #AmbientVehicles >= CONFIG.maxAmbientVehicles then
        return nil
    end
    
    if not isPositionClearOfDMNPCs(x, y, z) then
        return nil
    end
    
    local model = getRandomVehicleModel()
    local veh = createVehicle(model, x, y, z)
    
    if not veh then
        return nil
    end
    
    setElementDimension(veh, dimension)
    setElementInterior(veh, interior)
    
    -- Create driver
    local driverModel = getRandomPedModel()
    local driver = createPed(driverModel, x, y, z)
    
    if driver then
        setElementDimension(driver, dimension)
        setElementInterior(driver, interior)
        warpPedIntoVehicle(driver, veh)
        
        -- Mark as ambient
        setElementData(driver, "ambient.npc", true)
        setElementData(driver, "ambient.type", "driver")
    end
    
    setElementData(veh, "ambient.vehicle", true)
    setElementData(veh, "ambient.spawnTime", getRealTime().timestamp)
    
    table.insert(AmbientVehicles, {
        element = veh,
        driver = driver,
        spawnTime = getRealTime().timestamp,
        state = "driving"
    })
    
    outputServerLog("Spawned ambient vehicle at " .. x .. ", " .. y .. ", " .. z)
    
    if CONFIG.showOwnDebug then
        outputDebugString("[NPC Integration] Spawned ambient vehicle at " .. x .. ", " .. y .. ", " .. z)
    end
    
    return veh
end

local function despawnAmbientVehicle(veh)
    if not isElement(veh) then return end
    
    -- Remove driver
    for i, data in ipairs(AmbientVehicles) do
        if data.element == veh then
            if isElement(data.driver) then
                destroyElement(data.driver)
            end
            table.remove(AmbientVehicles, i)
            break
        end
    end
    
    destroyElement(veh)
end

--------------------------------------------------------------------------------
-- PATHFINDING & MOVEMENT (Integrates with NPC-HLC)
--------------------------------------------------------------------------------

local function updatePedMovement(pedData)
    local ped = pedData.element
    
    if not isElement(ped) then
        return
    end
    
    local px, py, pz = getElementPosition(ped)
    
    -- If no target, pick a random nearby point
    if not pedData.targetX then
        local targetX, targetY, targetZ = findNearestRoadNode(px, py, pz)
        pedData.targetX = targetX + math.random(-20, 20)
        pedData.targetY = targetY + math.random(-20, 20)
        pedData.targetZ = targetZ
    end
    
    -- Check if reached target
    local distance = getDistanceBetweenPoints2D(px, py, pedData.targetX, pedData.targetY)
    
    if distance < 2.0 then
        -- Reached target, pick new one
        pedData.targetX = nil
        pedData.targetY = nil
        pedData.state = "idle"
        setPedAnimation(ped, "PED", "IDLE_stance", -1, true, false, false, false)
        
        -- Wait a bit before moving again
        setTimer(function()
            if isElement(ped) then
                pedData.state = "walking"
                setPedAnimation(ped, "PED", "WALK_civi", -1, true, false, false, false)
            end
        end, math.random(2000, 5000), 1)
        
        return
    end
    
    -- Check if path is clear
    if isPathClear(px, py, pz, pedData.targetX, pedData.targetY, pedData.targetZ) then
        -- Move toward target using MTA's pathfinding
        -- In real implementation, this would use NPC-HLC's enhanced pathfinding
        local dx = pedData.targetX - px
        local dy = pedData.targetY - py
        local angle = math.atan2(dy, dx)
        
        setPedRotation(ped, math.deg(angle) - 90)
        
        -- Simple movement (NPC-HLC would handle this better)
        local speed = pedData.state == "running" and CONFIG.runSpeed or CONFIG.walkSpeed
        local moveX = px + math.cos(angle) * speed * 0.1
        local moveY = py + math.sin(angle) * speed * 0.1
        
        setElementPosition(ped, moveX, moveY, pz)
    else
        -- Obstacle detected, recalculate path
        pedData.targetX = nil
        pedData.targetY = nil
    end
end

local function updateVehicleMovement(vehData)
    local veh = vehData.element
    
    if not isElement(veh) then
        return
    end
    
    -- Basic vehicle AI (NPC-HLC would provide proper traffic AI)
    -- This is a placeholder - real implementation would use NPC-HLC's traffic system
end

--------------------------------------------------------------------------------
-- SPAWN ZONE MANAGEMENT
--------------------------------------------------------------------------------

local function updatePlayerSpawnZone(player)
    if not isElement(player) then return end
    
    local px, py, pz = getElementPosition(player)
    local dimension = getElementDimension(player)
    local interior = getElementInterior(player)
    
    -- Spawn pedestrians around player
    local spawnCount = math.min(5, CONFIG.maxAmbientPeds - #AmbientPeds)
    
    for i = 1, spawnCount do
        local angle = math.random() * 2 * math.pi
        local distance = CONFIG.spawnDistance + math.random(-20, 20)
        
        local spawnX = px + math.cos(angle) * distance
        local spawnY = py + math.sin(angle) * distance
        local spawnZ = pz -- Just use player's Z level for now
        
        spawnAmbientPed(spawnX, spawnY, spawnZ, dimension, interior)
    end
    
    -- Spawn vehicles on roads
    local vehicleSpawnCount = math.min(2, CONFIG.maxAmbientVehicles - #AmbientVehicles)
    
    for i = 1, vehicleSpawnCount do
        local angle = math.random() * 2 * math.pi
        local distance = CONFIG.spawnDistance + math.random(-10, 10)
        
        local spawnX, spawnY, spawnZ = findNearestRoadNode(
            px + math.cos(angle) * distance,
            py + math.sin(angle) * distance,
            pz
        )
        
        spawnAmbientVehicle(spawnX, spawnY, spawnZ, dimension, interior)
    end
end

local function cleanupDistantNPCs()
    -- Despawn NPCs too far from any player
    for i = #AmbientPeds, 1, -1 do
        local pedData = AmbientPeds[i]
        if isElement(pedData.element) then
            local px, py, pz = getElementPosition(pedData.element)
            local tooFar = true
            
            for _, player in ipairs(getElementsByType("player")) do
                local plx, ply, plz = getElementPosition(player)
                local distance = getDistanceBetweenPoints3D(px, py, pz, plx, ply, plz)
                
                if distance < CONFIG.despawnDistance then
                    tooFar = false
                    break
                end
            end
            
            if tooFar then
                despawnAmbientPed(pedData.element)
            end
        else
            table.remove(AmbientPeds, i)
        end
    end
    
    -- Same for vehicles
    for i = #AmbientVehicles, 1, -1 do
        local vehData = AmbientVehicles[i]
        if isElement(vehData.element) then
            local vx, vy, vz = getElementPosition(vehData.element)
            local tooFar = true
            
            for _, player in ipairs(getElementsByType("player")) do
                local plx, ply, plz = getElementPosition(player)
                local distance = getDistanceBetweenPoints3D(vx, vy, vz, plx, ply, plz)
                
                if distance < CONFIG.despawnDistance then
                    tooFar = false
                    break
                end
            end
            
            if tooFar then
                despawnAmbientVehicle(vehData.element)
            end
        else
            table.remove(AmbientVehicles, i)
        end
    end
end

--------------------------------------------------------------------------------
-- INTEGRATION WITH DUNGEON MASTER SYSTEM
--------------------------------------------------------------------------------

-- Track when DM spawns an NPC
addEvent("onDMNPCSpawned", true)
addEventHandler("onDMNPCSpawned", root, function(npc)
    if isElement(npc) then
        DMControlledNPCs[npc] = true
    end
end)

addEvent("onDMNPCDespawned", true)
addEventHandler("onDMNPCDespawned", root, function(npc)
    DMControlledNPCs[npc] = nil
end)

-- Hook into dungeon_master.lua NPC spawning
if NPC and NPC.spawn then
    local originalSpawn = NPC.spawn
    function NPC:spawn(...)
        local success, ped = originalSpawn(self, ...)
        if success and ped then
            triggerEvent("onDMNPCSpawned", root, ped)
        end
        return success, ped
    end
end

if NPC and NPC.despawn then
    local originalDespawn = NPC.despawn
    function NPC:despawn()
        local ped = self:getPed()
        if ped then
            triggerEvent("onDMNPCDespawned", root, ped)
        end
        return originalDespawn(self)
    end
end

--------------------------------------------------------------------------------
-- MAIN UPDATE LOOP
--------------------------------------------------------------------------------

setTimer(function()
    -- Update movement for all ambient peds
    for _, pedData in ipairs(AmbientPeds) do
        updatePedMovement(pedData)
    end
    
    -- Update movement for all ambient vehicles
    for _, vehData in ipairs(AmbientVehicles) do
        updateVehicleMovement(vehData)
    end
end, CONFIG.pathfindInterval, 0)

setTimer(function()
    -- Spawn NPCs around active players
    for _, player in ipairs(getElementsByType("player")) do
        updatePlayerSpawnZone(player)
    end
    
    -- Clean up distant NPCs
    cleanupDistantNPCs()
end, CONFIG.updateInterval, 0)

--------------------------------------------------------------------------------
-- COMMANDS (Admin/Testing)
--------------------------------------------------------------------------------

addCommandHandler("npcstats", function(player)
    outputChatBox("=== Ambient NPC Stats ===", player, 255, 255, 0)
    outputChatBox("Pedestrians: " .. #AmbientPeds .. "/" .. CONFIG.maxAmbientPeds, player, 255, 255, 255)
    outputChatBox("Vehicles: " .. #AmbientVehicles .. "/" .. CONFIG.maxAmbientVehicles, player, 255, 255, 255)
    outputChatBox("DM NPCs: " .. table.size(DMControlledNPCs), player, 255, 255, 255)
end)

addCommandHandler("clearnpcs", function(player)
    -- Check if admin/DM
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master to use this command", player, 255, 0, 0)
        return
    end
    
    local count = 0
    
    for i = #AmbientPeds, 1, -1 do
        despawnAmbientPed(AmbientPeds[i].element)
        count = count + 1
    end
    
    for i = #AmbientVehicles, 1, -1 do
        despawnAmbientVehicle(AmbientVehicles[i].element)
        count = count + 1
    end
    
    outputChatBox("Cleared " .. count .. " ambient NPCs", player, 0, 255, 0)
end)

addCommandHandler("npcdebug", function(player, cmd, mode)
    -- Check if admin/DM
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master to use this command", player, 255, 0, 0)
        return
    end
    
    if not mode then
        outputChatBox("Current: suppressNPCDebug = " .. tostring(CONFIG.suppressNPCDebug) .. ", showOwnDebug = " .. tostring(CONFIG.showOwnDebug), player, 255, 255, 0)
        outputChatBox("Usage: /npcdebug [on|off|full]", player, 255, 255, 0)
        outputChatBox("  on   - Show our debug only", player, 200, 200, 200)
        outputChatBox("  off  - Suppress all NPC debug", player, 200, 200, 200)
        outputChatBox("  full - Show all debug messages", player, 200, 200, 200)
        return
    end
    
    if mode == "off" then
        CONFIG.suppressNPCDebug = true
        CONFIG.showOwnDebug = false
        outputChatBox("Debug: All NPC debug suppressed", player, 0, 255, 0)
    elseif mode == "on" then
        CONFIG.suppressNPCDebug = true
        CONFIG.showOwnDebug = true
        outputChatBox("Debug: Showing integration debug only", player, 0, 255, 0)
    elseif mode == "full" then
        CONFIG.suppressNPCDebug = false
        CONFIG.showOwnDebug = true
        outputChatBox("Debug: Showing all debug messages", player, 255, 165, 0)
        outputChatBox("Warning: This will spam console!", player, 255, 0, 0)
    else
        outputChatBox("Invalid mode. Use: on, off, or full", player, 255, 0, 0)
    end
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onResourceStop", resourceRoot, function()
    -- Clean up all ambient NPCs
    for _, pedData in ipairs(AmbientPeds) do
        if isElement(pedData.element) then
            destroyElement(pedData.element)
        end
    end
    
    for _, vehData in ipairs(AmbientVehicles) do
        if isElement(vehData.driver) then
            destroyElement(vehData.driver)
        end
        if isElement(vehData.element) then
            destroyElement(vehData.element)
        end
    end
    
    -- Restore original functions
    _G.outputChatBox = originalOutputChatBox
    _G.outputDebugString = originalOutputDebugString
end)

-- Utility function
function table.size(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

outputServerLog("===== NPC_INTEGRATION.LUA LOADED =====")
outputServerLog("Ambient NPC System: Ready")
outputServerLog("Max Peds: " .. CONFIG.maxAmbientPeds .. " | Max Vehicles: " .. CONFIG.maxAmbientVehicles)
