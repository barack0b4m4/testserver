-- MTA San Andreas: Character Selection GUI (Client-side)

local charSelectWindow = nil
local charSelectElements = {}  -- Separate table for element storage
local characterList = {}
local selectedCharIndex = nil

-- GUI dimensions
local screenW, screenH = guiGetScreenSize()
local windowW, windowH = 600, 450
local windowX = (screenW - windowW) / 2
local windowY = (screenH - windowH) / 2

--------------------------------------------------------------------------------
-- CREATE CHARACTER SELECTION WINDOW
--------------------------------------------------------------------------------

function createCharacterSelectWindow(characters)
    if charSelectWindow and isElement(charSelectWindow) then
        destroyElement(charSelectWindow)
    end
    
    characterList = characters or {}
    
    -- Main window
    charSelectWindow = guiCreateWindow(windowX, windowY, windowW, windowH, "Select Your Character", false)
    guiWindowSetSizable(charSelectWindow, false)
    
    -- Title
    local titleLabel = guiCreateLabel(0.1, 0.05, 0.8, 0.08, "Choose a character to play", true, charSelectWindow)
    guiSetFont(titleLabel, "default-bold-small")
    guiLabelSetHorizontalAlign(titleLabel, "center")
    
    -- Character list (gridlist)
    local charGrid = guiCreateGridList(0.05, 0.15, 0.9, 0.5, true, charSelectWindow)
    guiGridListAddColumn(charGrid, "Name", 0.35)
    guiGridListAddColumn(charGrid, "Level", 0.15)
    guiGridListAddColumn(charGrid, "Gender", 0.15)
    guiGridListAddColumn(charGrid, "Playtime", 0.30)
    
    -- Populate character list
    for i, char in ipairs(characterList) do
        local row = guiGridListAddRow(charGrid)
        guiGridListSetItemText(charGrid, row, 1, char.name, false, false)
        guiGridListSetItemText(charGrid, row, 2, tostring(char.level), false, false)
        guiGridListSetItemText(charGrid, row, 3, char.gender or "Unknown", false, false)
        
        -- Convert playtime seconds to readable format
        local hours = math.floor(char.playTime / 3600)
        local minutes = math.floor((char.playTime % 3600) / 60)
        local timeStr = string.format("%dh %dm", hours, minutes)
        guiGridListSetItemText(charGrid, row, 4, timeStr, false, false)
    end
    
    -- Character info panel
    local infoPanel = guiCreateLabel(0.05, 0.68, 0.9, 0.12, "Select a character to see details", true, charSelectWindow)
    guiLabelSetHorizontalAlign(infoPanel, "center")
    guiLabelSetVerticalAlign(infoPanel, "center")
    guiSetFont(infoPanel, "default-bold-small")
    
    -- Buttons
    local playBtn = guiCreateButton(0.05, 0.83, 0.25, 0.12, "Play", true, charSelectWindow)
    local createBtn = guiCreateButton(0.35, 0.83, 0.25, 0.12, "Create New", true, charSelectWindow)
    local deleteBtn = guiCreateButton(0.70, 0.83, 0.25, 0.12, "Delete", true, charSelectWindow)
    
    -- Initially disable play/delete buttons
    guiSetEnabled(playBtn, false)
    guiSetEnabled(deleteBtn, false)
    
    -- Disable create button if player has 3 characters
    if #characterList >= 3 then
        guiSetEnabled(createBtn, false)
    end
    
    -- Store elements
    charSelectElements.charGrid = charGrid
    charSelectElements.infoPanel = infoPanel
    charSelectElements.playBtn = playBtn
    charSelectElements.deleteBtn = deleteBtn
    
    -- Grid selection handler
    addEventHandler("onClientGUIClick", charGrid, function()
        local selectedRow = guiGridListGetSelectedItem(charGrid)
        if selectedRow ~= -1 then
            selectedCharIndex = selectedRow + 1
            local char = characterList[selectedCharIndex]
            
            if char then
                local info = string.format(
                    "Character: %s | Level: %d | Skin ID: %d | Gender: %s",
                    char.name, char.level, char.skin, char.gender or "Unknown"
                )
                guiSetText(infoPanel, info)
                guiSetEnabled(playBtn, true)
                guiSetEnabled(deleteBtn, true)
            end
        end
    end, false)
    
    -- Play button
    addEventHandler("onClientGUIClick", playBtn, function()
        if selectedCharIndex and characterList[selectedCharIndex] then
            local charName = characterList[selectedCharIndex].name
            triggerServerEvent("onCharacterSelect", resourceRoot, charName)
        end
    end, false)
    
    -- Create new button
    addEventHandler("onClientGUIClick", createBtn, function()
        hideCharacterSelectWindow()
        triggerEvent("showCharacterCreation", root)
    end, false)
    
    -- Delete button
    addEventHandler("onClientGUIClick", deleteBtn, function()
        if selectedCharIndex and characterList[selectedCharIndex] then
            local charName = characterList[selectedCharIndex].name
            
            -- Confirmation dialog (simple version)
            local confirmMsg = "Are you sure you want to delete '" .. charName .. "'?\nThis action cannot be undone!"
            outputChatBox(confirmMsg, 255, 0, 0)
            outputChatBox("Type /confirmdelete to confirm deletion", 255, 255, 0)
            
            -- Store character to delete
            charSelectElements.charToDelete = charName
        end
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
end

--------------------------------------------------------------------------------
-- SHOW/HIDE FUNCTIONS
--------------------------------------------------------------------------------

function showCharacterSelectWindow(characters)
    createCharacterSelectWindow(characters)
end

function hideCharacterSelectWindow()
    if charSelectWindow and isElement(charSelectWindow) then
        destroyElement(charSelectWindow)
        charSelectWindow = nil
        charSelectElements = {}  -- Clear element references
        showCursor(false)
        guiSetInputMode("allow_binds")
        selectedCharIndex = nil
    end
end

--------------------------------------------------------------------------------
-- SERVER EVENT HANDLERS
--------------------------------------------------------------------------------

-- Server triggers this with character list
addEvent("showCharacterSelect", true)
addEventHandler("showCharacterSelect", root, function(characters)
    -- Hide other windows first
    triggerEvent("hideLoginGUI", root)
    triggerEvent("hideCharCreateGUI", root)
    showCharacterSelectWindow(characters)
end)

-- Hide character select GUI specifically
addEvent("hideCharSelectGUI", true)
addEventHandler("hideCharSelectGUI", root, function()
    hideCharacterSelectWindow()
end)

-- Hide all GUI (global event)
addEvent("hideAllGUI", true)
addEventHandler("hideAllGUI", root, function()
    hideCharacterSelectWindow()
    triggerEvent("hideLoginGUI", root)
    triggerEvent("hideCharCreateGUI", root)
end)

-- Clean up on resource stop
addEventHandler("onClientResourceStop", resourceRoot, function()
    hideCharacterSelectWindow()
end)

--------------------------------------------------------------------------------
-- COMMANDS
--------------------------------------------------------------------------------

-- Confirm character deletion
addCommandHandler("confirmdelete", function()
    if charSelectWindow and charSelectElements.charToDelete then
        local charName = charSelectElements.charToDelete
        triggerServerEvent("onCharacterDelete", resourceRoot, charName)
        charSelectElements.charToDelete = nil
    else
        outputChatBox("No character selected for deletion", 255, 0, 0)
    end
end)
