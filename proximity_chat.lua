-- proximity_chat.lua (SERVER)
-- Proximity-based chat system with character names

outputServerLog("===== PROXIMITY_CHAT.LUA LOADING =====")

-- Disable MTA's built-in /me command
addEventHandler("onResourceStart", resourceRoot, function()
    -- Remove default /me handler (won't error if it doesn't exist)
    removeCommandHandler("me")
    outputServerLog("Removed default /me command handler")
end)

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CHAT_RANGES = {
    normal = 30,      -- Normal talking distance (meters)
    shout = 100,      -- Shouting distance
    whisper = 5,      -- Whisper distance
    me = 20,          -- /me action distance
    describe = 20     -- /do narration distance
}

local CHAT_COLORS = {
    normal = {255, 255, 255},   -- White
    shout = {255, 100, 100},    -- Red
    whisper = {180, 180, 180},  -- Gray
    me = {194, 162, 218},       -- Purple
    describe = {100, 200, 100}  -- Green
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

-- Get character name for a player
local function getCharacterName(player)
    -- Try element data first (most reliable - set when character spawns)
    local charName = getElementData(player, "character.name")
    if charName and charName ~= "" then
        return charName
    end
    
    -- Fallback to AccountManager
    if AccountManager then
        local char = AccountManager:getActiveCharacter(player)
        if char then
            return char.name
        end
    end
    
    -- Last resort: player name
    return getPlayerName(player)
end

-- Get players within range
local function getPlayersInRange(player, range)
    if not isElement(player) then return {} end
    
    local px, py, pz = getElementPosition(player)
    local dimension = getElementDimension(player)
    local interior = getElementInterior(player)
    local nearbyPlayers = {}
    
    for _, p in ipairs(getElementsByType("player")) do
        if p ~= player and isElement(p) then  -- Check element validity
            local success, tx, ty, tz = pcall(getElementPosition, p)
            if success then  -- Only process if getElementPosition worked
                local tDim = getElementDimension(p)
                local tInt = getElementInterior(p)
                
                -- Check same dimension and interior
                if tDim == dimension and tInt == interior then
                    local distance = getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz)
                    if distance <= range then
                        table.insert(nearbyPlayers, {player = p, distance = distance})
                    end
                end
            end
        end
    end
    
    return nearbyPlayers
end

-- Calculate fade based on distance (volume/opacity effect)
local function calculateFade(distance, maxRange)
    if distance >= maxRange then return 0 end
    return math.max(0, math.min(255, 255 - (distance / maxRange * 155)))
end

--------------------------------------------------------------------------------
-- PROXIMITY CHAT FUNCTION
--------------------------------------------------------------------------------

function sendProximityMessage(player, message, chatType, range)
    if not player or not isElement(player) then return end
    if not message or message == "" then return end
    
    chatType = chatType or "normal"
    range = range or CHAT_RANGES[chatType] or CHAT_RANGES.normal
    
    local charName = getCharacterName(player)
    local color = CHAT_COLORS[chatType] or CHAT_COLORS.normal
    
    -- Get nearby players
    local nearbyPlayers = getPlayersInRange(player, range)
    
    -- Format message based on type
    local formattedMessage = ""
    
    if chatType == "normal" then
        formattedMessage = charName .. " says: " .. message
    elseif chatType == "shout" then
        formattedMessage = charName .. " shouts: " .. message:upper() .. "!"
    elseif chatType == "whisper" then
        formattedMessage = charName .. " whispers: " .. message
    elseif chatType == "me" then
        formattedMessage = "* " .. charName .. " " .. message
    elseif chatType == "describe" then
        formattedMessage = "* " .. message .. " ((" .. charName .. "))"
    end
    
    -- Send to sender
    outputChatBox(formattedMessage, player, color[1], color[2], color[3])
    
    -- Send to nearby players with distance-based fade
    for _, data in ipairs(nearbyPlayers) do
        local fade = calculateFade(data.distance, range)
        local r = math.floor(color[1] * (fade / 255))
        local g = math.floor(color[2] * (fade / 255))
        local b = math.floor(color[3] * (fade / 255))
        
        -- Ensure minimum visibility
        r = math.max(r, color[1] * 0.3)
        g = math.max(g, color[2] * 0.3)
        b = math.max(b, color[3] * 0.3)
        
        outputChatBox(formattedMessage, data.player, r, g, b)
    end
    
    -- Log to server
    outputServerLog("[" .. chatType:upper() .. "] " .. charName .. ": " .. message)
