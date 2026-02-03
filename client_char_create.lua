-- client_char_create.lua
-- D&D-style character creation GUI with stat allocation + skin preview

local window
local remainingLabel
local statInfoLabel
local nameEdit
local maleRadio
local femaleRadio
local skinLabel
local previewLabel

local previewPed = nil
local rotateTimer = nil

-- Stat system
local BASE_STAT = 8
local MAX_STAT = 18
local STAT_POOL = 27

local stats = {
    STR = 8,
    DEX = 8,
    CON = 8,
    INT = 8,
    WIS = 8,
    CHA = 8
}

local statDesc = {
    STR = "Strength: melee damage, carry weight",
    DEX = "Dexterity: gun skill, movement",
    CON = "Constitution: health, stamina",
    INT = "Intelligence: XP, skills",
    WIS = "Wisdom: awareness, resistances",
    CHA = "Charisma: NPC reactions"
}

-- Skin categories
local maleSkins = {0, 1, 2, 7, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 32, 33, 34, 35, 36, 37, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 57, 58, 59, 60, 61, 62, 66, 67, 68, 70, 71, 72, 73, 78, 79, 80, 81, 82, 83, 84}
local femaleSkins = {9, 10, 11, 12, 13, 31, 38, 39, 40, 41, 53, 54, 55, 56, 63, 64, 65, 69, 75, 76, 77, 85, 87, 88, 89, 90, 91, 92, 93}

local currentSkinID = 0

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function remainingPoints()
    local spent = 0
    for _, v in pairs(stats) do
        spent = spent + (v - BASE_STAT)
    end
    return STAT_POOL - spent
end

local function updateRemaining()
    if remainingLabel and isElement(remainingLabel) then
        guiSetText(remainingLabel, "Remaining points: " .. remainingPoints())
    end
end

function findSkinIndex(skins, skinID)
    for i, id in ipairs(skins) do
        if id == skinID then
            return i
        end
    end
    return 1
end

function updateSkinPreview()
    outputChatBox("updateSkinPreview called! Skin ID: " .. currentSkinID, 255, 255, 0)
    
    if not skinLabel or not isElement(skinLabel) then
        outputChatBox("ERROR: skinLabel is nil!", 255, 0, 0)
        return
    end
    
    -- Update label
    guiSetText(skinLabel, "Skin ID: " .. currentSkinID)
    
    -- Kill existing rotate timer
    if rotateTimer and isTimer(rotateTimer) then
        killTimer(rotateTimer)
        rotateTimer = nil
    end
    
    -- Destroy old preview ped
    if previewPed and isElement(previewPed) then
        destroyElement(previewPed)
    end
    
    -- Get player position (or use Los Santos spawn if not spawned yet)
    local x, y, z = 1958.33, -1714.46, 20  -- Los Santos spawn point
    local rotZ = 0
    
    if localPlayer and isElement(localPlayer) then
        local px, py, pz = getElementPosition(localPlayer)
        -- Only use player position if they're actually spawned somewhere real
        if px ~= 0 or py ~= 0 then
            x, y, z = px, py, pz
            local rotX, rotY
            rotX, rotY, rotZ = getElementRotation(localPlayer)
            
            -- Calculate position 3 units in front
            local radians = math.rad(rotZ)
            local offsetX = math.sin(radians) * 3
            local offsetY = math.cos(radians) * 3
            
            x = x + offsetX
            y = y + offsetY
        end
    end
    
    outputChatBox("Creating ped at: " .. x .. ", " .. y .. ", " .. z, 255, 255, 0)
    previewPed = createPed(currentSkinID, x, y, z)
    
    if previewPed then
        outputChatBox("Preview ped created successfully!", 0, 255, 0)
        setElementRotation(previewPed, 0, 0, 180)  -- Face camera
        setElementFrozen(previewPed, true)
        setElementInterior(previewPed, 0)
        setElementDimension(previewPed, 0)
        
        -- Set camera to look at ped from the front
        local pedX, pedY, pedZ = getElementPosition(previewPed)
        
        -- Camera position: 3 units in front, slightly up
        local cameraX = pedX
        local cameraY = pedY - 3
        local cameraZ = pedZ + 0.8
        
        -- Set player interior/dimension to match
        setElementInterior(localPlayer, 0)
        setElementDimension(localPlayer, 0)
        
        setCameraMatrix(cameraX, cameraY, cameraZ, pedX, pedY, pedZ + 0.5)
        fadeCamera(true)
        
        -- Start rotation timer
        rotateTimer = setTimer(function()
            if previewPed and isElement(previewPed) then
                local rx, ry, rz = getElementRotation(previewPed)
                setElementRotation(previewPed, rx, ry, rz + 2)
            end
        end, 50, 0)
        
        -- Update info label
        if previewLabel and isElement(previewLabel) then
            guiSetText(previewLabel, "Preview rotating in front of you")
            guiLabelSetColor(previewLabel, 0, 255, 0)
        end
    else
        outputChatBox("FAILED to create preview ped!", 255, 0, 0)
    end
