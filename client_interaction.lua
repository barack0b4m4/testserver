-- client_interaction.lua (CLIENT)
-- Context menu system for players and DMs
-- Includes: Click menus, POI examination, Property creation GUI, Object highlighting

local screenW, screenH = guiGetScreenSize()

--------------------------------------------------------------------------------
-- VARIABLES
--------------------------------------------------------------------------------

-- Context menu
local contextMenu = nil
local contextElements = {}
local contextTarget = nil
local contextTargetType = nil
local contextWorldPos = nil

-- Property creation GUI
local propertyWindow = nil
local propertyElements = {}

-- POI creation/edit GUI
local poiWindow = nil
local poiElements = {}
local editingPOI = nil

-- Object highlighting
local highlightedObjects = {}
local HIGHLIGHT_ALPHA = 180

-- Selection for DM actions
local selectedObjects = {}
local SELECT_ALPHA = 155

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

local function getElementUnderCursor()
    local cursorX, cursorY = getCursorPosition()
    if not cursorX then return nil end
    
    cursorX, cursorY = cursorX * screenW, cursorY * screenH
    
    local worldX, worldY, worldZ = getWorldFromScreenPosition(cursorX, cursorY, 300)
    local camX, camY, camZ = getCameraMatrix()
    
    local hit, hitX, hitY, hitZ, hitElement = processLineOfSight(
        camX, camY, camZ,
        worldX, worldY, worldZ,
        true, true, true, true, true, false, false, true
    )
    
    return hitElement, hitX, hitY, hitZ
end

local function isPlayerDM()
    return getElementData(localPlayer, "isDungeonMaster") == true
end

local function isDMMode()
    return getElementData(localPlayer, "dm.mode") == true
end

local function getTargetType(element)
    if not element then return "world" end
    
    local elementType = getElementType(element)
    
    if elementType == "player" then
        return "player"
    elseif elementType == "ped" then
        if getElementData(element, "isNPC") then
            return "npc"
        elseif getElementData(element, "isShopkeeper") then
            return "shopkeeper"
        end
        return "ped"
    elseif elementType == "marker" then
        -- Check if it's a POI marker
        local isPOI = getElementData(element, "isPOI")
        outputDebugString("[DEBUG] Found marker! isPOI data: " .. tostring(isPOI) .. " (type: " .. type(isPOI) .. ")")
        
        -- Check both string "true" and boolean true
        if isPOI == "true" or isPOI == true then
            outputDebugString("[DEBUG] Marker identified as POI!")
            return "poi"
        end
        return "marker"
    elseif elementType == "object" then
        local isPOI = getElementData(element, "isPOI")
        -- Check both string "true" and boolean true
        if isPOI == "true" or isPOI == true then
            return "poi"
        elseif getElementData(element, "property.entrance") then
            return "property_entrance"
        end
        return "object"
    elseif elementType == "vehicle" then
        return "vehicle"
    end
    
    return "unknown"
end

--------------------------------------------------------------------------------
-- CONTEXT MENU SYSTEM
--------------------------------------------------------------------------------

local function closeContextMenu()
    if contextMenu and isElement(contextMenu) then
        destroyElement(contextMenu)
        contextMenu = nil
        contextElements = {}
        contextTarget = nil
        contextTargetType = nil
        contextWorldPos = nil
    end
end

