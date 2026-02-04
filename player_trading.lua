-- player_trading.lua (SERVER)
-- Secure player-to-player trading system

outputServerLog("===== PLAYER_TRADING.LUA LOADING =====")

-- Active trades: [player] = {partner, items, money, locked}
ActiveTrades = ActiveTrades or {}

--------------------------------------------------------------------------------
-- TRADE MANAGEMENT
--------------------------------------------------------------------------------

function initiateTrade(player1, player2)
    if not player1 or not player2 or not isElement(player1) or not isElement(player2) then
        return false, "Invalid players"
    end
    
    if player1 == player2 then
        return false, "Can't trade with yourself"
    end
    
    -- Check if already in trade
    if ActiveTrades[player1] then
        return false, "You're already in a trade"
    end
    
    if ActiveTrades[player2] then
        return false, "That player is already trading"
    end
    
    -- Check distance (must be within 5 meters)
    local x1, y1, z1 = getElementPosition(player1)
    local x2, y2, z2 = getElementPosition(player2)
    local dist = getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2)
    
    if dist > 5.0 then
        return false, "Too far away (must be within 5 meters)"
    end
    
    -- Check dimensions/interiors match
    if getElementDimension(player1) ~= getElementDimension(player2) or
       getElementInterior(player1) ~= getElementInterior(player2) then
        return false, "Players must be in same location"
    end
    
    -- Initialize trade states
    ActiveTrades[player1] = {
        partner = player2,
        items = {},  -- {instanceID = quantity}
        money = 0,
        locked = false
    }
    
    ActiveTrades[player2] = {
        partner = player1,
        items = {},
        money = 0,
        locked = false
    }
    
    -- Notify both players
    local name1 = getElementData(player1, "character.name") or getPlayerName(player1)
    local name2 = getElementData(player2, "character.name") or getPlayerName(player2)
    
    triggerClientEvent(player1, "trade:start", player1, player2, name2)
    triggerClientEvent(player2, "trade:start", player2, player1, name1)
    
    outputChatBox("Trade started with " .. name2, player1, 100, 255, 100)
    outputChatBox("Trade started with " .. name1, player2, 100, 255, 100)
    
    return true
end

function addTradeItem(player, instanceID, quantity)
    local trade = ActiveTrades[player]
    if not trade then return false, "Not in trade" end
    if trade.locked then return false, "Trade is locked" end
    
    -- Verify player has the item
    local inv = getPlayerInventory(player)
    if not inv then return false, "No inventory" end
    
    local item = nil
    for _, invItem in ipairs(inv.items) do
        if invItem.instanceID == instanceID then
            item = invItem
            break
        end
    end
    
    if not item then return false, "Item not found" end
    
    -- Check if item is equipped
    for slot, equipped in pairs(inv.equipped) do
        if equipped and equipped.instanceID == instanceID then
            return false, "Can't trade equipped items"
        end
    end
    
    -- Check quantity
    if quantity > item.quantity then
        return false, "Not enough quantity"
    end
    
    -- Add to trade
    trade.items[instanceID] = (trade.items[instanceID] or 0) + quantity
    
    -- Make sure we're not trying to trade more than we have
    if trade.items[instanceID] > item.quantity then
        trade.items[instanceID] = item.quantity
    end
    
    -- Update both players
    updateTradeWindow(player)
    updateTradeWindow(trade.partner)
    
    return true
end

function removeTradeItem(player, instanceID, quantity)
    local trade = ActiveTrades[player]
    if not trade then return false, "Not in trade" end
    if trade.locked then return false, "Trade is locked" end
    
    if not trade.items[instanceID] then return false, "Item not in trade" end
    
    trade.items[instanceID] = trade.items[instanceID] - quantity
    
    if trade.items[instanceID] <= 0 then
        trade.items[instanceID] = nil
    end
    
    -- Update both players
    updateTradeWindow(player)
    updateTradeWindow(trade.partner)
    
    return true
end

function setTradeMoney(player, amount)
    local trade = ActiveTrades[player]
    if not trade then return false, "Not in trade" end
    if trade.locked then return false, "Trade is locked" end
    
    amount = math.max(0, math.floor(amount))
    
    -- Check if player has enough money
    local playerMoney = getElementData(player, "character.money") or 0
    if amount > playerMoney then
        return false, "Not enough money"
    end
    
    trade.money = amount
    
    -- Update both players
    updateTradeWindow(player)
    updateTradeWindow(trade.partner)
    
    return true
end