end

--------------------------------------------------------------------------------
-- CREATE WINDOW
--------------------------------------------------------------------------------

function showCharacterCreationWindow()
    outputChatBox("=== SHOWING CHARACTER CREATION WINDOW ===", 0, 255, 255)
    
    -- Close existing window
    if window and isElement(window) then 
        destroyElement(window) 
    end

    -- Hide other GUIs
    triggerEvent("hideLoginGUI", root)
    triggerEvent("hideCharSelectGUI", root)

    -- Reset stats to base values
    for k in pairs(stats) do
        stats[k] = BASE_STAT
    end

    local sw, sh = guiGetScreenSize()
    window = guiCreateWindow(sw/2 - 300, sh/2 - 320, 600, 640, "Create Character", false)
    guiWindowSetSizable(window, false)

    -- Name input
    guiCreateLabel(20, 40, 100, 25, "Name:", false, window)
    nameEdit = guiCreateEdit(130, 40, 440, 25, "", false, window)
    guiEditSetMaxLength(nameEdit, 20)
    
    -- Keep input mode when clicking on name field
    addEventHandler("onClientGUIClick", nameEdit, function()
        guiBringToFront(nameEdit)
        guiSetInputMode("no_binds_when_editing")
    end, false)
    
    addEventHandler("onClientGUIFocus", nameEdit, function()
        guiSetInputMode("no_binds_when_editing")
    end, false)

    -- Gender selection
    guiCreateLabel(20, 75, 100, 25, "Gender:", false, window)
    maleRadio = guiCreateRadioButton(130, 75, 100, 25, "Male", true, window)
    femaleRadio = guiCreateRadioButton(240, 75, 100, 25, "Female", true, window)
    guiRadioButtonSetSelected(maleRadio, true)
    
    -- Gender change handlers
    addEventHandler("onClientGUIClick", maleRadio, function()
        currentSkinID = maleSkins[1]
        updateSkinPreview()
    end, false)
    
    addEventHandler("onClientGUIClick", femaleRadio, function()
        currentSkinID = femaleSkins[1]
        updateSkinPreview()
    end, false)

    -- Skin selection
    guiCreateLabel(20, 110, 560, 25, "Skin (use arrows to browse):", false, window)
    
    local prevSkinBtn = guiCreateButton(20, 140, 80, 30, "< Previous", false, window)
    skinLabel = guiCreateLabel(110, 140, 380, 30, "Skin ID: 0", false, window)
    guiLabelSetHorizontalAlign(skinLabel, "center")
    guiLabelSetVerticalAlign(skinLabel, "center")
    guiSetFont(skinLabel, "default-bold-small")
    local nextSkinBtn = guiCreateButton(500, 140, 80, 30, "Next >", false, window)
    
    -- Preview info
    previewLabel = guiCreateLabel(20, 175, 560, 25, "Preview will appear in front of you", false, window)
    guiLabelSetHorizontalAlign(previewLabel, "center")
    guiLabelSetColor(previewLabel, 200, 200, 200)
    
    -- Skin navigation handlers
    addEventHandler("onClientGUIClick", prevSkinBtn, function()
        local skins = guiRadioButtonGetSelected(maleRadio) and maleSkins or femaleSkins
        local currentIndex = findSkinIndex(skins, currentSkinID)
        
        currentIndex = currentIndex - 1
        if currentIndex < 1 then
            currentIndex = #skins
        end
        
        currentSkinID = skins[currentIndex]
        updateSkinPreview()
    end, false)
    
    addEventHandler("onClientGUIClick", nextSkinBtn, function()
        local skins = guiRadioButtonGetSelected(maleRadio) and maleSkins or femaleSkins
        local currentIndex = findSkinIndex(skins, currentSkinID)
        
        currentIndex = currentIndex + 1
        if currentIndex > #skins then
            currentIndex = 1
        end
        
        currentSkinID = skins[currentIndex]
        updateSkinPreview()
    end, false)

    -- Attributes header
    local attributesLabel = guiCreateLabel(20, 215, 560, 25, "=== D&D Attributes ===", false, window)
    guiSetFont(attributesLabel, "default-bold-small")
    guiLabelSetHorizontalAlign(attributesLabel, "center")

    local y = 250
    local valueLabels = {}

    -- Create stat allocation UI for each stat (in order)
    for _, statName in ipairs({"STR", "DEX", "CON", "INT", "WIS", "CHA"}) do
        local value = stats[statName]
        
        -- Stat name label
        local statNameLabel = guiCreateLabel(20, y, 60, 22, statName, false, window)
        guiSetFont(statNameLabel, "default-bold-small")
        
        -- Current value label
        local valLabel = guiCreateLabel(90, y, 40, 22, tostring(value), false, window)
        guiLabelSetHorizontalAlign(valLabel, "center")
        guiSetFont(valLabel, "default-bold-small")

        -- Minus button
        local minus = guiCreateButton(140, y, 30, 22, "-", false, window)
        
        -- Plus button
        local plus = guiCreateButton(175, y, 30, 22, "+", false, window)
        
        -- Description label (shows on same line)
        local descLabel = guiCreateLabel(215, y, 365, 22, statDesc[statName], false, window)

        -- Show description on hover over value
        addEventHandler("onClientMouseEnter", valLabel, function()
            if statInfoLabel and isElement(statInfoLabel) then
                guiSetText(statInfoLabel, statDesc[statName])
                guiLabelSetColor(statInfoLabel, 255, 255, 0)
            end
        end, false)
        
        addEventHandler("onClientMouseLeave", valLabel, function()
            if statInfoLabel and isElement(statInfoLabel) then
                guiSetText(statInfoLabel, "Hover over a stat value to see its description")
                guiLabelSetColor(statInfoLabel, 200, 200, 200)
            end
        end, false)

        -- Minus button handler
        addEventHandler("onClientGUIClick", minus, function()
            if stats[statName] > BASE_STAT then
                stats[statName] = stats[statName] - 1
                guiSetText(valLabel, tostring(stats[statName]))
                updateRemaining()
            end
        end, false)

        -- Plus button handler
        addEventHandler("onClientGUIClick", plus, function()
            if stats[statName] < MAX_STAT and remainingPoints() > 0 then
                stats[statName] = stats[statName] + 1
                guiSetText(valLabel, tostring(stats[statName]))
                updateRemaining()
            end
        end, false)

        valueLabels[statName] = valLabel
        y = y + 30
    end

    -- Remaining points label
    remainingLabel = guiCreateLabel(20, y + 10, 560, 25, "", false, window)
    guiSetFont(remainingLabel, "default-bold-small")
    guiLabelSetColor(remainingLabel, 255, 255, 0)
    updateRemaining()

    -- Stat info label (shows descriptions on hover)
    statInfoLabel = guiCreateLabel(20, y + 40, 560, 30, "Hover over a stat value to see its description", false, window)
    guiLabelSetColor(statInfoLabel, 200, 200, 200)

    -- Create button
    local createBtn = guiCreateButton(60, 580, 200, 40, "Create Character", false, window)
    
    -- Cancel button
    local cancelBtn = guiCreateButton(340, 580, 200, 40, "Cancel", false, window)

    -- Create button handler
    addEventHandler("onClientGUIClick", createBtn, function()
        local charName = guiGetText(nameEdit)
        
        -- Validate name
        if charName == "" then
            guiSetText(statInfoLabel, "Please enter a character name!")
            guiLabelSetColor(statInfoLabel, 255, 0, 0)
            return
        end
        
        if #charName < 3 or #charName > 20 then
            guiSetText(statInfoLabel, "Name must be 3-20 characters!")
            guiLabelSetColor(statInfoLabel, 255, 0, 0)
            return
        end
        
        -- Validate stats - must use all points
        if remainingPoints() ~= 0 then
            guiSetText(statInfoLabel, "You must spend all " .. STAT_POOL .. " stat points!")
            guiLabelSetColor(statInfoLabel, 255, 255, 0)
            return
        end
        
        -- Get gender
        local gender = guiRadioButtonGetSelected(maleRadio) and "Male" or "Female"
        
        outputChatBox("Creating character: " .. charName, 0, 255, 0)
        outputChatBox("Gender: " .. gender, 0, 255, 0)
        outputChatBox("Skin: " .. currentSkinID, 0, 255, 0)
        outputChatBox("Stats: STR=" .. stats.STR .. " DEX=" .. stats.DEX .. " CON=" .. stats.CON, 0, 255, 0)
        
        -- Send to server - pass name, stats table, gender, and skin ID
        triggerServerEvent("onCharacterCreate", resourceRoot, charName, stats, gender, currentSkinID)
        
        -- Hide window
        hideCharacterCreationWindow()
    end, false)

    -- Cancel button handler
    addEventHandler("onClientGUIClick", cancelBtn, function()
        hideCharacterCreationWindow()
        -- Request to go back to character select
        triggerServerEvent("onPlayerRequestCharSelect", resourceRoot)
    end, false)

    -- Initialize with first male skin
    currentSkinID = maleSkins[1]
    updateSkinPreview()

    -- Enable cursor and input - FORCE IT MULTIPLE TIMES
    showCursor(true, true)
    guiSetInputMode("no_binds_when_editing")
    
    -- Force again with small delay to ensure it works
    setTimer(function()
        showCursor(true, true)
        guiSetInputMode("no_binds_when_editing")
    end, 100, 1)
    
    -- And once more for good measure
    setTimer(function()
        showCursor(true, true)
    end, 250, 1)
    
    outputChatBox("Character creation window shown!", 0, 255, 0)
