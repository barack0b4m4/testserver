-- MTA San Andreas RP Server
-- Full server.lua with D&D-style RPG stats integrated

outputServerLog("===== SERVER.LUA LOADING =====")

--------------------------------------------------------------------------------
-- DATABASE
--------------------------------------------------------------------------------

database = nil  -- Global: shared with other systems

function initializeDatabase()
    database = dbConnect("sqlite", "serverdata.db")
    if not database then
        outputServerLog("CRITICAL: Database connection failed!")
        return false
    end

    dbExec(database, [[
        CREATE TABLE IF NOT EXISTS accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE,
            password_hash TEXT,
            created_date INTEGER,
            last_login INTEGER
        )
    ]])

    dbExec(database, [[
        CREATE TABLE IF NOT EXISTS characters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id INTEGER,
            name TEXT,
            skin INTEGER,
            gender TEXT,
            level INTEGER,
            money INTEGER,
            health REAL,
            armor REAL,
            pos_x REAL,
            pos_y REAL,
            pos_z REAL,
            interior INTEGER DEFAULT 0,
            dimension INTEGER DEFAULT 0,
            created_date INTEGER,
            play_time INTEGER
        )
    ]])

    dbExec(database, [[
        CREATE TABLE IF NOT EXISTS character_stats (
            character_id INTEGER PRIMARY KEY,
            str INTEGER,
            dex INTEGER,
            con INTEGER,
            int INTEGER,
            wis INTEGER,
            cha INTEGER
        )
    ]])

    dbExec(database, [[
        CREATE TABLE IF NOT EXISTS inventory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            character_id INTEGER,
            item_id TEXT,
            quantity INTEGER,
            durability INTEGER,
            instance_id TEXT UNIQUE,
            slot_index INTEGER
        )
    ]])
    
    dbExec(database, [[
        CREATE TABLE IF NOT EXISTS dungeon_masters (
            account_id INTEGER PRIMARY KEY,
            username TEXT UNIQUE,
            granted_date INTEGER,
            granted_by TEXT
        )
    ]])

    outputServerLog("Database initialized successfully")
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    if initializeDatabase() then
        AccountManager:loadAllAccounts()
        outputServerLog("Server started successfully")
    else
        outputServerLog("CRITICAL: Server failed to start - database error")
    end
end)

--------------------------------------------------------------------------------
-- ACCOUNT
--------------------------------------------------------------------------------

Account = {}
Account.__index = Account

function Account:new(username, passwordHash, dbId)
    local a = setmetatable({}, Account)
    a.id = dbId
    a.username = username
    a.passwordHash = passwordHash
    a.characters = {}
    a.createdDate = getRealTime().timestamp
    a.lastLogin = getRealTime().timestamp
    return a
end

function Account:addCharacter(char)
    if #self:getCharacterList() >= 3 then
        return false, "Max characters reached"
    end
    self.characters[char.name] = char
    return true
end

function Account:getCharacterList()
    local t = {}
    for _, c in pairs(self.characters) do table.insert(t, c) end
    return t
end

function Account:getCharacterListForClient()
    local list = {}
    for _, c in pairs(self.characters) do
        table.insert(list, {
            name = c.name,
            level = c.level,
            gender = c.gender,
            skin = c.skin,
            playTime = c.playTime or 0
        })
    end
    return list
end

function Account:hasCharacter(name)
    return self.characters[name] ~= nil
end

--------------------------------------------------------------------------------
-- CHARACTER
--------------------------------------------------------------------------------

Character = {}
Character.__index = Character

function Character:new(name, skin, gender, accountId, dbId)
    local c = setmetatable({}, Character)

    c.id = dbId
    c.accountId = accountId
    c.name = name
    c.skin = skin or 0
    c.gender = gender or "Male"
    c.level = 1
    c.money = 5000
    c.health = 100
    c.armor = 0
    c.position = {x = 1958.33, y = -1714.46, z = 13.38}
    c.interior = 0
    c.dimension = 0
    c.createdDate = getRealTime().timestamp
    c.playTime = 0

    -- D&D STATS
    c.stats = {
        STR = 10, DEX = 10, CON = 10,
        INT = 10, WIS = 10, CHA = 10
    }

    c.modifiers = {}
    return c