function lockTrade(player)
    local trade = ActiveTrades[player]
    if not trade then return false end
    
    trade.locked = true
    
    -- Notify both players
    local name = getElementData(player, "character.name") or getPlayerName(player)
    outputChatBox(name .. " locked their trade", trade.partner, 255, 255, 0)
    
    -- Check if both locked
    local partnerTrade = ActiveTrades[trade.partner]
    if partnerTrade and partnerTrade.locked then
        -- Both locked, can execute trade
        triggerClientEvent(player, "trade:bothLocked", player)
        triggerClientEvent(trade.partner, "trade:bothLocked", trade.partner)
    end
    
    updateTradeWindow(player)
    updateTradeWindow(trade.partner)
    
    return true
end

function unlockTrade(player)
    local trade = ActiveTrades[player]
    if not trade then return false end
    
    trade.locked = false
    
    local name = getElementData(player, "character.name") or getPlayerName(player)
    outputChatBox(name .. " unlocked their trade", trade.partner, 255, 255, 0)
    
    updateTradeWindow(player)
    updateTradeWindow(trade.partner)
    
    return true
end

function executeTrade(player)
    local trade = ActiveTrades[player]
    if not trade then return false, "Not in trade" end
    
    local partnerTrade = ActiveTrades[trade.partner]
    if not partnerTrade then return false, "Partner not in trade" end
    
    -- Both must be locked
    if not trade.locked or not partnerTrade.locked then
        return false, "Both players must lock the trade"
    end
    
    -- Get inventories
    local inv1 = getPlayerInventory(player)
    local inv2 = getPlayerInventory(trade.partner)
    
    if not inv1 or not inv2 then
        cancelTrade(player, "Inventory error")
        return false, "Inventory error"
    end
    
    -- Verify both players still have their offered items and money
    local playerMoney = getElementData(player, "character.money") or 0
    local partnerMoney = getElementData(trade.partner, "character.money") or 0
    
    if trade.money > playerMoney then
        cancelTrade(player, "Insufficient money")
        return false, "You don't have enough money"
    end
    
    if partnerTrade.money > partnerMoney then
        cancelTrade(player, "Partner has insufficient money")
        return false, "Partner doesn't have enough money"
    end
    
    -- Verify items
    for instanceID, quantity in pairs(trade.items) do
        local found = false
        for _, item in ipairs(inv1.items) do
            if item.instanceID == instanceID and item.quantity >= quantity then
                found = true
                break
            end
        end
        if not found then
            cancelTrade(player, "Item verification failed")
            return false, "Item missing or insufficient quantity"
        end
    end
    
    for instanceID, quantity in pairs(partnerTrade.items) do
        local found = false
        for _, item in ipairs(inv2.items) do
            if item.instanceID == instanceID and item.quantity >= quantity then
                found = true
                break
            end
        end
        if not found then
            cancelTrade(player, "Partner item verification failed")
            return false, "Partner item missing"
        end
    end
    
    -- Check inventory space
    -- TODO: Could add weight/slot checks here
    
    -- EXECUTE TRADE
    
    -- Transfer items from player to partner
    for instanceID, quantity in pairs(trade.items) do
        local item = nil
        for _, invItem in ipairs(inv1.items) do
            if invItem.instanceID == instanceID then
                item = invItem
                break
            end
        end
        
        if item then
            inv1:removeItem(instanceID, quantity)
            inv2:addItem(item.id, quantity)
        end
    end
    
    -- Transfer items from partner to player
    for instanceID, quantity in pairs(partnerTrade.items) do
        local item = nil
        for _, invItem in ipairs(inv2.items) do
            if invItem.instanceID == instanceID then
                item = invItem
                break
            end
        end
        
        if item then
            inv2:removeItem(instanceID, quantity)
            inv1:addItem(item.id, quantity)
        end
    end
    
    -- Transfer money
    if trade.money > 0 then
        setElementData(player, "character.money", playerMoney - trade.money)
        setElementData(trade.partner, "character.money", partnerMoney + trade.money)
    end
    
    if partnerTrade.money > 0 then
        setElementData(trade.partner, "character.money", partnerMoney - partnerTrade.money)
        setElementData(player, "character.money", playerMoney + partnerTrade.money)
    end
    
    -- Save both characters
    if AccountManager then
        local char1 = AccountManager:getActiveCharacter(player)
        local char2 = AccountManager:getActiveCharacter(trade.partner)
        if char1 then AccountManager:saveCharacter(player, char1) end
        if char2 then AccountManager:saveCharacter(trade.partner, char2) end
    end
    
    -- Notify
    local name1 = getElementData(player, "character.name") or getPlayerName(player)
    local name2 = getElementData(trade.partner, "character.name") or getPlayerName(trade.partner)
    
    outputChatBox("Trade completed with " .. name2, player, 100, 255, 100)
    outputChatBox("Trade completed with " .. name1, trade.partner, 100, 255, 100)
    
    triggerClientEvent(player, "trade:complete", player)
    triggerClientEvent(trade.partner, "trade:complete", trade.partner)
    
    -- Clear trade data
    ActiveTrades[player] = nil
    ActiveTrades[trade.partner] = nil
    
    return true
