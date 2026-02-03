-- MTA San Andreas: Login/Register GUI (Client-side)

outputChatBox("===== CLIENT_LOGIN.LUA LOADED =====", 255, 255, 0)

local loginWindow = nil
local loginElements = {}  -- Separate table for storing element references
local isWindowVisible = false

-- GUI dimensions
local screenW, screenH = guiGetScreenSize()
local windowW, windowH = 400, 300
local windowX = (screenW - windowW) / 2
local windowY = (screenH - windowH) / 2

--------------------------------------------------------------------------------
-- CREATE LOGIN WINDOW
--------------------------------------------------------------------------------

function createLoginWindow()
    -- Force cursor on
    showCursor(true, true)
    
    if loginWindow and isElement(loginWindow) then
        destroyElement(loginWindow)
    end
    
    -- Main window
    loginWindow = guiCreateWindow(windowX, windowY, windowW, windowH, "MTA RP - Login", false)
    guiWindowSetSizable(loginWindow, false)
    
    -- Title label
    local titleLabel = guiCreateLabel(0.1, 0.1, 0.8, 0.1, "Welcome! Please login or register.", true, loginWindow)
    guiSetFont(titleLabel, "default-bold-small")
    guiLabelSetHorizontalAlign(titleLabel, "center")
    
    -- Username
    guiCreateLabel(0.1, 0.25, 0.3, 0.08, "Username:", true, loginWindow)
    local usernameEdit = guiCreateEdit(0.4, 0.25, 0.5, 0.08, "", true, loginWindow)
    
    addEventHandler("onClientGUIClick", usernameEdit, function()
        guiBringToFront(usernameEdit)
        guiSetInputMode("no_binds_when_editing")
    end, false)
    
    addEventHandler("onClientGUIFocus", usernameEdit, function()
        guiSetInputMode("no_binds_when_editing")
    end, false)
    
    -- Password
    guiCreateLabel(0.1, 0.38, 0.3, 0.08, "Password:", true, loginWindow)
    local passwordEdit = guiCreateEdit(0.4, 0.38, 0.5, 0.08, "", true, loginWindow)
    guiEditSetMasked(passwordEdit, true)
    
    addEventHandler("onClientGUIClick", passwordEdit, function()
        guiBringToFront(passwordEdit)
        guiSetInputMode("no_binds_when_editing")
    end, false)
    
    addEventHandler("onClientGUIFocus", passwordEdit, function()
        guiSetInputMode("no_binds_when_editing")
    end, false)
    
    -- Status label (create BEFORE buttons so it can be referenced)
    local statusLabel = guiCreateLabel(0.1, 0.75, 0.8, 0.15, "", true, loginWindow)
    guiLabelSetHorizontalAlign(statusLabel, "center")
    guiLabelSetColor(statusLabel, 255, 255, 255)
    
    -- Store elements for access (before buttons use them)
    loginElements.usernameEdit = usernameEdit
    loginElements.passwordEdit = passwordEdit
    loginElements.statusLabel = statusLabel
    
    -- Buttons - CREATE AND ATTACH HANDLERS IMMEDIATELY
    local loginBtn = guiCreateButton(0.1, 0.55, 0.35, 0.12, "Login", true, loginWindow)
    addEventHandler("onClientGUIClick", loginBtn, function()
        outputChatBox("LOGIN BUTTON CLICKED!", 0, 255, 0)
        
        local username = guiGetText(usernameEdit)
        local password = guiGetText(passwordEdit)
        
        if username == "" or password == "" then
            guiSetText(statusLabel, "Please fill in all fields")
            guiLabelSetColor(statusLabel, 255, 0, 0)
            return
        end
        
        guiSetText(statusLabel, "Logging in...")
        guiLabelSetColor(statusLabel, 255, 255, 0)
        
        -- FIX: Use correct event name that server listens for
        triggerServerEvent("auth:login", resourceRoot, username, password)
    end, false)
    
    local registerBtn = guiCreateButton(0.55, 0.55, 0.35, 0.12, "Register", true, loginWindow)
    addEventHandler("onClientGUIClick", registerBtn, function()
        outputChatBox("REGISTER BUTTON CLICKED!", 0, 255, 0)
        
        local username = guiGetText(usernameEdit)
        local password = guiGetText(passwordEdit)
        
        outputChatBox("Username: " .. username, 255, 255, 0)
        outputChatBox("Password length: " .. #password, 255, 255, 0)
        
        if username == "" or password == "" then
            guiSetText(statusLabel, "Please fill in all fields")
            guiLabelSetColor(statusLabel, 255, 0, 0)
            outputChatBox("VALIDATION FAILED: Empty fields", 255, 0, 0)
            return
        end
        
        if #username < 3 or #username > 20 then
            guiSetText(statusLabel, "Username must be 3-20 characters")
            guiLabelSetColor(statusLabel, 255, 0, 0)
            outputChatBox("VALIDATION FAILED: Username length", 255, 0, 0)
            return
        end
        
        if #password < 6 then
            guiSetText(statusLabel, "Password must be at least 6 characters")
            guiLabelSetColor(statusLabel, 255, 0, 0)
            outputChatBox("VALIDATION FAILED: Password too short", 255, 0, 0)
            return
        end
        
        guiSetText(statusLabel, "Creating account...")
        guiLabelSetColor(statusLabel, 255, 255, 0)
        
        outputChatBox("TRIGGERING SERVER EVENT: auth:register", 0, 255, 255)
        triggerServerEvent("auth:register", resourceRoot, username, password)
        outputChatBox("SERVER EVENT TRIGGERED", 0, 255, 255)
    end, false)
    
    outputChatBox("Buttons created and handlers attached", 255, 255, 0)
    
    -- Enter key support
    addEventHandler("onClientGUIAccepted", usernameEdit, function()
        guiSetInputMode("no_binds_when_editing")
        guiBringToFront(passwordEdit)
    end)
    
    addEventHandler("onClientGUIAccepted", passwordEdit, function()
        local username = guiGetText(usernameEdit)
        local password = guiGetText(passwordEdit)
        
        if username ~= "" and password ~= "" then
            -- FIX: Use correct event name that server listens for
            triggerServerEvent("auth:login", resourceRoot, username, password)
        end
    end)
    
    showCursor(true, true)
    guiSetInputMode("no_binds_when_editing")
    isWindowVisible = true
    
    outputChatBox("===== LOGIN WINDOW FULLY CREATED =====", 0, 255, 0)
end

--------------------------------------------------------------------------------
-- SHOW/HIDE FUNCTIONS
--------------------------------------------------------------------------------

function showLoginWindow()
    createLoginWindow()
end

function hideLoginWindow()
    if loginWindow and isElement(loginWindow) then
        destroyElement(loginWindow)
        loginWindow = nil
        loginElements = {}  -- Clear element references
        showCursor(false)
        guiSetInputMode("allow_binds")
        isWindowVisible = false
    end
end

--------------------------------------------------------------------------------
-- SERVER EVENT HANDLERS
--------------------------------------------------------------------------------

-- Server triggers this when player joins
addEvent("showLoginWindow", true)
addEventHandler("showLoginWindow", root, function()
    outputChatBox("===== SHOW LOGIN WINDOW EVENT RECEIVED =====", 0, 255, 255)
    showLoginWindow()
end)

-- Registration result
addEvent("registrationResult", true)
addEventHandler("registrationResult", root, function(success, errorMsg)
    if loginWindow and isElement(loginWindow) and loginElements.statusLabel then
        if success then
            guiSetText(loginElements.statusLabel, "Account created! Please login.")
            guiLabelSetColor(loginElements.statusLabel, 0, 255, 0)
        else
            guiSetText(loginElements.statusLabel, errorMsg or "Registration failed")
            guiLabelSetColor(loginElements.statusLabel, 255, 0, 0)
        end
    end
end)

-- Login result
addEvent("loginResult", true)
addEventHandler("loginResult", root, function(success, errorMsg)
    if loginWindow and isElement(loginWindow) and loginElements.statusLabel then
        if success then
            guiSetText(loginElements.statusLabel, "Login successful!")
            guiLabelSetColor(loginElements.statusLabel, 0, 255, 0)
            -- Don't hide here - server will trigger character select/create which hides via hideAllGUI
        else
            guiSetText(loginElements.statusLabel, errorMsg or "Login failed")
            guiLabelSetColor(loginElements.statusLabel, 255, 0, 0)
        end
    end
end)

-- Hide login GUI specifically
addEvent("hideLoginGUI", true)
addEventHandler("hideLoginGUI", root, function()
    hideLoginWindow()
end)

-- Clean up on resource stop
addEventHandler("onClientResourceStop", resourceRoot, function()
    hideLoginWindow()
end)

-- Function to toggle the cursor
function toggleMouse()
    if isCursorShowing() then
        showCursor(false)
        -- Optional: Re-enable character control when cursor is hidden
        setControlState("fire", false)
    else
        showCursor(true)
        -- Optional: Disable character control when cursor is shown
        setControlState("fire", false)
    end
end

-- Bind the 'm' key to the toggleMouse function
bindKey("m", "down", toggleMouse)