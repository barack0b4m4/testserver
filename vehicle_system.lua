--[[
================================================================================
    VEHICLE_SYSTEM.LUA - Vehicle Ownership & Management
================================================================================
    Manages vehicle ownership, spawning, locking, and economy integration.
    Vehicles can be owned by characters or companies, locked/unlocked,
    and can be produced by companies or purchased from shopkeepers.
    
    FEATURES:
    - Vehicle ownership (character OR company)
    - Lock/unlock system for owners
    - Custom descriptions set by owners
    - Transfer between characters and companies
    - Economy integration (vehicles as purchasable items)
    - DM vehicle spawning and management
    - Persistent vehicle storage in database
    
    OWNERSHIP TYPES:
    - "character" - Owned by a player character (ownerID = character_id)
    - "company" - Owned by a company (ownerID = company_id)
    
    DM COMMANDS:
    - /spawnvehicle modelID [color1] [color2]
    - /setvehicleowner vehicleID character/company ownerID
    - /deletevehicle
    - /listvehicles [owner]
    - /givevehicle modelID player
    
    PLAYER COMMANDS:
    - /lock, /unlock
    - /vehicledesc "description"
    - /myvehicles
    - /transfervehicle companyID
    - /spawnmyvehicle vehicleID
    - /storevehicle
================================================================================
]]

outputServerLog("===== VEHICLE_SYSTEM.LUA LOADING =====")

local db = nil

-- Global tables
OwnedVehicles = OwnedVehicles or {}
VehicleElements = VehicleElements or {}

-- Owner type constants
VEHICLE_OWNER_TYPE = {
    CHARACTER = "character",
    COMPANY = "company"
}

-- GTA:SA Vehicle names by model ID
VEHICLE_NAMES = {
    [400] = "Landstalker", [401] = "Bravura", [402] = "Buffalo", [403] = "Linerunner",
    [404] = "Perennial", [405] = "Sentinel", [406] = "Dumper", [407] = "Firetruck",
    [408] = "Trashmaster", [409] = "Stretch", [410] = "Manana", [411] = "Infernus",
    [412] = "Voodoo", [413] = "Pony", [414] = "Mule", [415] = "Cheetah",
    [416] = "Ambulance", [417] = "Leviathan", [418] = "Moonbeam", [419] = "Esperanto",
    [420] = "Taxi", [421] = "Washington", [422] = "Bobcat", [423] = "Mr Whoopee",
    [424] = "BF Injection", [425] = "Hunter", [426] = "Premier", [427] = "Enforcer",
    [428] = "Securicar", [429] = "Banshee", [430] = "Predator", [431] = "Bus",
    [432] = "Rhino", [433] = "Barracks", [434] = "Hotknife", [436] = "Previon",
    [437] = "Coach", [438] = "Cabbie", [439] = "Stallion", [440] = "Rumpo",
    [442] = "Romero", [443] = "Packer", [444] = "Monster", [445] = "Admiral",
    [451] = "Turismo", [458] = "Solair", [461] = "PCJ-600", [462] = "Faggio",
    [463] = "Freeway", [466] = "Glendale", [467] = "Oceanic", [468] = "Sanchez",
    [470] = "Patriot", [471] = "Quad", [474] = "Hermes", [475] = "Sabre",
    [477] = "ZR-350", [478] = "Walton", [479] = "Regina", [480] = "Comet",
    [481] = "BMX", [482] = "Burrito", [483] = "Camper", [487] = "Maverick",
    [489] = "Rancher", [491] = "Virgo", [492] = "Greenwood", [495] = "Sandking",
    [496] = "Blista Compact", [500] = "Mesa", [505] = "Rancher Lure", [506] = "Super GT",
    [507] = "Elegant", [508] = "Journey", [509] = "Bike", [510] = "Mountain Bike",
    [516] = "Nebula", [517] = "Majestic", [518] = "Buccaneer", [521] = "FCR-900",
    [522] = "NRG-500", [526] = "Fortune", [527] = "Cadrona", [529] = "Willard",
    [533] = "Feltzer", [534] = "Remington", [535] = "Slamvan", [536] = "Blade",
    [540] = "Vincent", [541] = "Bullet", [542] = "Clover", [543] = "Sadler",
    [545] = "Hustler", [546] = "Intruder", [547] = "Primo", [549] = "Tampa",
    [550] = "Sunrise", [551] = "Merit", [555] = "Windsor", [558] = "Uranus",
    [559] = "Jester", [560] = "Sultan", [561] = "Stratum", [562] = "Elegy",
    [565] = "Flash", [566] = "Tahoma", [567] = "Savanna", [575] = "Broadway",
    [576] = "Tornado", [579] = "Huntley", [580] = "Stafford", [585] = "Emperor",
    [587] = "Euros", [589] = "Club", [596] = "Police LS", [597] = "Police SF",
    [598] = "Police LV", [599] = "Police Ranger", [600] = "Picador", [602] = "Alpha",
    [603] = "Phoenix"
}

