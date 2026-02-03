-- MTA San Andreas: Login/Account & Character Creation/Selection System
-- Server-side script with OOP design and SQLite database persistence

--------------------------------------------------------------------------------
-- DATABASE INITIALIZATION
--------------------------------------------------------------------------------

local database = nil

function initializeDatabase()
    -- Connect to SQLite database (creates file if doesn't exist)
    database = dbConnect("sqlite", "serverdata.db")
    
    if not database then
        outputDebugString("ERROR: Failed to connect to database!", 1)
        return false
    end
    
    -- Create accounts table
    dbExec(database, [[
        CREATE TABLE IF NOT EXISTS accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            created_date INTEGER NOT NULL,
            last_login INTEGER NOT NULL
        )
    ]])
    
    -- Create characters table
    dbExec(database, [[
        CREATE TABLE IF NOT EXISTS characters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            skin INTEGER NOT NULL,
            gender TEXT NOT NULL,
            level INTEGER DEFAULT 1,
            money INTEGER DEFAULT 5000,
            health REAL DEFAULT 100,
            armor REAL DEFAULT 0,
            pos_x REAL DEFAULT 0,
            pos_y REAL DEFAULT 0,
            pos_z REAL DEFAULT 3,
            created_date INTEGER NOT NULL,
            play_time INTEGER DEFAULT 0,
            FOREIGN KEY (account_id) REFERENCES accounts(id),
            UNIQUE(account_id, name)
        )
    ]])
    
    -- Create inventory table
    dbExec(database, [[
        CREATE TABLE IF NOT EXISTS inventory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            character_id INTEGER NOT NULL,
            item_id TEXT NOT NULL,
            item_name TEXT NOT NULL,
            weight REAL NOT NULL,
            stackable INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            is_weapon INTEGER NOT NULL,
            weapon_id INTEGER DEFAULT 0,
            current_ammo INTEGER DEFAULT 0,
            max_ammo INTEGER DEFAULT 0,
            FOREIGN KEY (character_id) REFERENCES characters(id)
        )
    ]])
    
    outputDebugString("Database initialized successfully")
    return true
end

-- Initialize database on resource start
addEventHandler("onResourceStart", resourceRoot, function()
    initializeDatabase()
    AccountManager:loadAllAccounts()
end)

--------------------------------------------------------------------------------
-- ACCOUNT CLASS - Manages player accounts
--------------------------------------------------------------------------------

Account = {}
Account.__index = Account

function Account:new(username, passwordHash, dbId)
    local account = {}
    setmetatable(account, Account)
    
    account.id = dbId  -- Database ID
    account.username = username
    account.passwordHash = passwordHash
    account.characters = {}  -- Hash table: characterName -> Character object
    account.createdDate = getRealTime().timestamp
    account.lastLogin = getRealTime().timestamp
    
    return account
end

function Account:saveToDatabase()
    if not self.id then
        -- Insert new account
        local query = dbExec(database, 
            "INSERT INTO accounts (username, password_hash, created_date, last_login) VALUES (?, ?, ?, ?)",
            self.username, self.passwordHash, self.createdDate, self.lastLogin
        )
        
        if query then
            -- Get the auto-generated ID
            local result = dbPoll(dbQuery(database, "SELECT last_insert_rowid() as id"), -1)
            if result and result[1] then
                self.id = result[1].id
            end
        end
    else
        -- Update existing account
        dbExec(database, 
            "UPDATE accounts SET last_login = ? WHERE id = ?",
            self.lastLogin, self.id
        )
    end
end

function Account:addCharacter(character)
    if #self:getCharacterList() >= 3 then  -- Max 3 characters per account
        return false, "Maximum 3 characters per account"
    end
    
    self.characters[character.name] = character
    return true
end

function Account:removeCharacter(characterName)
    if self.characters[characterName] then
        self.characters[characterName] = nil
        return true
    end
    return false
end

function Account:getCharacterList()
    local list = {}
    for _, char in pairs(self.characters) do
        table.insert(list, char)
    end
    return list
end

function Account:hasCharacter(characterName)
    return self.characters[characterName] ~= nil
end


--------------------------------------------------------------------------------
-- CHARACTER CLASS - Manages individual characters
--------------------------------------------------------------------------------

Character = {}
Character.__index = Character

function Character:new(name, skin, gender, accountId, dbId)
    local character = {}
    setmetatable(character, Character)
    
    character.id = dbId  -- Database ID
    character.accountId = accountId  -- Link to account
    character.name = name
    character.skin = skin or 0
    character.gender = gender or "male"
    character.level = 1
    character.money = 5000  -- Starting money
    character.health = 100
    character.armor = 0
    character.position = {x = 0, y = 0, z = 3}  -- Spawn position
    character.createdDate = getRealTime().timestamp
    character.playTime = 0  -- In seconds
    
    return character
end

