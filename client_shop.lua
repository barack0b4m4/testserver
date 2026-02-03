-- client_shop.lua
-- Client-side shop GUI for interacting with shopkeeper NPCs

outputChatBox("===== CLIENT_SHOP.LUA LOADED =====", 255, 255, 0)

local shopWindow = nil
local shopElements = {}
local currentShopID = nil
local currentShopData = nil
local isDMEditing = false

local screenW, screenH = guiGetScreenSize()

--------------------------------------------------------------------------------
-- SHOP GUI (Player View)
--------------------------------------------------------------------------------

function createShopWindow(shopData)
    if shopWindow and isElement(shopWindow) then
        destroyElement(shopWindow)
    end
    
    currentShopData = shopData
    isDMEditing = false
    
    local windowW, windowH = 500, 450
    local windowX = (screenW - windowW) / 2
    local windowY = (screenH - windowH) / 2
    
    shopWindow = guiCreateWindow(windowX, windowY, windowW, windowH, shopData.name .. " - Shop", false)
    guiWindowSetSizable(shopWindow, false)
    
    -- Shop description
    local descLabel = guiCreateLabel(10, 25, windowW - 20, 20, shopData.description or "Welcome to my shop!", false, shopWindow)
    guiLabelSetHorizontalAlign(descLabel, "center")
    guiLabelSetColor(descLabel, 200, 200, 200)
    
    -- Player money display
    local money = getPlayerMoney()
    local moneyLabel = guiCreateLabel(10, 45, windowW - 20, 20, "Your Money: $" .. money, false, shopWindow)
    guiLabelSetHorizontalAlign(moneyLabel, "right")
    guiLabelSetColor(moneyLabel, 100, 255, 100)
    shopElements.moneyLabel = moneyLabel
    
    -- Items grid
    local gridList = guiCreateGridList(10, 70, windowW - 20, 280, false, shopWindow)
    guiGridListAddColumn(gridList, "Item", 0.35)
    guiGridListAddColumn(gridList, "Price", 0.15)
    guiGridListAddColumn(gridList, "Stock", 0.12)
    guiGridListAddColumn(gridList, "Category", 0.18)
    guiGridListAddColumn(gridList, "Quality", 0.15)
    shopElements.gridList = gridList
    
    -- Populate items
    if shopData.items then
        for _, item in ipairs(shopData.items) do
            local row = guiGridListAddRow(gridList)
            guiGridListSetItemText(gridList, row, 1, item.name, false, false)
            guiGridListSetItemText(gridList, row, 2, "$" .. item.price, false, false)
            guiGridListSetItemText(gridList, row, 3, item.stock == -1 and "∞" or tostring(item.stock), false, false)
            guiGridListSetItemText(gridList, row, 4, item.category or "misc", false, false)
            guiGridListSetItemText(gridList, row, 5, item.quality or "Common", false, false)
            
            -- Store item ID in row data
            guiGridListSetItemData(gridList, row, 1, item.itemID)
            
            -- Color based on affordability
            if item.price > money then
                guiGridListSetItemColor(gridList, row, 1, 150, 150, 150)
                guiGridListSetItemColor(gridList, row, 2, 255, 100, 100)
            end
        end
    end
    
    -- Quantity input
    guiCreateLabel(10, 360, 60, 25, "Quantity:", false, shopWindow)
    local qtyEdit = guiCreateEdit(75, 358, 50, 25, "1", false, shopWindow)
    guiEditSetMaxLength(qtyEdit, 3)
    shopElements.qtyEdit = qtyEdit
    
    -- Item info label
    local infoLabel = guiCreateLabel(140, 360, 250, 25, "Select an item to buy", false, shopWindow)
    guiLabelSetColor(infoLabel, 200, 200, 200)
    shopElements.infoLabel = infoLabel
    
    -- Buy button
    local buyBtn = guiCreateButton(10, 395, 150, 40, "Buy", false, shopWindow)
    shopElements.buyBtn = buyBtn
    
    -- Close button
    local closeBtn = guiCreateButton(windowW - 160, 395, 150, 40, "Close", false, shopWindow)
    
    -- Event handlers
    addEventHandler("onClientGUIClick", gridList, function()
        local row = guiGridListGetSelectedItem(gridList)
        if row ~= -1 then
            local itemID = guiGridListGetItemData(gridList, row, 1)
            local item = getShopItem(itemID)
            if item then
                local qty = tonumber(guiGetText(qtyEdit)) or 1
                local total = item.price * qty
                guiSetText(infoLabel, item.name .. " - Total: $" .. total)
                
                if total > getPlayerMoney() then
                    guiLabelSetColor(infoLabel, 255, 100, 100)
                else
                    guiLabelSetColor(infoLabel, 100, 255, 100)
                end
            end
        end
    end, false)
    
    addEventHandler("onClientGUIChanged", qtyEdit, function()
        local row = guiGridListGetSelectedItem(gridList)
        if row ~= -1 then
            local itemID = guiGridListGetItemData(gridList, row, 1)
            local item = getShopItem(itemID)
            if item then
                local qty = tonumber(guiGetText(qtyEdit)) or 1
                local total = item.price * qty
                guiSetText(infoLabel, item.name .. " - Total: $" .. total)
                
                if total > getPlayerMoney() then
                    guiLabelSetColor(infoLabel, 255, 100, 100)
                else
                    guiLabelSetColor(infoLabel, 100, 255, 100)
                end
            end
        end
    end, false)
    
    addEventHandler("onClientGUIClick", buyBtn, function()
        local row = guiGridListGetSelectedItem(gridList)
        if row == -1 then
            outputChatBox("Select an item first", 255, 0, 0)
            return
        end
        
        local itemID = guiGridListGetItemData(gridList, row, 1)
        local qty = tonumber(guiGetText(qtyEdit)) or 1
        
        if qty < 1 then
            outputChatBox("Invalid quantity", 255, 0, 0)
            return
        end
        
        triggerServerEvent("shop:buyItem", resourceRoot, currentShopID, itemID, qty)
    end, false)
    
    addEventHandler("onClientGUIClick", closeBtn, function()
        closeShopWindow()
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
end

function getShopItem(itemID)
    if not currentShopData or not currentShopData.items then return nil end
    for _, item in ipairs(currentShopData.items) do
        if item.itemID == itemID then
            return item
        end
    end
    return nil
end

function closeShopWindow()
    if shopWindow and isElement(shopWindow) then
        destroyElement(shopWindow)
        shopWindow = nil
        shopElements = {}
        currentShopID = nil
        currentShopData = nil
        showCursor(false)
        guiSetInputMode("allow_binds")
    end
end

--------------------------------------------------------------------------------
-- DM EDIT GUI
--------------------------------------------------------------------------------

function createDMEditWindow(shopData)
    if shopWindow and isElement(shopWindow) then
        destroyElement(shopWindow)
    end
    
    currentShopData = shopData
    isDMEditing = true
    
    local windowW, windowH = 600, 550
    local windowX = (screenW - windowW) / 2
    local windowY = (screenH - windowH) / 2
    
    shopWindow = guiCreateWindow(windowX, windowY, windowW, windowH, "[DM] Edit Shop: " .. shopData.name, false)
    guiWindowSetSizable(shopWindow, false)
    
    -- Shop name edit
    guiCreateLabel(10, 30, 80, 20, "Shop Name:", false, shopWindow)
    local nameEdit = guiCreateEdit(95, 28, 200, 25, shopData.name, false, shopWindow)
    shopElements.nameEdit = nameEdit
    
    -- Shop description
    guiCreateLabel(310, 30, 80, 20, "Description:", false, shopWindow)
    local descEdit = guiCreateEdit(395, 28, 195, 25, shopData.description or "", false, shopWindow)
    shopElements.descEdit = descEdit
    
    -- Current items grid
    guiCreateLabel(10, 60, 200, 20, "Current Shop Inventory:", false, shopWindow)
    local gridList = guiCreateGridList(10, 80, windowW - 20, 200, false, shopWindow)
    guiGridListAddColumn(gridList, "Item ID", 0.25)
    guiGridListAddColumn(gridList, "Name", 0.25)
    guiGridListAddColumn(gridList, "Price", 0.15)
    guiGridListAddColumn(gridList, "Stock", 0.12)
    guiGridListAddColumn(gridList, "Markup", 0.13)
    shopElements.gridList = gridList
    
    -- Populate current items
    if shopData.items then
        for _, item in ipairs(shopData.items) do
            local row = guiGridListAddRow(gridList)
            guiGridListSetItemText(gridList, row, 1, item.itemID, false, false)
            guiGridListSetItemText(gridList, row, 2, item.name, false, false)
            guiGridListSetItemText(gridList, row, 3, "$" .. item.price, false, false)
            guiGridListSetItemText(gridList, row, 4, item.stock == -1 and "∞" or tostring(item.stock), false, false)
            guiGridListSetItemText(gridList, row, 5, (item.markup or 1.0) .. "x", false, false)
            guiGridListSetItemData(gridList, row, 1, item.itemID)
        end
    end
    
    -- Add item section
    guiCreateLabel(10, 290, 200, 20, "Add Item to Shop:", false, shopWindow)
    
    guiCreateLabel(10, 315, 60, 20, "Item ID:", false, shopWindow)
    local itemIDEdit = guiCreateEdit(75, 313, 150, 25, "", false, shopWindow)
    shopElements.itemIDEdit = itemIDEdit
    
    guiCreateLabel(235, 315, 50, 20, "Price:", false, shopWindow)
    local priceEdit = guiCreateEdit(290, 313, 80, 25, "", false, shopWindow)
    shopElements.priceEdit = priceEdit
    
    guiCreateLabel(380, 315, 50, 20, "Stock:", false, shopWindow)
    local stockEdit = guiCreateEdit(435, 313, 60, 25, "-1", false, shopWindow)
    shopElements.stockEdit = stockEdit
    
    guiCreateLabel(505, 315, 50, 20, "(-1 = ∞)", false, shopWindow)
    guiLabelSetColor(guiCreateLabel(505, 315, 50, 20, "(-1 = ∞)", false, shopWindow), 150, 150, 150)
    
    -- Markup explanation
    guiCreateLabel(10, 345, 60, 20, "Markup:", false, shopWindow)
    local markupEdit = guiCreateEdit(75, 343, 60, 25, "1.5", false, shopWindow)
    shopElements.markupEdit = markupEdit
    guiCreateLabel(145, 345, 200, 20, "(multiplier on base value)", false, shopWindow)
    
    -- Add/Remove buttons
    local addBtn = guiCreateButton(10, 380, 120, 35, "Add Item", false, shopWindow)
    local removeBtn = guiCreateButton(140, 380, 120, 35, "Remove Item", false, shopWindow)
    local autoFillBtn = guiCreateButton(270, 380, 120, 35, "Auto-Fill Price", false, shopWindow)
    
    -- Bottom buttons
    local saveBtn = guiCreateButton(10, 500, 150, 40, "Save Changes", false, shopWindow)
    local deleteShopBtn = guiCreateButton(170, 500, 150, 40, "Delete Shop", false, shopWindow)
    local closeBtn = guiCreateButton(windowW - 160, 500, 150, 40, "Close", false, shopWindow)
    
    -- Info label
    local infoLabel = guiCreateLabel(10, 420, windowW - 20, 60, "Tip: Use /listitems in chat to see available items.\nLeave price empty to auto-calculate from item value * markup.", false, shopWindow)
    guiLabelSetColor(infoLabel, 180, 180, 180)
    shopElements.infoLabel = infoLabel
    
    -- Event handlers
    addEventHandler("onClientGUIClick", addBtn, function()
        local itemID = guiGetText(itemIDEdit)
        local price = guiGetText(priceEdit)
        local stock = guiGetText(stockEdit)
        local markup = guiGetText(markupEdit)
        
        if itemID == "" then
            guiSetText(infoLabel, "ERROR: Enter an item ID")
            guiLabelSetColor(infoLabel, 255, 100, 100)
            return
        end
        
        triggerServerEvent("shop:addItem", resourceRoot, currentShopID, itemID, 
            tonumber(price), tonumber(stock) or -1, tonumber(markup) or 1.5)
    end, false)
    
    addEventHandler("onClientGUIClick", removeBtn, function()
        local row = guiGridListGetSelectedItem(gridList)
        if row == -1 then
            guiSetText(infoLabel, "ERROR: Select an item to remove")
            guiLabelSetColor(infoLabel, 255, 100, 100)
            return
        end
        
        local itemID = guiGridListGetItemData(gridList, row, 1)
        triggerServerEvent("shop:removeItem", resourceRoot, currentShopID, itemID)
    end, false)
    
    addEventHandler("onClientGUIClick", autoFillBtn, function()
        local itemID = guiGetText(itemIDEdit)
        if itemID ~= "" then
            triggerServerEvent("shop:getItemValue", resourceRoot, itemID)
        end
    end, false)
    
    addEventHandler("onClientGUIClick", saveBtn, function()
        local newName = guiGetText(nameEdit)
        local newDesc = guiGetText(descEdit)
        triggerServerEvent("shop:updateInfo", resourceRoot, currentShopID, newName, newDesc)
    end, false)
    
    addEventHandler("onClientGUIClick", deleteShopBtn, function()
        local confirm = guiCreateWindow(screenW/2 - 150, screenH/2 - 75, 300, 150, "Confirm Delete", false)
        guiWindowSetSizable(confirm, false)
        
        guiCreateLabel(10, 30, 280, 40, "Are you sure you want to delete this shop?\nThis cannot be undone!", false, confirm)
        
        local yesBtn = guiCreateButton(30, 90, 100, 40, "Yes, Delete", false, confirm)
        local noBtn = guiCreateButton(170, 90, 100, 40, "Cancel", false, confirm)
        
        addEventHandler("onClientGUIClick", yesBtn, function()
            triggerServerEvent("shop:delete", resourceRoot, currentShopID)
            destroyElement(confirm)
            closeShopWindow()
        end, false)
        
        addEventHandler("onClientGUIClick", noBtn, function()
            destroyElement(confirm)
        end, false)
    end, false)
    
    addEventHandler("onClientGUIClick", closeBtn, function()
        closeShopWindow()
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
end

--------------------------------------------------------------------------------
-- SERVER EVENTS
--------------------------------------------------------------------------------

-- Open shop (player view)
addEvent("shop:open", true)
addEventHandler("shop:open", root, function(shopID, shopData)
    currentShopID = shopID
    createShopWindow(shopData)
end)

-- Open shop editor (DM view)
addEvent("shop:openEditor", true)
addEventHandler("shop:openEditor", root, function(shopID, shopData)
    currentShopID = shopID
    createDMEditWindow(shopData)
end)

-- Refresh shop data
addEvent("shop:refresh", true)
addEventHandler("shop:refresh", root, function(shopData)
    if not shopWindow or not isElement(shopWindow) then return end
    
    currentShopData = shopData
    
    if isDMEditing then
        createDMEditWindow(shopData)
    else
        createShopWindow(shopData)
    end
end)

-- Update money display after purchase
addEvent("shop:updateMoney", true)
addEventHandler("shop:updateMoney", root, function()
    if shopElements.moneyLabel and isElement(shopElements.moneyLabel) then
        guiSetText(shopElements.moneyLabel, "Your Money: $" .. getPlayerMoney())
    end
end)

-- Receive item value for auto-fill
addEvent("shop:itemValue", true)
addEventHandler("shop:itemValue", root, function(value, itemName)
    if shopElements.priceEdit and isElement(shopElements.priceEdit) then
        local markup = tonumber(guiGetText(shopElements.markupEdit)) or 1.5
        local price = math.floor(value * markup)
        guiSetText(shopElements.priceEdit, tostring(price))
        
        if shopElements.infoLabel then
            guiSetText(shopElements.infoLabel, "Auto-filled price for " .. itemName .. ": $" .. price .. " (base: $" .. value .. " x " .. markup .. ")")
            guiLabelSetColor(shopElements.infoLabel, 100, 255, 100)
        end
    end
end)

-- Close shop
addEvent("shop:close", true)
addEventHandler("shop:close", root, function()
    closeShopWindow()
end)

-- Result message
addEvent("shop:message", true)
addEventHandler("shop:message", root, function(message, isError)
    if shopElements.infoLabel and isElement(shopElements.infoLabel) then
        guiSetText(shopElements.infoLabel, message)
        guiLabelSetColor(shopElements.infoLabel, isError and 255 or 100, isError and 100 or 255, 100)
    end
    outputChatBox(message, isError and 255 or 0, isError and 0 or 255, 0)
end)

--------------------------------------------------------------------------------
-- CLICK DETECTION
--------------------------------------------------------------------------------

addEventHandler("onClientClick", root, function(button, state, absX, absY, worldX, worldY, worldZ, element)
    if button ~= "left" or state ~= "down" then return end
    if not element then return end
    
    -- Check if clicked element is a shopkeeper NPC
    if getElementType(element) == "ped" then
        local isShopkeeper = getElementData(element, "shop.id")
        if isShopkeeper then
            local shopID = getElementData(element, "shop.id")
            
            -- Check distance
            local px, py, pz = getElementPosition(localPlayer)
            local ex, ey, ez = getElementPosition(element)
            local distance = getDistanceBetweenPoints3D(px, py, pz, ex, ey, ez)
            
            if distance <= 5 then
                -- Request shop data from server
                triggerServerEvent("shop:requestOpen", resourceRoot, shopID)
            else
                outputChatBox("You're too far away from the shopkeeper", 255, 255, 0)
            end
        end
    end
end)

-- Clean up on resource stop
addEventHandler("onClientResourceStop", resourceRoot, function()
    closeShopWindow()
end)

outputChatBox("===== CLIENT_SHOP.LUA READY =====", 0, 255, 0)