--------------------------------------------------------------------------------
-- DATABASE INITIALIZATION
--------------------------------------------------------------------------------

local function initializeVehicleTables()
    if not db then return end
    
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS owned_vehicles (
            id TEXT PRIMARY KEY,
            model_id INTEGER NOT NULL,
            owner_type TEXT DEFAULT 'character',
            owner_id TEXT,
            owner_name TEXT,
            description TEXT DEFAULT '',
            is_locked INTEGER DEFAULT 1,
            color1 INTEGER DEFAULT 0,
            color2 INTEGER DEFAULT 0,
            spawn_x REAL,
            spawn_y REAL,
            spawn_z REAL,
            spawn_rotation REAL DEFAULT 0,
            spawn_dimension INTEGER DEFAULT 0,
            spawn_interior INTEGER DEFAULT 0,
            is_spawned INTEGER DEFAULT 0,
            created_date INTEGER,
            created_by TEXT
        )
    ]])
    
    outputServerLog("Vehicle database tables initialized")
end

addEventHandler("onResourceStart", resourceRoot, function()
    db = database
    if not db then
        outputServerLog("ERROR: Could not access database for vehicle system")
        return
    end
    
    initializeVehicleTables()
    loadAllVehicles()
end)

--------------------------------------------------------------------------------
-- VEHICLE LOADING
--------------------------------------------------------------------------------