end

function cancelTrade(player, reason)
    local trade = ActiveTrades[player]
    if not trade then return end
    
    local partner = trade.partner
    
    -- Clear trade data
    ActiveTrades[player] = nil
    ActiveTrades[partner] = nil
    
    -- Notify
    local name = getElementData(player, "character.name") or getPlayerName(player)
    outputChatBox("Trade cancelled: " .. (reason or ""), player, 255, 100, 100)
    outputChatBox(name .. " cancelled the trade: " .. (reason or ""), partner, 255, 100, 100)
    
    triggerClientEvent(player, "trade:cancel", player)
    triggerClientEvent(partner, "trade:cancel", partner)
end

function updateTradeWindow(player)
    local trade = ActiveTrades[player]
    if not trade then return end
    
    local partnerTrade = ActiveTrades[trade.partner]
    if not partnerTrade then return end
    
    -- Build item lists
    local myItems = {}
    local inv = getPlayerInventory(player)
    if inv then
        for instanceID, quantity in pairs(trade.items) do
            for _, item in ipairs(inv.items) do
                if item.instanceID == instanceID then
                    table.insert(myItems, {
                        name = item.name,
                        quantity = quantity,
                        quality = item.quality.name
                    })
                    break
                end
            end
        end
    end
    
    local partnerItems = {}
    local partnerInv = getPlayerInventory(trade.partner)
    if partnerInv then
        for instanceID, quantity in pairs(partnerTrade.items) do
            for _, item in ipairs(partnerInv.items) do
                if item.instanceID == instanceID then
                    table.insert(partnerItems, {
                        name = item.name,
                        quantity = quantity,
                        quality = item.quality.name
                    })
                    break
                end
            end
        end
    end
    
    triggerClientEvent(player, "trade:update", player, {
        myItems = myItems,
        myMoney = trade.money,
        myLocked = trade.locked,
        partnerItems = partnerItems,
        partnerMoney = partnerTrade.money,
        partnerLocked = partnerTrade.locked
    })
end

--------------------------------------------------------------------------------
-- EVENTS
--------------------------------------------------------------------------------

addEvent("trade:addItem", true)
addEventHandler("trade:addItem", root, function(instanceID, quantity)
    addTradeItem(client, instanceID, quantity)
end)

addEvent("trade:removeItem", true)
addEventHandler("trade:removeItem", root, function(instanceID, quantity)
    removeTradeItem(client, instanceID, quantity)
end)

addEvent("trade:setMoney", true)
addEventHandler("trade:setMoney", root, function(amount)
    setTradeMoney(client, amount)
end)

addEvent("trade:lock", true)
addEventHandler("trade:lock", root, function()
    lockTrade(client)
end)

addEvent("trade:unlock", true)
addEventHandler("trade:unlock", root, function()
    unlockTrade(client)
end)

addEvent("trade:accept", true)
addEventHandler("trade:accept", root, function()
    executeTrade(client)
end)

addEvent("trade:cancel", true)
addEventHandler("trade:cancel", root, function()
    cancelTrade(client, "Cancelled by player")
end)

--------------------------------------------------------------------------------
-- COMMANDS
--------------------------------------------------------------------------------

addCommandHandler("trade", function(player, cmd, targetName)
    if not targetName then
        outputChatBox("Usage: /trade [player name]", player, 255, 255, 0)
        return
    end
    
    -- Find target player
    local target = nil
    for _, p in ipairs(getElementsByType("player")) do
        local name = getElementData(p, "character.name") or getPlayerName(p)
        if name:lower():find(targetName:lower(), 1, true) then
            target = p
            break
        end
    end
    
    if not target then
        outputChatBox("Player not found", player, 255, 0, 0)
        return
    end
    
    local success, msg = initiateTrade(player, target)
    if not success then
        outputChatBox(msg, player, 255, 0, 0)
    end
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onPlayerQuit", root, function()
    if ActiveTrades[source] then
        cancelTrade(source, "Player disconnected")
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    -- Cancel all active trades
    for player, _ in pairs(ActiveTrades) do
        if isElement(player) then
            cancelTrade(player, "Server restart")
        end
    end
end)

outputServerLog("===== PLAYER_TRADING.LUA LOADED =====")