end

function hideCharacterCreationWindow()
    -- Kill rotate timer
    if rotateTimer and isTimer(rotateTimer) then
        killTimer(rotateTimer)
        rotateTimer = nil
    end
    
    -- Destroy window
    if window and isElement(window) then
        destroyElement(window)
        window = nil
    end
    
    -- Destroy preview ped
    if previewPed and isElement(previewPed) then
        destroyElement(previewPed)
        previewPed = nil
    end
    
    -- Restore camera to player
    setCameraTarget(localPlayer)
    
    -- Clear references
    nameEdit = nil
    remainingLabel = nil
    statInfoLabel = nil
    maleRadio = nil
    femaleRadio = nil
    skinLabel = nil
    previewLabel = nil
    
    showCursor(false)
    guiSetInputMode("allow_binds")
end

--------------------------------------------------------------------------------
-- SERVER EVENT HANDLERS
--------------------------------------------------------------------------------

-- Server triggers this to show character creation
addEvent("showCharacterCreation", true)
addEventHandler("showCharacterCreation", root, function()
    outputChatBox("=== RECEIVED showCharacterCreation EVENT ===", 255, 0, 255)
    
    -- Hide other windows first
    triggerEvent("hideLoginGUI", root)
    triggerEvent("hideCharSelectGUI", root)
    
    showCharacterCreationWindow()
    
    -- Force cursor on
    showCursor(true, true)
    guiSetInputMode("no_binds_when_editing")
end)

-- Hide character creation GUI specifically
addEvent("hideCharCreateGUI", true)
addEventHandler("hideCharCreateGUI", root, function()
    hideCharacterCreationWindow()
end)

-- Clean up on resource stop
addEventHandler("onClientResourceStop", resourceRoot, function()
    hideCharacterCreationWindow()
end)

outputChatBox("===== CLIENT_CHAR_CREATE.LUA LOADED =====", 255, 255, 0)
