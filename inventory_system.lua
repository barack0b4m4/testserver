--[[
================================================================================
    INVENTORY_SYSTEM.LUA - Dynamic Item & Inventory Management
================================================================================
    Provides a complete item definition system and player inventory management.
    Items are defined via DM commands and stored in the database.
    
    FEATURES:
    - Database-driven item definitions (no hardcoded items)
    - Item categories: weapon, armor, consumable, quest, material, resource, tool, misc
    - Item qualities: Common, Uncommon, Rare, Epic, Legendary
    - Stackable items with configurable stack sizes
    - Usable items with effects (heal, armor, stat buffs)
    - Equippable items (weapons, armor, accessories)
    - Weight-based inventory with STR modifier integration
    - Durability system for equipment
    
    RESOURCE CATEGORY:
    The "resource" category is specifically for raw materials used in the
    economic system (ore, crops, lumber, etc.). Resource companies can
    produce these items using employee labor.
    
    INTEGRATION POINTS:
    ┌─────────────────────────────────────────────────────────────────────────┐
    │ DEPENDS ON:                                                             │
    │   - server.lua: database connection, AccountManager                     │
    │                                                                         │
    │ PROVIDES TO:                                                            │
    │   - crafting_system.lua: ItemRegistry for recipe validation             │
    │   - shopkeeper_system.lua: Item data for shop displays                  │
    │   - economic_system.lua: Resource items for company production          │
    │   - server.lua: initializePlayerInventory() called on spawn             │
    │   - dice_system.lua: Equipment bonuses for stat rolls                   │
    │                                                                         │
    │ GLOBAL EXPORTS:                                                         │
    │   - ItemRegistry: Item definition management singleton                  │
    │   - PlayerInventories: Per-player inventory data                        │
    │   - ITEM_CATEGORY: Category constants                                   │
    │   - ITEM_QUALITY: Quality tier definitions                              │
    │   - initializePlayerInventory(player, charID, maxWeight)                │
    │   - savePlayerInventory(player)                                         │
    │   - getPlayerInventory(player)                                          │
    │   - addItemToInventory(player, itemID, qty)                             │
    │   - removeItemFromInventory(player, itemID, qty)                        │
    │   - getInventoryForClient(player)                                       │
    └─────────────────────────────────────────────────────────────────────────┘
    
    DM COMMANDS:
    - /createitem "Name" category [options]
    - /edititem itemID [options]
    - /deleteitem itemID
    - /listitems [category] [search]
    - /iteminfo itemID
    - /giveitem itemID [qty] [player]
    
    PLAYER COMMANDS:
    - /inv - View inventory
    - /use [slot] - Use consumable
    - /equip [slot] - Equip item
    - /unequip [slot] - Unequip item
    - /drop [slot] [qty] - Drop item
    - /equipped - Show equipped items
================================================================================
]]

-- inventory_system.lua (SERVER)
-- Dynamic D&D-style inventory system with database-driven item definitions
-- Items are created via commands and stored in the database

outputServerLog("===== INVENTORY_SYSTEM.LUA LOADING =====")

local db = nil

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

ITEM_CATEGORY = {
    WEAPON = "weapon",
    ARMOR = "armor",
    CONSUMABLE = "consumable",
    QUEST = "quest",
    MATERIAL = "material",
    RESOURCE = "resource",  -- Raw materials for economy system (ore, crops, lumber, etc.)
    VEHICLE = "vehicle",    -- Vehicle items - cannot be stored in inventory, spawn as owned vehicle on purchase
    TOOL = "tool",
    MISC = "misc"
}

ITEM_QUALITY = {
    COMMON = {name = "Common", color = {200, 200, 200}, tier = 1},
    UNCOMMON = {name = "Uncommon", color = {100, 255, 100}, tier = 2},
    RARE = {name = "Rare", color = {100, 100, 255}, tier = 3},
    EPIC = {name = "Epic", color = {200, 100, 255}, tier = 4},
    LEGENDARY = {name = "Legendary", color = {255, 165, 0}, tier = 5}
}

local QUALITY_LOOKUP = {}
for k, v in pairs(ITEM_QUALITY) do
    QUALITY_LOOKUP[k:lower()] = v
    QUALITY_LOOKUP[v.name:lower()] = v
end

local CATEGORY_LOOKUP = {}
for k, v in pairs(ITEM_CATEGORY) do
    CATEGORY_LOOKUP[k:lower()] = v
    CATEGORY_LOOKUP[v:lower()] = v
