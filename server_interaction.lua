-- server_interaction.lua (SERVER)
-- Handles interaction events, POI management, descriptions
-- Works with client_interaction.lua

outputServerLog("===== SERVER_INTERACTION.LUA LOADING =====")

local db = nil

-- Points of Interest storage
PointsOfInterest = PointsOfInterest or {}

-- Pending property entrance position (per DM)
PendingPropertyEntrance = PendingPropertyEntrance or {}

--------------------------------------------------------------------------------
-- DATABASE INITIALIZATION
--------------------------------------------------------------------------------

local function initializePOITables()
    if not db then return end
    
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS points_of_interest (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT DEFAULT '',
            pos_x REAL,
            pos_y REAL,
            pos_z REAL,
            model_id INTEGER DEFAULT NULL,
            highlighted INTEGER DEFAULT 0,
            dimension INTEGER DEFAULT 0,
            interior INTEGER DEFAULT 0,
            created_by TEXT,
            created_date INTEGER
        )
    ]])
    
    -- Add description column to characters table if it doesn't exist
    local checkQuery = dbQuery(db, "PRAGMA table_info(characters)")
    local columns = dbPoll(checkQuery, -1)
    
    local hasDescription = false
    if columns then
        for _, col in ipairs(columns) do
            if col.name == "description" then
                hasDescription = true
                break
            end
        end
    end
    
    if not hasDescription then
        dbExec(db, "ALTER TABLE characters ADD COLUMN description TEXT DEFAULT ''")
        outputServerLog("Added description column to characters")
    end
    
    outputServerLog("POI database tables initialized")
end

addEventHandler("onResourceStart", resourceRoot, function()
    db = database
    if not db then
        outputServerLog("ERROR: Could not access database for interaction system")
        return
    end
    
    initializePOITables()
    loadAllPOIs()
end)

--------------------------------------------------------------------------------
-- POI MANAGEMENT
--------------------------------------------------------------------------------

