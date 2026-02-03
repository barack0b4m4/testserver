-- shopkeeper_system.lua (SERVER)
-- Shopkeeper NPC system with persistent inventory and DM management
-- Now integrates with CHA stat for price modifiers!

outputServerLog("===== SHOPKEEPER_SYSTEM.LUA LOADING =====")

local db = nil

ShopNPCs = ShopNPCs or {}
Shops = Shops or {}

--------------------------------------------------------------------------------
-- DATABASE INITIALIZATION
--------------------------------------------------------------------------------

local function initializeShopTables()
    if not db then return end
    
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS shops (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT DEFAULT '',
            npc_id TEXT,
            skin INTEGER DEFAULT 0,
            pos_x REAL,
            pos_y REAL,
            pos_z REAL,
            dimension INTEGER DEFAULT 0,
            interior INTEGER DEFAULT 0,
            created_by TEXT,
            created_date INTEGER
        )
    ]])
    
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS shop_inventory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            shop_id TEXT NOT NULL,
            item_id TEXT NOT NULL,
            price INTEGER NOT NULL,
            stock INTEGER DEFAULT -1,
            markup REAL DEFAULT 1.5,
            FOREIGN KEY (shop_id) REFERENCES shops(id),
            UNIQUE(shop_id, item_id)
        )
    ]])
    
    outputServerLog("Shop database tables initialized")
end

addEventHandler("onResourceStart", resourceRoot, function()
    db = database
    if not db then
        outputServerLog("ERROR: Could not access database for shop system")
        return
    end
    
    outputServerLog("Shop system connected to database")
    initializeShopTables()
    loadAllShops()
end)

--------------------------------------------------------------------------------
-- CHA PRICE MODIFIER HELPER
--------------------------------------------------------------------------------

function getPlayerPriceModifier(player)
    local priceModifier = getElementData(player, "stat.priceModifier")
    if priceModifier then return priceModifier end
    
    if AccountManager then
        local char = AccountManager:getActiveCharacter(player)
        if char and char.stats then
            local chaMod = math.floor((char.stats.CHA - 10) / 2)
            local modifier = 1.0 - (chaMod * 0.05)
            return math.max(0.7, math.min(1.3, modifier))
        end
    end
    
    return 1.0
end

function calculatePlayerPrice(player, basePrice)
    return math.floor(basePrice * getPlayerPriceModifier(player))
end

--------------------------------------------------------------------------------
-- SHOP MANAGEMENT
--------------------------------------------------------------------------------

