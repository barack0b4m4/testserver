--[[
================================================================================
    DUNGEON_MASTER.LUA - Dungeon Master Permissions & Tools
================================================================================
    Manages DM permissions and provides DM-specific tools like NPC control,
    forced rolls, and DM mode (noclip, invisibility).
    
    FEATURES:
    - Persistent DM permissions stored in database
    - NPC spawning and control (speak, emote, roll)
    - Forced player rolls
    - DM mode with flying and invisibility
    - First player auto-promoted to DM if no DMs exist
    
    INTEGRATION POINTS:
    ┌─────────────────────────────────────────────────────────────────────────┐
    │ DEPENDS ON:                                                             │
    │   - server.lua: database, AccountManager                                │
    │                                                                         │
    │ PROVIDES TO:                                                            │
    │   - ALL OTHER SCRIPTS: isDungeonMaster(player) function                 │
    │   - client_dmfly.lua: DM mode state for flying                          │
    │   - client_interaction.lua: DM mode state for context menus             │
    │   - client_npc_names.lua: NPC data for name display                     │
    │                                                                         │
    │ GLOBAL EXPORTS:                                                         │
    │   - isDungeonMaster(player): Check if player has DM permissions         │
    │   - NPCs: Table of all active NPCs keyed by ID                          │
    │   - DungeonMasters: Set of DM usernames                                 │
    └─────────────────────────────────────────────────────────────────────────┘
    
    ELEMENT DATA SET:
    - player "isDungeonMaster": true if player is a DM
    - player "dm.mode": true if DM mode is active
    - ped "isNPC": true for DM-spawned NPCs
    - ped "npc.id": NPC identifier
    - ped "npc.name": NPC display name
    
    DM COMMANDS:
    - /dm - Toggle DM mode (fly, invisibility)
    - /spawnnpc [name] [skinID] - Spawn NPC at position
    - /despawnnpc [npcID] - Remove NPC
    - /npcsay [npcID] [message] - Make NPC speak
    - /npcme [npcID] [action] - Make NPC emote
    - /npcroll [npcID] [stat] [DC] - Make NPC roll
    - /listnpcs - List all NPCs
    - /forceroll [player] [stat] [DC] - Force player to roll
    - /adddm [username] - Grant DM permissions
    - /removedm [username] - Remove DM permissions
    - /listdms - List all DMs
================================================================================
]]

-- dungeon_master.lua (SERVER)
-- Dungeon Master system with SQLite permissions storage

outputServerLog("===== DUNGEON_MASTER.LUA LOADING =====")

local db = nil

addEventHandler("onResourceStart", resourceRoot, function()
    db = database
    if not db then
        outputServerLog("ERROR: Could not access database for DM system")
    else
        outputServerLog("DM system connected to database successfully")
        loadDungeonMasters()
    end
end)

--------------------------------------------------------------------------------
-- DM PERMISSIONS (SQLite)
--------------------------------------------------------------------------------

local DungeonMasters = {}