end

function Character:calculateModifiers()
    for k, v in pairs(self.stats) do
        self.modifiers[k] = math.floor((v - 10) / 2)
    end
end

-- D&D STAT EFFECTS:
-- STR: Melee damage, carry weight
-- DEX: Weapon accuracy, movement speed, stamina
-- CON: Max health, damage resistance
-- INT: XP gain bonus
-- WIS: Luck in rolls, driving skill
-- CHA: Shop prices, NPC respect

function Character:applyGTAModifiers(player)
    if not isElement(player) then return end
    
    self:calculateModifiers()
    
    local equipBonuses = getElementData(player, "equipment.bonuses") or {}
    local tempBuffs = getElementData(player, "temp.buffs") or {}
    
    local totalMods = {}
    for _, stat in ipairs({"STR", "DEX", "CON", "INT", "WIS", "CHA"}) do
        totalMods[stat] = self.modifiers[stat] + (equipBonuses[stat] or 0) + (tempBuffs[stat] or 0)
    end

    -- STR: Melee damage and carry weight
    local meleeStat = math.max(0, math.min(1000, 500 + totalMods.STR * 100))
    setPedStat(player, 23, meleeStat)
    
    local inv = PlayerInventories and PlayerInventories[player]
    if inv then
        inv.maxWeight = 50 + totalMods.STR * 5
    end

    -- DEX: Weapon skills and movement
    local weaponSkill = math.max(0, math.min(1000, 500 + totalMods.DEX * 100))
    for stat = 69, 79 do
        setPedStat(player, stat, weaponSkill)
    end
    
    local speedMultiplier = 1.0 + (totalMods.DEX * 0.05)
    speedMultiplier = math.max(0.7, math.min(1.3, speedMultiplier))
    setElementData(player, "stat.speedMultiplier", speedMultiplier)
    
    local staminaStat = math.max(0, math.min(1000, 500 + totalMods.DEX * 80))
    setPedStat(player, 22, staminaStat)  -- Stamina

    -- CON: Max health
    local maxHealth = math.max(50, 100 + totalMods.CON * 15)
    setElementData(player, "maxHealth", maxHealth)
    
    local currentHealth = getElementHealth(player)
    if currentHealth > maxHealth then
        setElementHealth(player, maxHealth)
    end
    
    local healthStat = math.max(0, math.min(1000, 500 + totalMods.CON * 100))
    setPedStat(player, 24, healthStat)
    
    local muscleStat = math.max(0, math.min(1000, 300 + totalMods.CON * 50 + totalMods.STR * 50))
    setPedStat(player, 21, muscleStat)

    -- INT: XP multiplier
    local xpMultiplier = 1.0 + (totalMods.INT * 0.1)
    setElementData(player, "stat.xpMultiplier", xpMultiplier)

    -- WIS: Luck and driving
    setElementData(player, "stat.luckBonus", totalMods.WIS)
    
    local drivingStat = math.max(0, math.min(1000, 500 + totalMods.WIS * 50 + totalMods.DEX * 50))
    setPedStat(player, 160, drivingStat)

    -- CHA: Price modifier and respect
    local priceModifier = 1.0 - (totalMods.CHA * 0.05)
    priceModifier = math.max(0.7, math.min(1.3, priceModifier))
    setElementData(player, "stat.priceModifier", priceModifier)
    
    local respectStat = math.max(0, math.min(1000, 500 + totalMods.CHA * 100))
    setPedStat(player, 68, respectStat)
    
    setElementData(player, "stat.totalModifiers", totalMods)
end