end

--------------------------------------------------------------------------------
-- DATABASE INITIALIZATION
--------------------------------------------------------------------------------

local function initializeItemTables()
    if not db then return end
    
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS item_definitions (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT DEFAULT '',
            category TEXT DEFAULT 'misc',
            quality TEXT DEFAULT 'common',
            weight REAL DEFAULT 1.0,
            stackable INTEGER DEFAULT 0,
            max_stack INTEGER DEFAULT 99,
            usable INTEGER DEFAULT 0,
            use_effect TEXT DEFAULT NULL,
            value INTEGER DEFAULT 1,
            durability INTEGER DEFAULT NULL,
            equippable INTEGER DEFAULT 0,
            weapon_id INTEGER DEFAULT NULL,
            armor_value INTEGER DEFAULT NULL,
            stat_str INTEGER DEFAULT 0,
            stat_dex INTEGER DEFAULT 0,
            stat_con INTEGER DEFAULT 0,
            stat_int INTEGER DEFAULT 0,
            stat_wis INTEGER DEFAULT 0,
            stat_cha INTEGER DEFAULT 0,
            created_by TEXT DEFAULT 'SYSTEM',
            created_date INTEGER DEFAULT 0
        )
    ]])
    
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS inventory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            character_id INTEGER NOT NULL,
            item_id TEXT NOT NULL,
            quantity INTEGER DEFAULT 1,
            durability INTEGER DEFAULT NULL,
            instance_id TEXT UNIQUE,
            slot_index INTEGER DEFAULT 0
        )
    ]])
    
    outputServerLog("Item database tables initialized")
end

addEventHandler("onResourceStart", resourceRoot, function()
    db = database
    if not db then
        outputServerLog("ERROR: Could not access database for inventory system")
        return
    end
    
    outputServerLog("Inventory system connected to database")
    initializeItemTables()
    ItemRegistry:loadFromDatabase()
end)

--------------------------------------------------------------------------------
-- ITEM REGISTRY (Database-backed)
--------------------------------------------------------------------------------

ItemRegistry = { items = {} }

