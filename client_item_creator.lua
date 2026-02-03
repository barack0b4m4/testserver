-- client_item_creator.lua (CLIENT)
-- GUI for DMs to create items visually

local window = nil
local elements = {}

-- Categories and qualities
local CATEGORIES = {"weapon", "armor", "consumable", "quest", "material", "tool", "misc"}
local QUALITIES = {"common", "uncommon", "rare", "epic", "legendary"}

--------------------------------------------------------------------------------
-- GUI CREATION
--------------------------------------------------------------------------------

function createItemCreatorGUI()
    if window and isElement(window) then
        destroyElement(window)
    end
    
    local sw, sh = guiGetScreenSize()
    local w, h = 500, 620
    
    window = guiCreateWindow((sw - w) / 2, (sh - h) / 2, w, h, "DM Item Creator", false)
    guiWindowSetSizable(window, false)
    
    local y = 30
    local labelW = 100
    local inputX = 115
    local inputW = 150
    
    -- Item Name
    guiCreateLabel(15, y, labelW, 20, "Item Name:", false, window)
    elements.nameEdit = guiCreateEdit(inputX, y, 200, 25, "", false, window)
    y = y + 35
    
    -- Description
    guiCreateLabel(15, y, labelW, 20, "Description:", false, window)
    elements.descEdit = guiCreateEdit(inputX, y, 370, 25, "", false, window)
    y = y + 35
    
    -- Category
    guiCreateLabel(15, y, labelW, 20, "Category:", false, window)
    elements.categoryCombo = guiCreateComboBox(inputX, y, inputW, 150, "", false, window)
    for _, cat in ipairs(CATEGORIES) do
        guiComboBoxAddItem(elements.categoryCombo, cat)
    end
    guiComboBoxSetSelected(elements.categoryCombo, 0)
    y = y + 35
    
    -- Quality
    guiCreateLabel(15, y, labelW, 20, "Quality:", false, window)
    elements.qualityCombo = guiCreateComboBox(inputX, y, inputW, 150, "", false, window)
    for _, qual in ipairs(QUALITIES) do
        guiComboBoxAddItem(elements.qualityCombo, qual)
    end
    guiComboBoxSetSelected(elements.qualityCombo, 0)
    y = y + 35
    
    -- Weight and Value on same row
    guiCreateLabel(15, y, labelW, 20, "Weight (kg):", false, window)
    elements.weightEdit = guiCreateEdit(inputX, y, 70, 25, "1.0", false, window)
    
    guiCreateLabel(200, y, 60, 20, "Value ($):", false, window)
    elements.valueEdit = guiCreateEdit(265, y, 70, 25, "1", false, window)
    y = y + 35
    
    -- Stackable
    elements.stackableCheck = guiCreateCheckBox(15, y, 100, 25, "Stackable", false, false, window)
    guiCreateLabel(130, y, 70, 20, "Max Stack:", false, window)
    elements.maxStackEdit = guiCreateEdit(205, y, 60, 25, "99", false, window)
    guiSetEnabled(elements.maxStackEdit, false)
    y = y + 35
    
    -- Usable
    elements.usableCheck = guiCreateCheckBox(15, y, 100, 25, "Usable", false, false, window)
    y = y + 30
    
    -- Use Effect
    guiCreateLabel(15, y, labelW, 20, "Use Effect:", false, window)
    elements.useEffectCombo = guiCreateComboBox(inputX, y, 200, 200, "", false, window)
    guiComboBoxAddItem(elements.useEffectCombo, "None")
    guiComboBoxAddItem(elements.useEffectCombo, "heal:25")
    guiComboBoxAddItem(elements.useEffectCombo, "heal:50")
    guiComboBoxAddItem(elements.useEffectCombo, "heal:100")
    guiComboBoxAddItem(elements.useEffectCombo, "armor:25")
    guiComboBoxAddItem(elements.useEffectCombo, "armor:50")
    guiComboBoxAddItem(elements.useEffectCombo, "buff_stat:STR:2:60000")
    guiComboBoxAddItem(elements.useEffectCombo, "buff_stat:DEX:2:60000")
    guiComboBoxAddItem(elements.useEffectCombo, "buff_stat:CON:2:60000")
    guiComboBoxSetSelected(elements.useEffectCombo, 0)
    guiSetEnabled(elements.useEffectCombo, false)
    y = y + 35
    
    -- Custom effect
    guiCreateLabel(15, y, labelW, 20, "Custom Effect:", false, window)
    elements.customEffectEdit = guiCreateEdit(inputX, y, 200, 25, "", false, window)
    guiSetEnabled(elements.customEffectEdit, false)
    y = y + 40
    
    -- Equipment section header
    guiCreateLabel(15, y, 200, 20, "=== Equipment Properties ===", false, window)
    y = y + 25
    
    -- Weapon ID and Armor Value on same row
    guiCreateLabel(15, y, labelW, 20, "Weapon ID:", false, window)
    elements.weaponIDEdit = guiCreateEdit(inputX, y, 60, 25, "0", false, window)
    
    guiCreateLabel(200, y, 80, 20, "Armor Value:", false, window)
    elements.armorEdit = guiCreateEdit(285, y, 60, 25, "0", false, window)
    y = y + 30
    
    -- Weapon IDs hint
    local hintLabel = guiCreateLabel(15, y, 470, 20, "Weapon IDs: 22=Pistol, 25=Shotgun, 30=AK47, 31=M4, 24=Deagle", false, window)
    guiLabelSetColor(hintLabel, 150, 150, 150)
    y = y + 25
    
    -- Durability
    guiCreateLabel(15, y, labelW, 20, "Durability:", false, window)
    elements.durabilityEdit = guiCreateEdit(inputX, y, 60, 25, "0", false, window)
    local durHint = guiCreateLabel(185, y, 150, 20, "(0 = unlimited)", false, window)
    guiLabelSetColor(durHint, 150, 150, 150)
    y = y + 35
    
    -- Stats section header
    guiCreateLabel(15, y, 200, 20, "=== Stat Bonuses ===", false, window)
    y = y + 25
    
    -- Stats in 2 columns
    local stats = {"STR", "DEX", "CON", "INT", "WIS", "CHA"}
    elements.statEdits = {}
    
    for i, stat in ipairs(stats) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local xPos = 15 + (col * 160)
        local yPos = y + (row * 30)
        
        guiCreateLabel(xPos, yPos, 40, 20, stat .. ":", false, window)
        elements.statEdits[stat] = guiCreateEdit(xPos + 45, yPos, 50, 25, "0", false, window)
    end
    y = y + 70
    
    -- Buttons at bottom
    local btnY = h - 60
    local btnW = 120
    local btnH = 40
    
    local createBtn = guiCreateButton(30, btnY, btnW, btnH, "Create Item", false, window)
    guiSetProperty(createBtn, "NormalTextColour", "FF00FF00")
    
    local previewBtn = guiCreateButton(170, btnY, btnW, btnH, "Preview", false, window)
    
    local cancelBtn = guiCreateButton(350, btnY, btnW, btnH, "Cancel", false, window)
    guiSetProperty(cancelBtn, "NormalTextColour", "FFFF0000")
    
    -- Event handlers for checkboxes
    addEventHandler("onClientGUIClick", elements.stackableCheck, function()
        guiSetEnabled(elements.maxStackEdit, guiCheckBoxGetSelected(elements.stackableCheck))
    end, false)
    
    addEventHandler("onClientGUIClick", elements.usableCheck, function()
        local enabled = guiCheckBoxGetSelected(elements.usableCheck)
        guiSetEnabled(elements.useEffectCombo, enabled)
        guiSetEnabled(elements.customEffectEdit, enabled)
    end, false)
    
    -- Auto-configure based on category selection
    addEventHandler("onClientGUIComboBoxAccepted", elements.categoryCombo, function()
        local selected = guiComboBoxGetSelected(elements.categoryCombo)
        if selected == -1 then return end
        
        local category = CATEGORIES[selected + 1]
        
        -- Auto-check stackable for consumables and materials
        if category == "consumable" or category == "material" then
            guiCheckBoxSetSelected(elements.stackableCheck, true)
            guiSetEnabled(elements.maxStackEdit, true)
        end
        
        -- Auto-check usable for consumables
        if category == "consumable" then
            guiCheckBoxSetSelected(elements.usableCheck, true)
            guiSetEnabled(elements.useEffectCombo, true)
            guiSetEnabled(elements.customEffectEdit, true)
        end
    end, false)
    
    -- Create button handler
    addEventHandler("onClientGUIClick", createBtn, function()
        local itemData = collectItemData()
        if itemData then
            triggerServerEvent("itemcreator:createItem", localPlayer, itemData)
        end
    end, false)
    
    -- Preview button handler
    addEventHandler("onClientGUIClick", previewBtn, function()
        local itemData = collectItemData()
        if itemData then
            showPreview(itemData)
        end
    end, false)
    
    -- Cancel button handler
    addEventHandler("onClientGUIClick", cancelBtn, function()
        hideItemCreatorGUI()
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
    
    outputChatBox("Item Creator opened. Fill in details and click Create Item.", 0, 255, 0)
end

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

function collectItemData()
    local name = guiGetText(elements.nameEdit)
    if name == "" then
        outputChatBox("ERROR: Item name is required!", 255, 0, 0)
        return nil
    end
    
    local categoryIdx = guiComboBoxGetSelected(elements.categoryCombo)
    if categoryIdx == -1 then
        outputChatBox("ERROR: Please select a category!", 255, 0, 0)
        return nil
    end
    local category = CATEGORIES[categoryIdx + 1]
    
    local qualityIdx = guiComboBoxGetSelected(elements.qualityCombo)
    local quality = QUALITIES[(qualityIdx >= 0 and qualityIdx + 1) or 1]
    
    local itemData = {
        name = name,
        description = guiGetText(elements.descEdit) or "",
        category = category,
        quality = quality,
        weight = tonumber(guiGetText(elements.weightEdit)) or 1.0,
        value = tonumber(guiGetText(elements.valueEdit)) or 1,
        stackable = guiCheckBoxGetSelected(elements.stackableCheck),
        maxStack = tonumber(guiGetText(elements.maxStackEdit)) or 99,
        usable = guiCheckBoxGetSelected(elements.usableCheck),
        weaponID = tonumber(guiGetText(elements.weaponIDEdit)) or 0,
        armorValue = tonumber(guiGetText(elements.armorEdit)) or 0,
        durability = tonumber(guiGetText(elements.durabilityEdit)) or 0,
        stats = {}
    }
    
    -- Get use effect
    if itemData.usable then
        -- Check custom effect first
        local customEffect = guiGetText(elements.customEffectEdit)
        if customEffect and customEffect ~= "" then
            itemData.useEffect = customEffect
        else
            -- Use combo selection
            local effectIdx = guiComboBoxGetSelected(elements.useEffectCombo)
            if effectIdx > 0 then
                itemData.useEffect = guiComboBoxGetItemText(elements.useEffectCombo, effectIdx)
            end
        end
    end
    
    -- Get stat bonuses
    for stat, edit in pairs(elements.statEdits) do
        local value = tonumber(guiGetText(edit)) or 0
        if value ~= 0 then
            itemData.stats[stat] = value
        end
    end
    
    return itemData
end

function showPreview(itemData)
    outputChatBox("=== Item Preview ===", 255, 255, 0)
    outputChatBox("Name: " .. itemData.name, 255, 255, 255)
    outputChatBox("Category: " .. itemData.category .. " | Quality: " .. itemData.quality, 200, 200, 200)
    outputChatBox("Weight: " .. itemData.weight .. " kg | Value: $" .. itemData.value, 200, 200, 200)
    
    if itemData.description ~= "" then
        outputChatBox("Description: " .. itemData.description, 180, 180, 180)
    end
    
    if itemData.stackable then
        outputChatBox("Stackable: Yes (max " .. itemData.maxStack .. ")", 200, 200, 200)
    end
    
    if itemData.weaponID > 0 then
        outputChatBox("Weapon ID: " .. itemData.weaponID, 255, 150, 150)
    end
    
    if itemData.armorValue > 0 then
        outputChatBox("Armor Value: " .. itemData.armorValue, 150, 150, 255)
    end
    
    if itemData.durability > 0 then
        outputChatBox("Durability: " .. itemData.durability, 200, 200, 200)
    end
    
    if itemData.usable and itemData.useEffect then
        outputChatBox("Use Effect: " .. itemData.useEffect, 150, 255, 150)
    end
    
    -- Stats
    local hasStats = false
    local statStr = "Stat Bonuses:"
    for stat, value in pairs(itemData.stats) do
        if value ~= 0 then
            hasStats = true
            local sign = value > 0 and "+" or ""
            statStr = statStr .. " " .. stat .. ":" .. sign .. value
        end
    end
    
    if hasStats then
        outputChatBox(statStr, 255, 255, 150)
    end
    
    outputChatBox("===================", 255, 255, 0)
end

function hideItemCreatorGUI()
    if window and isElement(window) then
        destroyElement(window)
        window = nil
        elements = {}
        showCursor(false)
        guiSetInputMode("allow_binds")
        outputChatBox("Item Creator closed.", 200, 200, 200)
    end
end

--------------------------------------------------------------------------------
-- SERVER EVENTS
--------------------------------------------------------------------------------

-- Server opens the GUI
addEvent("itemcreator:open", true)
addEventHandler("itemcreator:open", root, function()
    createItemCreatorGUI()
end)

-- Server sends result
addEvent("itemcreator:result", true)
addEventHandler("itemcreator:result", root, function(success, message)
    if success then
        outputChatBox("[SUCCESS] " .. message, 0, 255, 0)
        -- Close GUI on successful creation
        hideItemCreatorGUI()
    else
        outputChatBox("[ERROR] " .. message, 255, 0, 0)
    end
end)

-- Clean up on resource stop
addEventHandler("onClientResourceStop", resourceRoot, function()
    hideItemCreatorGUI()
end)

outputChatBox("Item Creator system loaded.", 200, 200, 200)
