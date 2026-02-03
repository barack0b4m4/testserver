-- MTA San Andreas: Character Creation GUI (Client-side)

local charCreateWindow = nil
local charCreateElements = {}  -- Separate table for storing element references
local currentSkinID = 0
local previewPed = nil
local rotateTimer = nil  -- FIX: Track timer so we can kill it

-- GUI dimensions
local screenW, screenH = guiGetScreenSize()
local windowW, windowH = 500, 400
local windowX = (screenW - windowW) / 2
local windowY = (screenH - windowH) / 2

-- Skin categories
local maleSkins = {0, 1, 2, 7, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 32, 33, 34, 35, 36, 37, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 57, 58, 59, 60, 61, 62, 66, 67, 68, 70, 71, 72, 73, 78, 79, 80, 81, 82, 83, 84}
local femaleSkins = {9, 10, 11, 12, 13, 31, 38, 39, 40, 41, 53, 54, 55, 56, 63, 64, 65, 69, 75, 76, 77, 85, 87, 88, 89, 90, 91, 92, 93}

--------------------------------------------------------------------------------
-- CREATE CHARACTER CREATION WINDOW
--------------------------------------------------------------------------------

function createCharacterCreationWindow()
    outputChatBox("=== CREATE CHARACTER CREATION WINDOW ===", 0, 255, 255)
    
    if charCreateWindow and isElement(charCreateWindow) then
        destroyElement(charCreateWindow)
    end
    
    -- Main window
    charCreateWindow = guiCreateWindow(windowX, windowY, windowW, windowH, "Create Your Character", false)
    guiWindowSetSizable(charCreateWindow, false)
    
    outputChatBox("Window created!", 0, 255, 255)
    
    -- Title
    local titleLabel = guiCreateLabel(0.1, 0.05, 0.8, 0.08, "Customize your character", true, charCreateWindow)
    guiSetFont(titleLabel, "default-bold-small")
    guiLabelSetHorizontalAlign(titleLabel, "center")
    
    -- Character Name
    guiCreateLabel(0.1, 0.15, 0.3, 0.08, "Character Name:", true, charCreateWindow)
    outputChatBox("Creating nameEdit...", 255, 255, 0)
    local nameEdit = guiCreateEdit(0.45, 0.15, 0.45, 0.08, "", true, charCreateWindow)
    outputChatBox("nameEdit created: " .. tostring(nameEdit), 255, 255, 0)
    
    if nameEdit then
        outputChatBox("nameEdit is valid, setting max length...", 255, 255, 0)
        guiEditSetMaxLength(nameEdit, 20)
        
        outputChatBox("Adding event handlers to nameEdit...", 255, 255, 0)
        -- Keep input mode when clicking on name field
        addEventHandler("onClientGUIClick", nameEdit, function()
            guiBringToFront(nameEdit)
            guiSetInputMode("no_binds_when_editing")
        end, false)
        
        addEventHandler("onClientGUIFocus", nameEdit, function()
            guiSetInputMode("no_binds_when_editing")
        end, false)
        outputChatBox("Event handlers added to nameEdit", 255, 255, 0)
    else
        outputChatBox("ERROR: nameEdit is NIL!", 255, 0, 0)
    end
    
    -- Gender selection
    guiCreateLabel(0.1, 0.27, 0.3, 0.08, "Gender:", true, charCreateWindow)
    local maleRadio = guiCreateRadioButton(0.45, 0.27, 0.2, 0.08, "Male", true, charCreateWindow)
    local femaleRadio = guiCreateRadioButton(0.70, 0.27, 0.2, 0.08, "Female", true, charCreateWindow)
    guiRadioButtonSetSelected(maleRadio, true)
    
    -- Skin selection
    guiCreateLabel(0.1, 0.39, 0.8, 0.08, "Skin (use arrows to browse):", true, charCreateWindow)
    
    local prevSkinBtn = guiCreateButton(0.1, 0.50, 0.15, 0.10, "<", true, charCreateWindow)
    local skinLabel = guiCreateLabel(0.30, 0.50, 0.4, 0.10, "Skin ID: 0", true, charCreateWindow)
    guiLabelSetHorizontalAlign(skinLabel, "center")
    guiLabelSetVerticalAlign(skinLabel, "center")
    guiSetFont(skinLabel, "default-bold-small")
    local nextSkinBtn = guiCreateButton(0.75, 0.50, 0.15, 0.10, ">", true, charCreateWindow)
    
    -- Preview info
    local previewLabel = guiCreateLabel(0.1, 0.65, 0.8, 0.08, "Preview will appear in front of you", true, charCreateWindow)
    guiLabelSetHorizontalAlign(previewLabel, "center")
    guiLabelSetColor(previewLabel, 200, 200, 200)
    
    -- Buttons
    outputChatBox("Creating buttons...", 0, 255, 255)
    local createBtn = guiCreateButton(0.1, 0.78, 0.35, 0.15, "Create", true, charCreateWindow)
    local cancelBtn = guiCreateButton(0.55, 0.78, 0.35, 0.15, "Cancel", true, charCreateWindow)
    outputChatBox("Buttons created", 0, 255, 255)
    
    -- Store elements
    outputChatBox("Storing elements...", 0, 255, 255)
    
    if not charCreateWindow or not isElement(charCreateWindow) then
        outputChatBox("ERROR: charCreateWindow is invalid!", 255, 0, 0)
        return
    end
    
    -- Store in separate table, not on the GUI element
    charCreateElements.nameEdit = nameEdit
    charCreateElements.maleRadio = maleRadio
    charCreateElements.femaleRadio = femaleRadio
    charCreateElements.skinLabel = skinLabel
    charCreateElements.previewLabel = previewLabel
    
    outputChatBox("Elements stored successfully", 0, 255, 0)
    
    -- Initialize with first male skin
    outputChatBox("Initializing skin...", 0, 255, 255)
    currentSkinID = maleSkins[1]
    outputChatBox("About to call updateSkinPreview, currentSkinID = " .. currentSkinID, 255, 255, 0)
    
    local success, err = pcall(updateSkinPreview)
    if not success then
        outputChatBox("ERROR calling updateSkinPreview: " .. tostring(err), 255, 0, 0)
    else
        outputChatBox("updateSkinPreview completed successfully", 0, 255, 0)
    end
    
    -- Gender radio button handlers
    addEventHandler("onClientGUIClick", maleRadio, function()
        currentSkinID = maleSkins[1]
        updateSkinPreview()
    end, false)
    
    addEventHandler("onClientGUIClick", femaleRadio, function()
        currentSkinID = femaleSkins[1]
        updateSkinPreview()
    end, false)
    
    -- Skin navigation buttons
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
    
    -- Create button
    addEventHandler("onClientGUIClick", createBtn, function()
        local charName = guiGetText(nameEdit)
        
        if charName == "" then
            guiSetText(previewLabel, "Please enter a character name!")
            guiLabelSetColor(previewLabel, 255, 0, 0)
            return
        end
        
        if #charName < 3 or #charName > 20 then
            guiSetText(previewLabel, "Name must be 3-20 characters!")
            guiLabelSetColor(previewLabel, 255, 0, 0)
            return
        end
        
        local gender = guiRadioButtonGetSelected(maleRadio) and "male" or "female"
        
        triggerServerEvent("onCharacterCreate", resourceRoot, charName, currentSkinID, gender)
        hideCharacterCreationWindow()
    end, false)
    
    -- Cancel button - FIX: Use correct event name
    addEventHandler("onClientGUIClick", cancelBtn, function()
        hideCharacterCreationWindow()
        triggerServerEvent("onPlayerRequestCharSelect", resourceRoot)
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
    
    outputChatBox("=== WINDOW CREATION COMPLETE ===", 0, 255, 0)
end

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

function findSkinIndex(skins, skinID)
    for i, id in ipairs(skins) do
        if id == skinID then
            return i
        end
    end
    return 1
end

function updateSkinPreview()
    outputChatBox("updateSkinPreview called!", 255, 0, 255)
    
    if not charCreateElements.skinLabel then
        outputChatBox("ERROR: skinLabel is nil!", 255, 0, 0)
        return
    end
    
    outputChatBox("=== UPDATE SKIN PREVIEW ===", 255, 255, 0)
    outputChatBox("Current skin ID: " .. currentSkinID, 255, 255, 0)
    
    -- Update label
    guiSetText(charCreateElements.skinLabel, "Skin ID: " .. currentSkinID)
    
    -- FIX: Kill existing rotate timer before creating new one
    if rotateTimer and isTimer(rotateTimer) then
        killTimer(rotateTimer)
        rotateTimer = nil
    end
    
    -- Destroy old preview ped
    if previewPed and isElement(previewPed) then
        outputChatBox("Destroying old preview ped", 255, 255, 0)
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
            
            outputChatBox("Using player position: " .. x .. ", " .. y .. ", " .. z, 255, 255, 0)
            
            -- Calculate position 3 units in front
            local radians = math.rad(rotZ)
            local offsetX = math.sin(radians) * 3
            local offsetY = math.cos(radians) * 3
            
            x = x + offsetX
            y = y + offsetY
        else
            outputChatBox("Using Los Santos spawn position", 255, 255, 0)
        end
    else
        outputChatBox("Using Los Santos spawn position", 255, 255, 0)
    end
    
    outputChatBox("Creating ped at: " .. x .. ", " .. y .. ", " .. z, 255, 255, 0)
    previewPed = createPed(currentSkinID, x, y, z)
    
    if previewPed then
        outputChatBox("Preview ped created successfully!", 0, 255, 0)
        setElementRotation(previewPed, 0, 0, 180)  -- Face camera (180 degrees)
        setElementFrozen(previewPed, true)
        setElementInterior(previewPed, 0)
        setElementDimension(previewPed, 0)
        
        -- Set camera to look at ped from the front
        local pedX, pedY, pedZ = getElementPosition(previewPed)
        outputChatBox("Ped position: " .. pedX .. ", " .. pedY .. ", " .. pedZ, 255, 255, 0)
        
        -- Camera position: 3 units in front, 1 unit up
        local cameraX = pedX
        local cameraY = pedY - 3
        local cameraZ = pedZ + 0.8
        
        outputChatBox("Setting camera to: " .. cameraX .. ", " .. cameraY .. ", " .. cameraZ, 255, 255, 0)
        
        -- Set player interior/dimension to match
        setElementInterior(localPlayer, 0)
        setElementDimension(localPlayer, 0)
        
        setCameraMatrix(cameraX, cameraY, cameraZ, pedX, pedY, pedZ + 0.5)
        fadeCamera(true)  -- Fade camera in
        
        outputChatBox("Camera positioned to view ped", 0, 255, 0)
        
        -- FIX: Store timer reference so we can kill it later
        rotateTimer = setTimer(function()
            if previewPed and isElement(previewPed) then
                local rx, ry, rz = getElementRotation(previewPed)
                setElementRotation(previewPed, rx, ry, rz + 2)
            end
        end, 50, 0)
    else
        outputChatBox("FAILED to create preview ped!", 255, 0, 0)
    end
end

--------------------------------------------------------------------------------
-- SHOW/HIDE FUNCTIONS
--------------------------------------------------------------------------------

function showCharacterCreationWindow()
    outputChatBox("=== SHOW CHARACTER CREATION WINDOW CALLED ===", 255, 0, 255)
    
    -- Force cursor on FIRST
    showCursor(true, true)
    guiSetInputMode("no_binds_when_editing")
    
    outputChatBox("Calling createCharacterCreationWindow...", 255, 0, 255)
    createCharacterCreationWindow()
    
    outputChatBox("Window created, forcing cursor again...", 255, 0, 255)
    -- Force cursor again after window creation
    showCursor(true, true)
    
    -- And one more time delayed to be sure
    setTimer(function()
        showCursor(true, true)
        guiSetInputMode("no_binds_when_editing")
        outputChatBox("Delayed cursor force complete", 255, 0, 255)
    end, 100, 1)
end

function hideCharacterCreationWindow()
    -- FIX: Kill rotate timer
    if rotateTimer and isTimer(rotateTimer) then
        killTimer(rotateTimer)
        rotateTimer = nil
    end
    
    if charCreateWindow and isElement(charCreateWindow) then
        destroyElement(charCreateWindow)
        charCreateWindow = nil
    end
    
    -- Clear element references
    charCreateElements = {}
    
    if previewPed and isElement(previewPed) then
        destroyElement(previewPed)
        previewPed = nil
    end
    
    -- Restore camera to player
    setCameraTarget(localPlayer)
    
    showCursor(false)
    guiSetInputMode("allow_binds")
end

--------------------------------------------------------------------------------
-- SERVER EVENT HANDLERS
--------------------------------------------------------------------------------

-- Server triggers this
addEvent("showCharacterCreation", true)
addEventHandler("showCharacterCreation", root, function()
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
