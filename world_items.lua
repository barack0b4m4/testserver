-- world_items.lua (SERVER)
-- Handles items dropped in the world as physical pickups

outputServerLog("===== WORLD_ITEMS.LUA LOADING =====")

local db = nil

-- World items storage: [worldItemID] = {element, itemID, quantity, instanceID, etc}
WorldItems = WorldItems or {}

-- Model IDs for different item categories (can customize these)
local ITEM_MODELS = {
    weapon = 1240,      -- Ammo/weapon pickup
    armor = 1242,       -- Armor pickup
    consumable = 1241,  -- Health pickup
    material = 1265,    -- Box/crate
    tool = 1279,        -- Briefcase
    quest = 1210,       -- Suitcase
    misc = 1254         -- Generic item
}

--------------------------------------------------------------------------------
-- DATABASE
--------------------------------------------------------------------------------

local function initializeWorldItemTables()
    if not db then return end
    
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS world_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id TEXT NOT NULL,
            quantity INTEGER DEFAULT 1,
            instance_id TEXT UNIQUE,
            pos_x REAL,
            pos_y REAL,
            pos_z REAL,
            dimension INTEGER DEFAULT 0,
            interior INTEGER DEFAULT 0,
            dropped_by TEXT,
            dropped_time INTEGER
        )
    ]])
    
    outputServerLog("World items database table initialized")
end

addEventHandler("onResourceStart", resourceRoot, function()
    db = database
    if not db then
        outputServerLog("ERROR: Could not access database for world items")
        return
    end
    
    initializeWorldItemTables()
    loadWorldItems()
end)

--------------------------------------------------------------------------------
-- WORLD ITEM MANAGEMENT
--------------------------------------------------------------------------------