function ItemRegistry:loadFromDatabase()
    if not db then return end
    
    local query = dbQuery(db, "SELECT * FROM item_definitions")
    local result = dbPoll(query, -1)
    
    if result then
        for _, row in ipairs(result) do
            self.items[row.id] = self:rowToItem(row)
        end
        outputServerLog("Loaded " .. #result .. " item definitions from database")
    end
end

function ItemRegistry:rowToItem(row)
    local quality = QUALITY_LOOKUP[row.quality:lower()] or ITEM_QUALITY.COMMON
    
    local item = {
        id = row.id,
        name = row.name,
        description = row.description or "",
        category = row.category or ITEM_CATEGORY.MISC,
        quality = quality,
        weight = row.weight or 1.0,
        stackable = (row.stackable == 1),
        maxStack = row.max_stack or 99,
        usable = (row.usable == 1),
        useEffect = row.use_effect,
        value = row.value or 1,
        durability = row.durability,
        equippable = (row.equippable == 1),
        weaponID = row.weapon_id,
        armorValue = row.armor_value,
        stats = {}
    }
    
    if row.stat_str and row.stat_str ~= 0 then item.stats.STR = row.stat_str end
    if row.stat_dex and row.stat_dex ~= 0 then item.stats.DEX = row.stat_dex end
    if row.stat_con and row.stat_con ~= 0 then item.stats.CON = row.stat_con end
    if row.stat_int and row.stat_int ~= 0 then item.stats.INT = row.stat_int end
    if row.stat_wis and row.stat_wis ~= 0 then item.stats.WIS = row.stat_wis end
    if row.stat_cha and row.stat_cha ~= 0 then item.stats.CHA = row.stat_cha end
    
    return item
end

function ItemRegistry:get(id)
    return self.items[id]
end

function ItemRegistry:exists(id)
    return self.items[id] ~= nil
end

function ItemRegistry:register(data, createdBy)
    if not db then return false, "Database not available" end
    if not data.id then return false, "Item ID required" end
    if not data.name then return false, "Item name required" end
    
    data.id = data.id:lower():gsub("%s+", "_")
    
    if self:exists(data.id) then
        return false, "Item ID already exists"
    end
    
    local category = CATEGORY_LOOKUP[(data.category or "misc"):lower()] or ITEM_CATEGORY.MISC
    local qualityName = (data.quality or "common"):lower()
    local quality = QUALITY_LOOKUP[qualityName] or ITEM_QUALITY.COMMON
    
    local success = dbExec(db, [[
        INSERT INTO item_definitions 
        (id, name, description, category, quality, weight, stackable, max_stack, 
         usable, use_effect, value, durability, equippable, weapon_id, armor_value,
         stat_str, stat_dex, stat_con, stat_int, stat_wis, stat_cha, created_by, created_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]],
        data.id, data.name, data.description or "", category, qualityName,
        data.weight or 1.0, data.stackable and 1 or 0, data.maxStack or 99,
        data.usable and 1 or 0, data.useEffect, data.value or 1, data.durability,
        data.equippable and 1 or 0, data.weaponID, data.armorValue,
        data.stats and data.stats.STR or 0, data.stats and data.stats.DEX or 0,
        data.stats and data.stats.CON or 0, data.stats and data.stats.INT or 0,
        data.stats and data.stats.WIS or 0, data.stats and data.stats.CHA or 0,
        createdBy or "SYSTEM", getRealTime().timestamp
    )
    
    if success then
        self.items[data.id] = {
            id = data.id, name = data.name, description = data.description or "",
            category = category, quality = quality, weight = data.weight or 1.0,
            stackable = data.stackable or false, maxStack = data.maxStack or 99,
            usable = data.usable or false, useEffect = data.useEffect,
            value = data.value or 1, durability = data.durability,
            equippable = data.equippable or false, weaponID = data.weaponID,
            armorValue = data.armorValue, stats = data.stats or {}
        }
        outputServerLog("Item registered: " .. data.id .. " (" .. data.name .. ")")
        return true, "Item created: " .. data.id
    end
    
    return false, "Database error"
end

function ItemRegistry:update(id, data)
    if not db then return false, "Database not available" end
    if not self:exists(id) then return false, "Item not found" end
    
    local existing = self.items[id]
    local category = data.category and CATEGORY_LOOKUP[data.category:lower()] or existing.category
    local qualityName = data.quality and data.quality:lower() or existing.quality.name:lower()
    
    local success = dbExec(db, [[
        UPDATE item_definitions SET
        name = ?, description = ?, category = ?, quality = ?, weight = ?,
        stackable = ?, max_stack = ?, usable = ?, use_effect = ?, value = ?,
        durability = ?, equippable = ?, weapon_id = ?, armor_value = ?,
        stat_str = ?, stat_dex = ?, stat_con = ?, stat_int = ?, stat_wis = ?, stat_cha = ?
        WHERE id = ?
    ]],
        data.name or existing.name, data.description or existing.description,
        category, qualityName, data.weight or existing.weight,
        (data.stackable ~= nil and data.stackable or existing.stackable) and 1 or 0,
        data.maxStack or existing.maxStack,
        (data.usable ~= nil and data.usable or existing.usable) and 1 or 0,
        data.useEffect or existing.useEffect, data.value or existing.value,
        data.durability or existing.durability,
        (data.equippable ~= nil and data.equippable or existing.equippable) and 1 or 0,
        data.weaponID or existing.weaponID, data.armorValue or existing.armorValue,
        data.stats and data.stats.STR or (existing.stats.STR or 0),
        data.stats and data.stats.DEX or (existing.stats.DEX or 0),
        data.stats and data.stats.CON or (existing.stats.CON or 0),
        data.stats and data.stats.INT or (existing.stats.INT or 0),
        data.stats and data.stats.WIS or (existing.stats.WIS or 0),
        data.stats and data.stats.CHA or (existing.stats.CHA or 0),
        id
    )
    
    if success then
        local query = dbQuery(db, "SELECT * FROM item_definitions WHERE id = ?", id)
        local result = dbPoll(query, -1)
        if result and result[1] then
            self.items[id] = self:rowToItem(result[1])
        end
        return true, "Item updated"
    end
    
    return false, "Database error"
end

function ItemRegistry:delete(id)
    if not db then return false, "Database not available" end
    if not self:exists(id) then return false, "Item not found" end
    
    local query = dbQuery(db, "SELECT COUNT(*) as count FROM inventory WHERE item_id = ?", id)
    local result = dbPoll(query, -1)
    if result and result[1] and result[1].count > 0 then
        return false, "Cannot delete: " .. result[1].count .. " instances in inventories"
    end
    
    if dbExec(db, "DELETE FROM item_definitions WHERE id = ?", id) then
        self.items[id] = nil
        return true, "Item deleted"
    end
    return false, "Database error"
end

function ItemRegistry:createInstance(id, quantity)
    local template = self:get(id)
    if not template then return nil end
    
    local item = {}
    for k, v in pairs(template) do
        if type(v) == "table" then
            item[k] = {}
            for k2, v2 in pairs(v) do item[k][k2] = v2 end
        else
            item[k] = v
        end
    end
    
    item.quantity = quantity or 1
    item.currentDurability = item.durability
    item.instanceID = generateItemInstanceID()
    return item
end

function ItemRegistry:search(query, category)
    local results = {}
    local searchTerm = query and query:lower() or ""
    
    for id, item in pairs(self.items) do
        local matches = true
        if searchTerm ~= "" then
            matches = item.name:lower():find(searchTerm) or item.id:lower():find(searchTerm)
        end
        if matches and category then
            matches = item.category == category
        end
        if matches then table.insert(results, item) end
    end
    
    table.sort(results, function(a, b) return a.name < b.name end)
    return results
end

local itemInstanceCounter = 0
function generateItemInstanceID()
    itemInstanceCounter = itemInstanceCounter + 1
    return "item_" .. itemInstanceCounter .. "_" .. getRealTime().timestamp
end

--------------------------------------------------------------------------------
-- USE EFFECTS
--------------------------------------------------------------------------------

local UseEffects = {}

UseEffects["heal"] = function(player, item, amount)
    amount = tonumber(amount) or 50
    local currentHP = getElementHealth(player)
    local maxHP = getElementData(player, "maxHealth") or 100
    setElementHealth(player, math.min(currentHP + amount, maxHP))
    outputChatBox("You restore " .. amount .. " HP", player, 0, 255, 0)
    return true
end

UseEffects["armor"] = function(player, item, amount)
    amount = tonumber(amount) or 25
    setPedArmor(player, math.min(getPedArmor(player) + amount, 100))
    outputChatBox("You gain " .. amount .. " armor", player, 0, 150, 255)
    return true
end

UseEffects["buff_stat"] = function(player, item, stat, amount, duration)
    stat, amount, duration = stat or "STR", tonumber(amount) or 2, tonumber(duration) or 60000
    local buffs = getElementData(player, "temp.buffs") or {}
    buffs[stat] = (buffs[stat] or 0) + amount
    setElementData(player, "temp.buffs", buffs)
    outputChatBox("+" .. amount .. " " .. stat .. " for " .. (duration/1000) .. "s", player, 255, 255, 0)
    setTimer(function()
        if isElement(player) then
            local b = getElementData(player, "temp.buffs") or {}
            b[stat] = (b[stat] or 0) - amount
            if b[stat] <= 0 then b[stat] = nil end
            setElementData(player, "temp.buffs", b)
        end
    end, duration, 1)
    return true
end

function executeUseEffect(player, item)
    if not item.useEffect then return false end
    local parts = split(item.useEffect, ":")
    local handler = UseEffects[parts[1]]
    if handler then return handler(player, item, unpack(parts, 2)) end
    return false
end

--------------------------------------------------------------------------------
-- INVENTORY CLASS
--------------------------------------------------------------------------------

Inventory = {}
Inventory.__index = Inventory

function Inventory:new(characterID, maxWeight, maxSlots)
    return setmetatable({
        characterID = characterID,
        maxWeight = maxWeight or 50,
        maxSlots = maxSlots or 30,
        items = {},
        equipped = { weapon = nil, armor = nil, accessory1 = nil, accessory2 = nil }
    }, Inventory)
end

function Inventory:addItem(itemID, quantity)
    quantity = quantity or 1
    local template = ItemRegistry:get(itemID)
    if not template then return false, "Item '" .. itemID .. "' does not exist" end
    
    if template.stackable then
        for _, item in ipairs(self.items) do
            if item.id == itemID and item.quantity < template.maxStack then
                local add = math.min(quantity, template.maxStack - item.quantity)
                item.quantity = item.quantity + add
                quantity = quantity - add
                if quantity <= 0 then return true, "Added " .. template.name end
            end
        end
    end
    
    while quantity > 0 do
        if #self.items >= self.maxSlots then return false, "Inventory full" end
        local newWeight = self:getCurrentWeight() + template.weight
        if newWeight > self.maxWeight then return false, "Too heavy" end
        
        local amt = template.stackable and math.min(quantity, template.maxStack) or 1
        table.insert(self.items, ItemRegistry:createInstance(itemID, amt))
        quantity = quantity - amt
    end
    
    return true, "Added " .. template.name
end

function Inventory:removeItem(instanceID, quantity)
    quantity = quantity or 1
    for i, item in ipairs(self.items) do
        if item.instanceID == instanceID then
            if item.stackable and item.quantity > quantity then
                item.quantity = item.quantity - quantity
            else
                table.remove(self.items, i)
            end
            return true
        end
    end
    return false
end

function Inventory:getItem(instanceID)
    for _, item in ipairs(self.items) do
        if item.instanceID == instanceID then return item end
    end
    return nil
end

function Inventory:hasItem(itemID, quantity)
    quantity = quantity or 1
    local total = 0
    for _, item in ipairs(self.items) do
        if item.id == itemID then total = total + (item.quantity or 1) end
    end
    return total >= quantity, total
end

function Inventory:getCurrentWeight()
    local total = 0
    for _, item in ipairs(self.items) do
        total = total + (item.weight * (item.quantity or 1))
    end
    return total
end

function Inventory:equipItem(player, instanceID, slot)
    local item = self:getItem(instanceID)
    if not item then return false, "Item not found" end
    if not item.equippable then return false, "Cannot be equipped" end
    
    slot = slot or (item.category == ITEM_CATEGORY.ARMOR and "armor" or "weapon")
    if self.equipped[slot] then self:unequipItem(player, slot) end
    
    self.equipped[slot] = item
    self:applyEquippedStats(player)
    if item.weaponID then giveWeapon(player, item.weaponID, 500, true) end
    if item.armorValue then setPedArmor(player, item.armorValue) end
    
    return true, "Equipped " .. item.name
end

function Inventory:unequipItem(player, slot)
    local item = self.equipped[slot]
    if not item then return false, "Nothing equipped" end
    if item.weaponID then takeWeapon(player, item.weaponID) end
    self.equipped[slot] = nil
    self:applyEquippedStats(player)
    return true, "Unequipped " .. item.name
end

function Inventory:applyEquippedStats(player)
    if not AccountManager then return end
    local char = AccountManager:getActiveCharacter(player)
    if not char then return end
    
    local bonuses = {STR = 0, DEX = 0, CON = 0, INT = 0, WIS = 0, CHA = 0}
    for _, item in pairs(self.equipped) do
        if item and item.stats then
            for stat, val in pairs(item.stats) do
                bonuses[stat] = bonuses[stat] + val
            end
        end
    end
    setElementData(player, "equipment.bonuses", bonuses)
    char:applyGTAModifiers(player)
end

function Inventory:useItem(player, instanceID)
    local item = self:getItem(instanceID)
    if not item then return false, "Item not found" end
    if not item.usable then return false, "Cannot be used" end
    
    local consumed = item.useEffect and executeUseEffect(player, item) or true
    if consumed then self:removeItem(instanceID, 1) end
    return true
end

function Inventory:saveToDatabase()
    if not self.characterID or not db then return end
    dbExec(db, "DELETE FROM inventory WHERE character_id = ?", self.characterID)
    for i, item in ipairs(self.items) do
        dbExec(db, "INSERT INTO inventory (character_id, item_id, quantity, durability, instance_id, slot_index) VALUES (?, ?, ?, ?, ?, ?)",
            self.characterID, item.id, item.quantity or 1, item.currentDurability, item.instanceID, i)
    end
end

function Inventory:loadFromDatabase()
    if not self.characterID or not db then return end
    local query = dbQuery(db, "SELECT * FROM inventory WHERE character_id = ? ORDER BY slot_index", self.characterID)
    local result = dbPoll(query, -1)
    if result then
        for _, row in ipairs(result) do
            local item = ItemRegistry:createInstance(row.item_id, row.quantity)
            if item then
                item.instanceID = row.instance_id
                if row.durability then item.currentDurability = row.durability end
                table.insert(self.items, item)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- PLAYER INVENTORY MANAGER
--------------------------------------------------------------------------------

PlayerInventories = {}

function getPlayerInventory(player) return PlayerInventories[player] end

function initializePlayerInventory(player, characterID, maxWeight)
    local inv = Inventory:new(characterID, maxWeight, 30)
    inv:loadFromDatabase()
    PlayerInventories[player] = inv
end

function savePlayerInventory(player)
    local inv = PlayerInventories[player]
    if inv then inv:saveToDatabase() end
end

--------------------------------------------------------------------------------
-- HELPER
--------------------------------------------------------------------------------

function split(str, delimiter)
    local result = {}
    for part in str:gmatch("([^" .. delimiter .. "]+)") do
        table.insert(result, part)
    end
    return result
end

--------------------------------------------------------------------------------
-- COMMANDS - ITEM MANAGEMENT (DM)
--------------------------------------------------------------------------------

addCommandHandler("createitem", function(player, cmd, ...)
    if isDungeonMaster and not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    local args = {...}
    if #args < 2 then
        outputChatBox("Usage: /createitem \"Name\" category [options]", player, 255, 255, 0)
        outputChatBox("Categories: weapon, armor, consumable, quest, material, tool, misc", player, 200, 200, 200)
        outputChatBox("Options: -w weight -v value -d durability -q quality -a armor", player, 200, 200, 200)
        outputChatBox("  -wpn weaponID -stack max -use effect -stat STR:2", player, 200, 200, 200)
        outputChatBox("Example: /createitem \"Kevlar Vest\" armor -a 100 -q uncommon", player, 150, 150, 150)
        return
    end
    
    local fullArgs = table.concat(args, " ")
    local itemName, rest
    
    if fullArgs:sub(1, 1) == '"' then
        local endQuote = fullArgs:find('"', 2)
        if endQuote then
            itemName = fullArgs:sub(2, endQuote - 1)
            rest = fullArgs:sub(endQuote + 2)
        else
            outputChatBox("Missing closing quote", player, 255, 0, 0)
            return
        end
    else
        itemName = args[1]
        rest = table.concat(args, " ", 2)
    end
    
    local restArgs = split(rest, " ")
    local category = restArgs[1]
    
    if not category or not CATEGORY_LOOKUP[category:lower()] then
        outputChatBox("Invalid category", player, 255, 0, 0)
        return
    end
    
    local itemData = {
        id = itemName:lower():gsub("%s+", "_"),
        name = itemName,
        category = category,
        stats = {}
    }
    
    local i = 2
    while i <= #restArgs do
        local opt, val = restArgs[i], restArgs[i + 1]
        if opt == "-w" and val then itemData.weight = tonumber(val); i = i + 2
        elseif opt == "-v" and val then itemData.value = tonumber(val); i = i + 2
        elseif opt == "-d" and val then itemData.durability = tonumber(val); i = i + 2
        elseif opt == "-q" and val then itemData.quality = val; i = i + 2
        elseif opt == "-a" and val then itemData.armorValue = tonumber(val); itemData.equippable = true; i = i + 2
        elseif opt == "-wpn" and val then itemData.weaponID = tonumber(val); itemData.equippable = true; i = i + 2
        elseif opt == "-stack" and val then itemData.stackable = true; itemData.maxStack = tonumber(val) or 99; i = i + 2
        elseif opt == "-use" and val then itemData.usable = true; itemData.useEffect = val; i = i + 2
        elseif opt == "-stat" and val then
            local p = split(val, ":")
            if #p == 2 then itemData.stats[p[1]:upper()] = tonumber(p[2]) end
            i = i + 2
        else i = i + 1 end
    end
    
    -- Category defaults
    if category:lower() == "armor" then itemData.equippable = true end
    if category:lower() == "weapon" then itemData.equippable = true end
    if category:lower() == "consumable" then itemData.usable = true; itemData.stackable = true end
    if category:lower() == "material" then itemData.stackable = true end
    
    local creator = getElementData(player, "character.name") or getPlayerName(player)
    local success, msg = ItemRegistry:register(itemData, creator)
    outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
    if success then outputChatBox("Use: /giveitem " .. itemData.id, player, 200, 200, 200) end
end)

addCommandHandler("edititem", function(player, cmd, itemID, ...)
    if isDungeonMaster and not isDungeonMaster(player) then return end
    if not itemID then outputChatBox("Usage: /edititem itemID [options]", player, 255, 255, 0); return end
    if not ItemRegistry:exists(itemID) then outputChatBox("Item not found", player, 255, 0, 0); return end
    
    local args, data = {...}, {stats = {}}
    local i = 1
    while i <= #args do
        local opt, val = args[i], args[i + 1]
        if opt == "-name" and val then data.name = val; i = i + 2
        elseif opt == "-w" and val then data.weight = tonumber(val); i = i + 2
        elseif opt == "-v" and val then data.value = tonumber(val); i = i + 2
        elseif opt == "-q" and val then data.quality = val; i = i + 2
        elseif opt == "-a" and val then data.armorValue = tonumber(val); i = i + 2
        elseif opt == "-stat" and val then
            local p = split(val, ":")
            if #p == 2 then data.stats[p[1]:upper()] = tonumber(p[2]) end
            i = i + 2
        else i = i + 1 end
    end
    
    local success, msg = ItemRegistry:update(itemID, data)
    outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
end)

addCommandHandler("deleteitem", function(player, cmd, itemID)
    if isDungeonMaster and not isDungeonMaster(player) then return end
    if not itemID then outputChatBox("Usage: /deleteitem itemID", player, 255, 255, 0); return end
    local success, msg = ItemRegistry:delete(itemID)
    outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
end)

addCommandHandler("listitems", function(player, cmd, arg1, arg2)
    local category, search = nil, nil
    if arg1 and CATEGORY_LOOKUP[arg1:lower()] then category = CATEGORY_LOOKUP[arg1:lower()]; search = arg2
    else search = arg1 end
    
    local items = ItemRegistry:search(search, category)
    outputChatBox("=== Items (" .. #items .. ") ===", player, 255, 255, 0)
    for _, item in ipairs(items) do
        outputChatBox(string.format("[%s] %s (%s)", item.quality.name:sub(1,1), item.name, item.id), player, unpack(item.quality.color))
    end
end)

addCommandHandler("iteminfo", function(player, cmd, itemID)
    if not itemID then outputChatBox("Usage: /iteminfo itemID", player, 255, 255, 0); return end
    local item = ItemRegistry:get(itemID)
    if not item then outputChatBox("Not found", player, 255, 0, 0); return end
    
    outputChatBox("=== " .. item.name .. " ===", player, unpack(item.quality.color))
    outputChatBox("ID: " .. item.id .. " | " .. item.category .. " | " .. item.quality.name, player, 200, 200, 200)
    outputChatBox("Weight: " .. item.weight .. "kg | Value: $" .. item.value, player, 200, 200, 200)
    if item.armorValue then outputChatBox("Armor: " .. item.armorValue, player, 100, 150, 255) end
    if item.weaponID then outputChatBox("WeaponID: " .. item.weaponID, player, 255, 100, 100) end
    if next(item.stats) then
        local s = "Stats:"
        for k, v in pairs(item.stats) do s = s .. " " .. k .. ":" .. v end
        outputChatBox(s, player, 255, 255, 100)
    end
    if item.useEffect then outputChatBox("Effect: " .. item.useEffect, player, 100, 255, 100) end
end)

--------------------------------------------------------------------------------
-- COMMANDS - PLAYER INVENTORY
--------------------------------------------------------------------------------

addCommandHandler("inv", function(player)
    local inv = getPlayerInventory(player)
    if not inv then outputChatBox("Select a character first", player, 255, 0, 0); return end
    
    outputChatBox("=== INVENTORY ===", player, 255, 255, 0)
    outputChatBox(string.format("Weight: %.1f/%.1f | Slots: %d/%d", inv:getCurrentWeight(), inv.maxWeight, #inv.items, inv.maxSlots), player, 255, 255, 255)
    
    if #inv.items == 0 then outputChatBox("Empty", player, 200, 200, 200)
    else
        for i, item in ipairs(inv.items) do
            local info = i .. ". [" .. item.quality.name:sub(1,1) .. "] " .. item.name
            if item.stackable and item.quantity > 1 then info = info .. " x" .. item.quantity end
            for slot, eq in pairs(inv.equipped) do
                if eq and eq.instanceID == item.instanceID then info = info .. " [E]" end
            end
            outputChatBox(info, player, unpack(item.quality.color))
        end
    end
end)

addCommandHandler("giveitem", function(player, cmd, itemID, qty, target)
    local targetPlayer, inv = player, getPlayerInventory(player)
    
    if target then
        if isDungeonMaster and not isDungeonMaster(player) then
            outputChatBox("DM required to give to others", player, 255, 0, 0); return
        end
        for _, p in ipairs(getElementsByType("player")) do
            local n = getElementData(p, "character.name") or getPlayerName(p)
            if n:lower():find(target:lower()) then targetPlayer = p; inv = getPlayerInventory(p); break end
        end
    end
    
    if not inv then outputChatBox("No character", player, 255, 0, 0); return end
    if not itemID then outputChatBox("Usage: /giveitem itemID [qty] [player]", player, 255, 255, 0); return end
    
    local success, msg = inv:addItem(itemID, tonumber(qty) or 1)
    outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
    if success and targetPlayer ~= player then
        outputChatBox("Received " .. itemID, targetPlayer, 0, 255, 0)
    end
end)

addCommandHandler("use", function(player, cmd, slot)
    local inv = getPlayerInventory(player)
    if not inv then return end
    if not slot then outputChatBox("Usage: /use [slot]", player, 255, 255, 0); return end
    local item = inv.items[tonumber(slot)]
    if not item then outputChatBox("No item", player, 255, 0, 0); return end
    inv:useItem(player, item.instanceID)
end)

addCommandHandler("equip", function(player, cmd, slot)
    local inv = getPlayerInventory(player)
    if not inv then return end
    if not slot then outputChatBox("Usage: /equip [slot]", player, 255, 255, 0); return end
    local item = inv.items[tonumber(slot)]
    if not item then outputChatBox("No item", player, 255, 0, 0); return end
    local success, msg = inv:equipItem(player, item.instanceID)
    outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
end)

addCommandHandler("unequip", function(player, cmd, slot)
    local inv = getPlayerInventory(player)
    if not inv or not slot then return end
    local success, msg = inv:unequipItem(player, slot:lower())
    outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
end)

addCommandHandler("drop", function(player, cmd, slot, qty)
    local inv = getPlayerInventory(player)
    if not inv or not slot then return end
    local item = inv.items[tonumber(slot)]
    if not item then return end
    if inv:removeItem(item.instanceID, tonumber(qty) or 1) then
        outputChatBox("Dropped " .. item.name, player, 255, 255, 0)
    end
end)

addCommandHandler("equipped", function(player)
    local inv = getPlayerInventory(player)
    if not inv then return end
    outputChatBox("=== Equipped ===", player, 255, 255, 0)
    local any = false
    for slot, item in pairs(inv.equipped) do
        if item then any = true; outputChatBox(slot:upper() .. ": " .. item.name, player, unpack(item.quality.color)) end
    end
    if not any then outputChatBox("Nothing", player, 200, 200, 200) end
end)

--------------------------------------------------------------------------------
-- GUI ITEM CREATOR (SERVER-SIDE)
--------------------------------------------------------------------------------

-- Command to open the GUI
addCommandHandler("itemgui", function(player)
    if isDungeonMaster and not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    triggerClientEvent(player, "itemcreator:open", player)
end)

-- Server-side handler for GUI item creation
addEvent("itemcreator:createItem", true)
addEventHandler("itemcreator:createItem", root, function(itemData)
    if isDungeonMaster and not isDungeonMaster(client) then
        triggerClientEvent(client, "itemcreator:result", client, false, "DM required")
        return
    end
    
    if not itemData or not itemData.name or not itemData.category then
        triggerClientEvent(client, "itemcreator:result", client, false, "Invalid item data")
        return
    end
    
    -- Generate item ID from name
    itemData.id = itemData.name:lower():gsub("%s+", "_"):gsub("[^a-z0-9_]", "")
    
    -- Apply category-specific defaults
    if itemData.category == "armor" or (itemData.armorValue and itemData.armorValue > 0) then
        itemData.equippable = true
    end
    
    if itemData.category == "weapon" or (itemData.weaponID and itemData.weaponID > 0) then
        itemData.equippable = true
    end
    
    if itemData.category == "consumable" then
        itemData.usable = true
        if not itemData.stackable then
            itemData.stackable = true
        end
    end
    
    if itemData.category == "material" and not itemData.stackable then
        itemData.stackable = true
    end
    
    if itemData.category == "resource" and not itemData.stackable then
        itemData.stackable = true
    end
    
    -- Get creator name
    local creator = getElementData(client, "character.name") or getPlayerName(client)
    
    -- Register the item
    local success, msg = ItemRegistry:register(itemData, creator)
    
    if success then
        triggerClientEvent(client, "itemcreator:result", client, true, 
            "Item '" .. itemData.name .. "' created! Use: /giveitem " .. itemData.id)
        outputServerLog("[ITEM CREATED] " .. creator .. " created item: " .. itemData.id)
    else
        triggerClientEvent(client, "itemcreator:result", client, false, msg)
    end
end)

outputServerLog("===== INVENTORY_SYSTEM.LUA LOADED =====")