function Character:spawn(player)
    if not isElement(player) then return end
    
    spawnPlayer(player, self.position.x, self.position.y, self.position.z, 0, self.skin)
    setElementInterior(player, self.interior or 0)
    setElementDimension(player, self.dimension or 0)
    setPlayerMoney(player, self.money)
    setPedArmor(player, self.armor)
    fadeCamera(player, true)
    setCameraTarget(player, player)
    
    setElementData(player, "character.name", self.name)
    setElementData(player, "character.id", self.id)

    self:calculateModifiers()

    if initializePlayerInventory then
        initializePlayerInventory(player, self.id, 50 + (self.modifiers.STR or 0) * 5)
    end

    self:applyGTAModifiers(player)
    
    local maxHealth = getElementData(player, "maxHealth") or 100
    setElementHealth(player, math.min(self.health, maxHealth))
    
    outputChatBox("Welcome, " .. self.name .. "!", player, 0, 255, 0)
    outputChatBox("Type /stats to view your character attributes", player, 255, 255, 0)
end

function Character:save(player)
    if not isElement(player) then return end
    
    local x, y, z = getElementPosition(player)
    self.position = {x = x, y = y, z = z}
    self.interior = getElementInterior(player)
    self.dimension = getElementDimension(player)
    self.health = getElementHealth(player)
    self.armor = getPedArmor(player)
    self.money = getPlayerMoney(player)
    self.skin = getElementModel(player)
end