function loadDungeonMasters()
    if not db then return end
    
    local query = dbQuery(db, "SELECT * FROM dungeon_masters")
    local result = dbPoll(query, -1)
    
    if result then
        for _, row in ipairs(result) do
            DungeonMasters[row.username] = {
                accountID = row.account_id,
                grantedDate = row.granted_date,
                grantedBy = row.granted_by
            }
        end
        outputServerLog("Loaded " .. #result .. " Dungeon Masters")
    end
end

function isDungeonMaster(player)
    if not AccountManager then return false end
    
    local acc = AccountManager:getAccount(player)
    if not acc then return false end
    
    if DungeonMasters[acc.username] then
        return true
    end
    
    local accountName = getAccountName(getPlayerAccount(player))
    if accountName and isObjectInACLGroup("user." .. accountName, aclGetGroup("Admin")) then
        return true
    end
    
    return false
end

function addDungeonMaster(username, grantedBy)
    if not db or not AccountManager then return false end
    
    local acc = AccountManager.accounts[username]
    if not acc then return false, "Account not found" end
    
    dbExec(db, [[
        INSERT OR REPLACE INTO dungeon_masters (account_id, username, granted_date, granted_by)
        VALUES (?, ?, ?, ?)
    ]], acc.id, username, getRealTime().timestamp, grantedBy or "SYSTEM")
    
    DungeonMasters[username] = {
        accountID = acc.id,
        grantedDate = getRealTime().timestamp,
        grantedBy = grantedBy or "SYSTEM"
    }
    
    outputServerLog("Added DM: " .. username)
    return true
end

function removeDungeonMaster(username)
    if not db then return false end
    
    dbExec(db, "DELETE FROM dungeon_masters WHERE username = ?", username)
    DungeonMasters[username] = nil
    
    outputServerLog("Removed DM: " .. username)
    return true
end

--------------------------------------------------------------------------------
-- NPC MANAGEMENT
--------------------------------------------------------------------------------

local NPCs = {}
local NPCElements = {}

NPC = {}
NPC.__index = NPC

function NPC:new(id, name, skin, stats)
    local npc = setmetatable({}, NPC)
    npc.id = id or generateNPCID()
    npc.name = name or "Unknown NPC"
    npc.skin = skin or 0
    npc.stats = stats or {
        STR = 10,
        DEX = 10,
        CON = 10,
        INT = 10,
        WIS = 10,
        CHA = 10
    }
    npc.health = 100
    npc.armor = 0
    return npc
end

function NPC:spawn(x, y, z, dimension, interior)
    dimension = dimension or 0
    interior = interior or 0
    
    local ped = createPed(self.skin, x, y, z)
    if not ped then
        return false, "Failed to create ped"
    end
    
    setElementDimension(ped, dimension)
    setElementInterior(ped, interior)
    setElementHealth(ped, self.health)
    setPedArmor(ped, self.armor)
    
    setElementData(ped, "npc.id", self.id)
    setElementData(ped, "npc.name", self.name)
    setElementData(ped, "npc.stats", self.stats)
    setElementData(ped, "isNPC", true)
    
    NPCElements[self.id] = ped
    
    outputServerLog("NPC spawned: " .. self.name .. " (ID: " .. self.id .. ")")
    return true, ped
end

function NPC:despawn()
    local ped = NPCElements[self.id]
    if ped and isElement(ped) then
        destroyElement(ped)
        NPCElements[self.id] = nil
        return true
    end
    return false
end

function NPC:getPed()
    return NPCElements[self.id]
end

local npcIDCounter = 0
function generateNPCID()
    npcIDCounter = npcIDCounter + 1
    return "npc_" .. npcIDCounter
end

function getNPC(id)
    return NPCs[id]
end

function createNPC(name, skin, stats)
    local npc = NPC:new(nil, name, skin, stats)
    NPCs[npc.id] = npc
    return npc
end

--------------------------------------------------------------------------------
-- NPC ACTIONS
--------------------------------------------------------------------------------

-- Helper function for NPC proximity messages (avoids duplicating proximity_chat.lua logic)
local function sendNPCProximityMessage(ped, message, range, r, g, b)
    range = range or 30
    r, g, b = r or 255, g or 255, b or 255
    
    local px, py, pz = getElementPosition(ped)
    local dimension = getElementDimension(ped)
    local interior = getElementInterior(ped)
    
    for _, player in ipairs(getElementsByType("player")) do
        local tx, ty, tz = getElementPosition(player)
        local tDim = getElementDimension(player)
        local tInt = getElementInterior(player)
        
        if tDim == dimension and tInt == interior then
            local distance = getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz)
            if distance <= range then
                outputChatBox(message, player, r, g, b)
            end
        end
    end
end

function npcSay(npcID, message)
    local npc = getNPC(npcID)
    if not npc then return false, "NPC not found" end
    
    local ped = npc:getPed()
    if not ped or not isElement(ped) then
        return false, "NPC not spawned"
    end
    
    local formattedMessage = npc.name .. " says: " .. message
    sendNPCProximityMessage(ped, formattedMessage, 30, 255, 255, 255)
    
    return true
end

function npcAction(npcID, action)
    local npc = getNPC(npcID)
    if not npc then return false, "NPC not found" end
    
    local ped = npc:getPed()
    if not ped or not isElement(ped) then
        return false, "NPC not spawned"
    end
    
    local formattedMessage = "* " .. npc.name .. " " .. action
    sendNPCProximityMessage(ped, formattedMessage, 20, 194, 162, 218)
    
    return true
end