function loadAllShops()
    if not db then return end
    
    local query = dbQuery(db, "SELECT * FROM shops")
    local result = dbPoll(query, -1)
    if not result then return end
    
    for _, row in ipairs(result) do
        local shop = {
            id = row.id, name = row.name, description = row.description,
            npcID = row.npc_id, skin = row.skin,
            position = {x = row.pos_x, y = row.pos_y, z = row.pos_z},
            dimension = row.dimension, interior = row.interior, items = {}
        }
        
        local invQuery = dbQuery(db, "SELECT * FROM shop_inventory WHERE shop_id = ?", row.id)
        local invResult = dbPoll(invQuery, -1)
        if invResult then
            for _, item in ipairs(invResult) do
                table.insert(shop.items, {
                    itemID = item.item_id, price = item.price,
                    stock = item.stock, markup = item.markup
                })
            end
        end
        
        Shops[shop.id] = shop
        if shop.position.x then spawnShopkeeper(shop.id) end
    end
    
    outputServerLog("Loaded " .. #result .. " shops")
    registerAllShopkeepersWithNPCSystem()
end

function registerAllShopkeepersWithNPCSystem()
    local count = 0
    for shopID, shop in pairs(Shops) do
        if ShopNPCs[shopID] and isElement(ShopNPCs[shopID]) then
            local npcID = "shopkeeper_" .. shopID
            if NPCs and not NPCs[npcID] then
                local npc = NPC:new(npcID, shop.name, shop.skin, {STR=10,DEX=10,CON=10,INT=10,WIS=10,CHA=10})
                NPCs[npcID] = npc
                if NPCElements then NPCElements[npcID] = ShopNPCs[shopID] end
                setElementData(ShopNPCs[shopID], "npc.id", npcID)
                count = count + 1
            end
        end
    end
    outputServerLog("Registered " .. count .. " shopkeepers with NPC system")
end

function spawnShopkeeper(shopID)
    local shop = Shops[shopID]
    if not shop then return false end
    
    if ShopNPCs[shopID] and isElement(ShopNPCs[shopID]) then
        destroyElement(ShopNPCs[shopID])
    end
    
    local ped = createPed(shop.skin, shop.position.x, shop.position.y, shop.position.z)
    if not ped then return false end
    
    setElementDimension(ped, shop.dimension)
    setElementInterior(ped, shop.interior)
    setElementFrozen(ped, true)
    setElementData(ped, "shop.id", shopID)
    setElementData(ped, "shop.name", shop.name)
    setElementData(ped, "isShopkeeper", true)
    setElementData(ped, "isNPC", true)
    setElementData(ped, "npc.name", shop.name)
    
    ShopNPCs[shopID] = ped
    
    if NPCs then
        local npcID = "shopkeeper_" .. shopID
        local npc = NPC:new(npcID, shop.name, shop.skin, {STR=10,DEX=10,CON=10,INT=10,WIS=10,CHA=10})
        NPCs[npcID] = npc
        setElementData(ped, "npc.id", npcID)
        NPCElements[npcID] = ped
    end
    
    outputServerLog("Shopkeeper spawned: " .. shop.name)
    return true
end

function createShop(name, skin, x, y, z, dimension, interior, createdBy)
    if not db then return nil, "Database not available" end
    
    local shopID = "shop_" .. getRealTime().timestamp .. "_" .. math.random(1000, 9999)
    
    local success = dbExec(db, [[
        INSERT INTO shops (id, name, description, skin, pos_x, pos_y, pos_z, dimension, interior, created_by, created_date)
        VALUES (?, ?, '', ?, ?, ?, ?, ?, ?, ?, ?)
    ]], shopID, name, skin, x, y, z, dimension, interior, createdBy, getRealTime().timestamp)
    
    if not success then return nil, "Database error" end
    
    Shops[shopID] = {
        id = shopID, name = name, description = "", skin = skin,
        position = {x = x, y = y, z = z},
        dimension = dimension, interior = interior, items = {}
    }
    
    spawnShopkeeper(shopID)
    return shopID
end

function deleteShop(shopID)
    if not db or not Shops[shopID] then return false end
    
    if ShopNPCs[shopID] and isElement(ShopNPCs[shopID]) then
        local npcID = "shopkeeper_" .. shopID
        if NPCs then NPCs[npcID] = nil end
        if NPCElements then NPCElements[npcID] = nil end
        destroyElement(ShopNPCs[shopID])
        ShopNPCs[shopID] = nil
    end
    
    dbExec(db, "DELETE FROM shop_inventory WHERE shop_id = ?", shopID)
    dbExec(db, "DELETE FROM shops WHERE id = ?", shopID)
    Shops[shopID] = nil
    
    outputServerLog("Shop deleted: " .. shopID)
    return true
end

function getShopDataForClient(shopID, player)
    local shop = Shops[shopID]
    if not shop then return nil end
    
    local priceModifier = player and getPlayerPriceModifier(player) or 1.0
    
    local data = {
        id = shop.id, name = shop.name, description = shop.description,
        priceModifier = priceModifier, items = {}
    }
    
    for _, shopItem in ipairs(shop.items) do
        local itemTemplate = ItemRegistry and ItemRegistry:get(shopItem.itemID)
        if itemTemplate then
            local adjustedPrice = math.floor(shopItem.price * priceModifier)
            table.insert(data.items, {
                itemID = shopItem.itemID, name = itemTemplate.name,
                basePrice = shopItem.price, price = adjustedPrice,
                stock = shopItem.stock, markup = shopItem.markup,
                category = itemTemplate.category, quality = itemTemplate.quality.name,
                description = itemTemplate.description
            })
        end
    end
    
    return data
end

--------------------------------------------------------------------------------
-- SHOP INVENTORY MANAGEMENT
--------------------------------------------------------------------------------

function addShopItem(shopID, itemID, price, stock, markup)
    if not db then return false, "Database not available" end
    local shop = Shops[shopID]
    if not shop then return false, "Shop not found" end
    if not ItemRegistry or not ItemRegistry:exists(itemID) then
        return false, "Item does not exist: " .. itemID
    end
    
    local itemTemplate = ItemRegistry:get(itemID)
    if not price then
        markup = markup or 1.5
        price = math.floor((itemTemplate.value or 1) * markup)
    end
    stock = stock or -1
    markup = markup or 1.5
    
    for i, item in ipairs(shop.items) do
        if item.itemID == itemID then
            shop.items[i] = {itemID = itemID, price = price, stock = stock, markup = markup}
            dbExec(db, "UPDATE shop_inventory SET price=?, stock=?, markup=? WHERE shop_id=? AND item_id=?",
                price, stock, markup, shopID, itemID)
            return true, "Item updated: " .. itemTemplate.name
        end
    end
    
    table.insert(shop.items, {itemID = itemID, price = price, stock = stock, markup = markup})
    dbExec(db, "INSERT INTO shop_inventory (shop_id, item_id, price, stock, markup) VALUES (?,?,?,?,?)",
        shopID, itemID, price, stock, markup)
    
    return true, "Item added: " .. itemTemplate.name .. " ($" .. price .. " base)"
end

function removeShopItem(shopID, itemID)
    if not db then return false, "Database not available" end
    local shop = Shops[shopID]
    if not shop then return false, "Shop not found" end
    
    for i, item in ipairs(shop.items) do
        if item.itemID == itemID then
            table.remove(shop.items, i)
            dbExec(db, "DELETE FROM shop_inventory WHERE shop_id=? AND item_id=?", shopID, itemID)
            return true, "Item removed"
        end
    end
    return false, "Item not in shop"
end

function updateShopInfo(shopID, name, description)
    if not db then return false end
    local shop = Shops[shopID]
    if not shop then return false end
    
    if name then shop.name = name end
    if description then shop.description = description end
    
    dbExec(db, "UPDATE shops SET name=?, description=? WHERE id=?", shop.name, shop.description, shopID)
    
    if ShopNPCs[shopID] and isElement(ShopNPCs[shopID]) then
        setElementData(ShopNPCs[shopID], "shop.name", shop.name)
        setElementData(ShopNPCs[shopID], "npc.name", shop.name)
    end
    
    return true
end

--------------------------------------------------------------------------------
-- PURCHASE SYSTEM - Uses CHA modifier!
--------------------------------------------------------------------------------

function purchaseItem(player, shopID, itemID, quantity)
    local shop = Shops[shopID]
    if not shop then return false, "Shop not found" end
    
    local shopItem, shopItemIndex = nil, nil
    for i, item in ipairs(shop.items) do
        if item.itemID == itemID then
            shopItem, shopItemIndex = item, i
            break
        end
    end
    
    if not shopItem then return false, "Item not available" end
    if shopItem.stock ~= -1 and shopItem.stock < quantity then
        return false, "Not enough stock (only " .. shopItem.stock .. " left)"
    end
    
    -- Apply CHA price modifier
    local basePrice = shopItem.price
    local priceModifier = getPlayerPriceModifier(player)
    local adjustedUnitPrice = math.floor(basePrice * priceModifier)
    local totalPrice = adjustedUnitPrice * quantity
    
    local playerMoney = getPlayerMoney(player)
    if playerMoney < totalPrice then
        return false, "Not enough money (need $" .. totalPrice .. ", have $" .. playerMoney .. ")"
    end
    
    local inv = getPlayerInventory(player)
    if not inv then return false, "No inventory" end
    
    local success, msg = inv:addItem(itemID, quantity)
    if not success then return false, msg end
    
    takePlayerMoney(player, totalPrice)
    
    if shopItem.stock ~= -1 then
        shop.items[shopItemIndex].stock = shopItem.stock - quantity
        dbExec(db, "UPDATE shop_inventory SET stock=? WHERE shop_id=? AND item_id=?",
            shop.items[shopItemIndex].stock, shopID, itemID)
    end
    
    local itemName = ItemRegistry and ItemRegistry:get(itemID) and ItemRegistry:get(itemID).name or itemID
    local discountPercent = math.floor((1 - priceModifier) * 100)
    
    local purchaseMsg = "Purchased " .. quantity .. "x " .. itemName .. " for $" .. totalPrice
    if discountPercent > 0 then
        purchaseMsg = purchaseMsg .. " (" .. discountPercent .. "% CHA discount!)"
    elseif discountPercent < 0 then
        purchaseMsg = purchaseMsg .. " (" .. math.abs(discountPercent) .. "% markup)"
    end
    
    outputServerLog("Purchase: " .. (getElementData(player, "character.name") or getPlayerName(player)) ..
        " bought " .. quantity .. "x " .. itemName .. " for $" .. totalPrice)
    
    return true, purchaseMsg
end

--------------------------------------------------------------------------------
-- CLIENT EVENTS
--------------------------------------------------------------------------------

addEvent("shop:requestOpen", true)
addEventHandler("shop:requestOpen", root, function(shopID)
    local player = client
    local isDM = isDungeonMaster and isDungeonMaster(player)
    local dmMode = getElementData(player, "dm.mode")
    
    local shopData = getShopDataForClient(shopID, player)
    if not shopData then
        outputChatBox("Shop not found", player, 255, 0, 0)
        return
    end
    
    local priceModifier = getPlayerPriceModifier(player)
    local discountPercent = math.floor((1 - priceModifier) * 100)
    if discountPercent > 0 then
        outputChatBox("Your charisma grants you a " .. discountPercent .. "% discount!", player, 100, 255, 100)
    elseif discountPercent < 0 then
        outputChatBox("Your low charisma causes a " .. math.abs(discountPercent) .. "% markup.", player, 255, 200, 100)
    end
    
    if isDM and dmMode then
        triggerClientEvent(player, "shop:openEditor", player, shopID, getShopDataForClient(shopID, nil))
    else
        triggerClientEvent(player, "shop:open", player, shopID, shopData)
    end
end)

addEvent("shop:buyItem", true)
addEventHandler("shop:buyItem", root, function(shopID, itemID, quantity)
    local player = client
    local success, msg = purchaseItem(player, shopID, itemID, quantity)
    
    if success then
        triggerClientEvent(player, "shop:message", player, msg, false)
        triggerClientEvent(player, "shop:updateMoney", player)
        triggerClientEvent(player, "shop:refresh", player, getShopDataForClient(shopID, player))
    else
        triggerClientEvent(player, "shop:message", player, msg, true)
    end
end)

addEvent("shop:addItem", true)
addEventHandler("shop:addItem", root, function(shopID, itemID, price, stock, markup)
    local player = client
    if not isDungeonMaster or not isDungeonMaster(player) then return end
    
    local success, msg = addShopItem(shopID, itemID, price, stock, markup)
    triggerClientEvent(player, "shop:message", player, msg, not success)
    if success then triggerClientEvent(player, "shop:refresh", player, getShopDataForClient(shopID, nil)) end
end)

addEvent("shop:removeItem", true)
addEventHandler("shop:removeItem", root, function(shopID, itemID)
    local player = client
    if not isDungeonMaster or not isDungeonMaster(player) then return end
    
    local success, msg = removeShopItem(shopID, itemID)
    triggerClientEvent(player, "shop:message", player, msg, not success)
    if success then triggerClientEvent(player, "shop:refresh", player, getShopDataForClient(shopID, nil)) end
end)

addEvent("shop:updateInfo", true)
addEventHandler("shop:updateInfo", root, function(shopID, name, description)
    local player = client
    if not isDungeonMaster or not isDungeonMaster(player) then return end
    
    if updateShopInfo(shopID, name, description) then
        triggerClientEvent(player, "shop:message", player, "Shop info updated", false)
        triggerClientEvent(player, "shop:refresh", player, getShopDataForClient(shopID, nil))
    end
end)

addEvent("shop:delete", true)
addEventHandler("shop:delete", root, function(shopID)
    local player = client
    if not isDungeonMaster or not isDungeonMaster(player) then return end
    if deleteShop(shopID) then outputChatBox("Shop deleted", player, 0, 255, 0) end
end)

addEvent("shop:getItemValue", true)
addEventHandler("shop:getItemValue", root, function(itemID)
    local player = client
    if ItemRegistry and ItemRegistry:exists(itemID) then
        local item = ItemRegistry:get(itemID)
        triggerClientEvent(player, "shop:itemValue", player, item.value or 1, item.name)
    else
        triggerClientEvent(player, "shop:message", player, "Item not found: " .. itemID, true)
    end
end)

--------------------------------------------------------------------------------
-- COMMANDS
--------------------------------------------------------------------------------

addCommandHandler("createshop", function(player, cmd, name, skinID)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    if not name then
        outputChatBox("Usage: /createshop \"Shop Name\" [skinID]", player, 255, 255, 0)
        return
    end
    
    skinID = tonumber(skinID) or 28
    local x, y, z = getElementPosition(player)
    local creatorName = getElementData(player, "character.name") or getPlayerName(player)
    
    local shopID, err = createShop(name, skinID, x, y, z, getElementDimension(player), getElementInterior(player), creatorName)
    
    if shopID then
        outputChatBox("Shop created: " .. name .. " (ID: " .. shopID .. ")", player, 0, 255, 0)
        outputChatBox("Click with DM mode ON to edit inventory", player, 200, 200, 200)
    else
        outputChatBox("Failed: " .. tostring(err), player, 255, 0, 0)
    end
end)

addCommandHandler("shopadditem", function(player, cmd, shopID, itemID, price, stock)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    if not shopID or not itemID then
        outputChatBox("Usage: /shopadditem shopID itemID [price] [stock]", player, 255, 255, 0)
        return
    end
    local success, msg = addShopItem(shopID, itemID, tonumber(price), tonumber(stock))
    outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
end)

addCommandHandler("listshops", function(player)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    outputChatBox("=== Shops ===", player, 255, 255, 0)
    local count = 0
    for id, shop in pairs(Shops) do
        local status = (ShopNPCs[id] and isElement(ShopNPCs[id])) and "SPAWNED" or "NOT SPAWNED"
        outputChatBox(string.format("%s - %s [%s] (%d items)", id, shop.name, status, #shop.items), player, 255, 255, 255)
        count = count + 1
    end
    if count == 0 then outputChatBox("No shops created", player, 200, 200, 200) end
end)

addCommandHandler("gotoshop", function(player, cmd, shopID)
    if not isDungeonMaster or not isDungeonMaster(player) then return end
    if not shopID then outputChatBox("Usage: /gotoshop shopID", player, 255, 255, 0); return end
    local shop = Shops[shopID]
    if not shop then outputChatBox("Shop not found", player, 255, 0, 0); return end
    setElementPosition(player, shop.position.x, shop.position.y, shop.position.z + 1)
    setElementDimension(player, shop.dimension)
    setElementInterior(player, shop.interior)
    outputChatBox("Teleported to: " .. shop.name, player, 0, 255, 0)
end)

addCommandHandler("respawnshop", function(player, cmd, shopID)
    if not isDungeonMaster or not isDungeonMaster(player) then return end
    if not shopID then outputChatBox("Usage: /respawnshop shopID", player, 255, 255, 0); return end
    if spawnShopkeeper(shopID) then
        outputChatBox("Shopkeeper respawned", player, 0, 255, 0)
    else
        outputChatBox("Failed to respawn", player, 255, 0, 0)
    end
end)

addCommandHandler("moveshop", function(player, cmd, shopID)
    if not isDungeonMaster or not isDungeonMaster(player) then return end
    if not shopID then outputChatBox("Usage: /moveshop shopID", player, 255, 255, 0); return end
    local shop = Shops[shopID]
    if not shop then outputChatBox("Shop not found", player, 255, 0, 0); return end
    
    local x, y, z = getElementPosition(player)
    shop.position = {x = x, y = y, z = z}
    shop.dimension = getElementDimension(player)
    shop.interior = getElementInterior(player)
    
    dbExec(db, "UPDATE shops SET pos_x=?, pos_y=?, pos_z=?, dimension=?, interior=? WHERE id=?",
        x, y, z, shop.dimension, shop.interior, shopID)
    spawnShopkeeper(shopID)
    outputChatBox("Shop moved to your position", player, 0, 255, 0)
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onResourceStop", resourceRoot, function()
    for id, ped in pairs(ShopNPCs) do
        if isElement(ped) then
            if NPCs then NPCs["shopkeeper_" .. id] = nil end
            if NPCElements then NPCElements["shopkeeper_" .. id] = nil end
            destroyElement(ped)
        end
    end
end)

outputServerLog("===== SHOPKEEPER_SYSTEM.LUA LOADED =====")