end

--------------------------------------------------------------------------------
-- CHAT COMMANDS
--------------------------------------------------------------------------------

-- Normal chat (default)
addEventHandler("onPlayerChat", root, function(message, messageType)
    if messageType == 0 then  -- Normal chat
        -- Cancel default chat
        cancelEvent()
        
        -- Check if player has active character
        if not AccountManager then return end
        local char = AccountManager:getActiveCharacter(source)
        if not char then
            outputChatBox("You must select a character to chat", source, 255, 0, 0)
            return
        end
        
        -- Send proximity message
        sendProximityMessage(source, message, "normal", CHAT_RANGES.normal)
    end
end)

-- /s or /shout - Shout
addCommandHandler("s", function(player, cmd, ...)
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Usage: /s [message]", player, 255, 255, 0)
        return
    end
    
    if not AccountManager then return end
    local char = AccountManager:getActiveCharacter(player)
    if not char then
        outputChatBox("You must select a character to chat", player, 255, 0, 0)
        return
    end
    
    sendProximityMessage(player, message, "shout", CHAT_RANGES.shout)
end)

addCommandHandler("shout", function(player, cmd, ...)
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Usage: /shout [message]", player, 255, 255, 0)
        return
    end
    
    if not AccountManager then return end
    local char = AccountManager:getActiveCharacter(player)
    if not char then
        outputChatBox("You must select a character to chat", player, 255, 0, 0)
        return
    end
    
    sendProximityMessage(player, message, "shout", CHAT_RANGES.shout)
end)

-- /w or /whisper - Whisper
addCommandHandler("w", function(player, cmd, ...)
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Usage: /w [message]", player, 255, 255, 0)
        return
    end
    
    if not AccountManager then return end
    local char = AccountManager:getActiveCharacter(player)
    if not char then
        outputChatBox("You must select a character to chat", player, 255, 0, 0)
        return
    end
    
    sendProximityMessage(player, message, "whisper", CHAT_RANGES.whisper)
end)

addCommandHandler("whisper", function(player, cmd, ...)
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Usage: /whisper [message]", player, 255, 255, 0)
        return
    end
    
    if not AccountManager then return end
    local char = AccountManager:getActiveCharacter(player)
    if not char then
        outputChatBox("You must select a character to chat", player, 255, 0, 0)
        return
    end
    
    sendProximityMessage(player, message, "whisper", CHAT_RANGES.whisper)
end)