function loadWorldItems()
    if not db then return end
    
    local query = dbQuery(db, "SELECT * FROM world_items")
    local result = dbPoll(query, -1)
    
    if not result then return end
    
    for _, row in ipairs(result) do
        spawnWorldItem(row.item_id, row.quantity, row.pos_x, row.pos_y, row.pos_z, 
                      row.dimension, row.interior, row.instance_id, row.id)
    end
    
    outputServerLog("Loaded " .. #result .. " world items")
end

function spawnWorldItem(itemID, quantity, x, y, z, dimension, interior, instanceID, dbID)
    if not ItemRegistry or not ItemRegistry:exists(itemID) then
        outputServerLog("ERROR: Cannot spawn unknown item: " .. itemID)
        return nil
    end
    
    local itemDef = ItemRegistry:get(itemID)
    local model = ITEM_MODELS[itemDef.category] or ITEM_MODELS.misc
    
    -- Create the pickup object
    local pickup = createObject(model, x, y, z)
    if not pickup then
        outputServerLog("ERROR: Failed to create pickup object")
        return nil
    end
    
    setElementDimension(pickup, dimension or 0)
    setElementInterior(pickup, interior or 0)
    
    -- Generate unique ID if not provided
    local worldItemID = dbID or (#WorldItems + 1)
    instanceID = instanceID or "world_" .. getRealTime().timestamp .. "_" .. math.random(1000, 9999)
    
    -- Set element data for client detection
    setElementData(pickup, "worldItem", true, true)
    setElementData(pickup, "worldItem.id", worldItemID, true)
    setElementData(pickup, "worldItem.itemID", itemID, true)
    setElementData(pickup, "worldItem.itemName", itemDef.name, true)
    setElementData(pickup, "worldItem.quantity", quantity, true)
    setElementData(pickup, "worldItem.quality", itemDef.quality.name, true)
    
    -- Store in memory
    WorldItems[worldItemID] = {
        element = pickup,
        itemID = itemID,
        quantity = quantity,
        instanceID = instanceID,
        position = {x = x, y = y, z = z},
        dimension = dimension or 0,
        interior = interior or 0,
        dbID = dbID
    }
    
    outputServerLog("[WORLD ITEM] Spawned: " .. itemDef.name .. " x" .. quantity .. " at " .. 
                    string.format("%.1f, %.1f, %.1f", x, y, z))
    
    return worldItemID
end

function dropItem(player, itemID, quantity, instanceID)
    if not player or not isElement(player) then return false end
    if not ItemRegistry:exists(itemID) then return false end
    
    -- Get player position (slightly in front)
    local x, y, z = getElementPosition(player)
    local rx, ry, rz = getElementRotation(player)
    local radRot = math.rad(rz)
    x = x + math.sin(radRot) * 1.5
    y = y + math.cos(radRot) * 1.5
    z = z - 0.5  -- Ground level
    
    local dimension = getElementDimension(player)
    local interior = getElementInterior(player)
    
    -- Spawn the world item
    local worldItemID = spawnWorldItem(itemID, quantity, x, y, z, dimension, interior, instanceID)
    
    if not worldItemID then return false end
    
    -- Save to database
    if db then
        local droppedBy = getElementData(player, "character.name") or getPlayerName(player)
        
        dbExec(db, [[
            INSERT INTO world_items (item_id, quantity, instance_id, pos_x, pos_y, pos_z, 
                                     dimension, interior, dropped_by, dropped_time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], itemID, quantity, WorldItems[worldItemID].instanceID, x, y, z, 
           dimension, interior, droppedBy, getRealTime().timestamp)
        
        -- Get the database ID
        local query = dbQuery(db, "SELECT last_insert_rowid() as id")
        local result = dbPoll(query, -1)
        if result and result[1] then
            WorldItems[worldItemID].dbID = result[1].id
        end
    end
    
    return true
end

function pickupWorldItem(player, worldItemID)
    if not player or not isElement(player) then return false end
    
    local worldItem = WorldItems[worldItemID]
    if not worldItem then return false end
    
    -- Get player inventory
    local inv = getPlayerInventory(player)
    if not inv then
        outputChatBox("No active character", player, 255, 0, 0)
        return false
    end
    
    -- Try to add to inventory
    local success, msg = inv:addItem(worldItem.itemID, worldItem.quantity)
    
    if success then
        -- Remove from world
        if isElement(worldItem.element) then
            destroyElement(worldItem.element)
        end
        
        -- Remove from database
        if db and worldItem.dbID then
            dbExec(db, "DELETE FROM world_items WHERE id = ?", worldItem.dbID)
        end
        
        -- Remove from memory
        WorldItems[worldItemID] = nil
        
        local itemDef = ItemRegistry:get(worldItem.itemID)
        outputChatBox("Picked up: " .. itemDef.name .. " x" .. worldItem.quantity, player, 100, 255, 100)
        return true
    else
        outputChatBox(msg, player, 255, 100, 100)
        return false
    end
end

--------------------------------------------------------------------------------
-- COMMANDS
--------------------------------------------------------------------------------

-- Override the existing /drop command
addCommandHandler("drop", function(player, cmd, slot, qty)
    local inv = getPlayerInventory(player)
    if not inv then
        outputChatBox("No active character", player, 255, 0, 0)
        return
    end
    
    if not slot then
        outputChatBox("Usage: /drop [slot] [quantity]", player, 255, 255, 0)
        return
    end
    
    local slotNum = tonumber(slot)
    if not slotNum or slotNum < 1 or slotNum > #inv.items then
        outputChatBox("Invalid slot number", player, 255, 0, 0)
        return
    end
    
    local item = inv.items[slotNum]
    if not item then
        outputChatBox("No item in that slot", player, 255, 0, 0)
        return
    end
    
    local dropQty = tonumber(qty) or item.quantity
    
    -- Can't drop more than you have
    if dropQty > item.quantity then
        dropQty = item.quantity
    end
    
    -- Check if item is equipped
    for equipSlot, equipped in pairs(inv.equipped) do
        if equipped and equipped.instanceID == item.instanceID then
            outputChatBox("Unequip the item first", player, 255, 100, 0)
            return
        end
    end
    
    -- Remove from inventory first
    if inv:removeItem(item.instanceID, dropQty) then
        -- Drop in world
        if dropItem(player, item.id, dropQty, item.instanceID) then
            outputChatBox("Dropped: " .. item.name .. " x" .. dropQty, player, 255, 255, 0)
        else
            -- If drop failed, give back to inventory
            inv:addItem(item.id, dropQty)
            outputChatBox("Failed to drop item", player, 255, 0, 0)
        end
    else
        outputChatBox("Failed to remove item from inventory", player, 255, 0, 0)
    end
end, false, false)

-- Pickup command (manual pickup)
addCommandHandler("pickup", function(player)
    local x, y, z = getElementPosition(player)
    local dimension = getElementDimension(player)
    local interior = getElementInterior(player)
    
    -- Find closest world item
    local closest = nil
    local closestDist = 3.0  -- 3 meter pickup range
    
    for worldItemID, worldItem in pairs(WorldItems) do
        if worldItem.element and isElement(worldItem.element) then
            local ix, iy, iz = getElementPosition(worldItem.element)
            local itemDim = getElementDimension(worldItem.element)
            local itemInt = getElementInterior(worldItem.element)
            
            if itemDim == dimension and itemInt == interior then
                local dist = getDistanceBetweenPoints3D(x, y, z, ix, iy, iz)
                if dist < closestDist then
                    closest = worldItemID
                    closestDist = dist
                end
            end
        end
    end
    
    if closest then
        pickupWorldItem(player, closest)
    else
        outputChatBox("No items nearby", player, 200, 200, 200)
    end
end)

-- List nearby items
addCommandHandler("nearby", function(player)
    local x, y, z = getElementPosition(player)
    local dimension = getElementDimension(player)
    local interior = getElementInterior(player)
    
    outputChatBox("=== Nearby Items ===", player, 255, 255, 0)
    
    local found = 0
    for worldItemID, worldItem in pairs(WorldItems) do
        if worldItem.element and isElement(worldItem.element) then
            local ix, iy, iz = getElementPosition(worldItem.element)
            local itemDim = getElementDimension(worldItem.element)
            local itemInt = getElementInterior(worldItem.element)
            
            if itemDim == dimension and itemInt == interior then
                local dist = getDistanceBetweenPoints3D(x, y, z, ix, iy, iz)
                if dist < 10 then
                    local itemDef = ItemRegistry:get(worldItem.itemID)
                    outputChatBox(string.format("%.1fm - %s x%d", dist, itemDef.name, worldItem.quantity), 
                                  player, unpack(itemDef.quality.color))
                    found = found + 1
                end
            end
        end
    end
    
    if found == 0 then
        outputChatBox("None", player, 200, 200, 200)
    end
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onResourceStop", resourceRoot, function()
    -- Destroy all world item objects
    for worldItemID, worldItem in pairs(WorldItems) do
        if worldItem.element and isElement(worldItem.element) then
            destroyElement(worldItem.element)
        end
    end
end)

outputServerLog("===== WORLD_ITEMS.LUA LOADED =====")