local function createContextMenu(x, y, options)
    closeContextMenu()
    
    local menuWidth = 200
    local itemHeight = 28
    local titleBarHeight = 24
    local padding = 5
    local menuHeight = titleBarHeight + (#options * itemHeight) + (padding * 2)
    
    -- Adjust position to stay on screen
    if x + menuWidth > screenW then x = screenW - menuWidth - 10 end
    if y + menuHeight > screenH then y = screenH - menuHeight - 10 end
    if x < 0 then x = 10 end
    if y < 0 then y = 10 end
    
    contextMenu = guiCreateWindow(x, y, menuWidth, menuHeight, "Actions", false)
    guiWindowSetSizable(contextMenu, false)
    guiWindowSetMovable(contextMenu, false)
    guiSetAlpha(contextMenu, 0.95)
    
    for i, option in ipairs(options) do
        local btnY = titleBarHeight + padding + ((i-1) * itemHeight)
        local btn = guiCreateButton(padding, btnY, menuWidth - (padding * 2), itemHeight - 3, option.label, false, contextMenu)
        
        if option.color then
            guiSetProperty(btn, "NormalTextColour", option.color)
        end
        
        if option.disabled then
            guiSetEnabled(btn, false)
        end
        
        contextElements[btn] = option.action
        
        addEventHandler("onClientGUIClick", btn, function()
            local action = contextElements[source]
            if action then
                action(contextTarget, contextTargetType, contextWorldPos)
            end
            closeContextMenu()
        end, false)
    end
    
    showCursor(true)
end

--------------------------------------------------------------------------------
-- PLAYER CONTEXT MENU OPTIONS
--------------------------------------------------------------------------------

local function getPlayerMenuOptions(target, targetType)
    local options = {}
    
    -- Interact option (default click action)
    if targetType == "shopkeeper" then
        table.insert(options, {
            label = "Talk / Shop",
            action = function(t)
                local shopID = getElementData(t, "shop.id")
                if shopID then
                    triggerServerEvent("shop:requestOpen", localPlayer, shopID)
                end
            end
        })
    elseif targetType == "npc" then
        table.insert(options, {
            label = "Talk",
            action = function(t)
                local npcName = getElementData(t, "npc.name") or "NPC"
                outputChatBox("You approach " .. npcName .. "...", 200, 200, 200)
            end
        })
    elseif targetType == "player" then
        table.insert(options, {
            label = "Wave",
            action = function(t)
                local playerName = getPlayerName(t)
                triggerServerEvent("interaction:wave", localPlayer, t)
            end
        })
    elseif targetType == "property_entrance" then
        table.insert(options, {
            label = "Enter Property",
            action = function(t)
                local propID = getElementData(t, "property.id")
                if propID then
                    triggerServerEvent("property:enter", localPlayer, propID)
                end
            end
        })
    elseif targetType == "poi" then
        -- Players can examine POIs
        table.insert(options, {
            label = "Examine",
            action = function(t, tt)
                triggerServerEvent("interaction:examine", localPlayer, t, tt)
            end
        })
    elseif targetType == "vehicle" then
        table.insert(options, {
            label = "Enter Vehicle",
            action = function(t)
                -- Default vehicle entry
            end
        })
    end
    
    -- Examine option (available for most things, but not POIs since they already have it)
    if targetType ~= "world" and targetType ~= "poi" then
        table.insert(options, {
            label = "Examine",
            action = function(t, tt)
                triggerServerEvent("interaction:examine", localPlayer, t, tt)
            end
        })
    end
    
    -- Cancel
    table.insert(options, {
        label = "Cancel",
        color = "FF888888",
        action = function() end
    })
    
    return options
end

--------------------------------------------------------------------------------
-- DM CONTEXT MENU OPTIONS
--------------------------------------------------------------------------------

local function getDMMenuOptions(target, targetType, worldX, worldY, worldZ)
    local options = {}
    
    -- Header showing what was clicked
    local headerLabel = "-- " .. targetType:upper() .. " --"
    table.insert(options, {
        label = headerLabel,
        color = "FFFFA500",
        disabled = true,
        action = function() end
    })
    
    -- World position actions (always available)
    table.insert(options, {
        label = "Set Property Entrance Here",
        action = function(t, tt, pos)
            if pos then
                triggerServerEvent("dm:setPropertyEntrance", localPlayer, pos.x, pos.y, pos.z)
            end
        end
    })
    
    table.insert(options, {
        label = "Teleport Here",
        action = function(t, tt, pos)
            if pos then
                setElementPosition(localPlayer, pos.x, pos.y, pos.z + 1)
            end
        end
    })
    
    -- Create POI - available for objects OR world clicks
    if targetType == "object" or targetType == "poi" then
        table.insert(options, {
            label = "Create POI From Object",
            action = function(t)
                openPOICreator(t)
            end
        })
        
        table.insert(options, {
            label = "Toggle Highlight",
            action = function(t)
                toggleObjectHighlight(t)
            end
        })
        
        table.insert(options, {
            label = "Toggle Selection",
            action = function(t)
                toggleObjectSelection(t)
            end
        })
    else
        -- For non-object clicks, allow creating POI at world position
        table.insert(options, {
            label = "Create POI Here",
            action = function(t, tt, pos)
                openPOICreatorAtPosition(pos)
            end
        })
    end
    
    -- POI-specific options
    if targetType == "poi" then
        table.insert(options, {
            label = "Edit POI",
            color = "FF66FF66",
            action = function(t)
                local poiID = getElementData(t, "poi.id")
                if poiID then
                    triggerServerEvent("poi:requestEdit", localPlayer, poiID)
                end
            end
        })
        
        table.insert(options, {
            label = "Delete POI",
            color = "FFFF6666",
            action = function(t)
                local poiID = getElementData(t, "poi.id")
                if poiID then
                    triggerServerEvent("poi:delete", localPlayer, poiID)
                end
            end
        })
    end
    
    -- NPC/Ped options
    if targetType == "npc" or targetType == "ped" or targetType == "shopkeeper" then
        table.insert(options, {
            label = "Set Description",
            action = function(t)
                openDescriptionEditor(t, targetType)
            end
        })
    end
    
    -- Player options
    if targetType == "player" and target ~= localPlayer then
        table.insert(options, {
            label = "Set Player Description",
            action = function(t)
                openDescriptionEditor(t, "player")
            end
        })
    end
    
    -- Property entrance options
    if targetType == "property_entrance" then
        table.insert(options, {
            label = "Edit Property",
            action = function(t)
                local propID = getElementData(t, "property.id")
                if propID then
                    triggerServerEvent("property:requestEdit", localPlayer, propID)
                end
            end
        })
    end
    
    -- Separator
    table.insert(options, {
        label = "--------",
        color = "FF555555",
        disabled = true,
        action = function() end
    })
    
    -- Create property at this location
    table.insert(options, {
        label = "Create Property Here",
        color = "FF66FF66",
        action = function(t, tt, pos)
            openPropertyCreator(pos)
        end
    })
    
    -- Cancel
    table.insert(options, {
        label = "Cancel",
        color = "FF888888",
        action = function() end
    })
    
    return options
end

--------------------------------------------------------------------------------
-- CLICK HANDLER
--------------------------------------------------------------------------------

local function onClientClick(button, state, absX, absY, worldX, worldY, worldZ, clickedElement)
    if button ~= "right" or state ~= "down" then return end
    
    -- Don't open menu if GUI is already open
    if guiGetInputMode() ~= "allow_binds" then return end
    
    -- Close any existing menu
    closeContextMenu()
    
    local target = clickedElement
    local targetType = getTargetType(clickedElement)
    
    -- MARKER FIX: processLineOfSight doesn't detect markers, so check manually
    -- If we didn't hit anything specific, check for nearby markers
    if not target or targetType == "world" or targetType == "unknown" then
        -- Get accurate world position using processLineOfSight
        local cursorX, cursorY = getCursorPosition()
        if cursorX then
            cursorX, cursorY = cursorX * screenW, cursorY * screenH
            
            -- Get camera position
            local camX, camY, camZ = getCameraMatrix()
            
            -- Get far point for ray
            local farX, farY, farZ = getWorldFromScreenPosition(cursorX, cursorY, 300)
            
            -- Cast ray to find actual hit position
            local hit, hitX, hitY, hitZ = processLineOfSight(
                camX, camY, camZ,
                farX, farY, farZ,
                true, true, true, true, true, false, false, false
            )
            
            -- Use hit position if we got one, otherwise use the passed worldX/Y/Z
            local worldClickX, worldClickY, worldClickZ
            if hit and hitX then
                worldClickX, worldClickY, worldClickZ = hitX, hitY, hitZ
            else
                worldClickX, worldClickY, worldClickZ = worldX, worldY, worldZ
            end
            
            -- Find closest marker within 3 meters of click position
            local closestMarker = nil
            local closestDist = 3.0  -- 3 meter search radius
            
            for _, marker in ipairs(getElementsByType("marker")) do
                if isElement(marker) then
                    local mx, my, mz = getElementPosition(marker)
                    local dist = getDistanceBetweenPoints3D(worldClickX, worldClickY, worldClickZ, mx, my, mz)
                    
                    if dist < closestDist then
                        -- Check if marker is in same dimension/interior
                        local markerDim = getElementDimension(marker)
                        local markerInt = getElementInterior(marker)
                        local playerDim = getElementDimension(localPlayer)
                        local playerInt = getElementInterior(localPlayer)
                        
                        if markerDim == playerDim and markerInt == playerInt then
                            closestMarker = marker
                            closestDist = dist
                        end
                    end
                end
            end
            
            if closestMarker then
                target = closestMarker
                targetType = getTargetType(closestMarker)
                
                -- DEBUG: Check what we found
                outputChatBox("[DEBUG] Found marker! isPOI: " .. tostring(getElementData(closestMarker, "isPOI")), 255, 255, 0)
                outputChatBox("[DEBUG] Target type returned: " .. targetType, 255, 255, 0)
            end
        end
    end
    
    -- DEBUG: What are we working with?
    if target and targetType ~= "world" then
        outputChatBox("[DEBUG] Final target type: " .. targetType .. ", Element type: " .. getElementType(target), 200, 200, 200)
    end
    
    -- Store world position
    contextTarget = target
    contextTargetType = targetType
    contextWorldPos = {x = worldX, y = worldY, z = worldZ}
    
    local options
    if isDMMode() then
        outputChatBox("[DEBUG] Using DM menu", 0, 255, 255)
        options = getDMMenuOptions(target, targetType, worldX, worldY, worldZ)
    else
        outputChatBox("[DEBUG] Using player menu", 0, 255, 255)
        options = getPlayerMenuOptions(target, targetType)
    end
    
    outputChatBox("[DEBUG] Generated " .. #options .. " menu options", 200, 200, 200)
    
    if #options > 0 then
        createContextMenu(absX, absY, options)
    end
end

addEventHandler("onClientClick", root, onClientClick)

-- Close menu when clicking elsewhere
addEventHandler("onClientGUIClick", root, function()
    if source ~= contextMenu and not contextElements[source] then
        -- Check if click was outside menu
        if contextMenu and isElement(contextMenu) then
            local mx, my = guiGetPosition(contextMenu, false)
            local mw, mh = guiGetSize(contextMenu, false)
            local cx, cy = getCursorPosition()
            cx, cy = cx * screenW, cy * screenH
            
            if cx < mx or cx > mx + mw or cy < my or cy > my + mh then
                closeContextMenu()
            end
        end
    end
end)

-- Close menu on escape
bindKey("escape", "down", function()
    if contextMenu then
        closeContextMenu()
        showCursor(false)
    end
end)

--------------------------------------------------------------------------------
-- OBJECT HIGHLIGHTING (for DMs)
--------------------------------------------------------------------------------

function toggleObjectHighlight(object)
    if not object or not isElement(object) then return end
    
    if highlightedObjects[object] then
        -- Remove highlight
        setElementAlpha(object, 255)
        highlightedObjects[object] = nil
        outputChatBox("Object highlight removed", 200, 200, 200)
    else
        -- Add highlight
        setElementAlpha(object, HIGHLIGHT_ALPHA)
        highlightedObjects[object] = true
        outputChatBox("Object highlighted", 255, 200, 100)
    end
end

function toggleObjectSelection(object)
    if not object or not isElement(object) then return end
    
    if selectedObjects[object] then
        setElementAlpha(object, 255)
        selectedObjects[object] = nil
        outputChatBox("Object deselected", 200, 200, 200)
    else
        setElementAlpha(object, SELECT_ALPHA)
        selectedObjects[object] = true
        outputChatBox("Object selected", 100, 255, 100)
    end
end

function getSelectedObjects()
    local objects = {}
    for obj, _ in pairs(selectedObjects) do
        if isElement(obj) then
            table.insert(objects, obj)
        end
    end
    return objects
end

function clearSelectedObjects()
    for obj, _ in pairs(selectedObjects) do
        if isElement(obj) then
            setElementAlpha(obj, 255)
        end
    end
    selectedObjects = {}
    outputChatBox("All objects deselected", 200, 200, 200)
end

addCommandHandler("clearselection", clearSelectedObjects)

--------------------------------------------------------------------------------
-- PROPERTY CREATION GUI (for DMs)
--------------------------------------------------------------------------------

function openPropertyCreator(worldPos)
    if propertyWindow and isElement(propertyWindow) then
        destroyElement(propertyWindow)
    end
    
    closeContextMenu()
    
    local w, h = 500, 480
    propertyWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "Create Property", false)
    guiWindowSetSizable(propertyWindow, false)
    
    local y = 30
    
    -- Property Name
    guiCreateLabel(15, y, 100, 20, "Property Name:", false, propertyWindow)
    propertyElements.nameEdit = guiCreateEdit(130, y, 350, 25, "", false, propertyWindow)
    y = y + 35
    
    -- Interior Type
    guiCreateLabel(15, y, 100, 20, "Interior Type:", false, propertyWindow)
    propertyElements.interiorCombo = guiCreateComboBox(130, y, 350, 400, "", false, propertyWindow)
    
    -- Store interior IDs for lookup - matches property_system.lua INTERIOR_PRESETS
    propertyElements.interiorIDs = {
        -- Houses & Apartments (1-12)
        {id = "1", name = "CJ's House (Grove St)"},
        {id = "2", name = "Ryder's House"},
        {id = "3", name = "Sweet's House"},
        {id = "4", name = "B Dup's Apartment"},
        {id = "5", name = "B Dup's Crack Palace"},
        {id = "6", name = "Colonel Fuhrberger's"},
        {id = "7", name = "Denise's House"},
        {id = "8", name = "Helena's Barn"},
        {id = "9", name = "Barbara's House"},
        {id = "10", name = "Michelle's House"},
        {id = "11", name = "Katie's House"},
        {id = "12", name = "Millie's House"},
        -- Safehouses (13-24)
        {id = "13", name = "Madd Dogg's Mansion"},
        {id = "14", name = "Verdant Bluffs Safehouse"},
        {id = "15", name = "Jefferson Motel"},
        {id = "16", name = "Willowfield Safehouse"},
        {id = "17", name = "El Corona Safehouse"},
        {id = "18", name = "Hashbury Safehouse"},
        {id = "19", name = "Verona Beach Safehouse"},
        {id = "20", name = "Santa Maria Safehouse"},
        {id = "21", name = "Mulholland Safehouse"},
        {id = "22", name = "Prickle Pine Safehouse"},
        {id = "23", name = "Whitewood Safehouse"},
        {id = "24", name = "Redsands West Safehouse"},
        -- Police Stations (25-27)
        {id = "25", name = "Los Santos Police Dept"},
        {id = "26", name = "San Fierro Police Dept"},
        {id = "27", name = "Las Venturas Police Dept"},
        -- Hospitals (28-30)
        {id = "28", name = "All Saints General (LS)"},
        {id = "29", name = "SF Medical Center"},
        {id = "30", name = "LV Hospital"},
        -- Fast Food (31-33)
        {id = "31", name = "Cluckin' Bell"},
        {id = "32", name = "Burger Shot"},
        {id = "33", name = "Well Stacked Pizza"},
        -- Bars & Clubs (34-37)
        {id = "34", name = "Ten Green Bottles Bar"},
        {id = "35", name = "Lil' Probe Inn"},
        {id = "36", name = "The Pig Pen (Strip Club)"},
        {id = "37", name = "Jizzy's Pleasure Domes"},
        -- Gyms (38-40)
        {id = "38", name = "Ganton Gym (LS)"},
        {id = "39", name = "Cobra Martial Arts (SF)"},
        {id = "40", name = "Below The Belt (LV)"},
        -- Shops (41-51)
        {id = "41", name = "Ammu-Nation 1"},
        {id = "42", name = "Ammu-Nation 2"},
        {id = "43", name = "Ammu-Nation 3"},
        {id = "44", name = "Ammu-Nation 4 (Booth)"},
        {id = "45", name = "Ammu-Nation 5 (Range)"},
        {id = "46", name = "Binco"},
        {id = "47", name = "Didier Sachs"},
        {id = "48", name = "Pro-Laps"},
        {id = "49", name = "Sub Urban"},
        {id = "50", name = "Victim"},
        {id = "51", name = "ZIP"},
        -- Barber Shops (52-54)
        {id = "52", name = "Barber Shop (LS)"},
        {id = "53", name = "Barber Shop (SF)"},
        {id = "54", name = "Barber Shop (LV)"},
        -- Tattoo Parlors (55-57)
        {id = "55", name = "Tattoo Parlor (LS)"},
        {id = "56", name = "Tattoo Parlor (SF)"},
        {id = "57", name = "Tattoo Parlor (LV)"},
        -- Casinos (58-60)
        {id = "58", name = "Four Dragons Casino"},
        {id = "59", name = "Caligula's Casino"},
        {id = "60", name = "Casino (Redsands)"},
        -- 24/7 Stores (61-66)
        {id = "61", name = "24/7 Store 1"},
        {id = "62", name = "24/7 Store 2"},
        {id = "63", name = "24/7 Store 3"},
        {id = "64", name = "24/7 Store 4"},
        {id = "65", name = "24/7 Store 5"},
        {id = "66", name = "24/7 Store 6"},
        -- Special Locations (67-73)
        {id = "67", name = "Warehouse 1"},
        {id = "68", name = "Warehouse 2 (RC Shop)"},
        {id = "69", name = "Diner"},
        {id = "70", name = "Diner 2"},
        {id = "71", name = "Crack Den"},
        {id = "72", name = "Brothel"},
        {id = "73", name = "Motel Room"},
        -- Offices & Business (74-78)
        {id = "74", name = "Planning Dept"},
        {id = "75", name = "Driving School"},
        {id = "76", name = "Bike School"},
        {id = "77", name = "Boat School"},
        {id = "78", name = "Airport Ticket Hall"},
        -- Other (79-85)
        {id = "79", name = "Sex Shop"},
        {id = "80", name = "Mansion (Madd Dogg)"},
        {id = "81", name = "Ryders House Large"},
        {id = "82", name = "Kickstart Stadium"},
        {id = "83", name = "8 Track Stadium"},
        {id = "84", name = "Blood Bowl Stadium"},
        {id = "85", name = "Dirt Track Stadium"},
    }
    
    for _, interior in ipairs(propertyElements.interiorIDs) do
        guiComboBoxAddItem(propertyElements.interiorCombo, interior.id .. ". " .. interior.name)
    end
    guiComboBoxSetSelected(propertyElements.interiorCombo, 0)
    y = y + 35
    
    -- Price
    guiCreateLabel(15, y, 100, 20, "Price ($):", false, propertyWindow)
    propertyElements.priceEdit = guiCreateEdit(130, y, 150, 25, "50000", false, propertyWindow)
    y = y + 35
    
    -- For Sale checkbox
    propertyElements.forSaleCheck = guiCreateCheckBox(15, y, 150, 20, "For Sale", true, false, propertyWindow)
    y = y + 30
    
    -- Entrance position display
    guiCreateLabel(15, y, 110, 20, "Entrance Position:", false, propertyWindow)
    local posText = worldPos and string.format("%.1f, %.1f, %.1f", worldPos.x, worldPos.y, worldPos.z) or "Current Position"
    propertyElements.posLabel = guiCreateLabel(130, y, 350, 20, posText, false, propertyWindow)
    guiLabelSetColor(propertyElements.posLabel, 150, 255, 150)
    y = y + 25
    
    propertyElements.useCurrentPosCheck = guiCreateCheckBox(15, y, 250, 20, "Use my current position instead", false, false, propertyWindow)
    y = y + 35
    
    -- Description
    guiCreateLabel(15, y, 100, 20, "Description:", false, propertyWindow)
    y = y + 25
    propertyElements.descMemo = guiCreateMemo(15, y, 470, 100, "A property in Los Santos.", false, propertyWindow)
    y = y + 110
    
    -- Store world position
    propertyElements.worldPos = worldPos
    
    -- Buttons
    propertyElements.createBtn = guiCreateButton(15, y, 220, 40, "Create Property", false, propertyWindow)
    guiSetProperty(propertyElements.createBtn, "NormalTextColour", "FF66FF66")
    
    propertyElements.cancelBtn = guiCreateButton(265, y, 220, 40, "Cancel", false, propertyWindow)
    
    -- Event handlers
    addEventHandler("onClientGUIClick", propertyElements.createBtn, function()
        local name = guiGetText(propertyElements.nameEdit)
        if not name or name == "" then
            outputChatBox("Please enter a property name", 255, 100, 100)
            return
        end
        
        local interiorIdx = guiComboBoxGetSelected(propertyElements.interiorCombo)
        if interiorIdx < 0 then
            outputChatBox("Please select an interior type", 255, 100, 100)
            return
        end
        
        -- Get the actual interior ID string from our lookup table
        local interiorID = propertyElements.interiorIDs[interiorIdx + 1].id
        
        local price = tonumber(guiGetText(propertyElements.priceEdit)) or 50000
        local forSale = guiCheckBoxGetSelected(propertyElements.forSaleCheck)
        local description = guiGetText(propertyElements.descMemo)
        
        local posX, posY, posZ
        if guiCheckBoxGetSelected(propertyElements.useCurrentPosCheck) then
            posX, posY, posZ = getElementPosition(localPlayer)
        elseif propertyElements.worldPos then
            posX = propertyElements.worldPos.x
            posY = propertyElements.worldPos.y
            posZ = propertyElements.worldPos.z
        else
            posX, posY, posZ = getElementPosition(localPlayer)
        end
        
        triggerServerEvent("property:createFromGUI", localPlayer, name, interiorID, price, forSale, description, posX, posY, posZ)
        
        closePropertyCreator()
    end, false)
    
    addEventHandler("onClientGUIClick", propertyElements.cancelBtn, function()
        closePropertyCreator()
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
end

function closePropertyCreator()
    if propertyWindow and isElement(propertyWindow) then
        destroyElement(propertyWindow)
        propertyWindow = nil
        propertyElements = {}
        showCursor(false)
        guiSetInputMode("allow_binds")
    end
end

--------------------------------------------------------------------------------
-- POI CREATION/EDIT GUI
--------------------------------------------------------------------------------

function openPOICreator(targetObject)
    if poiWindow and isElement(poiWindow) then
        destroyElement(poiWindow)
    end
    
    closeContextMenu()
    editingPOI = nil
    
    local w, h = 400, 350
    poiWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "Create Point of Interest", false)
    guiWindowSetSizable(poiWindow, false)
    
    local y = 30
    
    -- POI Name
    guiCreateLabel(15, y, 100, 20, "POI Name:", false, poiWindow)
    poiElements.nameEdit = guiCreateEdit(120, y, 260, 25, "", false, poiWindow)
    y = y + 35
    
    -- Object info
    if targetObject and isElement(targetObject) then
        local modelID = getElementModel(targetObject)
        local objX, objY, objZ = getElementPosition(targetObject)
        guiCreateLabel(15, y, 100, 20, "Object Model:", false, poiWindow)
        guiCreateLabel(120, y, 260, 20, tostring(modelID), false, poiWindow)
        y = y + 25
        
        guiCreateLabel(15, y, 100, 20, "Position:", false, poiWindow)
        guiCreateLabel(120, y, 260, 20, string.format("%.1f, %.1f, %.1f", objX, objY, objZ), false, poiWindow)
        y = y + 30
        
        poiElements.targetObject = targetObject
        poiElements.worldPos = nil
    else
        guiCreateLabel(15, y, 360, 20, "POI will be created at your current position", false, poiWindow)
        y = y + 30
        poiElements.targetObject = nil
        poiElements.worldPos = nil
    end
    
    -- Description
    guiCreateLabel(15, y, 100, 20, "Description:", false, poiWindow)
    y = y + 25
    poiElements.descMemo = guiCreateMemo(15, y, 370, 120, "Describe what players will see when they examine this...", false, poiWindow)
    y = y + 130
    
    -- Highlight option
    poiElements.highlightCheck = guiCreateCheckBox(15, y, 200, 20, "Highlight this location", true, false, poiWindow)
    y = y + 35
    
    -- Buttons
    poiElements.createBtn = guiCreateButton(15, y, 175, 35, "Create POI", false, poiWindow)
    guiSetProperty(poiElements.createBtn, "NormalTextColour", "FF66FF66")
    
    poiElements.cancelBtn = guiCreateButton(210, y, 175, 35, "Cancel", false, poiWindow)
    
    -- Event handlers
    addEventHandler("onClientGUIClick", poiElements.createBtn, function()
        local name = guiGetText(poiElements.nameEdit)
        if not name or name == "" then
            outputChatBox("Please enter a POI name", 255, 100, 100)
            return
        end
        
        local description = guiGetText(poiElements.descMemo)
        local highlight = guiCheckBoxGetSelected(poiElements.highlightCheck)
        
        local posX, posY, posZ
        local modelID = nil
        
        if poiElements.targetObject and isElement(poiElements.targetObject) then
            posX, posY, posZ = getElementPosition(poiElements.targetObject)
            modelID = getElementModel(poiElements.targetObject)
        elseif poiElements.worldPos then
            posX, posY, posZ = poiElements.worldPos.x, poiElements.worldPos.y, poiElements.worldPos.z
        else
            posX, posY, posZ = getElementPosition(localPlayer)
        end
        
        triggerServerEvent("poi:create", localPlayer, name, description, posX, posY, posZ, modelID, highlight)
        
        closePOIWindow()
    end, false)
    
    addEventHandler("onClientGUIClick", poiElements.cancelBtn, function()
        closePOIWindow()
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
end

function openPOICreatorAtPosition(worldPos)
    if poiWindow and isElement(poiWindow) then
        destroyElement(poiWindow)
    end
    
    closeContextMenu()
    editingPOI = nil
    
    local w, h = 400, 320
    poiWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "Create Point of Interest", false)
    guiWindowSetSizable(poiWindow, false)
    
    local y = 30
    
    -- POI Name
    guiCreateLabel(15, y, 100, 20, "POI Name:", false, poiWindow)
    poiElements.nameEdit = guiCreateEdit(120, y, 260, 25, "", false, poiWindow)
    y = y + 35
    
    -- Position info
    guiCreateLabel(15, y, 100, 20, "Position:", false, poiWindow)
    local posText = worldPos and string.format("%.1f, %.1f, %.1f", worldPos.x, worldPos.y, worldPos.z) or "Your current position"
    guiCreateLabel(120, y, 260, 20, posText, false, poiWindow)
    guiLabelSetColor(guiCreateLabel(120, y, 260, 20, posText, false, poiWindow), 150, 255, 150)
    y = y + 30
    
    poiElements.targetObject = nil
    poiElements.worldPos = worldPos
    
    -- Description
    guiCreateLabel(15, y, 100, 20, "Description:", false, poiWindow)
    y = y + 25
    poiElements.descMemo = guiCreateMemo(15, y, 370, 100, "Describe what players will see when they examine this...", false, poiWindow)
    y = y + 110
    
    -- Highlight option
    poiElements.highlightCheck = guiCreateCheckBox(15, y, 200, 20, "Show marker at location", true, false, poiWindow)
    y = y + 35
    
    -- Buttons
    poiElements.createBtn = guiCreateButton(15, y, 175, 35, "Create POI", false, poiWindow)
    guiSetProperty(poiElements.createBtn, "NormalTextColour", "FF66FF66")
    
    poiElements.cancelBtn = guiCreateButton(210, y, 175, 35, "Cancel", false, poiWindow)
    
    -- Event handlers
    addEventHandler("onClientGUIClick", poiElements.createBtn, function()
        local name = guiGetText(poiElements.nameEdit)
        if not name or name == "" then
            outputChatBox("Please enter a POI name", 255, 100, 100)
            return
        end
        
        local description = guiGetText(poiElements.descMemo)
        local highlight = guiCheckBoxGetSelected(poiElements.highlightCheck)
        
        local posX, posY, posZ
        if poiElements.worldPos then
            posX, posY, posZ = poiElements.worldPos.x, poiElements.worldPos.y, poiElements.worldPos.z
        else
            posX, posY, posZ = getElementPosition(localPlayer)
        end
        
        triggerServerEvent("poi:create", localPlayer, name, description, posX, posY, posZ, nil, highlight)
        
        closePOIWindow()
    end, false)
    
    addEventHandler("onClientGUIClick", poiElements.cancelBtn, function()
        closePOIWindow()
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
end

function openPOIEditor(poiData)
    if poiWindow and isElement(poiWindow) then
        destroyElement(poiWindow)
    end
    
    closeContextMenu()
    editingPOI = poiData.id
    
    local w, h = 400, 300
    poiWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "Edit Point of Interest", false)
    guiWindowSetSizable(poiWindow, false)
    
    local y = 30
    
    -- POI Name
    guiCreateLabel(15, y, 100, 20, "POI Name:", false, poiWindow)
    poiElements.nameEdit = guiCreateEdit(120, y, 260, 25, poiData.name or "", false, poiWindow)
    y = y + 35
    
    -- Description
    guiCreateLabel(15, y, 100, 20, "Description:", false, poiWindow)
    y = y + 25
    poiElements.descMemo = guiCreateMemo(15, y, 370, 120, poiData.description or "", false, poiWindow)
    y = y + 130
    
    -- Highlight option
    poiElements.highlightCheck = guiCreateCheckBox(15, y, 200, 20, "Highlight this object", poiData.highlighted or false, false, poiWindow)
    y = y + 35
    
    -- Buttons
    poiElements.saveBtn = guiCreateButton(15, y, 175, 35, "Save Changes", false, poiWindow)
    guiSetProperty(poiElements.saveBtn, "NormalTextColour", "FF66FF66")
    
    poiElements.cancelBtn = guiCreateButton(210, y, 175, 35, "Cancel", false, poiWindow)
    
    -- Event handlers
    addEventHandler("onClientGUIClick", poiElements.saveBtn, function()
        local name = guiGetText(poiElements.nameEdit)
        local description = guiGetText(poiElements.descMemo)
        local highlight = guiCheckBoxGetSelected(poiElements.highlightCheck)
        
        triggerServerEvent("poi:update", localPlayer, editingPOI, name, description, highlight)
        
        closePOIWindow()
    end, false)
    
    addEventHandler("onClientGUIClick", poiElements.cancelBtn, function()
        closePOIWindow()
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
end

function closePOIWindow()
    if poiWindow and isElement(poiWindow) then
        destroyElement(poiWindow)
        poiWindow = nil
        poiElements = {}
        editingPOI = nil
        showCursor(false)
        guiSetInputMode("allow_binds")
    end
end

--------------------------------------------------------------------------------
-- DESCRIPTION EDITOR (for NPCs, players, etc.)
--------------------------------------------------------------------------------

local descWindow = nil
local descElements = {}
local descTarget = nil
local descTargetType = nil

function openDescriptionEditor(target, targetType)
    if descWindow and isElement(descWindow) then
        destroyElement(descWindow)
    end
    
    closeContextMenu()
    descTarget = target
    descTargetType = targetType
    
    local currentDesc = getElementData(target, "description") or ""
    local targetName = ""
    
    if targetType == "player" then
        targetName = getPlayerName(target)
    elseif targetType == "npc" or targetType == "shopkeeper" then
        targetName = getElementData(target, "npc.name") or "NPC"
    else
        targetName = "Object"
    end
    
    local w, h = 400, 250
    descWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "Set Description: " .. targetName, false)
    guiWindowSetSizable(descWindow, false)
    
    guiCreateLabel(15, 30, 370, 20, "Enter description (what players see when examining):", false, descWindow)
    
    descElements.memo = guiCreateMemo(15, 55, 370, 120, currentDesc, false, descWindow)
    
    descElements.saveBtn = guiCreateButton(15, 185, 175, 35, "Save", false, descWindow)
    guiSetProperty(descElements.saveBtn, "NormalTextColour", "FF66FF66")
    
    descElements.cancelBtn = guiCreateButton(210, 185, 175, 35, "Cancel", false, descWindow)
    
    addEventHandler("onClientGUIClick", descElements.saveBtn, function()
        local description = guiGetText(descElements.memo)
        triggerServerEvent("interaction:setDescription", localPlayer, descTarget, descTargetType, description)
        closeDescriptionEditor()
    end, false)
    
    addEventHandler("onClientGUIClick", descElements.cancelBtn, function()
        closeDescriptionEditor()
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
end

function closeDescriptionEditor()
    if descWindow and isElement(descWindow) then
        destroyElement(descWindow)
        descWindow = nil
        descElements = {}
        descTarget = nil
        descTargetType = nil
        showCursor(false)
        guiSetInputMode("allow_binds")
    end
end

--------------------------------------------------------------------------------
-- SERVER EVENTS
--------------------------------------------------------------------------------

-- Examination result
addEvent("interaction:examineResult", true)
addEventHandler("interaction:examineResult", root, function(name, description, targetType)
    outputChatBox("=== " .. name .. " ===", 255, 200, 100)
    if description and description ~= "" then
        outputChatBox(description, 200, 200, 200)
    else
        outputChatBox("Nothing particularly interesting.", 150, 150, 150)
    end
end)

-- POI edit data received
addEvent("poi:editData", true)
addEventHandler("poi:editData", root, function(poiData)
    openPOIEditor(poiData)
end)

-- Property created confirmation
addEvent("property:created", true)
addEventHandler("property:created", root, function(success, message)
    if success then
        outputChatBox("[Property] " .. message, 100, 255, 100)
    else
        outputChatBox("[Property] " .. message, 255, 100, 100)
    end
end)

-- POI messages
addEvent("poi:message", true)
addEventHandler("poi:message", root, function(message, isError)
    if isError then
        outputChatBox("[POI] " .. message, 255, 100, 100)
    else
        outputChatBox("[POI] " .. message, 100, 255, 100)
    end
end)

-- Description set confirmation
addEvent("interaction:descriptionSet", true)
addEventHandler("interaction:descriptionSet", root, function(success, message)
    if success then
        outputChatBox(message, 100, 255, 100)
    else
        outputChatBox(message, 255, 100, 100)
    end
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeContextMenu()
    closePropertyCreator()
    closePOIWindow()
    closeDescriptionEditor()
    
    -- Restore all highlighted/selected objects
    for obj, _ in pairs(highlightedObjects) do
        if isElement(obj) then setElementAlpha(obj, 255) end
    end
    for obj, _ in pairs(selectedObjects) do
        if isElement(obj) then setElementAlpha(obj, 255) end
    end
end)

outputChatBox("Interaction system loaded. Right-click on things to interact.", 200, 200, 200)