function Character:saveToDatabase()
    if not self.id then
        dbExec(database, [[
            INSERT INTO characters
            (account_id, name, skin, gender, level, money, health, armor, pos_x, pos_y, pos_z, interior, dimension, created_date, play_time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]],
            self.accountId, self.name, self.skin, self.gender, self.level,
            self.money, self.health, self.armor,
            self.position.x, self.position.y, self.position.z,
            self.interior or 0, self.dimension or 0,
            self.createdDate, self.playTime
        )

        dbQuery(function(qh)
            local result = dbPoll(qh, 0)
            if result and result[1] then
                self.id = result[1].id
                dbExec(database, [[
                    INSERT INTO character_stats (character_id, str, dex, con, int, wis, cha)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ]], self.id, self.stats.STR, self.stats.DEX, self.stats.CON,
                    self.stats.INT, self.stats.WIS, self.stats.CHA)
            end
        end, database, "SELECT last_insert_rowid() AS id")
    else
        dbExec(database, [[
            UPDATE characters SET
            skin = ?, gender = ?, level = ?, money = ?, health = ?, armor = ?,
            pos_x = ?, pos_y = ?, pos_z = ?, interior = ?, dimension = ?, play_time = ?
            WHERE id = ?
        ]],
            self.skin, self.gender, self.level, self.money, self.health, self.armor,
            self.position.x, self.position.y, self.position.z,
            self.interior or 0, self.dimension or 0, self.playTime, self.id
        )
        
        dbExec(database, [[
            REPLACE INTO character_stats (character_id, str, dex, con, int, wis, cha)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]], self.id, self.stats.STR, self.stats.DEX, self.stats.CON,
            self.stats.INT, self.stats.WIS, self.stats.CHA)
    end
end

--------------------------------------------------------------------------------
-- ACCOUNT MANAGER
--------------------------------------------------------------------------------

AccountManager = {
    accounts = {},
    loggedInPlayers = {},
    activeCharacters = {}
}

function AccountManager:loadAllAccounts()
    outputServerLog("Loading accounts from database...")
    
    local query = dbQuery(database, "SELECT * FROM accounts")
    local result = dbPoll(query, -1)
    
    if not result then
        outputServerLog("No accounts found or database error")
        return
    end
    
    for _, row in ipairs(result) do
        local acc = Account:new(row.username, row.password_hash, row.id)
        acc.createdDate = row.created_date
        acc.lastLogin = row.last_login
        
        local charQuery = dbQuery(database, "SELECT * FROM characters WHERE account_id = ?", row.id)
        local charResult = dbPoll(charQuery, -1)
        
        if charResult then
            for _, charRow in ipairs(charResult) do
                local char = Character:new(charRow.name, charRow.skin, charRow.gender, row.id, charRow.id)
                char.level = charRow.level
                char.money = charRow.money
                char.health = charRow.health
                char.armor = charRow.armor
                char.position = {x = charRow.pos_x, y = charRow.pos_y, z = charRow.pos_z}
                char.interior = charRow.interior or 0
                char.dimension = charRow.dimension or 0
                char.createdDate = charRow.created_date
                char.playTime = charRow.play_time or 0
                
                local statsQuery = dbQuery(database, "SELECT * FROM character_stats WHERE character_id = ?", charRow.id)
                local statsResult = dbPoll(statsQuery, -1)
                
                if statsResult and statsResult[1] then
                    char.stats = {
                        STR = statsResult[1].str or 10,
                        DEX = statsResult[1].dex or 10,
                        CON = statsResult[1].con or 10,
                        INT = statsResult[1].int or 10,
                        WIS = statsResult[1].wis or 10,
                        CHA = statsResult[1].cha or 10
                    }
                end
                
                char:calculateModifiers()
                acc.characters[char.name] = char
            end
        end
        
        self.accounts[row.username] = acc
    end
    
    outputServerLog("Loaded " .. #result .. " accounts")
end

function AccountManager:login(player, username, password)
    local acc = self.accounts[username]
    if not acc then return false end
    
    local hashed = hash("sha256", password)
    if acc.passwordHash ~= hashed then return false end
    
    self.loggedInPlayers[player] = acc
    acc.lastLogin = getRealTime().timestamp
    
    dbExec(database, "UPDATE accounts SET last_login = ? WHERE id = ?", acc.lastLogin, acc.id)
    
    outputServerLog("Player logged in: " .. username)
    return true
end

function AccountManager:logout(player)
    self.loggedInPlayers[player] = nil
    self.activeCharacters[player] = nil
end

function AccountManager:getAccount(player)
    return self.loggedInPlayers[player]
end

function AccountManager:setActiveCharacter(player, char)
    self.activeCharacters[player] = char
end

function AccountManager:getActiveCharacter(player)
    return self.activeCharacters[player]
end

--------------------------------------------------------------------------------
-- AUTH EVENTS
--------------------------------------------------------------------------------

addEvent("auth:register", true)
addEventHandler("auth:register", root, function(username, password)
    outputServerLog("Registration attempt: " .. username)
    
    if AccountManager.accounts[username] then
        triggerClientEvent(client, "registrationResult", client, false, "Username already exists")
        return
    end
    
    local hashed = hash("sha256", password)
    local timestamp = getRealTime().timestamp
    
    dbExec(database, "INSERT INTO accounts (username, password_hash, created_date, last_login) VALUES (?, ?, ?, ?)",
        username, hashed, timestamp, timestamp)
    
    dbQuery(function(qh)
        local result = dbPoll(qh, 0)
        if result and result[1] then
            local acc = Account:new(username, hashed, result[1].id)
            AccountManager.accounts[username] = acc
            triggerClientEvent(client, "registrationResult", client, true)
            outputServerLog("Account created: " .. username)
        else
            triggerClientEvent(client, "registrationResult", client, false, "Database error")
        end
    end, database, "SELECT last_insert_rowid() AS id")
end)

addEvent("auth:login", true)
addEventHandler("auth:login", root, function(username, password)
    outputServerLog("Login attempt: " .. username)
    
    local success = AccountManager:login(client, username, password)
    
    if success then
        triggerClientEvent(client, "loginResult", client, true)
        
        local acc = AccountManager:getAccount(client)
        local chars = acc:getCharacterListForClient()
        
        if #chars == 0 then
            triggerClientEvent(client, "showCharacterCreation", client)
        else
            triggerClientEvent(client, "showCharacterSelect", client, chars)
        end
    else
        triggerClientEvent(client, "loginResult", client, false, "Invalid username or password")
    end
end)

--------------------------------------------------------------------------------
-- CHARACTER EVENTS
--------------------------------------------------------------------------------

addEvent("onCharacterCreate", true)
addEventHandler("onCharacterCreate", root, function(name, stats, gender, skinID)
    outputServerLog("Character creation attempt: " .. tostring(name))
    
    local acc = AccountManager:getAccount(client)
    if not acc then return end
    
    if not name or #name < 3 or #name > 20 then
        outputChatBox("Invalid character name", client, 255, 0, 0)
        return
    end
    
    if acc:hasCharacter(name) then
        outputChatBox("You already have a character with that name", client, 255, 0, 0)
        return
    end
    
    for _, otherAcc in pairs(AccountManager.accounts) do
        if otherAcc:hasCharacter(name) then
            outputChatBox("Character name already taken", client, 255, 0, 0)
            return
        end
    end
    
    if not stats or type(stats) ~= "table" then return end
    
    local allowedKeys = {STR=true, DEX=true, CON=true, INT=true, WIS=true, CHA=true}
    local total = 0
    
    for k, v in pairs(stats) do
        if not allowedKeys[k] then return end
        if type(v) ~= "number" or v < 8 or v > 18 then return end
        total = total + (v - 8)
    end
    
    if total ~= 27 then return end
    
    if not skinID or type(skinID) ~= "number" or skinID < 0 or skinID > 312 then
        skinID = (gender == "Female") and 9 or 0
    end
    
    local char = Character:new(name, skinID, gender, acc.id, nil)
    char.stats = stats
    char:saveToDatabase()
    
    local success, err = acc:addCharacter(char)
    if not success then
        outputChatBox(err, client, 255, 0, 0)
        return
    end
    
    outputServerLog("Character created: " .. name .. " for " .. acc.username)
    triggerClientEvent(client, "showCharacterSelect", client, acc:getCharacterListForClient())
end)

addEvent("onCharacterSelect", true)
addEventHandler("onCharacterSelect", resourceRoot, function(name)
    local acc = AccountManager:getAccount(client)
    local char = acc and acc.characters[name]
    
    if not char then return end
    
    AccountManager:setActiveCharacter(client, char)
    triggerClientEvent(client, "hideAllGUI", client)
    char:spawn(client)
    
    outputServerLog("Player " .. getPlayerName(client) .. " selected character: " .. name)
end)

addEvent("onCharacterDelete", true)
addEventHandler("onCharacterDelete", root, function(charName)
    local acc = AccountManager:getAccount(client)
    if not acc then return end
    
    local char = acc.characters[charName]
    if not char then return end
    
    dbExec(database, "DELETE FROM characters WHERE id = ?", char.id)
    dbExec(database, "DELETE FROM character_stats WHERE character_id = ?", char.id)
    dbExec(database, "DELETE FROM inventory WHERE character_id = ?", char.id)
    
    acc.characters[charName] = nil
    
    outputServerLog("Character deleted: " .. charName)
    outputChatBox("Character '" .. charName .. "' deleted", client, 255, 255, 0)
    
    triggerClientEvent(client, "showCharacterSelect", client, acc:getCharacterListForClient())
end)

addEvent("onPlayerRequestCharSelect", true)
addEventHandler("onPlayerRequestCharSelect", root, function()
    local acc = AccountManager:getAccount(client)
    if acc then
        triggerClientEvent(client, "showCharacterSelect", client, acc:getCharacterListForClient())
    end
end)

--------------------------------------------------------------------------------
-- PLAYER EVENTS
--------------------------------------------------------------------------------

addEventHandler("onPlayerJoin", root, function()
    outputServerLog("Player joined: " .. getPlayerName(source))
    triggerClientEvent(source, "showLoginWindow", source)
end)

addEventHandler("onPlayerQuit", root, function()
    local char = AccountManager:getActiveCharacter(source)
    if char then
        char:save(source)
        char:saveToDatabase()
        
        if savePlayerInventory then
            savePlayerInventory(source)
        end
        
        outputServerLog("Saved character on quit: " .. char.name)
    end
    
    AccountManager.loggedInPlayers[source] = nil
    AccountManager.activeCharacters[source] = nil
    if PlayerInventories then
        PlayerInventories[source] = nil
    end
end)

--------------------------------------------------------------------------------
-- COMMANDS
--------------------------------------------------------------------------------

addCommandHandler("givemoney", function(player, cmd, targetName, amount)
    -- Check if DM
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master to use this command", player, 255, 0, 0)
        return
    end
    
    if not targetName or not amount then
        outputChatBox("Usage: /givemoney [player name] [amount]", player, 255, 255, 0)
        return
    end
    
    amount = tonumber(amount)
    if not amount or amount < 1 then
        outputChatBox("Invalid amount", player, 255, 0, 0)
        return
    end
    
    -- Find target player
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
    
    -- Get target's character
    local char = AccountManager:getActiveCharacter(targetPlayer)
    if not char then
        outputChatBox("Target player has no active character", player, 255, 0, 0)
        return
    end
    
    -- Give money
    local currentMoney = getPlayerMoney(targetPlayer)
    setPlayerMoney(targetPlayer, currentMoney + amount)
    char.money = getPlayerMoney(targetPlayer)
    
    -- Notify both players
    local targetCharName = getElementData(targetPlayer, "character.name") or getPlayerName(targetPlayer)
    local dmName = getElementData(player, "character.name") or getPlayerName(player)
    
    outputChatBox("You gave $" .. amount .. " to " .. targetCharName, player, 0, 255, 0)
    outputChatBox("The Dungeon Master gave you $" .. amount, targetPlayer, 0, 255, 0)
    
    outputServerLog("[DM] " .. dmName .. " gave $" .. amount .. " to " .. targetCharName)
end)

addCommandHandler("stats", function(p)
    local c = AccountManager:getActiveCharacter(p)
    if not c then 
        outputChatBox("You must be playing a character", p, 255, 0, 0)
        return 
    end
    
    c:calculateModifiers()
    
    local equipBonuses = getElementData(p, "equipment.bonuses") or {}
    local tempBuffs = getElementData(p, "temp.buffs") or {}
    
    outputChatBox("=== " .. c.name .. "'s Stats ===", p, 255, 255, 0)
    
    for _, stat in ipairs({"STR", "DEX", "CON", "INT", "WIS", "CHA"}) do
        local base = c.stats[stat]
        local mod = c.modifiers[stat]
        local equip = equipBonuses[stat] or 0
        local buff = tempBuffs[stat] or 0
        local total = mod + equip + buff
        
        local modStr = (total >= 0) and ("+" .. total) or tostring(total)
        local line = stat .. ": " .. base .. " (" .. modStr .. ")"
        
        if equip ~= 0 then line = line .. " [Equip:" .. (equip >= 0 and "+" or "") .. equip .. "]" end
        if buff ~= 0 then line = line .. " [Buff:" .. (buff >= 0 and "+" or "") .. buff .. "]" end
        
        outputChatBox(line, p, 200, 200, 200)
    end
    
    outputChatBox("--- Derived Stats ---", p, 255, 200, 100)
    
    local maxHealth = getElementData(p, "maxHealth") or 100
    local speedMult = getElementData(p, "stat.speedMultiplier") or 1.0
    local priceMod = getElementData(p, "stat.priceModifier") or 1.0
    
    outputChatBox("Max HP: " .. maxHealth .. " | Speed: " .. string.format("%.0f%%", speedMult * 100), p, 180, 180, 180)
    outputChatBox("Shop Prices: " .. string.format("%.0f%%", priceMod * 100), p, 180, 180, 180)
end)

addCommandHandler("savechar", function(p)
    local c = AccountManager:getActiveCharacter(p)
    if not c then return end
    
    c:save(p)
    c:saveToDatabase()
    
    if savePlayerInventory then
        savePlayerInventory(p)
    end
    
    outputChatBox("Character saved!", p, 0, 255, 0)
end)

addCommandHandler("refreshstats", function(p)
    local c = AccountManager:getActiveCharacter(p)
    if not c then 
        outputChatBox("You must be playing a character", p, 255, 0, 0)
        return 
    end
    
    c:applyGTAModifiers(p)
    outputChatBox("Stats refreshed!", p, 0, 255, 0)
end)

outputServerLog("===== SERVER.LUA LOADED =====")