function loadAllPOIs()
    if not db then return end
    
    local query = dbQuery(db, "SELECT * FROM points_of_interest")
    local result = dbPoll(query, -1)
    
    if not result then return end
    
    for _, row in ipairs(result) do
        local poi = {
            id = row.id,
            name = row.name,
            description = row.description,
            position = {x = row.pos_x, y = row.pos_y, z = row.pos_z},
            modelID = row.model_id,
            highlighted = row.highlighted == 1,
            dimension = row.dimension or 0,
            interior = row.interior or 0,
            createdBy = row.created_by,
            createdDate = row.created_date
        }
        
        PointsOfInterest[poi.id] = poi
        
        -- Create marker or attach to existing object
        spawnPOIMarker(poi)
    end
    
    outputServerLog("Loaded " .. #result .. " Points of Interest")
end

function spawnPOIMarker(poi)
    -- Create an invisible marker for POI detection
    -- Alpha = 0 (invisible) - we detect these manually in client click handler
    -- since processLineOfSight doesn't see markers
    
    local marker = createMarker(poi.position.x, poi.position.y, poi.position.z - 1, "cylinder", 1.5, 255, 200, 0, 0)
    
    if marker then
        setElementDimension(marker, poi.dimension)
        setElementInterior(marker, poi.interior)
        setElementData(marker, "isPOI", "true")  -- Use string for consistency
        setElementData(marker, "poi.id", poi.id)
        setElementData(marker, "poi.name", poi.name)
        setElementData(marker, "description", poi.description)
        
        poi.marker = marker
        
        -- Create visible highlight marker if highlighted
        if poi.highlighted then
            local corona = createMarker(poi.position.x, poi.position.y, poi.position.z, "corona", 1.0, 255, 200, 0, 100)
            if corona then
                setElementDimension(corona, poi.dimension)
                setElementInterior(corona, poi.interior)
                -- Corona also gets POI data so it can be clicked
                setElementData(corona, "isPOI", "true")
                setElementData(corona, "poi.id", poi.id)
                setElementData(corona, "poi.name", poi.name)
                setElementData(corona, "description", poi.description)
                poi.corona = corona
            end
        end
    end
end

function createPOI(name, description, x, y, z, modelID, highlighted, createdBy)
    if not db then return nil, "Database not available" end
    
    local poiID = "poi_" .. getRealTime().timestamp .. "_" .. math.random(1000, 9999)
    
    local dimension = 0
    local interior = 0
    
    -- If created near a player, use their dimension/interior
    for _, player in ipairs(getElementsByType("player")) do
        local px, py, pz = getElementPosition(player)
        if getDistanceBetweenPoints3D(x, y, z, px, py, pz) < 50 then
            dimension = getElementDimension(player)
            interior = getElementInterior(player)
            break
        end
    end
    
    local success = dbExec(db, [[
        INSERT INTO points_of_interest (id, name, description, pos_x, pos_y, pos_z, model_id, highlighted, dimension, interior, created_by, created_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], poiID, name, description, x, y, z, modelID, highlighted and 1 or 0, dimension, interior, createdBy, getRealTime().timestamp)
    
    if not success then return nil, "Database error" end
    
    local poi = {
        id = poiID,
        name = name,
        description = description,
        position = {x = x, y = y, z = z},
        modelID = modelID,
        highlighted = highlighted,
        dimension = dimension,
        interior = interior,
        createdBy = createdBy,
        createdDate = getRealTime().timestamp
    }
    
    PointsOfInterest[poiID] = poi
    spawnPOIMarker(poi)
    
    outputServerLog("POI created: " .. name .. " (" .. poiID .. ")")
    return poiID, "POI created: " .. name
end

function updatePOI(poiID, name, description, highlighted)
    if not db then return false, "Database not available" end
    
    local poi = PointsOfInterest[poiID]
    if not poi then return false, "POI not found" end
    
    poi.name = name or poi.name
    poi.description = description or poi.description
    poi.highlighted = highlighted
    
    dbExec(db, [[
        UPDATE points_of_interest SET name = ?, description = ?, highlighted = ? WHERE id = ?
    ]], poi.name, poi.description, highlighted and 1 or 0, poiID)
    
    -- Update marker data (with sync enabled)
    if poi.marker and isElement(poi.marker) then
        setElementData(poi.marker, "poi.name", poi.name)
        setElementData(poi.marker, "description", poi.description)
    end
    
    -- Handle highlight corona
    if highlighted and not poi.corona then
        local corona = createMarker(poi.position.x, poi.position.y, poi.position.z, "corona", 1.0, 255, 200, 0, 100)
        if corona then
            setElementDimension(corona, poi.dimension)
            setElementInterior(corona, poi.interior)
            -- Corona also gets POI data so it can be clicked
            setElementData(corona, "isPOI", "true")
            setElementData(corona, "poi.id", poi.id)
            setElementData(corona, "poi.name", poi.name)
            setElementData(corona, "description", poi.description)
            poi.corona = corona
        end
    elseif not highlighted and poi.corona then
        if isElement(poi.corona) then
            destroyElement(poi.corona)
        end
        poi.corona = nil
    elseif highlighted and poi.corona and isElement(poi.corona) then
        -- Update existing corona data
        setElementData(poi.corona, "poi.name", poi.name, true)
        setElementData(poi.corona, "description", poi.description, true)
    end
    
    return true, "POI updated"
end

function deletePOI(poiID)
    if not db then return false, "Database not available" end
    
    local poi = PointsOfInterest[poiID]
    if not poi then return false, "POI not found" end
    
    -- Remove markers
    if poi.marker and isElement(poi.marker) then
        destroyElement(poi.marker)
    end
    if poi.corona and isElement(poi.corona) then
        destroyElement(poi.corona)
    end
    
    dbExec(db, "DELETE FROM points_of_interest WHERE id = ?", poiID)
    PointsOfInterest[poiID] = nil
    
    outputServerLog("POI deleted: " .. poiID)
    return true, "POI deleted"
end

--------------------------------------------------------------------------------
-- EXAMINATION SYSTEM
--------------------------------------------------------------------------------

function examineTarget(player, target, targetType)
    local name = "Unknown"
    local description = ""
    
    if targetType == "player" then
        name = getPlayerName(target)
        local char = AccountManager and AccountManager:getActiveCharacter(target)
        if char then
            name = char.name or name
            description = getElementData(target, "description") or ""
        end
        
        if description == "" then
            description = "A person going about their business."
        end
        
    elseif targetType == "npc" or targetType == "shopkeeper" then
        name = getElementData(target, "npc.name") or "NPC"
        description = getElementData(target, "description") or ""
        
        if description == "" then
            if targetType == "shopkeeper" then
                description = "A merchant ready to do business."
            else
                description = "A local resident."
            end
        end
        
    elseif targetType == "poi" then
        local poiID = getElementData(target, "poi.id")
        if poiID and PointsOfInterest[poiID] then
            name = PointsOfInterest[poiID].name
            description = PointsOfInterest[poiID].description
        else
            name = getElementData(target, "poi.name") or "Point of Interest"
            description = getElementData(target, "description") or ""
        end
        
    elseif targetType == "property_entrance" then
        local propID = getElementData(target, "property.id")
        name = getElementData(target, "property.name") or "Property"
        description = getElementData(target, "description") or "An entrance to a building."
        
    elseif targetType == "object" then
        name = "Object"
        description = getElementData(target, "description") or "Nothing particularly interesting about this."
        
    elseif targetType == "vehicle" then
        name = getVehicleName(target) or "Vehicle"
        description = getElementData(target, "description") or "A vehicle."
        
    else
        name = "Something"
        description = getElementData(target, "description") or ""
    end
    
    triggerClientEvent(player, "interaction:examineResult", player, name, description, targetType)
end

--------------------------------------------------------------------------------
-- CLIENT EVENTS
--------------------------------------------------------------------------------

-- Player examines something
addEvent("interaction:examine", true)
addEventHandler("interaction:examine", root, function(target, targetType)
    examineTarget(client, target, targetType)
end)

-- Player waves at another player
addEvent("interaction:wave", true)
addEventHandler("interaction:wave", root, function(targetPlayer)
    local sourceName = getElementData(client, "character.name") or getPlayerName(client)
    local targetName = getElementData(targetPlayer, "character.name") or getPlayerName(targetPlayer)
    
    -- Notify both players
    outputChatBox(sourceName .. " waves at " .. targetName .. ".", client, 200, 200, 100)
    outputChatBox(sourceName .. " waves at you.", targetPlayer, 200, 200, 100)
end)

-- DM sets description on something
addEvent("interaction:setDescription", true)
addEventHandler("interaction:setDescription", root, function(target, targetType, description)
    if not isDungeonMaster or not isDungeonMaster(client) then
        triggerClientEvent(client, "interaction:descriptionSet", client, false, "DM required")
        return
    end
    
    if not target or not isElement(target) then
        triggerClientEvent(client, "interaction:descriptionSet", client, false, "Invalid target")
        return
    end
    
    setElementData(target, "description", description)
    
    -- If it's an NPC, also store in NPC system if available
    if targetType == "npc" or targetType == "shopkeeper" then
        local npcID = getElementData(target, "npc.id")
        if npcID and NPCs and NPCs[npcID] then
            NPCs[npcID].description = description
        end
    end
    
    triggerClientEvent(client, "interaction:descriptionSet", client, true, "Description set")
    outputServerLog("Description set by " .. getPlayerName(client) .. " on " .. targetType)
end)

-- DM sets property entrance position
addEvent("dm:setPropertyEntrance", true)
addEventHandler("dm:setPropertyEntrance", root, function(x, y, z)
    if not isDungeonMaster or not isDungeonMaster(client) then
        outputChatBox("DM required", client, 255, 0, 0)
        return
    end
    
    PendingPropertyEntrance[client] = {x = x, y = y, z = z, dimension = getElementDimension(client), interior = getElementInterior(client)}
    outputChatBox("Property entrance position set. Use /setpropertyentrance [propertyID] to apply.", client, 100, 255, 100)
    outputChatBox(string.format("Position: %.2f, %.2f, %.2f", x, y, z), client, 200, 200, 200)
end)

-- DM creates POI
addEvent("poi:create", true)
addEventHandler("poi:create", root, function(name, description, x, y, z, modelID, highlighted)
    if not isDungeonMaster or not isDungeonMaster(client) then
        triggerClientEvent(client, "poi:message", client, "DM required", true)
        return
    end
    
    local createdBy = getElementData(client, "character.name") or getPlayerName(client)
    local poiID, msg = createPOI(name, description, x, y, z, modelID, highlighted, createdBy)
    
    triggerClientEvent(client, "poi:message", client, msg, poiID == nil)
end)

-- DM requests POI edit data
addEvent("poi:requestEdit", true)
addEventHandler("poi:requestEdit", root, function(poiID)
    if not isDungeonMaster or not isDungeonMaster(client) then
        return
    end
    
    local poi = PointsOfInterest[poiID]
    if not poi then
        triggerClientEvent(client, "poi:message", client, "POI not found", true)
        return
    end
    
    triggerClientEvent(client, "poi:editData", client, {
        id = poi.id,
        name = poi.name,
        description = poi.description,
        highlighted = poi.highlighted
    })
end)

-- DM updates POI
addEvent("poi:update", true)
addEventHandler("poi:update", root, function(poiID, name, description, highlighted)
    if not isDungeonMaster or not isDungeonMaster(client) then
        triggerClientEvent(client, "poi:message", client, "DM required", true)
        return
    end
    
    local success, msg = updatePOI(poiID, name, description, highlighted)
    triggerClientEvent(client, "poi:message", client, msg, not success)
end)

-- DM deletes POI
addEvent("poi:delete", true)
addEventHandler("poi:delete", root, function(poiID)
    if not isDungeonMaster or not isDungeonMaster(client) then
        triggerClientEvent(client, "poi:message", client, "DM required", true)
        return
    end
    
    local success, msg = deletePOI(poiID)
    triggerClientEvent(client, "poi:message", client, msg, not success)
end)

-- DM creates property via GUI
addEvent("property:createFromGUI", true)
addEventHandler("property:createFromGUI", root, function(name, interiorID, price, forSale, description, posX, posY, posZ)
    if not isDungeonMaster or not isDungeonMaster(client) then
        triggerClientEvent(client, "property:created", client, false, "DM required")
        return
    end
    
    -- interiorID is now a string like "1", "2", etc. that matches INTERIOR_PRESETS keys
    local createdBy = getElementData(client, "character.name") or getPlayerName(client)
    local dimension = getElementDimension(client)
    local interior = getElementInterior(client)
    
    -- Use property system's createProperty function if available
    -- Signature: createProperty(name, description, price, interiorID, entranceX, entranceY, entranceZ, entranceDim, entranceInt, createdBy)
    if createProperty then
        local propID, err = createProperty(name, description, price, interiorID, posX, posY, posZ, dimension, interior, createdBy)
        
        if propID then
            -- Update for sale status if needed
            if Properties and Properties[propID] and not forSale then
                Properties[propID].forSale = false
                if database then
                    dbExec(database, "UPDATE properties SET for_sale = 0 WHERE id = ?", propID)
                end
                -- Refresh marker
                if spawnPropertyMarker then
                    spawnPropertyMarker(propID)
                end
                if spawnPropertyBlip then
                    spawnPropertyBlip(propID)
                end
            end
            
            triggerClientEvent(client, "property:created", client, true, "Property created: " .. name .. " (ID: " .. propID .. ")")
            outputServerLog("Property created via GUI: " .. name .. " by " .. createdBy)
        else
            triggerClientEvent(client, "property:created", client, false, err or "Failed to create property")
        end
    else
        triggerClientEvent(client, "property:created", client, false, "Property system not available")
    end
end)

--------------------------------------------------------------------------------
-- DM COMMANDS
--------------------------------------------------------------------------------

-- Apply pending property entrance to a property
addCommandHandler("setpropertyentrance", function(player, cmd, propertyID)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    if not propertyID then
        outputChatBox("Usage: /setpropertyentrance propertyID", player, 255, 255, 0)
        return
    end
    
    local pending = PendingPropertyEntrance[player]
    if not pending then
        outputChatBox("No entrance position set. Right-click a location first.", player, 255, 0, 0)
        return
    end
    
    -- Update property entrance
    if Properties and Properties[propertyID] then
        Properties[propertyID].entrance = pending
        
        -- Update marker position
        if PropertyMarkers and PropertyMarkers[propertyID] and isElement(PropertyMarkers[propertyID]) then
            setElementPosition(PropertyMarkers[propertyID], pending.x, pending.y, pending.z)
            setElementDimension(PropertyMarkers[propertyID], pending.dimension)
            setElementInterior(PropertyMarkers[propertyID], pending.interior)
        end
        
        -- Save to database
        if database then
            dbExec(database, "UPDATE properties SET entrance_x = ?, entrance_y = ?, entrance_z = ?, entrance_dim = ?, entrance_int = ? WHERE id = ?",
                pending.x, pending.y, pending.z, pending.dimension, pending.interior, propertyID)
        end
        
        PendingPropertyEntrance[player] = nil
        outputChatBox("Property entrance updated for: " .. propertyID, player, 0, 255, 0)
    else
        outputChatBox("Property not found: " .. propertyID, player, 255, 0, 0)
    end
end)

-- List POIs
addCommandHandler("listpois", function(player, cmd, search)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    outputChatBox("=== Points of Interest ===", player, 255, 255, 0)
    
    local count = 0
    for id, poi in pairs(PointsOfInterest) do
        if not search or poi.name:lower():find(search:lower(), 1, true) then
            local highlight = poi.highlighted and " [H]" or ""
            outputChatBox(string.format("%s - %s%s", id, poi.name, highlight), player, 200, 200, 200)
            count = count + 1
        end
    end
    
    if count == 0 then
        outputChatBox("No POIs found", player, 200, 200, 200)
    else
        outputChatBox("Total: " .. count, player, 255, 255, 0)
    end
end)

-- Teleport to POI
addCommandHandler("gotopoi", function(player, cmd, poiID)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    if not poiID then
        outputChatBox("Usage: /gotopoi poiID", player, 255, 255, 0)
        return
    end
    
    local poi = PointsOfInterest[poiID]
    if not poi then
        outputChatBox("POI not found", player, 255, 0, 0)
        return
    end
    
    setElementPosition(player, poi.position.x, poi.position.y, poi.position.z + 1)
    setElementDimension(player, poi.dimension)
    setElementInterior(player, poi.interior)
    outputChatBox("Teleported to: " .. poi.name, player, 0, 255, 0)
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onPlayerQuit", root, function()
    PendingPropertyEntrance[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    -- Destroy POI markers
    for id, poi in pairs(PointsOfInterest) do
        if poi.marker and isElement(poi.marker) then
            destroyElement(poi.marker)
        end
        if poi.corona and isElement(poi.corona) then
            destroyElement(poi.corona)
        end
    end
end)

outputServerLog("===== SERVER_INTERACTION.LUA LOADED =====")