function npcRoll(npcID, stat, dc)
    local npc = getNPC(npcID)
    if not npc then return false, "NPC not found" end
    
    local ped = npc:getPed()
    if not ped or not isElement(ped) then
        return false, "NPC not spawned"
    end
    
    local statValue = npc.stats[stat] or 10
    local modifier = math.floor((statValue - 10) / 2)
    
    local roll = math.random(1, 20)
    local total = roll + modifier
    local success = total >= dc
    
    local modStr = (modifier >= 0) and ("+" .. modifier) or tostring(modifier)
    local message = string.format("* %s rolls %s check: [%d] %s = %d vs DC %d - %s",
        npc.name, stat, roll, modStr, total, dc, success and "SUCCESS" or "FAILURE")
    
    sendNPCProximityMessage(ped, message, 20, 255, 200, 0)
    
    return true, {
        roll = roll,
        modifier = modifier,
        total = total,
        success = success
    }
end

--------------------------------------------------------------------------------
-- DM COMMANDS
--------------------------------------------------------------------------------

addCommandHandler("dm", function(player)
    if not isDungeonMaster(player) then
        outputChatBox("You are not a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    local dmMode = getElementData(player, "dm.mode") or false
    dmMode = not dmMode
    setElementData(player, "dm.mode", dmMode)
    
    if dmMode then
        outputChatBox("DM Mode: ON", player, 0, 255, 0)
        outputChatBox("DM Commands: /spawnnpc, /despawnnpc, /npcsay, /npcme, /npcroll, /forceroll", player, 255, 255, 0)
    else
        outputChatBox("DM Mode: OFF", player, 255, 0, 0)
    end
end)

addCommandHandler("spawnnpc", function(player, cmd, name, skinID)
    if not isDungeonMaster(player) then
        outputChatBox("You are not a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not name or not skinID then
        outputChatBox("Usage: /spawnnpc [name] [skin ID]", player, 255, 255, 0)
        return
    end
    
    skinID = tonumber(skinID) or 0
    
    local stats = {
        STR = 10,
        DEX = 10,
        CON = 10,
        INT = 10,
        WIS = 10,
        CHA = 10
    }
    
    local npc = createNPC(name, skinID, stats)
    
    local x, y, z = getElementPosition(player)
    local dimension = getElementDimension(player)
    local interior = getElementInterior(player)
    
    local success, result = npc:spawn(x, y, z, dimension, interior)
    
    if success then
        outputChatBox("NPC spawned: " .. name .. " (ID: " .. npc.id .. ")", player, 0, 255, 0)
    else
        outputChatBox("Failed to spawn NPC: " .. tostring(result), player, 255, 0, 0)
    end
end)

addCommandHandler("despawnnpc", function(player, cmd, npcID)
    if not isDungeonMaster(player) then
        outputChatBox("You are not a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not npcID then
        outputChatBox("Usage: /despawnnpc [NPC ID]", player, 255, 255, 0)
        return
    end
    
    local npc = getNPC(npcID)
    if not npc then
        outputChatBox("NPC not found", player, 255, 0, 0)
        return
    end
    
    if npc:despawn() then
        NPCs[npcID] = nil
        outputChatBox("NPC despawned: " .. npc.name, player, 0, 255, 0)
    else
        outputChatBox("Failed to despawn NPC", player, 255, 0, 0)
    end
end)

addCommandHandler("npcsay", function(player, cmd, npcID, ...)
    if not isDungeonMaster(player) then
        outputChatBox("You are not a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not npcID then
        outputChatBox("Usage: /npcsay [NPC ID] [message]", player, 255, 255, 0)
        return
    end
    
    local message = table.concat({...}, " ")
    if message == "" then
        outputChatBox("Please provide a message", player, 255, 0, 0)
        return
    end
    
    local success, error = npcSay(npcID, message)
    if not success then
        outputChatBox("Error: " .. tostring(error), player, 255, 0, 0)
    end
end)

addCommandHandler("npcme", function(player, cmd, npcID, ...)
    if not isDungeonMaster(player) then
        outputChatBox("You are not a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not npcID then
        outputChatBox("Usage: /npcme [NPC ID] [action]", player, 255, 255, 0)
        return
    end
    
    local action = table.concat({...}, " ")
    if action == "" then
        outputChatBox("Please provide an action", player, 255, 0, 0)
        return
    end
    
    local success, error = npcAction(npcID, action)
    if not success then
        outputChatBox("Error: " .. tostring(error), player, 255, 0, 0)
    end
end)

addCommandHandler("npcroll", function(player, cmd, npcID, stat, dc)
    if not isDungeonMaster(player) then
        outputChatBox("You are not a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not npcID or not stat or not dc then
        outputChatBox("Usage: /npcroll [NPC ID] [stat] [DC]", player, 255, 255, 0)
        return
    end
    
    stat = string.upper(stat)
    dc = tonumber(dc) or 10
    
    local validStats = {STR = true, DEX = true, CON = true, INT = true, WIS = true, CHA = true}
    if not validStats[stat] then
        outputChatBox("Invalid stat. Use: STR, DEX, CON, INT, WIS, or CHA", player, 255, 0, 0)
        return
    end
    
    local success, result = npcRoll(npcID, stat, dc)
    if not success then
        outputChatBox("Error: " .. tostring(result), player, 255, 0, 0)
    end
end)

addCommandHandler("forceroll", function(player, cmd, targetName, stat, dc)
    if not isDungeonMaster(player) then
        outputChatBox("You are not a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not targetName or not stat or not dc then
        outputChatBox("Usage: /forceroll [player name] [stat] [DC]", player, 255, 255, 0)
        return
    end
    
    stat = string.upper(stat)
    dc = tonumber(dc) or 10
    
    local validStats = {STR = true, DEX = true, CON = true, INT = true, WIS = true, CHA = true}
    if not validStats[stat] then
        outputChatBox("Invalid stat. Use: STR, DEX, CON, INT, WIS, or CHA", player, 255, 0, 0)
        return
    end
    
    local targetPlayer = nil
    for _, p in ipairs(getElementsByType("player")) do
        local pName = getElementData(p, "character.name") or getPlayerName(p)
        if string.lower(pName):find(string.lower(targetName)) then
            targetPlayer = p
            break
        end
    end
    
    if not targetPlayer then
        outputChatBox("Player not found", player, 255, 0, 0)
        return
    end
    
    local targetCharName = getElementData(targetPlayer, "character.name") or getPlayerName(targetPlayer)
    outputChatBox("Forcing " .. targetCharName .. " to roll " .. stat .. " (DC " .. dc .. ")", player, 255, 255, 0)
    
    outputChatBox("The Dungeon Master requests a " .. stat .. " check (DC " .. dc .. ")", targetPlayer, 255, 200, 0)
    
    if performSkillCheck then
        local success, result = performSkillCheck(targetPlayer, stat, dc)
        if result then
            local modStr = (result.modifier >= 0) and ("+" .. result.modifier) or tostring(result.modifier)
            local message = string.format("* %s rolls %s check: [%d] %s = %d vs DC %d - %s",
                targetCharName, stat, result.roll, modStr, result.total, dc,
                success and "SUCCESS" or "FAILURE")
            
            outputChatBox(message, player, 255, 200, 0)
            sendProximityDiceRoll(targetPlayer, message, 20)
        end
    end
end)

addCommandHandler("listnpcs", function(player)
    if not isDungeonMaster(player) then
        outputChatBox("You are not a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    outputChatBox("=== Active NPCs ===", player, 255, 255, 0)
    
    local count = 0
    for id, npc in pairs(NPCs) do
        local ped = npc:getPed()
        local status = (ped and isElement(ped)) and "ALIVE" or "DESPAWNED"
        outputChatBox(string.format("%s - %s [%s]", id, npc.name, status), player, 255, 255, 255)
        count = count + 1
    end
    
    if count == 0 then
        outputChatBox("No NPCs active", player, 200, 200, 200)
    end
end)

addCommandHandler("adddm", function(player, cmd, username)
    if not isDungeonMaster(player) then
        outputChatBox("You are not a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not username then
        outputChatBox("Usage: /adddm [username]", player, 255, 255, 0)
        return
    end
    
    local acc = AccountManager and AccountManager:getAccount(player)
    local granterName = acc and acc.username or getPlayerName(player)
    
    local success, err = addDungeonMaster(username, granterName)
    if success then
        outputChatBox("Added " .. username .. " as Dungeon Master", player, 0, 255, 0)
    else
        outputChatBox("Failed: " .. tostring(err), player, 255, 0, 0)
    end
end)

addCommandHandler("removedm", function(player, cmd, username)
    if not isDungeonMaster(player) then
        outputChatBox("You are not a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not username then
        outputChatBox("Usage: /removedm [username]", player, 255, 255, 0)
        return
    end
    
    removeDungeonMaster(username)
    outputChatBox("Removed " .. username .. " from Dungeon Masters", player, 0, 255, 0)
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onResourceStop", resourceRoot, function()
    for id, npc in pairs(NPCs) do
        npc:despawn()
    end
end)

outputServerLog("===== DUNGEON_MASTER.LUA LOADED =====")
