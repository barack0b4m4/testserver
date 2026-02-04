-- client_trading.lua (CLIENT)
-- Trade GUI for player-to-player trading

local screenW, screenH = guiGetScreenSize()

-- Trade window
local tradeWindow = nil
local tradeElements = {}
local tradePartner = nil
local tradePartnerName = nil
local tradeData = nil

--------------------------------------------------------------------------------
-- GUI CREATION
--------------------------------------------------------------------------------

local function createTradeWindow(partner, partnerName)
    if tradeWindow and isElement(tradeWindow) then
        destroyElement(tradeWindow)
    end
    
    tradePartner = partner
    tradePartnerName = partnerName
    
    local w, h = 600, 450
    local x, y = (screenW - w) / 2, (screenH - h) / 2
    
    tradeWindow = guiCreateWindow(x, y, w, h, "Trading with " .. partnerName, false)
    guiWindowSetSizable(tradeWindow, false)
    guiWindowSetMovable(tradeWindow, true)
    
    -- Your offer section
    guiCreateLabel(15, 30, 270, 20, "Your Offer:", false, tradeWindow)
    
    tradeElements.myItemsList = guiCreateGridList(15, 55, 270, 250, false, tradeWindow)
    guiGridListAddColumn(tradeElements.myItemsList, "Item", 0.6)
    guiGridListAddColumn(tradeElements.myItemsList, "Qty", 0.3)
    
    guiCreateLabel(15, 315, 100, 20, "Money:", false, tradeWindow)
    tradeElements.myMoneyEdit = guiCreateEdit(120, 312, 165, 25, "0", false, tradeWindow)
    
    tradeElements.myLockBtn = guiCreateButton(15, 345, 270, 35, "Lock Offer", false, tradeWindow)
    guiSetProperty(tradeElements.myLockBtn, "NormalTextColour", "FFFFFF00")
    
    -- Their offer section
    guiCreateLabel(315, 30, 270, 20, partnerName .. "'s Offer:", false, tradeWindow)
    
    tradeElements.theirItemsList = guiCreateGridList(315, 55, 270, 250, false, tradeWindow)
    guiGridListAddColumn(tradeElements.theirItemsList, "Item", 0.6)
    guiGridListAddColumn(tradeElements.theirItemsList, "Qty", 0.3)
    
    guiCreateLabel(315, 315, 100, 20, "Money:", false, tradeWindow)
    tradeElements.theirMoneyLabel = guiCreateLabel(420, 315, 165, 20, "$0", false, tradeWindow)
    guiLabelSetHorizontalAlign(tradeElements.theirMoneyLabel, "center")
    
    tradeElements.theirStatusLabel = guiCreateLabel(315, 345, 270, 35, "Not Locked", false, tradeWindow)
    guiLabelSetHorizontalAlign(tradeElements.theirStatusLabel, "center")
    guiLabelSetVerticalAlign(tradeElements.theirStatusLabel, "center")
    guiSetFont(tradeElements.theirStatusLabel, "default-bold-small")
    
    -- Bottom buttons
    tradeElements.acceptBtn = guiCreateButton(15, 395, 190, 40, "Accept Trade", false, tradeWindow)
    guiSetProperty(tradeElements.acceptBtn, "NormalTextColour", "FF66FF66")
    guiSetEnabled(tradeElements.acceptBtn, false)
    
    tradeElements.addItemBtn = guiCreateButton(215, 395, 170, 40, "Add Item", false, tradeWindow)
    
    tradeElements.cancelBtn = guiCreateButton(395, 395, 190, 40, "Cancel Trade", false, tradeWindow)
    guiSetProperty(tradeElements.cancelBtn, "NormalTextColour", "FFFF6666")
    
    -- Event handlers
    addEventHandler("onClientGUIClick", tradeElements.myLockBtn, function()
        if tradeData and tradeData.myLocked then
            -- Unlock
            triggerServerEvent("trade:unlock", localPlayer)
        else
            -- Lock
            triggerServerEvent("trade:lock", localPlayer)
        end
    end, false)
    
    addEventHandler("onClientGUIClick", tradeElements.acceptBtn, function()
        triggerServerEvent("trade:accept", localPlayer)
    end, false)
    
    addEventHandler("onClientGUIClick", tradeElements.cancelBtn, function()
        triggerServerEvent("trade:cancel", localPlayer)
        closeTradeWindow()
    end, false)
    
    addEventHandler("onClientGUIClick", tradeElements.addItemBtn, function()
        -- Open inventory selection (simplified - just use /inv to see slots)
        outputChatBox("Use /tradeitem [slot] [quantity] to add items", 255, 255, 0)
        outputChatBox("Use /trademoney [amount] to set money offer", 255, 255, 0)
    end, false)
    
    -- Money edit handler
    addEventHandler("onClientGUIAccepted", tradeElements.myMoneyEdit, function()
        local amount = tonumber(guiGetText(source)) or 0
        triggerServerEvent("trade:setMoney", localPlayer, amount)
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
    
    outputChatBox("=== Trade Window Opened ===", 100, 255, 100)
    outputChatBox("Use /tradeitem [slot] [qty] to add items", 200, 200, 200)
    outputChatBox("Use /trademoney [amount] to set money", 200, 200, 200)
end

local function closeTradeWindow()
    if tradeWindow and isElement(tradeWindow) then
        destroyElement(tradeWindow)
        tradeWindow = nil
        tradeElements = {}
        tradePartner = nil
        tradePartnerName = nil
        tradeData = nil
        showCursor(false)
        guiSetInputMode("allow_binds")
    end
end

local function updateTradeDisplay(data)
    if not tradeWindow or not isElement(tradeWindow) then return end
    
    tradeData = data
    
    -- Update your items list
    guiGridListClear(tradeElements.myItemsList)
    for _, item in ipairs(data.myItems) do
        local row = guiGridListAddRow(tradeElements.myItemsList)
        guiGridListSetItemText(tradeElements.myItemsList, row, 1, item.name, false, false)
        guiGridListSetItemText(tradeElements.myItemsList, row, 2, tostring(item.quantity), false, false)
    end
    
    -- Update their items list
    guiGridListClear(tradeElements.theirItemsList)
    for _, item in ipairs(data.partnerItems) do
        local row = guiGridListAddRow(tradeElements.theirItemsList)
        guiGridListSetItemText(tradeElements.theirItemsList, row, 1, item.name, false, false)
        guiGridListSetItemText(tradeElements.theirItemsList, row, 2, tostring(item.quantity), false, false)
    end
    
    -- Update money displays
    guiSetText(tradeElements.myMoneyEdit, tostring(data.myMoney))
    guiSetText(tradeElements.theirMoneyLabel, "$" .. tostring(data.partnerMoney))
    
    -- Update lock status
    if data.myLocked then
        guiSetText(tradeElements.myLockBtn, "Unlock Offer")
        guiSetProperty(tradeElements.myLockBtn, "NormalTextColour", "FFFF6666")
        guiSetEnabled(tradeElements.myMoneyEdit, false)
    else
        guiSetText(tradeElements.myLockBtn, "Lock Offer")
        guiSetProperty(tradeElements.myLockBtn, "NormalTextColour", "FFFFFF00")
        guiSetEnabled(tradeElements.myMoneyEdit, true)
    end
    
    if data.partnerLocked then
        guiSetText(tradeElements.theirStatusLabel, "LOCKED")
        guiSetProperty(tradeElements.theirStatusLabel, "NormalTextColour", "FF00FF00")
    else
        guiSetText(tradeElements.theirStatusLabel, "Not Locked")
        guiSetProperty(tradeElements.theirStatusLabel, "NormalTextColour", "FFFFFFFF")
    end
    
    -- Enable accept button only if both locked
    if data.myLocked and data.partnerLocked then
        guiSetEnabled(tradeElements.acceptBtn, true)
    else
        guiSetEnabled(tradeElements.acceptBtn, false)
    end
end

--------------------------------------------------------------------------------
-- SERVER EVENTS
--------------------------------------------------------------------------------

addEvent("trade:start", true)
addEventHandler("trade:start", root, function(partner, partnerName)
    createTradeWindow(partner, partnerName)
end)

addEvent("trade:update", true)
addEventHandler("trade:update", root, function(data)
    updateTradeDisplay(data)
end)

addEvent("trade:complete", true)
addEventHandler("trade:complete", root, function()
    outputChatBox("Trade completed successfully!", 100, 255, 100)
    closeTradeWindow()
end)

addEvent("trade:cancel", true)
addEventHandler("trade:cancel", root, function()
    closeTradeWindow()
end)

addEvent("trade:bothLocked", true)
addEventHandler("trade:bothLocked", root, function()
    outputChatBox("Both players locked! Click 'Accept Trade' to complete.", 255, 255, 0)
end)

--------------------------------------------------------------------------------
-- COMMANDS (Helper commands for adding items)
--------------------------------------------------------------------------------

addCommandHandler("tradeitem", function(cmd, slot, qty)
    if not tradeWindow then
        outputChatBox("Not in a trade", 255, 0, 0)
        return
    end
    
    if not slot then
        outputChatBox("Usage: /tradeitem [slot] [quantity]", 255, 255, 0)
        return
    end
    
    -- This is a simplified approach - server will validate
    outputChatBox("This feature needs inventory integration - use the item creator for now", 255, 165, 0)
    outputChatBox("Full implementation requires hooking into your Inventory class", 200, 200, 200)
end)

addCommandHandler("trademoney", function(cmd, amount)
    if not tradeWindow then
        outputChatBox("Not in a trade", 255, 0, 0)
        return
    end
    
    local money = tonumber(amount) or 0
    triggerServerEvent("trade:setMoney", localPlayer, money)
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeTradeWindow()
end)

outputChatBox("Trading system loaded. Use /trade [player] to start a trade.", 200, 200, 200)