-- /me - Roleplay action (override MTA's built-in /me)
addCommandHandler("me", function(player, cmd, ...)
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Usage: /me [action]", player, 255, 255, 0)
        return
    end
    
    if not AccountManager then return end
    local char = AccountManager:getActiveCharacter(player)
    if not char then
        outputChatBox("You must select a character to chat", player, 255, 0, 0)
        return
    end
    
    sendProximityMessage(player, message, "me", CHAT_RANGES.me)
end, false, false)

-- /do - Narration/environment description
addCommandHandler("do", function(player, cmd, ...)
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Usage: /do [description]", player, 255, 255, 0)
        return
    end
    
    if not AccountManager then return end
    local char = AccountManager:getActiveCharacter(player)
    if not char then
        outputChatBox("You must select a character to chat", player, 255, 0, 0)
        return
    end
    
    sendProximityMessage(player, message, "describe", CHAT_RANGES.describe)
end)

-- /b - Local Out of Character (OOC) - Proximity based
addCommandHandler("b", function(player, cmd, ...)
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Usage: /b [ooc message]", player, 255, 255, 0)
        return
    end
    
    local charName = getCharacterName(player)
    local px, py, pz = getElementPosition(player)
    local dimension = getElementDimension(player)
    local interior = getElementInterior(player)
    local range = 20  -- Local OOC range
    
    local oocMessage = "(( [Local OOC] " .. charName .. ": " .. message .. " ))"
    
    -- Send to sender
    outputChatBox(oocMessage, player, 150, 150, 150)
    
    -- Send to nearby players
    local nearbyPlayers = getPlayersInRange(player, range)
    for _, data in ipairs(nearbyPlayers) do
        outputChatBox(oocMessage, data.player, 150, 150, 150)
    end
end)

-- /ooc - Global Out of Character (OOC) - All players
addCommandHandler("ooc", function(player, cmd, ...)
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Usage: /ooc [ooc message]", player, 255, 255, 0)
        return
    end
    
    local charName = getCharacterName(player)
    local oocMessage = "(( [Global OOC] " .. charName .. ": " .. message .. " ))"
    
    -- Send to all players (global OOC)
    outputChatBox(oocMessage, root, 100, 100, 100)
    outputServerLog("[GLOBAL OOC] " .. charName .. ": " .. message)
end)

-- /try - Chance-based action
addCommandHandler("try", function(player, cmd, ...)
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Usage: /try [action]", player, 255, 255, 0)
        return
    end
    
    if not AccountManager then return end
    local char = AccountManager:getActiveCharacter(player)
    if not char then
        outputChatBox("You must select a character to chat", player, 255, 0, 0)
        return
    end
    
    local success = math.random(1, 2) == 1  -- 50/50 chance
    local result = success and "succeeds" or "fails"
    local resultMessage = message .. " ((" .. result .. "))"
    
    sendProximityMessage(player, resultMessage, "me", CHAT_RANGES.me)
end)

-- /ame - Action with text above head (uses element data for client-side rendering)
addCommandHandler("ame", function(player, cmd, ...)
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Usage: /ame [action]", player, 255, 255, 0)
        return
    end
    
    if not AccountManager then return end
    local char = AccountManager:getActiveCharacter(player)
    if not char then
        outputChatBox("You must select a character to chat", player, 255, 0, 0)
        return
    end
    
    -- Send as proximity /me
    sendProximityMessage(player, message, "me", CHAT_RANGES.me)
    
    -- Set element data for overhead text (clients can render this with DX)
    local charName = getCharacterName(player)
    setElementData(player, "ame.text", "* " .. charName .. " " .. message)
    setElementData(player, "ame.time", getTickCount())
    
    -- Clear after 5 seconds
    setTimer(function()
        if isElement(player) then
            setElementData(player, "ame.text", nil)
            setElementData(player, "ame.time", nil)
        end
    end, 5000, 1)
end)

--------------------------------------------------------------------------------
-- ADMIN COMMANDS
--------------------------------------------------------------------------------

-- /a - Admin chat
addCommandHandler("a", function(player, cmd, ...)
    -- You can add admin check here
    -- if not isPlayerAdmin(player) then return end
    
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Usage: /a [admin message]", player, 255, 255, 0)
        return
    end
    
    local playerName = getPlayerName(player)
    local adminMessage = "[ADMIN] " .. playerName .. ": " .. message
    
    -- Send to all admins only (you'll need to implement admin system)
    outputChatBox(adminMessage, root, 255, 165, 0)  -- Orange
    outputServerLog(adminMessage)
end)

--------------------------------------------------------------------------------
-- HELP COMMAND
--------------------------------------------------------------------------------

addCommandHandler("helpme", function(player)
    outputChatBox("=== Proximity Chat Commands ===", player, 255, 255, 0)
    outputChatBox("Normal chat - Just type and press enter (30m range)", player, 255, 255, 255)
    outputChatBox("/s or /shout [text] - Shout (100m range)", player, 255, 100, 100)
    outputChatBox("/w or /whisper [text] - Whisper (5m range)", player, 180, 180, 180)
    outputChatBox("/me [action] - Roleplay action (20m range)", player, 194, 162, 218)
    outputChatBox("/do [description] - Environment description (20m range)", player, 100, 200, 100)
    outputChatBox("/ame [action] - Action with 3D text above head", player, 194, 162, 218)
    outputChatBox("/try [action] - 50/50 chance action", player, 194, 162, 218)
    outputChatBox("/b [text] - Local out-of-character chat (20m range)", player, 150, 150, 150)
    outputChatBox("/ooc [text] - Global out-of-character chat", player, 100, 100, 100)
end)

outputServerLog("===== PROXIMITY_CHAT.LUA LOADED =====")