function Character:saveToDatabase()
    if not self.id then
        -- Insert new character
        dbExec(database,
            [[INSERT INTO characters 
            (account_id, name, skin, gender, level, money, health, armor, pos_x, pos_y, pos_z, created_date, play_time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            self.accountId, self.name, self.skin, self.gender, self.level, self.money,
            self.health, self.armor, self.position.x, self.position.y, self.position.z,
            self.createdDate, self.playTime
        )
        
        -- Get auto-generated ID
        local result = dbPoll(dbQuery(database, "SELECT last_insert_rowid() as id"), -1)
        if result and result[1] then
            self.id = result[1].id
        end
    else
        -- Update existing character
        dbExec(database,
            [[UPDATE characters SET 
            skin = ?, level = ?, money = ?, health = ?, armor = ?,
            pos_x = ?, pos_y = ?, pos_z = ?, play_time = ?
            WHERE id = ?]],
            self.skin, self.level, self.money, self.health, self.armor,
            self.position.x, self.position.y, self.position.z, self.playTime,
            self.id
        )
    end
end

function Character:deleteFromDatabase()
    if self.id then
        dbExec(database, "DELETE FROM characters WHERE id = ?", self.id)
    end
end

function Character:spawn(player)
    spawnPlayer(player, self.position.x, self.position.y, self.position.z, 0, self.skin)
    setElementHealth(player, self.health)
    setPedArmor(player, self.armor)
    setPlayerMoney(player, self.money)
    fadeCamera(player, true)
    setCameraTarget(player, player)
    
    -- Create and load inventory
    local inventory = Inventory:new(self.id, 50.0)
    inventory:loadFromDatabase()
    PlayerInventories[player] = inventory
end

function Character:save(player)
    -- Update character data from current player state
    local x, y, z = getElementPosition(player)
    self.position = {x = x, y = y, z = z}
    self.health = getElementHealth(player)
    self.armor = getPedArmor(player)
    self.money = getPlayerMoney(player)
    self.skin = getElementModel(player)
    
    -- Save inventory and update weapon ammo from equipped weapons
    local inventory = PlayerInventories[player]
    if inventory then
        -- Update ammo for all weapons in inventory from currently equipped weapons
        for _, item in pairs(inventory.items) do
            if getmetatable(item) == Weapon then
                -- Loop through all weapon slots to find this weapon
                for slot = 0, 12 do
                    local weaponID = getPedWeapon(player, slot)
                    if weaponID == item.weaponID then
                        local currentAmmo = getPedTotalAmmo(player, slot)
                        if currentAmmo then
                            item.currentAmmo = currentAmmo
                        end
                        break
                    end
                end
            end
        end
        
        inventory:saveToDatabase()
    end
end


--------------------------------------------------------------------------------
-- INVENTORY SYSTEM
--------------------------------------------------------------------------------

-- ITEM CLASS - Base class for all items
Item = {}
Item.__index = Item

function Item:new(id, name, weight, stackable)
    local item = {}
    setmetatable(item, Item)
    
    item.id = id
    item.name = name
    item.weight = weight or 1.0
    item.stackable = stackable or false
    item.quantity = 1
    
    return item
end

function Item:getTotalWeight()
    return self.weight * self.quantity
end

-- WEAPON CLASS - Extends Item with ammo tracking
Weapon = {}
Weapon.__index = Weapon
setmetatable(Weapon, {__index = Item})

function Weapon:new(id, name, weight, weaponID, maxAmmo)
    local weapon = Item:new(id, name, weight, false)
    setmetatable(weapon, Weapon)
    
    weapon.weaponID = weaponID
    weapon.currentAmmo = 0
    weapon.maxAmmo = maxAmmo or 500
    
    return weapon
end

function Weapon:addAmmo(amount)
    local newAmmo = self.currentAmmo + amount
    if newAmmo > self.maxAmmo then
        local overflow = newAmmo - self.maxAmmo
        self.currentAmmo = self.maxAmmo
        return overflow
    else
        self.currentAmmo = newAmmo
        return 0
    end
end

function Weapon:removeAmmo(amount)
    if self.currentAmmo >= amount then
        self.currentAmmo = self.currentAmmo - amount
        return true
    else
        return false
    end
end

-- INVENTORY CLASS - Manages inventory
Inventory = {}
Inventory.__index = Inventory

function Inventory:new(characterId, maxWeight)
    local inventory = {}
    setmetatable(inventory, Inventory)
    
    inventory.characterId = characterId
    inventory.items = {}
    inventory.maxWeight = maxWeight or 50.0
    inventory.currentWeight = 0
    
    return inventory
end

function Inventory:getCurrentWeight()
    return self.currentWeight
end

function Inventory:canAddItem(item)
    return (self.currentWeight + item:getTotalWeight()) <= self.maxWeight
end

function Inventory:addItem(item)
    local existingItem = self.items[item.id]
    
    if existingItem and item.stackable then
        local weightDiff = item.weight * item.quantity
        
        if self.currentWeight + weightDiff > self.maxWeight then
            return false, "Inventory full"
        end
        
        existingItem.quantity = existingItem.quantity + item.quantity
        self.currentWeight = self.currentWeight + weightDiff
        return true
    end
    
    if not self:canAddItem(item) then
        return false, "Inventory full"
    end
    
    self.items[item.id] = item
    self.currentWeight = self.currentWeight + item:getTotalWeight()
    return true
end

function Inventory:removeItem(itemId, quantity)
    quantity = quantity or 1
    local item = self.items[itemId]
    
    if not item then
        return false
    end
    
    if item.quantity < quantity then
        return false
    end
    
    local weightDiff = item.weight * quantity
    self.currentWeight = self.currentWeight - weightDiff
    
    if item.stackable and item.quantity > quantity then
        item.quantity = item.quantity - quantity
    else
        self.items[itemId] = nil
    end
    
    return true
end

function Inventory:getItem(itemId)
    return self.items[itemId]
end

function Inventory:hasItem(itemId, quantity)
    quantity = quantity or 1
    local item = self.items[itemId]
    return item and item.quantity >= quantity
end

function Inventory:saveToDatabase()
    if not self.characterId then return end
    
    -- Clear old inventory
    dbExec(database, "DELETE FROM inventory WHERE character_id = ?", self.characterId)
    
    -- Save each item
    for _, item in pairs(self.items) do
        local isWeapon = getmetatable(item) == Weapon
        local weaponID = isWeapon and item.weaponID or 0
        local currentAmmo = isWeapon and item.currentAmmo or 0
        local maxAmmo = isWeapon and item.maxAmmo or 0
        
        dbExec(database,
            [[INSERT INTO inventory (character_id, item_id, item_name, weight, stackable, quantity, is_weapon, weapon_id, current_ammo, max_ammo)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            self.characterId, item.id, item.name, item.weight, item.stackable and 1 or 0,
            item.quantity, isWeapon and 1 or 0, weaponID, currentAmmo, maxAmmo
        )
    end
end

function Inventory:loadFromDatabase()
    if not self.characterId then return end
    
    local query = dbQuery(database, "SELECT * FROM inventory WHERE character_id = ?", self.characterId)
    local result = dbPoll(query, -1)
    
    if result then
        for _, row in ipairs(result) do
            local item
            if row.is_weapon == 1 then
                item = Weapon:new(row.item_id, row.item_name, row.weight, row.weapon_id, row.max_ammo)
                item.currentAmmo = row.current_ammo
            else
                item = Item:new(row.item_id, row.item_name, row.weight, row.stackable == 1)
            end
            item.quantity = row.quantity
            
            self.items[item.id] = item
            self.currentWeight = self.currentWeight + item:getTotalWeight()
        end
    end
end

-- Player Inventory Manager
PlayerInventories = {}

function getPlayerInventory(player)
    return PlayerInventories[player]
end


--------------------------------------------------------------------------------
-- ACCOUNT MANAGER - Handles all accounts
--------------------------------------------------------------------------------

AccountManager = {}
AccountManager.accounts = {}  -- Hash table: username -> Account object
AccountManager.loggedInPlayers = {}  -- player -> Account object
AccountManager.activeCharacters = {}  -- player -> Character object

function AccountManager:loadAllAccounts()
    -- Load all accounts from database
    local query = dbQuery(database, "SELECT * FROM accounts")
    local result = dbPoll(query, -1)
    
    if result then
        for _, row in ipairs(result) do
            local account = Account:new(row.username, row.password_hash, row.id)
            account.createdDate = row.created_date
            account.lastLogin = row.last_login
            
            -- Load characters for this account
            self:loadCharactersForAccount(account)
            
            self.accounts[account.username] = account
        end
        outputDebugString("Loaded " .. #result .. " accounts from database")
    end
end

function AccountManager:loadCharactersForAccount(account)
    local query = dbQuery(database, "SELECT * FROM characters WHERE account_id = ?", account.id)
    local result = dbPoll(query, -1)
    
    if result then
        for _, row in ipairs(result) do
            local character = Character:new(row.name, row.skin, row.gender, account.id, row.id)
            character.level = row.level
            character.money = row.money
            character.health = row.health
            character.armor = row.armor
            character.position = {x = row.pos_x, y = row.pos_y, z = row.pos_z}
            character.createdDate = row.created_date
            character.playTime = row.play_time
            
            account.characters[character.name] = character
        end
    end
end

function AccountManager:createAccount(username, password)
    if self.accounts[username] then
        return false, "Username already exists"
    end
    
    local passwordHash = hash("sha256", password)  -- Hash password for security
    local account = Account:new(username, passwordHash)
    account:saveToDatabase()  -- Save to database
    
    self.accounts[username] = account
    
    return true, account
end

function AccountManager:login(player, username, password)
    local account = self.accounts[username]
    
    if not account then
        return false, "Invalid username or password"
    end
    
    local passwordHash = hash("sha256", password)
    if account.passwordHash ~= passwordHash then
        return false, "Invalid username or password"
    end
    
    account.lastLogin = getRealTime().timestamp
    account:saveToDatabase()  -- Update last login in database
    
    self.loggedInPlayers[player] = account
    
    return true, account
end

function AccountManager:logout(player)
    local character = self.activeCharacters[player]
    if character then
        character:save(player)
        character:saveToDatabase()  -- Save to database
    end
    
    self.loggedInPlayers[player] = nil
    self.activeCharacters[player] = nil
end

function AccountManager:isLoggedIn(player)
    return self.loggedInPlayers[player] ~= nil
end

function AccountManager:getAccount(player)
    return self.loggedInPlayers[player]
end

function AccountManager:getActiveCharacter(player)
    return self.activeCharacters[player]
end

function AccountManager:setActiveCharacter(player, character)
    self.activeCharacters[player] = character
end


--------------------------------------------------------------------------------
-- GUI FUNCTIONS - Trigger client-side GUI
--------------------------------------------------------------------------------

function showLoginGUI(player)
    triggerClientEvent(player, "showLoginWindow", player)
end

function showCharacterSelectGUI(player)
    local account = AccountManager:getAccount(player)
    if not account then return end
    
    local characterList = {}
    for _, char in pairs(account.characters) do
        table.insert(characterList, {
            name = char.name,
            level = char.level,
            skin = char.skin,
            gender = char.gender,  -- FIX: Include gender field
            playTime = char.playTime
        })
    end
    
    triggerClientEvent(player, "showCharacterSelect", player, characterList)
end

function showCharacterCreationGUI(player)
    triggerClientEvent(player, "showCharacterCreation", player)
end


--------------------------------------------------------------------------------
-- EVENT HANDLERS - Server-side
--------------------------------------------------------------------------------

-- Handle account registration
addEvent("auth:register", true)
addEventHandler("auth:register", resourceRoot, function(username, password)
    outputDebugString("=== REGISTRATION EVENT TRIGGERED ===")
    outputDebugString("Username: " .. tostring(username))
    outputDebugString("Password length: " .. tostring(#password))
    outputDebugString("Client: " .. tostring(client))
    
    local success, result = AccountManager:createAccount(username, password)
    
    outputDebugString("Registration success: " .. tostring(success))
    outputDebugString("Result: " .. tostring(result))
    
    if success then
        outputChatBox("Account created successfully! Please login.", client, 0, 255, 0)
        triggerClientEvent(client, "registrationResult", client, true)
    else
        outputChatBox("Registration failed: " .. result, client, 255, 0, 0)
        triggerClientEvent(client, "registrationResult", client, false, result)
    end
end)

-- Handle login
addEvent("auth:login", true)
addEventHandler("auth:login", resourceRoot, function(username, password)
    outputDebugString("Login attempt: " .. username)
    local success, result = AccountManager:login(client, username, password)
    
    if success then
        outputChatBox("Login successful! Welcome, " .. username, client, 0, 255, 0)
        
        -- FIX: Trigger loginResult to update client GUI
        triggerClientEvent(client, "loginResult", client, true)
        
        -- Check if account has characters
        local charCount = #result:getCharacterList()
        if charCount == 0 then
            showCharacterCreationGUI(client)
        else
            showCharacterSelectGUI(client)
        end
    else
        outputChatBox("Login failed: " .. result, client, 255, 0, 0)
        triggerClientEvent(client, "loginResult", client, false, result)
    end
end)

-- Handle character creation
addEvent("onCharacterCreate", true)
addEventHandler("onCharacterCreate", resourceRoot, function(charName, skinID, gender)
    local account = AccountManager:getAccount(client)
    if not account then
        outputChatBox("You must be logged in to create a character", client, 255, 0, 0)
        return
    end
    
    -- Validate character name
    if #charName < 3 or #charName > 20 then
        outputChatBox("Character name must be 3-20 characters", client, 255, 0, 0)
        return
    end
    
    if account:hasCharacter(charName) then
        outputChatBox("You already have a character with this name", client, 255, 0, 0)
        return
    end
    
    -- Create character with account ID
    local character = Character:new(charName, skinID, gender, account.id)
    local success, errorMsg = account:addCharacter(character)
    
    if success then
        character:saveToDatabase()  -- Save to database
        outputChatBox("Character '" .. charName .. "' created successfully!", client, 0, 255, 0)
        showCharacterSelectGUI(client)
    else
        outputChatBox("Character creation failed: " .. errorMsg, client, 255, 0, 0)
    end
end)

-- Handle character selection
addEvent("onCharacterSelect", true)
addEventHandler("onCharacterSelect", resourceRoot, function(charName)
    local account = AccountManager:getAccount(client)
    if not account then
        outputChatBox("You must be logged in", client, 255, 0, 0)
        return
    end
    
    local character = account.characters[charName]
    if not character then
        outputChatBox("Character not found", client, 255, 0, 0)
        return
    end
    
    -- Set active character and spawn
    AccountManager:setActiveCharacter(client, character)
    character:spawn(client)
    
    outputChatBox("Welcome back, " .. charName .. "!", client, 0, 255, 0)
    triggerClientEvent(client, "hideAllGUI", client)
end)

-- Handle character deletion
addEvent("onCharacterDelete", true)
addEventHandler("onCharacterDelete", resourceRoot, function(charName)
    local account = AccountManager:getAccount(client)
    if not account then return end
    
    local character = account.characters[charName]
    if character then
        character:deleteFromDatabase()  -- Delete from database
        account:removeCharacter(charName)
        outputChatBox("Character '" .. charName .. "' deleted", client, 255, 255, 0)
        showCharacterSelectGUI(client)
    end
end)

-- FIX: Handle request to go back to character selection (from character creation cancel)
addEvent("onPlayerRequestCharSelect", true)
addEventHandler("onPlayerRequestCharSelect", resourceRoot, function()
    local account = AccountManager:getAccount(client)
    if not account then
        -- Not logged in, show login
        showLoginGUI(client)
        return
    end
    
    -- Check if account has characters
    local charCount = #account:getCharacterList()
    if charCount == 0 then
        -- No characters, show creation again
        showCharacterCreationGUI(client)
    else
        -- Has characters, show selection
        showCharacterSelectGUI(client)
    end
end)

-- Player joins server
addEventHandler("onPlayerJoin", root, function()
    fadeCamera(source, false)
    showLoginGUI(source)
end)

-- Player quits server
addEventHandler("onPlayerQuit", root, function()
    AccountManager:logout(source)
    -- Clean up inventory
    PlayerInventories[source] = nil
end)

-- Periodically save active characters
setTimer(function()
    for player, character in pairs(AccountManager.activeCharacters) do
        if isElement(player) then
            character:save(player)
            character:saveToDatabase()  -- Save to database
        end
    end
end, 60000, 0)  -- Save every 60 seconds

-- Save all characters on server shutdown
addEventHandler("onResourceStop", resourceRoot, function()
    outputDebugString("[AUTH SYSTEM] Saving all characters before shutdown...")
    for player, character in pairs(AccountManager.activeCharacters) do
        if isElement(player) then
            character:save(player)
            character:saveToDatabase()
        end
    end
    outputDebugString("[AUTH SYSTEM] All characters saved")
    
    -- Clean up inventories
    PlayerInventories = {}
end)


--------------------------------------------------------------------------------
-- INVENTORY COMMANDS
--------------------------------------------------------------------------------

-- Command: /inventory - Show player's inventory
addCommandHandler("inventory", function(player)
    local inv = getPlayerInventory(player)
    if not inv then
        outputChatBox("You must be playing with a character first", player, 255, 0, 0)
        return
    end
    
    outputChatBox("========== INVENTORY ==========", player, 255, 255, 0)
    outputChatBox("Weight: " .. string.format("%.1f", inv:getCurrentWeight()) .. "/" .. inv.maxWeight .. " kg", player, 255, 255, 255)
    
    local itemCount = 0
    for _ in pairs(inv.items) do itemCount = itemCount + 1 end
    
    if itemCount == 0 then
        outputChatBox("Empty", player, 200, 200, 200)
    else
        local i = 1
        for _, item in pairs(inv.items) do
            local info = i .. ". " .. item.name
            
            if item.stackable and item.quantity > 1 then
                info = info .. " x" .. item.quantity
            end
            
            info = info .. " (" .. string.format("%.1f", item:getTotalWeight()) .. " kg)"
            
            if getmetatable(item) == Weapon then
                info = info .. " [" .. item.currentAmmo .. "/" .. item.maxAmmo .. " rounds]"
            end
            
            outputChatBox(info, player, 255, 255, 255)
            i = i + 1
        end
    end
    outputChatBox("===============================", player, 255, 255, 0)
end)

-- Command: /giveme [itemname] - Give yourself an item (testing)
addCommandHandler("giveme", function(player, cmd, itemName)
    local inv = getPlayerInventory(player)
    if not inv then
        outputChatBox("You must be playing with a character first", player, 255, 0, 0)
        return
    end
    
    if not itemName then
        outputChatBox("Usage: /giveme [medkit|food|armor|m4|pistol|shotgun]", player)
        return
    end
    
    -- Create item based on name
    local item
    if itemName == "medkit" then
        item = Item:new("medkit", "Medical Kit", 2.0, true)
        item.quantity = 5
    elseif itemName == "food" then
        item = Item:new("food", "Canned Food", 0.5, true)
        item.quantity = 10
    elseif itemName == "armor" then
        item = Item:new("armor", "Body Armor", 5.0, false)
    elseif itemName == "m4" then
        item = Weapon:new("m4", "M4 Rifle", 3.5, 31, 500)
        item:addAmmo(100)
    elseif itemName == "pistol" then
        item = Weapon:new("pistol", "9mm Pistol", 1.0, 22, 200)
        item:addAmmo(50)
    elseif itemName == "shotgun" then
        item = Weapon:new("shotgun", "Shotgun", 4.0, 25, 100)
        item:addAmmo(30)
    else
        outputChatBox("Unknown item: " .. itemName, player, 255, 0, 0)
        return
    end
    
    local success, err = inv:addItem(item)
    if success then
        outputChatBox("Added " .. item.name .. " to inventory", player, 0, 255, 0)
    else
        outputChatBox("Failed to add item: " .. err, player, 255, 0, 0)
    end
end)

-- Command: /equip [weaponname] - Equip a weapon from inventory
addCommandHandler("equip", function(player, cmd, weaponName)
    local inv = getPlayerInventory(player)
    if not inv then
        outputChatBox("You must be playing with a character first", player, 255, 0, 0)
        return
    end
    
    if not weaponName then
        outputChatBox("Usage: /equip [m4|pistol|shotgun]", player)
        return
    end
    
    local item = inv:getItem(weaponName)
    if not item then
        outputChatBox("Weapon not in inventory", player, 255, 0, 0)
        return
    end
    
    if getmetatable(item) == Weapon then
        -- Check if player already has this exact weapon (by checking total ammo in weapon slot)
        local currentAmmoInSlot = getPedTotalAmmo(player, getPedWeaponSlot(item.weaponID))
        
        if currentAmmoInSlot and currentAmmoInSlot > 0 then
            -- Player has a weapon in this slot, check if it's the same weapon
            local weaponInSlot = getPedWeapon(player, getPedWeaponSlot(item.weaponID))
            if weaponInSlot == item.weaponID then
                outputChatBox("You already have this weapon equipped", player, 255, 255, 0)
                return
            end
        end
        
        giveWeapon(player, item.weaponID, item.currentAmmo, true)
        outputChatBox("Equipped " .. item.name .. " (" .. item.currentAmmo .. " rounds)", player, 0, 255, 0)
    else
        outputChatBox("This item is not a weapon", player, 255, 0, 0)
    end
end)

-- Command: /unequip [weaponname] - Unequip a weapon and save ammo to inventory
addCommandHandler("unequip", function(player, cmd, weaponName)
    local inv = getPlayerInventory(player)
    if not inv then
        outputChatBox("You must be playing with a character first", player, 255, 0, 0)
        return
    end
    
    if not weaponName then
        outputChatBox("Usage: /unequip [m4|pistol|shotgun]", player)
        return
    end
    
    local item = inv:getItem(weaponName)
    if not item then
        outputChatBox("Weapon not in inventory", player, 255, 0, 0)
        return
    end
    
    if getmetatable(item) == Weapon then
        -- Check all weapon slots to find this weapon
        local currentAmmo = 0
        local hasWeapon = false
        
        for slot = 0, 12 do
            local weaponID = getPedWeapon(player, slot)
            if weaponID == item.weaponID then
                currentAmmo = getPedTotalAmmo(player, slot)
                hasWeapon = true
                break
            end
        end
        
        if hasWeapon then
            -- Update inventory ammo
            item.currentAmmo = currentAmmo
            
            -- Remove weapon from player
            takeWeapon(player, item.weaponID)
            
            outputChatBox("Unequipped " .. item.name .. " (saved " .. currentAmmo .. " rounds)", player, 0, 255, 0)
        else
            outputChatBox("You don't have this weapon equipped", player, 255, 255, 0)
        end
    else
        outputChatBox("This item is not a weapon", player, 255, 0, 0)
    end
end)

-- Command: /drop [itemname] [quantity] - Drop an item
addCommandHandler("drop", function(player, cmd, itemName, quantity)
    local inv = getPlayerInventory(player)
    if not inv then
        outputChatBox("You must be playing with a character first", player, 255, 0, 0)
        return
    end
    
    if not itemName then
        outputChatBox("Usage: /drop [itemname] [quantity]", player)
        return
    end
    
    quantity = tonumber(quantity) or 1
    
    if inv:removeItem(itemName, quantity) then
        outputChatBox("Dropped " .. quantity .. "x " .. itemName, player, 255, 255, 0)
    else
        outputChatBox("Item not found or insufficient quantity", player, 255, 0, 0)
    end
end)


--------------------------------------------------------------------------------
-- ADMIN COMMANDS
--------------------------------------------------------------------------------

-- Command: /createchar - Force show character creation
addCommandHandler("createchar", function(player)
    if AccountManager:isLoggedIn(player) then
        showCharacterCreationGUI(player)
    else
        outputChatBox("You must be logged in first", player, 255, 0, 0)
    end
end)

-- Command: /selectchar - Force show character selection
addCommandHandler("selectchar", function(player)
    if AccountManager:isLoggedIn(player) then
        showCharacterSelectGUI(player)
    else
        outputChatBox("You must be logged in first", player, 255, 0, 0)
    end
end)


--------------------------------------------------------------------------------
-- NOTES
--------------------------------------------------------------------------------

--[[
DATABASE STRUCTURE:
This system now uses SQLite for persistent storage. Data is saved to "serverdata.db"

TABLES:
1. accounts - Stores user accounts with hashed passwords
2. characters - Stores character data linked to accounts via account_id

DATA PERSISTENCE:
- Accounts are saved immediately on creation
- Characters are saved immediately on creation/deletion
- Active characters auto-save every 60 seconds
- Character data saves on player quit
- All data loads from database on server start

CLIENT-SIDE SCRIPTS NEEDED:
1. client_login.lua - Login/Register GUI
2. client_char_select.lua - Character selection GUI
3. client_char_create.lua - Character creation GUI with skin preview

NEXT STEPS FOR ENHANCEMENT:
- Add bcrypt/argon2 password hashing (more secure than SHA256)
- Add rate limiting for login attempts
- Add session tokens
- Add email verification
- Add password recovery system
- Add admin panel for account management
- Add ban system (store banned accounts in database)
- Add inventory system integration (save inventory to database)
- Add skill/stats system
- Add vehicle ownership
- Add property/house ownership

SECURITY NOTES:
- Passwords are hashed with SHA256 before storage
- Never send plaintext passwords in events (already doing this)
- Validate all client input on server-side (already doing this)
- Consider adding salt to password hashing for extra security
- Add brute force protection (limit login attempts per IP)

DATABASE FILE LOCATION:
The database file "serverdata.db" is created in your MTA server's resource folder.
Make sure to back this up regularly!
]]--


--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- PERSISTENT VEHICLE SYSTEM
--------------------------------------------------------------------------------

-- VEHICLE CLASS - Manages persistent vehicles
Vehicle = {}
Vehicle.__index = Vehicle

function Vehicle:new(id, model, x, y, z, rx, ry, rz, color1, color2, health, locked)
    local vehicle = {}
    setmetatable(vehicle, Vehicle)
    
    vehicle.id = id  -- Database ID (nil if not saved yet)
    vehicle.model = model
    vehicle.position = {x = x, y = y, z = z}
    vehicle.rotation = {x = rx or 0, y = ry or 0, z = rz or 0}
    vehicle.color1 = color1 or {math.random(0, 255), math.random(0, 255), math.random(0, 255)}
    vehicle.color2 = color2 or {math.random(0, 255), math.random(0, 255), math.random(0, 255)}
    vehicle.health = health or 1000
    vehicle.locked = locked or false
    vehicle.element = nil  -- MTA vehicle element
    
    return vehicle
end

function Vehicle:spawn()
    if self.element and isElement(self.element) then
        destroyElement(self.element)
    end
    
    -- Create vehicle in world
    self.element = createVehicle(
        self.model,
        self.position.x, self.position.y, self.position.z,
        self.rotation.x, self.rotation.y, self.rotation.z
    )
    
    if self.element then
        -- Set properties
        setVehicleColor(self.element, 
            self.color1[1], self.color1[2], self.color1[3],
            self.color2[1], self.color2[2], self.color2[3]
        )
        setElementHealth(self.element, self.health)
        setVehicleLocked(self.element, self.locked)
        
        -- Store vehicle ID in element data
        setElementData(self.element, "vehicle:id", self.id)
        setElementData(self.element, "vehicle:persistent", true)
    end
    
    return self.element
end

function Vehicle:updateFromElement()
    if self.element and isElement(self.element) then
        local x, y, z = getElementPosition(self.element)
        local rx, ry, rz = getElementRotation(self.element)
        
        self.position = {x = x, y = y, z = z}
        self.rotation = {x = rx, y = ry, z = rz}
        self.health = getElementHealth(self.element)
        
        -- Get colors
        local r1, g1, b1, r2, g2, b2 = getVehicleColor(self.element, true)
        self.color1 = {r1, g1, b1}
        self.color2 = {r2, g2, b2}
    end
end

function Vehicle:saveToDatabase()
    self:updateFromElement()
    
    if not self.id then
        -- Insert new vehicle
        dbExec(database,
            [[INSERT INTO vehicles 
            (model, pos_x, pos_y, pos_z, rot_x, rot_y, rot_z, 
             color1_r, color1_g, color1_b, color2_r, color2_g, color2_b,
             health, locked)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            self.model,
            self.position.x, self.position.y, self.position.z,
            self.rotation.x, self.rotation.y, self.rotation.z,
            self.color1[1], self.color1[2], self.color1[3],
            self.color2[1], self.color2[2], self.color2[3],
            self.health, self.locked and 1 or 0
        )
        
        -- Get auto-generated ID
        local result = dbPoll(dbQuery(database, "SELECT last_insert_rowid() as id"), -1)
        if result and result[1] then
            self.id = result[1].id
            if self.element then
                setElementData(self.element, "vehicle:id", self.id)
            end
        end
    else
        -- Update existing vehicle
        dbExec(database,
            [[UPDATE vehicles SET 
            model = ?, pos_x = ?, pos_y = ?, pos_z = ?,
            rot_x = ?, rot_y = ?, rot_z = ?,
            color1_r = ?, color1_g = ?, color1_b = ?,
            color2_r = ?, color2_g = ?, color2_b = ?,
            health = ?, locked = ?
            WHERE id = ?]],
            self.model,
            self.position.x, self.position.y, self.position.z,
            self.rotation.x, self.rotation.y, self.rotation.z,
            self.color1[1], self.color1[2], self.color1[3],
            self.color2[1], self.color2[2], self.color2[3],
            self.health, self.locked and 1 or 0,
            self.id
        )
    end
end

function Vehicle:deleteFromDatabase()
    if self.id then
        dbExec(database, "DELETE FROM vehicles WHERE id = ?", self.id)
    end
    
    if self.element and isElement(self.element) then
        destroyElement(self.element)
    end
end

-- VEHICLE MANAGER - Manages all persistent vehicles
VehicleManager = {}
VehicleManager.vehicles = {}  -- Table of all Vehicle objects

function VehicleManager:loadAll()
    local query = dbQuery(database, "SELECT * FROM vehicles")
    local result = dbPoll(query, -1)
    
    if result then
        for _, row in ipairs(result) do
            local vehicle = Vehicle:new(
                row.id,
                row.model,
                row.pos_x, row.pos_y, row.pos_z,
                row.rot_x, row.rot_y, row.rot_z,
                {row.color1_r, row.color1_g, row.color1_b},
                {row.color2_r, row.color2_g, row.color2_b},
                row.health,
                row.locked == 1
            )
            
            vehicle:spawn()
            self.vehicles[vehicle.id] = vehicle
        end
        
        outputDebugString("[VEHICLE SYSTEM] Loaded " .. #result .. " vehicles")
    end
end

function VehicleManager:saveAll()
    for _, vehicle in pairs(self.vehicles) do
        vehicle:saveToDatabase()
    end
    outputDebugString("[VEHICLE SYSTEM] Saved all vehicles")
end

function VehicleManager:createVehicle(model, x, y, z, rx, ry, rz)
    local vehicle = Vehicle:new(nil, model, x, y, z, rx, ry, rz)
    vehicle:spawn()
    vehicle:saveToDatabase()
    
    if vehicle.id then
        self.vehicles[vehicle.id] = vehicle
    end
    
    return vehicle
end

function VehicleManager:deleteVehicle(vehicleId)
    local vehicle = self.vehicles[vehicleId]
    if vehicle then
        vehicle:deleteFromDatabase()
        self.vehicles[vehicleId] = nil
        return true
    end
    return false
end

function VehicleManager:getVehicleByElement(element)
    local vehicleId = getElementData(element, "vehicle:id")
    if vehicleId then
        return self.vehicles[vehicleId]
    end
    return nil
end

-- Initialize vehicle system on resource start
addEventHandler("onResourceStart", resourceRoot, function()
    -- Create vehicles table in database
    dbExec(database, [[
        CREATE TABLE IF NOT EXISTS vehicles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model INTEGER NOT NULL,
            pos_x REAL NOT NULL,
            pos_y REAL NOT NULL,
            pos_z REAL NOT NULL,
            rot_x REAL DEFAULT 0,
            rot_y REAL DEFAULT 0,
            rot_z REAL DEFAULT 0,
            color1_r INTEGER DEFAULT 0,
            color1_g INTEGER DEFAULT 0,
            color1_b INTEGER DEFAULT 0,
            color2_r INTEGER DEFAULT 0,
            color2_g INTEGER DEFAULT 0,
            color2_b INTEGER DEFAULT 0,
            health REAL DEFAULT 1000,
            locked INTEGER DEFAULT 0
        )
    ]])
    
    -- Load all vehicles
    VehicleManager:loadAll()
end)

-- Save all vehicles periodically
setTimer(function()
    VehicleManager:saveAll()
end, 120000, 0)  -- Save every 2 minutes

-- Save vehicles on resource stop
addEventHandler("onResourceStop", resourceRoot, function()
    VehicleManager:saveAll()
end)


--------------------------------------------------------------------------------
-- VEHICLE COMMANDS
--------------------------------------------------------------------------------

-- Command: /createveh [model] - Create a vehicle at your position
addCommandHandler("createveh", function(player, cmd, model)
    model = tonumber(model)
    
    if not model or model < 400 or model > 611 then
        outputChatBox("Usage: /createveh [model] (400-611)", player, 255, 100, 100)
        outputChatBox("Example: /createveh 411 (creates Infernus)", player, 255, 255, 255)
        return
    end
    
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    
    -- Spawn vehicle in front of player
    local offsetX = x + math.cos(math.rad(rz)) * 5
    local offsetY = y + math.sin(math.rad(rz)) * 5
    
    local vehicle = VehicleManager:createVehicle(model, offsetX, offsetY, z, 0, 0, rz)
    
    if vehicle then
        outputChatBox("Vehicle created! (ID: " .. vehicle.id .. ")", player, 0, 255, 0)
    else
        outputChatBox("Failed to create vehicle", player, 255, 0, 0)
    end
end)

-- Command: /nearestveh - Get info about nearest vehicle
addCommandHandler("nearestveh", function(player)
    local x, y, z = getElementPosition(player)
    local nearestVeh = nil
    local nearestDist = 999999
    
    for _, vehicle in pairs(VehicleManager.vehicles) do
        if vehicle.element and isElement(vehicle.element) then
            local vx, vy, vz = getElementPosition(vehicle.element)
            local dist = getDistanceBetweenPoints3D(x, y, z, vx, vy, vz)
            
            if dist < nearestDist then
                nearestDist = dist
                nearestVeh = vehicle
            end
        end
    end
    
    if nearestVeh then
        outputChatBox("========== NEAREST VEHICLE ==========", player, 255, 255, 0)
        outputChatBox("ID: " .. nearestVeh.id, player, 255, 255, 255)
        outputChatBox("Model: " .. nearestVeh.model .. " (" .. getVehicleName(nearestVeh.element) .. ")", player, 255, 255, 255)
        outputChatBox("Distance: " .. string.format("%.1f", nearestDist) .. "m", player, 255, 255, 255)
        outputChatBox("Health: " .. string.format("%.0f", nearestVeh.health), player, 255, 255, 255)
        outputChatBox("====================================", player, 255, 255, 0)
    else
        outputChatBox("No vehicles found", player, 255, 0, 0)
    end
end)

-- Command: /delveh - Delete nearest vehicle
addCommandHandler("delveh", function(player)
    local x, y, z = getElementPosition(player)
    local nearestVeh = nil
    local nearestDist = 999999
    
    for _, vehicle in pairs(VehicleManager.vehicles) do
        if vehicle.element and isElement(vehicle.element) then
            local vx, vy, vz = getElementPosition(vehicle.element)
            local dist = getDistanceBetweenPoints3D(x, y, z, vx, vy, vz)
            
            if dist < nearestDist then
                nearestDist = dist
                nearestVeh = vehicle
            end
        end
    end
    
    if nearestVeh and nearestDist < 10 then
        VehicleManager:deleteVehicle(nearestVeh.id)
        outputChatBox("Vehicle deleted (ID: " .. nearestVeh.id .. ")", player, 255, 255, 0)
    else
        outputChatBox("No vehicle nearby (must be within 10m)", player, 255, 0, 0)
    end
end)

-- Command: /savevehicles - Manually save all vehicles
addCommandHandler("savevehicles", function(player)
    VehicleManager:saveAll()
    outputChatBox("All vehicles saved to database", player, 0, 255, 0)
end)

-- Command: /vehtotal - Show total vehicle count
addCommandHandler("vehtotal", function(player)
    local count = 0
    for _ in pairs(VehicleManager.vehicles) do
        count = count + 1
    end
    outputChatBox("Total persistent vehicles: " .. count, player, 255, 255, 0)
end)

-- Command: /repairveh - Repair nearest vehicle
addCommandHandler("repairveh", function(player)
    local x, y, z = getElementPosition(player)
    local nearestVeh = nil
    local nearestDist = 999999
    
    for _, vehicle in pairs(VehicleManager.vehicles) do
        if vehicle.element and isElement(vehicle.element) then
            local vx, vy, vz = getElementPosition(vehicle.element)
            local dist = getDistanceBetweenPoints3D(x, y, z, vx, vy, vz)
            
            if dist < nearestDist then
                nearestDist = dist
                nearestVeh = vehicle
            end
        end
    end
    
    if nearestVeh and nearestDist < 10 then
        fixVehicle(nearestVeh.element)
        setElementHealth(nearestVeh.element, 1000)
        nearestVeh.health = 1000
        outputChatBox("Vehicle repaired!", player, 0, 255, 0)
    else
        outputChatBox("No vehicle nearby (must be within 10m)", player, 255, 0, 0)
    end
end)