function loadAllVehicles()
    if not db then return end
    
    local query = dbQuery(db, "SELECT * FROM owned_vehicles")
    local result = dbPoll(query, -1)
    
    if not result then return end
    
    for _, row in ipairs(result) do
        local vehicle = {
            id = row.id,
            modelID = row.model_id,
            ownerType = row.owner_type or VEHICLE_OWNER_TYPE.CHARACTER,
            ownerID = row.owner_id,
            ownerName = row.owner_name,
            description = row.description or "",
            isLocked = (row.is_locked == 1),
            color1 = row.color1 or 0,
            color2 = row.color2 or 0,
            spawnPos = {
                x = row.spawn_x, y = row.spawn_y, z = row.spawn_z,
                rotation = row.spawn_rotation or 0,
                dimension = row.spawn_dimension or 0,
                interior = row.spawn_interior or 0
            },
            isSpawned = (row.is_spawned == 1),
            createdDate = row.created_date,
            createdBy = row.created_by
        }
        
        OwnedVehicles[vehicle.id] = vehicle
        
        if vehicle.isSpawned and vehicle.spawnPos.x then
            spawnVehicleElement(vehicle.id)
        end
    end
    
    outputServerLog("Loaded " .. #result .. " owned vehicles")
end

--------------------------------------------------------------------------------
-- VEHICLE ELEMENT MANAGEMENT
--------------------------------------------------------------------------------

function spawnVehicleElement(vehicleID)
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then return nil end
    
    if VehicleElements[vehicleID] and isElement(VehicleElements[vehicleID]) then
        destroyElement(VehicleElements[vehicleID])
    end
    
    local pos = vehicle.spawnPos
    if not pos or not pos.x then return nil end
    
    local veh = createVehicle(vehicle.modelID, pos.x, pos.y, pos.z, 0, 0, pos.rotation or 0)
    
    if veh then
        setElementDimension(veh, pos.dimension or 0)
        setElementInterior(veh, pos.interior or 0)
        setVehicleColor(veh, vehicle.color1 or 0, vehicle.color2 or 0, 0, 0)
        setVehicleLocked(veh, vehicle.isLocked)
        
        setElementData(veh, "vehicle.id", vehicleID)
        setElementData(veh, "vehicle.owner", vehicle.ownerName or "Unknown")
        setElementData(veh, "vehicle.owner_type", vehicle.ownerType)
        setElementData(veh, "vehicle.description", vehicle.description or "")
        setElementData(veh, "vehicle.is_locked", vehicle.isLocked)
        
        VehicleElements[vehicleID] = veh
        vehicle.isSpawned = true
        
        dbExec(db, "UPDATE owned_vehicles SET is_spawned = 1 WHERE id = ?", vehicleID)
        
        return veh
    end
    
    return nil
end

function despawnVehicleElement(vehicleID)
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then return false end
    
    if VehicleElements[vehicleID] and isElement(VehicleElements[vehicleID]) then
        local veh = VehicleElements[vehicleID]
        local x, y, z = getElementPosition(veh)
        local _, _, rz = getElementRotation(veh)
        
        vehicle.spawnPos.x = x
        vehicle.spawnPos.y = y
        vehicle.spawnPos.z = z
        vehicle.spawnPos.rotation = rz
        vehicle.spawnPos.dimension = getElementDimension(veh)
        vehicle.spawnPos.interior = getElementInterior(veh)
        
        destroyElement(veh)
        VehicleElements[vehicleID] = nil
    end
    
    vehicle.isSpawned = false
    
    dbExec(db, [[
        UPDATE owned_vehicles SET 
            is_spawned = 0, spawn_x = ?, spawn_y = ?, spawn_z = ?, 
            spawn_rotation = ?, spawn_dimension = ?, spawn_interior = ?
        WHERE id = ?
    ]], vehicle.spawnPos.x, vehicle.spawnPos.y, vehicle.spawnPos.z,
        vehicle.spawnPos.rotation, vehicle.spawnPos.dimension, vehicle.spawnPos.interior,
        vehicleID)
    
    return true
end

--------------------------------------------------------------------------------
-- VEHICLE OWNERSHIP FUNCTIONS
--------------------------------------------------------------------------------

function createOwnedVehicle(ownerType, ownerID, ownerName, modelID, x, y, z, rotation, dimension, interior, color1, color2, createdBy)
    if not db then return nil end
    
    if not VEHICLE_NAMES[modelID] then
        return nil, "Invalid vehicle model"
    end
    
    local vehicleID = "veh_" .. getRealTime().timestamp .. "_" .. math.random(1000, 9999)
    
    local vehicle = {
        id = vehicleID,
        modelID = modelID,
        ownerType = ownerType,
        ownerID = ownerID,
        ownerName = ownerName,
        description = "",
        isLocked = true,
        color1 = color1 or 0,
        color2 = color2 or 0,
        spawnPos = {
            x = x, y = y, z = z,
            rotation = rotation or 0,
            dimension = dimension or 0,
            interior = interior or 0
        },
        isSpawned = false,
        createdDate = getRealTime().timestamp,
        createdBy = createdBy or "SYSTEM"
    }
    
    local success = dbExec(db, [[
        INSERT INTO owned_vehicles 
        (id, model_id, owner_type, owner_id, owner_name, description, is_locked,
         color1, color2, spawn_x, spawn_y, spawn_z, spawn_rotation, spawn_dimension,
         spawn_interior, is_spawned, created_date, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], vehicleID, modelID, ownerType, ownerID, ownerName, "",
        1, color1 or 0, color2 or 0, x, y, z, rotation or 0, dimension or 0,
        interior or 0, 0, vehicle.createdDate, vehicle.createdBy)
    
    if not success then return nil, "Database error" end
    
    OwnedVehicles[vehicleID] = vehicle
    
    outputServerLog("Vehicle created: " .. vehicleID .. " (" .. VEHICLE_NAMES[modelID] .. ") for " .. ownerName)
    
    return vehicleID
end

function deleteOwnedVehicle(vehicleID)
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then return false end
    
    if VehicleElements[vehicleID] and isElement(VehicleElements[vehicleID]) then
        destroyElement(VehicleElements[vehicleID])
        VehicleElements[vehicleID] = nil
    end
    
    dbExec(db, "DELETE FROM owned_vehicles WHERE id = ?", vehicleID)
    OwnedVehicles[vehicleID] = nil
    
    return true
end

function canAccessVehicle(player, vehicleID)
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then return true end
    if not vehicle.isLocked then return true end
    if isDungeonMaster and isDungeonMaster(player) then return true end
    return isVehicleOwner(player, vehicleID)
end

function isVehicleOwner(player, vehicleID)
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then return false end
    if not vehicle.ownerID then return false end
    
    if vehicle.ownerType == VEHICLE_OWNER_TYPE.CHARACTER then
        local char = AccountManager and AccountManager:getActiveCharacter(player)
        if char and tostring(char.id) == tostring(vehicle.ownerID) then
            return true
        end
    elseif vehicle.ownerType == VEHICLE_OWNER_TYPE.COMPANY then
        if Companies then
            local company = Companies[vehicle.ownerID]
            if company and company.ownerType == "player" then
                local char = AccountManager and AccountManager:getActiveCharacter(player)
                if char and tostring(char.id) == tostring(company.ownerID) then
                    return true
                end
            end
        end
    end
    
    return false
end

function lockVehicle(vehicleID)
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then return false end
    
    vehicle.isLocked = true
    
    if VehicleElements[vehicleID] and isElement(VehicleElements[vehicleID]) then
        setVehicleLocked(VehicleElements[vehicleID], true)
        setElementData(VehicleElements[vehicleID], "vehicle.is_locked", true)
    end
    
    dbExec(db, "UPDATE owned_vehicles SET is_locked = 1 WHERE id = ?", vehicleID)
    return true
end

function unlockVehicle(vehicleID)
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then return false end
    
    vehicle.isLocked = false
    
    if VehicleElements[vehicleID] and isElement(VehicleElements[vehicleID]) then
        setVehicleLocked(VehicleElements[vehicleID], false)
        setElementData(VehicleElements[vehicleID], "vehicle.is_locked", false)
    end
    
    dbExec(db, "UPDATE owned_vehicles SET is_locked = 0 WHERE id = ?", vehicleID)
    return true
end

function setVehicleDescription(vehicleID, description)
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then return false end
    
    vehicle.description = description
    
    if VehicleElements[vehicleID] and isElement(VehicleElements[vehicleID]) then
        setElementData(VehicleElements[vehicleID], "vehicle.description", description)
    end
    
    dbExec(db, "UPDATE owned_vehicles SET description = ? WHERE id = ?", description, vehicleID)
    return true
end

function transferVehicle(vehicleID, newOwnerType, newOwnerID, newOwnerName)
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then return false, "Vehicle not found" end
    
    vehicle.ownerType = newOwnerType
    vehicle.ownerID = newOwnerID
    vehicle.ownerName = newOwnerName
    
    if VehicleElements[vehicleID] and isElement(VehicleElements[vehicleID]) then
        setElementData(VehicleElements[vehicleID], "vehicle.owner", newOwnerName)
        setElementData(VehicleElements[vehicleID], "vehicle.owner_type", newOwnerType)
    end
    
    dbExec(db, "UPDATE owned_vehicles SET owner_type = ?, owner_id = ?, owner_name = ? WHERE id = ?",
        newOwnerType, newOwnerID, newOwnerName, vehicleID)
    
    return true, "Vehicle transferred to " .. newOwnerName
end

function getCharacterVehicles(characterID)
    local owned = {}
    for vehID, vehicle in pairs(OwnedVehicles) do
        if vehicle.ownerType == VEHICLE_OWNER_TYPE.CHARACTER and 
           tostring(vehicle.ownerID) == tostring(characterID) then
            table.insert(owned, vehID)
        end
    end
    return owned
end

function getCompanyVehicles(companyID)
    local owned = {}
    for vehID, vehicle in pairs(OwnedVehicles) do
        if vehicle.ownerType == VEHICLE_OWNER_TYPE.COMPANY and vehicle.ownerID == companyID then
            table.insert(owned, vehID)
        end
    end
    return owned
end

function spawnVehicleFromItem(player, itemID, modelID)
    local char = AccountManager and AccountManager:getActiveCharacter(player)
    if not char then return nil, "No active character" end
    
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    
    -- Spawn in front of player (where they're facing), not behind
    local spawnX = x + math.cos(math.rad(rz)) * 5
    local spawnY = y + math.sin(math.rad(rz)) * 5
    
    local vehicleID = createOwnedVehicle(
        VEHICLE_OWNER_TYPE.CHARACTER, tostring(char.id), char.name, modelID,
        spawnX, spawnY, z + 0.5,
        rz + 90, -- Face perpendicular to player so they can easily enter
        getElementDimension(player), getElementInterior(player), 0, 0, char.name
    )
    
    if vehicleID then
        spawnVehicleElement(vehicleID)
        -- Unlock the vehicle so owner can get in immediately
        unlockVehicle(vehicleID)
        return vehicleID
    end
    
    return nil, "Failed to create vehicle"
end

--------------------------------------------------------------------------------
-- VEHICLE ENTRY HANDLING
--------------------------------------------------------------------------------

addEventHandler("onVehicleStartEnter", root, function(player, seat)
    local vehicleID = getElementData(source, "vehicle.id")
    if not vehicleID then return end
    
    if not canAccessVehicle(player, vehicleID) then
        cancelEvent()
        outputChatBox("This vehicle is locked", player, 255, 100, 100)
    end
end)

addEventHandler("onVehicleExit", root, function(player, seat)
    local vehicleID = getElementData(source, "vehicle.id")
    if not vehicleID then return end
    
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then return end
    
    local x, y, z = getElementPosition(source)
    local _, _, rz = getElementRotation(source)
    
    vehicle.spawnPos.x = x
    vehicle.spawnPos.y = y
    vehicle.spawnPos.z = z
    vehicle.spawnPos.rotation = rz
end)

--------------------------------------------------------------------------------
-- HELPER: Find nearest owned vehicle
--------------------------------------------------------------------------------

local VEHICLE_INTERACT_DISTANCE = 10.0

function findNearestOwnedVehicle(player)
    local px, py, pz = getElementPosition(player)
    local pDim = getElementDimension(player)
    local pInt = getElementInterior(player)
    
    local nearestVeh = nil
    local nearestDist = VEHICLE_INTERACT_DISTANCE
    local nearestID = nil
    
    for vehicleID, vehElement in pairs(VehicleElements) do
        if isElement(vehElement) then
            if getElementDimension(vehElement) == pDim and getElementInterior(vehElement) == pInt then
                local vx, vy, vz = getElementPosition(vehElement)
                local dist = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
                if dist < nearestDist then
                    nearestDist = dist
                    nearestVeh = vehElement
                    nearestID = vehicleID
                end
            end
        end
    end
    
    return nearestVeh, nearestID, nearestDist
end

--------------------------------------------------------------------------------
-- PLAYER COMMANDS
--------------------------------------------------------------------------------

addCommandHandler("lock", function(player)
    -- First check if in a vehicle
    local veh = getPedOccupiedVehicle(player)
    local vehicleID = nil
    
    if veh then
        vehicleID = getElementData(veh, "vehicle.id")
    else
        -- Check for nearby vehicle
        local nearVeh, nearID = findNearestOwnedVehicle(player)
        if nearVeh then
            veh = nearVeh
            vehicleID = nearID
        end
    end
    
    if not veh or not vehicleID then
        outputChatBox("No owned vehicle nearby", player, 255, 100, 100)
        return
    end
    
    if not isVehicleOwner(player, vehicleID) then
        outputChatBox("Not your vehicle", player, 255, 100, 100)
        return
    end
    
    lockVehicle(vehicleID)
    local vehicle = OwnedVehicles[vehicleID]
    local name = VEHICLE_NAMES[vehicle.modelID] or "Vehicle"
    outputChatBox(name .. " locked", player, 0, 255, 0)
end)

addCommandHandler("unlock", function(player)
    -- First check if in a vehicle
    local veh = getPedOccupiedVehicle(player)
    local vehicleID = nil
    
    if veh then
        vehicleID = getElementData(veh, "vehicle.id")
    else
        -- Check for nearby vehicle
        local nearVeh, nearID = findNearestOwnedVehicle(player)
        if nearVeh then
            veh = nearVeh
            vehicleID = nearID
        end
    end
    
    if not veh or not vehicleID then
        outputChatBox("No owned vehicle nearby", player, 255, 100, 100)
        return
    end
    
    if not isVehicleOwner(player, vehicleID) then
        outputChatBox("Not your vehicle", player, 255, 100, 100)
        return
    end
    
    unlockVehicle(vehicleID)
    local vehicle = OwnedVehicles[vehicleID]
    local name = VEHICLE_NAMES[vehicle.modelID] or "Vehicle"
    outputChatBox(name .. " unlocked", player, 0, 255, 0)
end)

addCommandHandler("vehicledesc", function(player, cmd, ...)
    -- First check if in a vehicle
    local veh = getPedOccupiedVehicle(player)
    local vehicleID = nil
    
    if veh then
        vehicleID = getElementData(veh, "vehicle.id")
    else
        -- Check for nearby vehicle
        local nearVeh, nearID = findNearestOwnedVehicle(player)
        if nearVeh then
            veh = nearVeh
            vehicleID = nearID
        end
    end
    
    if not veh or not vehicleID then
        outputChatBox("No owned vehicle nearby", player, 255, 100, 100)
        return
    end
    
    if not isVehicleOwner(player, vehicleID) then
        outputChatBox("Not your vehicle", player, 255, 100, 100)
        return
    end
    
    local description = table.concat({...}, " ")
    if description == "" then outputChatBox("Usage: /vehicledesc <description>", player, 255, 255, 0) return end
    
    setVehicleDescription(vehicleID, description)
    outputChatBox("Vehicle description updated", player, 0, 255, 0)
end)

addCommandHandler("myvehicles", function(player)
    local char = AccountManager and AccountManager:getActiveCharacter(player)
    if not char then outputChatBox("No active character", player, 255, 0, 0) return end
    
    local vehicles = getCharacterVehicles(char.id)
    outputChatBox("=== Your Vehicles (" .. #vehicles .. ") ===", player, 255, 255, 0)
    
    if #vehicles == 0 then
        outputChatBox("You don't own any vehicles", player, 200, 200, 200)
        return
    end
    
    for _, vehID in ipairs(vehicles) do
        local vehicle = OwnedVehicles[vehID]
        local name = VEHICLE_NAMES[vehicle.modelID] or "Unknown"
        local status = vehicle.isSpawned and "[Spawned]" or "[Stored]"
        outputChatBox(status .. " " .. name .. " (" .. vehID .. ")", player, 200, 200, 200)
    end
end)

addCommandHandler("transfervehicle", function(player, cmd, companyID)
    local veh = getPedOccupiedVehicle(player)
    if not veh then outputChatBox("You must be in a vehicle", player, 255, 100, 100) return end
    
    local vehicleID = getElementData(veh, "vehicle.id")
    if not vehicleID then outputChatBox("Not an owned vehicle", player, 255, 100, 100) return end
    if not isVehicleOwner(player, vehicleID) then outputChatBox("Not your vehicle", player, 255, 100, 100) return end
    
    if not companyID then outputChatBox("Usage: /transfervehicle <companyID or 'me'>", player, 255, 255, 0) return end
    
    if companyID == "me" then
        local char = AccountManager and AccountManager:getActiveCharacter(player)
        if not char then outputChatBox("No active character", player, 255, 0, 0) return end
        local success, msg = transferVehicle(vehicleID, VEHICLE_OWNER_TYPE.CHARACTER, tostring(char.id), char.name)
        outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
    else
        if not Companies or not Companies[companyID] then outputChatBox("Company not found", player, 255, 0, 0) return end
        local company = Companies[companyID]
        local char = AccountManager and AccountManager:getActiveCharacter(player)
        if not char or company.ownerType ~= "player" or tostring(company.ownerID) ~= tostring(char.id) then
            outputChatBox("You don't own that company", player, 255, 0, 0) return
        end
        local success, msg = transferVehicle(vehicleID, VEHICLE_OWNER_TYPE.COMPANY, companyID, company.name)
        outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
    end
end)

addCommandHandler("spawnmyvehicle", function(player, cmd, vehicleID)
    if not vehicleID then
        outputChatBox("Usage: /spawnmyvehicle vehicleID", player, 255, 255, 0)
        return
    end
    
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then outputChatBox("Vehicle not found", player, 255, 0, 0) return end
    if not isVehicleOwner(player, vehicleID) then outputChatBox("Not your vehicle", player, 255, 0, 0) return end
    if vehicle.isSpawned then outputChatBox("Already spawned", player, 255, 100, 100) return end
    
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    
    -- Spawn in front of player
    vehicle.spawnPos.x = x + math.cos(math.rad(rz)) * 5
    vehicle.spawnPos.y = y + math.sin(math.rad(rz)) * 5
    vehicle.spawnPos.z = z + 0.5
    vehicle.spawnPos.rotation = rz + 90
    vehicle.spawnPos.dimension = getElementDimension(player)
    vehicle.spawnPos.interior = getElementInterior(player)
    
    if spawnVehicleElement(vehicleID) then
        unlockVehicle(vehicleID)  -- Spawn unlocked for owner
        outputChatBox("Vehicle spawned", player, 0, 255, 0)
    else
        outputChatBox("Failed to spawn", player, 255, 0, 0)
    end
end)

addCommandHandler("storevehicle", function(player)
    local veh = getPedOccupiedVehicle(player)
    if not veh then outputChatBox("You must be in a vehicle", player, 255, 100, 100) return end
    
    local vehicleID = getElementData(veh, "vehicle.id")
    if not vehicleID then outputChatBox("Not an owned vehicle", player, 255, 100, 100) return end
    if not isVehicleOwner(player, vehicleID) then outputChatBox("Not your vehicle", player, 255, 100, 100) return end
    
    removePedFromVehicle(player)
    setTimer(function()
        despawnVehicleElement(vehicleID)
        outputChatBox("Vehicle stored. Use /spawnmyvehicle to retrieve it.", player, 0, 255, 0)
    end, 500, 1)
end)

--------------------------------------------------------------------------------
-- DM COMMANDS
--------------------------------------------------------------------------------

addCommandHandler("spawnvehicle", function(player, cmd, modelID, color1, color2)
    if isDungeonMaster and not isDungeonMaster(player) then outputChatBox("DM required", player, 255, 0, 0) return end
    
    modelID = tonumber(modelID)
    if not modelID or not VEHICLE_NAMES[modelID] then
        outputChatBox("Usage: /spawnvehicle modelID [color1] [color2]", player, 255, 255, 0)
        return
    end
    
    local char = AccountManager and AccountManager:getActiveCharacter(player)
    local ownerName = char and char.name or getPlayerName(player)
    local ownerID = char and tostring(char.id) or "0"
    
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    
    -- Spawn in front of player
    local spawnX = x + math.cos(math.rad(rz)) * 5
    local spawnY = y + math.sin(math.rad(rz)) * 5
    
    local vehicleID = createOwnedVehicle(
        VEHICLE_OWNER_TYPE.CHARACTER, ownerID, ownerName, modelID,
        spawnX, spawnY, z + 0.5,
        rz + 90, getElementDimension(player), getElementInterior(player),
        tonumber(color1) or 0, tonumber(color2) or 0, ownerName
    )
    
    if vehicleID then
        spawnVehicleElement(vehicleID)
        unlockVehicle(vehicleID)  -- Spawn unlocked
        outputChatBox("Spawned " .. VEHICLE_NAMES[modelID] .. " (" .. vehicleID .. ")", player, 0, 255, 0)
    else
        outputChatBox("Failed to spawn vehicle", player, 255, 0, 0)
    end
end)

addCommandHandler("setvehicleowner", function(player, cmd, vehicleID, ownerType, ownerID)
    if isDungeonMaster and not isDungeonMaster(player) then outputChatBox("DM required", player, 255, 0, 0) return end
    
    if not vehicleID or not ownerType then
        outputChatBox("Usage: /setvehicleowner vehicleID character/company ownerID", player, 255, 255, 0)
        return
    end
    
    local vehicle = OwnedVehicles[vehicleID]
    if not vehicle then outputChatBox("Vehicle not found", player, 255, 0, 0) return end
    
    local ownerName = "Unknown"
    if ownerType == "character" then
        local query = dbQuery(db, "SELECT name FROM characters WHERE id = ?", tonumber(ownerID))
        local result = dbPoll(query, -1)
        if result and result[1] then ownerName = result[1].name end
    elseif ownerType == "company" then
        if Companies and Companies[ownerID] then ownerName = Companies[ownerID].name end
    else
        outputChatBox("Type must be 'character' or 'company'", player, 255, 0, 0) return
    end
    
    local success, msg = transferVehicle(vehicleID, ownerType, ownerID, ownerName)
    outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
end)

addCommandHandler("deletevehicle", function(player)
    if isDungeonMaster and not isDungeonMaster(player) then outputChatBox("DM required", player, 255, 0, 0) return end
    
    local veh = getPedOccupiedVehicle(player)
    if not veh then outputChatBox("You must be in a vehicle", player, 255, 100, 100) return end
    
    local vehicleID = getElementData(veh, "vehicle.id")
    
    removePedFromVehicle(player)
    setTimer(function()
        if vehicleID then
            deleteOwnedVehicle(vehicleID)
            outputChatBox("Owned vehicle deleted", player, 0, 255, 0)
        else
            destroyElement(veh)
            outputChatBox("Vehicle destroyed", player, 255, 255, 0)
        end
    end, 500, 1)
end)

addCommandHandler("listvehicles", function(player, cmd, ownerSearch)
    if isDungeonMaster and not isDungeonMaster(player) then outputChatBox("DM required", player, 255, 0, 0) return end
    
    outputChatBox("=== Owned Vehicles ===", player, 255, 255, 0)
    
    local count = 0
    for vehID, vehicle in pairs(OwnedVehicles) do
        if not ownerSearch or (vehicle.ownerName and vehicle.ownerName:lower():find(ownerSearch:lower())) then
            local name = VEHICLE_NAMES[vehicle.modelID] or "Unknown"
            outputChatBox((vehicle.isSpawned and "[S]" or "[D]") .. " " .. name .. " - " .. vehicle.ownerName, player, 200, 200, 200)
            count = count + 1
            if count >= 20 then outputChatBox("...(max 20 shown)", player, 150, 150, 150) break end
        end
    end
    
    if count == 0 then outputChatBox("No vehicles found", player, 200, 200, 200) end
end)

addCommandHandler("givevehicle", function(player, cmd, modelID, targetName)
    if isDungeonMaster and not isDungeonMaster(player) then outputChatBox("DM required", player, 255, 0, 0) return end
    
    modelID = tonumber(modelID)
    if not modelID or not VEHICLE_NAMES[modelID] or not targetName then
        outputChatBox("Usage: /givevehicle modelID playerName", player, 255, 255, 0)
        return
    end
    
    local targetPlayer = nil
    for _, p in ipairs(getElementsByType("player")) do
        local name = getElementData(p, "character.name") or getPlayerName(p)
        if name:lower():find(targetName:lower()) then targetPlayer = p break end
    end
    
    if not targetPlayer then outputChatBox("Player not found", player, 255, 0, 0) return end
    
    local char = AccountManager and AccountManager:getActiveCharacter(targetPlayer)
    if not char then outputChatBox("Target has no character", player, 255, 0, 0) return end
    
    local x, y, z = getElementPosition(targetPlayer)
    local _, _, rz = getElementRotation(targetPlayer)
    
    -- Spawn in front of target player
    local spawnX = x + math.cos(math.rad(rz)) * 5
    local spawnY = y + math.sin(math.rad(rz)) * 5
    
    local vehicleID = createOwnedVehicle(
        VEHICLE_OWNER_TYPE.CHARACTER, tostring(char.id), char.name, modelID,
        spawnX, spawnY, z + 0.5,
        rz + 90, getElementDimension(targetPlayer), getElementInterior(targetPlayer), 0, 0, "DM"
    )
    
    if vehicleID then
        spawnVehicleElement(vehicleID)
        unlockVehicle(vehicleID)  -- Spawn unlocked
        outputChatBox("Gave " .. VEHICLE_NAMES[modelID] .. " to " .. char.name, player, 0, 255, 0)
        outputChatBox("You received a " .. VEHICLE_NAMES[modelID] .. "!", targetPlayer, 0, 255, 0)
    end
end)

-- Create vehicle item (for shops/economy)
addCommandHandler("createvehicleitem", function(player, cmd, itemID, modelID, price, ...)
    if isDungeonMaster and not isDungeonMaster(player) then outputChatBox("DM required", player, 255, 0, 0) return end
    
    modelID = tonumber(modelID)
    price = tonumber(price)
    
    if not itemID or not modelID or not VEHICLE_NAMES[modelID] then
        outputChatBox("Usage: /createvehicleitem itemID modelID price [name...]", player, 255, 255, 0)
        outputChatBox("Example: /createvehicleitem sultan_car 560 15000 Sultan Sports Car", player, 200, 200, 200)
        outputChatBox("Model IDs: 400-611 (use /listvehiclemodels to see options)", player, 200, 200, 200)
        return
    end
    
    local name = table.concat({...}, " ")
    if name == "" then name = VEHICLE_NAMES[modelID] end
    
    if not ItemRegistry then
        outputChatBox("Item registry not available", player, 255, 0, 0)
        return
    end
    
    local success, msg = ItemRegistry:register({
        id = itemID,
        name = name,
        description = "A " .. VEHICLE_NAMES[modelID] .. " vehicle. Cannot be stored in inventory.",
        category = "vehicle",
        quality = "uncommon",
        weight = 0,
        stackable = false,
        maxStack = 1,
        value = price or 10000,
        weaponID = modelID  -- Repurpose weaponID to store vehicle model
    }, getPlayerName(player))
    
    if success then
        outputChatBox("Vehicle item created: " .. name .. " (" .. itemID .. ")", player, 0, 255, 0)
        outputChatBox("Model: " .. VEHICLE_NAMES[modelID] .. " | Price: $" .. (price or 10000), player, 200, 200, 200)
        outputChatBox("Add to shops with: /addshopitem shopID " .. itemID .. " " .. (price or 10000), player, 255, 255, 0)
    else
        outputChatBox("Failed: " .. (msg or "Unknown error"), player, 255, 0, 0)
    end
end)

-- List vehicle models
addCommandHandler("listvehiclemodels", function(player, cmd, search)
    if isDungeonMaster and not isDungeonMaster(player) then outputChatBox("DM required", player, 255, 0, 0) return end
    
    outputChatBox("=== Vehicle Models ===", player, 255, 255, 0)
    
    local count = 0
    for modelID, name in pairs(VEHICLE_NAMES) do
        if not search or name:lower():find(search:lower()) then
            outputChatBox(modelID .. ": " .. name, player, 200, 200, 200)
            count = count + 1
            if count >= 25 then
                outputChatBox("...(max 25 shown, use /listvehiclemodels search)", player, 150, 150, 150)
                break
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onResourceStop", resourceRoot, function()
    for vehicleID, veh in pairs(VehicleElements) do
        if isElement(veh) then
            local vehicle = OwnedVehicles[vehicleID]
            if vehicle then
                local x, y, z = getElementPosition(veh)
                local _, _, rz = getElementRotation(veh)
                dbExec(db, "UPDATE owned_vehicles SET spawn_x=?, spawn_y=?, spawn_z=?, spawn_rotation=? WHERE id=?",
                    x, y, z, rz, vehicleID)
            end
            destroyElement(veh)
        end
    end
end)

outputServerLog("===== VEHICLE_SYSTEM.LUA LOADED =====")
