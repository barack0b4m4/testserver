--[[
================================================================================
    ECONOMIC_SYSTEM.LUA - Core Economic Simulation
================================================================================
    Implements a dynamic, player-driven economy with:
    - Market tiers (Global, National, State) as money sources/sinks
    - Company system (Resource, Manufacturing, Retail, Tech, Special)
    - Employee system with labor power
    - Deal system for inter-company trade
    - 24-hour cycle processing
    
    INTEGRATION POINTS:
    ┌─────────────────────────────────────────────────────────────────────────┐
    │ DEPENDS ON:                                                             │
    │   - server.lua: database, AccountManager                                │
    │   - inventory_system.lua: ItemRegistry for item definitions             │
    │   - dungeon_master.lua: isDungeonMaster() for admin commands            │
    │                                                                         │
    │ PROVIDES TO:                                                            │
    │   - client_economy.lua: Company/deal management GUIs                    │
    │   - All scripts: Global economy state                                   │
    │                                                                         │
    │ GLOBAL EXPORTS:                                                         │
    │   - GlobalEconomy: Market state and cycle info                          │
    │   - Companies: All companies keyed by ID                                │
    │   - Deals: All active deals keyed by ID                                 │
    │   - EconomyConfig: Tunable parameters                                   │
    └─────────────────────────────────────────────────────────────────────────┘
================================================================================
]]

outputServerLog("===== ECONOMIC_SYSTEM.LUA LOADING =====")

local db = nil

--------------------------------------------------------------------------------
-- SECTION 1: CONFIGURATION & CONSTANTS
--------------------------------------------------------------------------------

-- Tunable economy parameters
EconomyConfig = {
    -- Cycle timing
    CYCLE_DURATION_HOURS = 24,
    CYCLE_START_HOUR = 0,  -- Midnight EST
    
    -- Labor system
    BASE_LABOR_POWER = 8,
    PLAYER_LABOR_BONUS = 0.5,  -- Players produce 8.5 LP
    SKILLED_EFFICIENCY_BONUS = 1.25,
    
    -- Wage minimums
    WAGE_UNSKILLED = 100,
    WAGE_SKILLED = 250,
    WAGE_PROFESSIONAL = 500,
    
    -- Market consumption (retail)
    RETAIL_MIN_CONSUMPTION = 0.05,  -- 5%
    RETAIL_MAX_CONSUMPTION = 0.15,  -- 15%
    
    -- Deal system
    BASE_DEAL_SLOTS = 2,
    DEAL_SLOTS_PER_PROFESSIONAL = 1,
    
    -- Logistics costs
    LOGISTICS_PER_ITEM_WEIGHT = 0.1,
    LOGISTICS_PER_10K_MONEY = 1,
    LOGISTICS_PER_POINT = 0.01,
    
    -- Starting values
    PLAYER_STARTING_MONEY = 5000,
    COMPANY_STARTING_CAPITAL = 50000,
}

-- Company types
COMPANY_TYPE = {
    RESOURCE = "resource",
    MANUFACTURING = "manufacturing",
    RETAIL = "retail",
    TECH = "tech",
    SPECIAL = "special"
}

-- Employee types
EMPLOYEE_TYPE = {
    UNSKILLED = "unskilled",
    SKILLED = "skilled",
    PROFESSIONAL = "professional"
}

-- Labor allocation options
LABOR_ALLOCATION = {
    ITEMS = "items",
    LOGISTICS = "logistics",
    EFFICIENCY = "efficiency",
    INNOVATION = "innovation"
}

-- Market tiers
MARKET_TIER = {
    GLOBAL = "global",
    NATIONAL = "national",
    STATE = "state"
}

-- Deal status
DEAL_STATUS = {
    PENDING = "pending",
    ACTIVE = "active",
    PAUSED = "paused",
    COMPLETED = "completed",
    FAILED = "failed"
}

--------------------------------------------------------------------------------
-- SECTION 2: GLOBAL STATE
--------------------------------------------------------------------------------

-- Global economy state
GlobalEconomy = {
    currentCycle = 0,
    nextCycleTime = 0,
    cycleTimer = nil,
    markets = {
        global = { money = 78000000000000 },    -- $78 trillion
        national = { money = 22000000000000 },  -- $22 trillion
        state = { money = 800000000000 }        -- $800 billion
    }
}

-- All companies keyed by ID
Companies = Companies or {}

-- All deals keyed by ID
Deals = Deals or {}

-- All employees keyed by ID (for quick lookup)
Employees = Employees or {}

-- Company perks definitions
CompanyPerks = {
    efficiency_boost_1 = { name = "Efficiency I", cost = 100, effect = { efficiency_cap = 5 } },
    efficiency_boost_2 = { name = "Efficiency II", cost = 500, effect = { efficiency_cap = 10 }, requires = "efficiency_boost_1" },
    efficiency_boost_3 = { name = "Efficiency III", cost = 2000, effect = { efficiency_cap = 20 }, requires = "efficiency_boost_2" },
    extra_deal_slot_1 = { name = "Trade Network I", cost = 200, effect = { deal_slots = 1 } },
    extra_deal_slot_2 = { name = "Trade Network II", cost = 1000, effect = { deal_slots = 2 }, requires = "extra_deal_slot_1" },
    wage_reduction_1 = { name = "HR Optimization I", cost = 300, effect = { wage_reduction = 0.05 } },
    wage_reduction_2 = { name = "HR Optimization II", cost = 1500, effect = { wage_reduction = 0.10 }, requires = "wage_reduction_1" },
    logistics_boost_1 = { name = "Logistics I", cost = 250, effect = { logistics_bonus = 10 } },
    logistics_boost_2 = { name = "Logistics II", cost = 1200, effect = { logistics_bonus = 25 }, requires = "logistics_boost_1" },
    production_speed_1 = { name = "Automation I", cost = 400, effect = { production_bonus = 0.10 } },
    production_speed_2 = { name = "Automation II", cost = 2000, effect = { production_bonus = 0.20 }, requires = "production_speed_1" },
}

--------------------------------------------------------------------------------
-- SECTION 3: DATABASE INITIALIZATION
--------------------------------------------------------------------------------

local function initializeEconomyTables()
    if not db then return end
    
    -- Global economy state
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS economy_state (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            current_cycle INTEGER DEFAULT 0,
            next_cycle_time INTEGER,
            market_global REAL DEFAULT 78000000000000,
            market_national REAL DEFAULT 22000000000000,
            market_state REAL DEFAULT 800000000000
        )
    ]])
    
    -- Companies table
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS companies (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            owner_type TEXT DEFAULT 'npc',
            owner_id TEXT,
            creation_cycle INTEGER,
            money REAL DEFAULT 0,
            efficiency REAL DEFAULT 0,
            innovation REAL DEFAULT 0,
            logistics REAL DEFAULT 0,
            current_recipe_id TEXT,
            auto_produce_item TEXT,
            perks TEXT DEFAULT '{}'
        )
    ]])
    
    -- Company inventory
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS company_inventory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id TEXT NOT NULL,
            item_id TEXT NOT NULL,
            quantity INTEGER DEFAULT 0,
            UNIQUE(company_id, item_id),
            FOREIGN KEY (company_id) REFERENCES companies(id)
        )
    ]])
    
    -- Employees table
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS company_employees (
            id TEXT PRIMARY KEY,
            company_id TEXT NOT NULL,
            type TEXT NOT NULL,
            is_player INTEGER DEFAULT 0,
            player_id TEXT,
            character_id INTEGER,
            wage REAL NOT NULL,
            labor_allocation TEXT DEFAULT 'items',
            hire_cycle INTEGER,
            efficiency_modifier REAL DEFAULT 1.0,
            status TEXT DEFAULT 'active',
            FOREIGN KEY (company_id) REFERENCES companies(id)
        )
    ]])
    
    -- Deals table
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS deals (
            id TEXT PRIMARY KEY,
            company_a_id TEXT NOT NULL,
            company_b_id TEXT NOT NULL,
            company_a_provides TEXT NOT NULL,
            company_b_provides TEXT NOT NULL,
            logistics_cost REAL DEFAULT 0,
            duration TEXT DEFAULT 'infinite',
            cycles_remaining INTEGER,
            status TEXT DEFAULT 'pending',
            created_cycle INTEGER,
            FOREIGN KEY (company_a_id) REFERENCES companies(id),
            FOREIGN KEY (company_b_id) REFERENCES companies(id)
        )
    ]])
    
    -- Market transaction log
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS market_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER,
            cycle INTEGER,
            type TEXT NOT NULL,
            market_tier TEXT,
            money_amount REAL,
            money_flow TEXT,
            company_id TEXT,
            player_id TEXT,
            items_involved TEXT,
            description TEXT
        )
    ]])
    
    -- Economic items extension (adds economy-specific fields to items)
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS economy_items (
            item_id TEXT PRIMARY KEY,
            labor_cost REAL DEFAULT 1.0,
            is_market_item INTEGER DEFAULT 0,
            market_tiers TEXT DEFAULT '[]',
            base_price REAL DEFAULT 10,
            logistics_weight REAL DEFAULT 1.0
        )
    ]])
    
    -- Manufacturing recipes
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS economy_recipes (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            company_type TEXT DEFAULT 'manufacturing',
            inputs TEXT NOT NULL,
            outputs TEXT NOT NULL,
            labor_required REAL DEFAULT 8,
            processing_cycles INTEGER DEFAULT 1
        )
    ]])
    
    outputServerLog("Economy database tables initialized")
end

local function loadEconomyState()
    if not db then return end
    
    -- Load or create global economy state
    local query = dbQuery(db, "SELECT * FROM economy_state WHERE id = 1")
    local result = dbPoll(query, -1)
    
    if result and result[1] then
        GlobalEconomy.currentCycle = result[1].current_cycle
        GlobalEconomy.nextCycleTime = result[1].next_cycle_time
        GlobalEconomy.markets.global.money = result[1].market_global
        GlobalEconomy.markets.national.money = result[1].market_national
        GlobalEconomy.markets.state.money = result[1].market_state
        outputServerLog("Loaded economy state: Cycle " .. GlobalEconomy.currentCycle)
    else
        -- Initialize economy state
        GlobalEconomy.nextCycleTime = getRealTime().timestamp + (EconomyConfig.CYCLE_DURATION_HOURS * 3600)
        dbExec(db, [[
            INSERT INTO economy_state (id, current_cycle, next_cycle_time, market_global, market_national, market_state)
            VALUES (1, 0, ?, 78000000000000, 22000000000000, 800000000000)
        ]], GlobalEconomy.nextCycleTime)
        outputServerLog("Initialized new economy state")
    end
end

local function saveEconomyState()
    if not db then return end
    
    dbExec(db, [[
        UPDATE economy_state SET 
            current_cycle = ?,
            next_cycle_time = ?,
            market_global = ?,
            market_national = ?,
            market_state = ?
        WHERE id = 1
    ]], GlobalEconomy.currentCycle, GlobalEconomy.nextCycleTime,
        GlobalEconomy.markets.global.money, GlobalEconomy.markets.national.money, GlobalEconomy.markets.state.money)
end

-- Make globally accessible
_G.saveEconomyState = saveEconomyState

--------------------------------------------------------------------------------
-- SECTION 4: COMPANY MANAGEMENT
--------------------------------------------------------------------------------

--- Create a new company
-- @param name string Company name
-- @param companyType string One of COMPANY_TYPE values
-- @param ownerType string "player" or "npc"
-- @param ownerID string Player account ID or nil for NPC
-- @param startingCapital number Initial money (deducted from state market)
-- @return string|nil Company ID or nil on failure
-- @return string Error message if failed
function createCompany(name, companyType, ownerType, ownerID, startingCapital)
    if not db then return nil, "Database not available" end
    
    -- Validate company type
    local validType = false
    for _, t in pairs(COMPANY_TYPE) do
        if t == companyType then validType = true break end
    end
    if not validType then return nil, "Invalid company type" end
    
    -- Set default starting capital
    startingCapital = startingCapital or EconomyConfig.COMPANY_STARTING_CAPITAL
    
    -- Check if state market has enough money
    if GlobalEconomy.markets.state.money < startingCapital then
        return nil, "State market has insufficient funds"
    end
    
    -- Generate company ID
    local companyID = "company_" .. getRealTime().timestamp .. "_" .. math.random(1000, 9999)
    
    -- Deduct from state market
    GlobalEconomy.markets.state.money = GlobalEconomy.markets.state.money - startingCapital
    
    -- Create company record
    local success = dbExec(db, [[
        INSERT INTO companies (id, name, type, owner_type, owner_id, creation_cycle, money)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], companyID, name, companyType, ownerType, ownerID, GlobalEconomy.currentCycle, startingCapital)
    
    if not success then
        -- Refund market
        GlobalEconomy.markets.state.money = GlobalEconomy.markets.state.money + startingCapital
        return nil, "Database error creating company"
    end
    
    -- Create in-memory company object
    local company = {
        id = companyID,
        name = name,
        type = companyType,
        ownerType = ownerType,
        ownerID = ownerID,
        creationCycle = GlobalEconomy.currentCycle,
        points = {
            money = startingCapital,
            efficiency = 0,
            innovation = 0,
            logistics = 0
        },
        inventory = {},
        employees = {},
        deals = {},
        perks = {},
        production = {
            currentRecipe = nil,
            autoProduceItem = nil
        },
        laborPool = {
            items = 0,
            logistics = 0,
            efficiency = 0,
            innovation = 0
        }
    }
    
    Companies[companyID] = company
    
    -- Log transaction
    logMarketTransaction("COMPANY_CREATION", MARKET_TIER.STATE, startingCapital, "FROM_MARKET", companyID, nil, nil, "Company created: " .. name)
    
    saveEconomyState()
    outputServerLog("Company created: " .. name .. " (" .. companyID .. ") - Type: " .. companyType)
    
    return companyID
end

--- Delete a company and return assets to market
-- @param companyID string Company ID to delete
-- @return boolean Success
-- @return string Message
function deleteCompany(companyID)
    if not db then return false, "Database not available" end
    
    local company = Companies[companyID]
    if not company then return false, "Company not found" end
    
    -- Return money to state market
    GlobalEconomy.markets.state.money = GlobalEconomy.markets.state.money + company.points.money
    
    -- Log transaction
    logMarketTransaction("COMPANY_DELETION", MARKET_TIER.STATE, company.points.money, "TO_MARKET", companyID, nil, nil, "Company deleted: " .. company.name)
    
    -- Fire all employees
    for empID, _ in pairs(company.employees) do
        fireEmployee(companyID, empID)
    end
    
    -- Cancel all deals
    for _, dealID in ipairs(company.deals) do
        if Deals[dealID] then
            Deals[dealID].status = DEAL_STATUS.FAILED
        end
    end
    
    -- Delete from database
    dbExec(db, "DELETE FROM company_inventory WHERE company_id = ?", companyID)
    dbExec(db, "DELETE FROM company_employees WHERE company_id = ?", companyID)
    dbExec(db, "DELETE FROM companies WHERE id = ?", companyID)
    
    -- Remove from memory
    Companies[companyID] = nil
    
    saveEconomyState()
    outputServerLog("Company deleted: " .. companyID)
    
    return true, "Company deleted"
end

--- Get company by ID
-- @param companyID string Company ID
-- @return table|nil Company data
function getCompany(companyID)
    return Companies[companyID]
end

--- Get all companies owned by a player
-- @param playerAccountID string Player's account ID
-- @return table Array of company data
function getPlayerCompanies(playerAccountID)
    local result = {}
    for id, company in pairs(Companies) do
        if company.ownerType == "player" and company.ownerID == playerAccountID then
            table.insert(result, company)
        end
    end
    return result
end

--- Add item to company inventory
-- @param companyID string Company ID
-- @param itemID string Item ID
-- @param quantity number Quantity to add
-- @return boolean Success
function addItemToCompany(companyID, itemID, quantity)
    local company = Companies[companyID]
    if not company then return false end
    
    company.inventory[itemID] = (company.inventory[itemID] or 0) + quantity
    
    -- Update database
    dbExec(db, [[
        INSERT OR REPLACE INTO company_inventory (company_id, item_id, quantity)
        VALUES (?, ?, ?)
    ]], companyID, itemID, company.inventory[itemID])
    
    return true
end

--- Remove item from company inventory
-- @param companyID string Company ID
-- @param itemID string Item ID
-- @param quantity number Quantity to remove
-- @return boolean Success
function removeItemFromCompany(companyID, itemID, quantity)
    local company = Companies[companyID]
    if not company then return false end
    
    if (company.inventory[itemID] or 0) < quantity then
        return false
    end
    
    company.inventory[itemID] = company.inventory[itemID] - quantity
    
    if company.inventory[itemID] <= 0 then
        company.inventory[itemID] = nil
        dbExec(db, "DELETE FROM company_inventory WHERE company_id = ? AND item_id = ?", companyID, itemID)
    else
        dbExec(db, "UPDATE company_inventory SET quantity = ? WHERE company_id = ? AND item_id = ?", 
            company.inventory[itemID], companyID, itemID)
    end
    
    return true
end

--------------------------------------------------------------------------------
-- SECTION 5: EMPLOYEE MANAGEMENT
--------------------------------------------------------------------------------

--- Hire an NPC employee
-- @param companyID string Company ID
-- @param employeeType string One of EMPLOYEE_TYPE values
-- @param wage number Wage per cycle (must meet minimum)
-- @param laborAllocation string One of LABOR_ALLOCATION values
-- @return string|nil Employee ID or nil on failure
-- @return string Error message if failed
function hireNPCEmployee(companyID, employeeType, wage, laborAllocation)
    if not db then return nil, "Database not available" end
    
    local company = Companies[companyID]
    if not company then return nil, "Company not found" end
    
    -- Validate employee type
    local validType = false
    for _, t in pairs(EMPLOYEE_TYPE) do
        if t == employeeType then validType = true break end
    end
    if not validType then return nil, "Invalid employee type" end
    
    -- Check minimum wage
    local minWage = EconomyConfig.WAGE_UNSKILLED
    if employeeType == EMPLOYEE_TYPE.SKILLED then minWage = EconomyConfig.WAGE_SKILLED end
    if employeeType == EMPLOYEE_TYPE.PROFESSIONAL then minWage = EconomyConfig.WAGE_PROFESSIONAL end
    
    if wage < minWage then
        return nil, "Wage below minimum ($" .. minWage .. " for " .. employeeType .. ")"
    end
    
    -- Validate labor allocation based on employee type
    if employeeType == EMPLOYEE_TYPE.PROFESSIONAL then
        if laborAllocation ~= LABOR_ALLOCATION.EFFICIENCY and laborAllocation ~= LABOR_ALLOCATION.INNOVATION then
            return nil, "Professionals can only work on efficiency or innovation"
        end
    else
        if laborAllocation ~= LABOR_ALLOCATION.ITEMS and laborAllocation ~= LABOR_ALLOCATION.LOGISTICS then
            return nil, "Unskilled/Skilled workers can only work on items or logistics"
        end
    end
    
    -- Generate employee ID
    local employeeID = "emp_" .. getRealTime().timestamp .. "_" .. math.random(1000, 9999)
    
    -- Calculate efficiency modifier for skilled workers
    local efficiencyMod = 1.0
    if employeeType == EMPLOYEE_TYPE.SKILLED then
        efficiencyMod = EconomyConfig.SKILLED_EFFICIENCY_BONUS
    end
    
    -- Create employee record
    local success = dbExec(db, [[
        INSERT INTO company_employees (id, company_id, type, is_player, wage, labor_allocation, hire_cycle, efficiency_modifier, status)
        VALUES (?, ?, ?, 0, ?, ?, ?, ?, 'active')
    ]], employeeID, companyID, employeeType, wage, laborAllocation, GlobalEconomy.currentCycle, efficiencyMod)
    
    if not success then return nil, "Database error" end
    
    -- Add to memory
    local employee = {
        id = employeeID,
        companyID = companyID,
        type = employeeType,
        isPlayer = false,
        playerID = nil,
        characterID = nil,
        wage = wage,
        laborAllocation = laborAllocation,
        hireCycle = GlobalEconomy.currentCycle,
        efficiencyModifier = efficiencyMod,
        status = "active"
    }
    
    company.employees[employeeID] = employee
    Employees[employeeID] = employee
    
    outputServerLog("NPC employee hired: " .. employeeID .. " at " .. company.name)
    return employeeID
end

--- Send job offer to a player
-- @param companyID string Company ID
-- @param player element Player to offer job to
-- @param employeeType string One of EMPLOYEE_TYPE values
-- @param wage number Wage per cycle
-- @param laborAllocation string One of LABOR_ALLOCATION values
-- @return boolean Success
function offerJobToPlayer(companyID, player, employeeType, wage, laborAllocation)
    local company = Companies[companyID]
    if not company then return false end
    
    -- Send job offer event to client
    triggerClientEvent(player, "economy:jobOffer", player, {
        companyID = companyID,
        companyName = company.name,
        employeeType = employeeType,
        wage = wage,
        laborAllocation = laborAllocation
    })
    
    return true
end

--- Fire an employee
-- @param companyID string Company ID
-- @param employeeID string Employee ID
-- @return boolean Success
function fireEmployee(companyID, employeeID)
    local company = Companies[companyID]
    if not company then return false end
    
    local employee = company.employees[employeeID]
    if not employee then return false end
    
    -- Notify player if applicable
    if employee.isPlayer and employee.playerID then
        local player = getPlayerFromAccountID(employee.playerID)
        if player then
            triggerClientEvent(player, "economy:fired", player, company.name)
        end
    end
    
    -- Remove from database
    dbExec(db, "DELETE FROM company_employees WHERE id = ?", employeeID)
    
    -- Remove from memory
    company.employees[employeeID] = nil
    Employees[employeeID] = nil
    
    return true
end

--- Change employee's labor allocation
-- @param employeeID string Employee ID
-- @param newAllocation string New labor allocation
-- @return boolean Success
-- @return string Error message if failed
function setEmployeeLaborAllocation(employeeID, newAllocation)
    local employee = Employees[employeeID]
    if not employee then return false, "Employee not found" end
    
    -- Validate allocation for employee type
    if employee.type == EMPLOYEE_TYPE.PROFESSIONAL then
        if newAllocation ~= LABOR_ALLOCATION.EFFICIENCY and newAllocation ~= LABOR_ALLOCATION.INNOVATION then
            return false, "Professionals can only work on efficiency or innovation"
        end
    else
        if newAllocation ~= LABOR_ALLOCATION.ITEMS and newAllocation ~= LABOR_ALLOCATION.LOGISTICS then
            return false, "Unskilled/Skilled workers can only work on items or logistics"
        end
    end
    
    employee.laborAllocation = newAllocation
    dbExec(db, "UPDATE company_employees SET labor_allocation = ? WHERE id = ?", newAllocation, employeeID)
    
    return true
end

--------------------------------------------------------------------------------
-- SECTION 6: MARKET TRANSACTIONS
--------------------------------------------------------------------------------

--- Log a market transaction
function logMarketTransaction(transType, marketTier, amount, flow, companyID, playerID, items, description)
    if not db then return end
    
    local itemsJSON = items and toJSON(items) or "{}"
    
    dbExec(db, [[
        INSERT INTO market_transactions (timestamp, cycle, type, market_tier, money_amount, money_flow, company_id, player_id, items_involved, description)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], getRealTime().timestamp, GlobalEconomy.currentCycle, transType, marketTier, amount, flow, companyID, playerID, itemsJSON, description)
end

--- Sell items to market
-- @param companyID string Company ID
-- @param itemID string Item to sell
-- @param quantity number Quantity to sell
-- @param marketTier string Which market tier to sell to
-- @return boolean Success
-- @return string Message
function sellToMarket(companyID, itemID, quantity, marketTier)
    local company = Companies[companyID]
    if not company then return false, "Company not found" end
    
    -- Check if company has the items
    if (company.inventory[itemID] or 0) < quantity then
        return false, "Insufficient inventory"
    end
    
    -- Get item economy data
    local itemEcon = getItemEconomyData(itemID)
    if not itemEcon then return false, "Item not configured for market" end
    if not itemEcon.isMarketItem then return false, "Item cannot be sold to market" end
    
    -- Check market tier validity
    local validTier = false
    for _, tier in ipairs(itemEcon.marketTiers) do
        if tier == marketTier then validTier = true break end
    end
    if not validTier then return false, "Item cannot be sold to this market tier" end
    
    -- Check minimum quantities for global/national
    if marketTier == MARKET_TIER.GLOBAL and quantity < 100000 then
        return false, "Global market requires minimum 100,000 units"
    end
    if marketTier == MARKET_TIER.NATIONAL and quantity < 1000 then
        return false, "National market requires minimum 1,000 units"
    end
    
    -- Calculate revenue
    local revenue = quantity * itemEcon.basePrice
    
    -- Get market reference
    local market = GlobalEconomy.markets[marketTier]
    if not market then return false, "Invalid market tier" end
    
    -- Check if market has funds
    if market.money < revenue then
        return false, "Market has insufficient funds"
    end
    
    -- Execute transaction
    removeItemFromCompany(companyID, itemID, quantity)
    company.points.money = company.points.money + revenue
    market.money = market.money - revenue
    
    -- Update company in DB
    dbExec(db, "UPDATE companies SET money = ? WHERE id = ?", company.points.money, companyID)
    
    -- Log transaction
    logMarketTransaction("SALE", marketTier, revenue, "FROM_MARKET", companyID, nil, {[itemID] = quantity}, 
        "Sold " .. quantity .. " " .. itemID .. " to " .. marketTier .. " market")
    
    saveEconomyState()
    
    return true, "Sold " .. quantity .. " items for $" .. revenue
end

--- Buy items from market
-- @param companyID string Company ID
-- @param itemID string Item to buy
-- @param quantity number Quantity to buy
-- @param marketTier string Which market tier to buy from (global or national only)
-- @return boolean Success
-- @return string Message
function buyFromMarket(companyID, itemID, quantity, marketTier)
    local company = Companies[companyID]
    if not company then return false, "Company not found" end
    
    -- State market doesn't sell
    if marketTier == MARKET_TIER.STATE then
        return false, "State market does not sell items - buy from other companies"
    end
    
    -- Get item economy data
    local itemEcon = getItemEconomyData(itemID)
    if not itemEcon then return false, "Item not found" end
    if not itemEcon.isMarketItem then return false, "Item not available from market" end
    
    -- Check minimum quantities
    if marketTier == MARKET_TIER.GLOBAL and quantity < 100000 then
        return false, "Global market requires minimum 100,000 units"
    end
    if marketTier == MARKET_TIER.NATIONAL and quantity < 1000 then
        return false, "National market requires minimum 1,000 units"
    end
    
    -- Calculate cost
    local cost = quantity * itemEcon.basePrice
    
    -- Check if company has funds
    if company.points.money < cost then
        return false, "Insufficient funds (need $" .. cost .. ")"
    end
    
    -- Get market reference
    local market = GlobalEconomy.markets[marketTier]
    if not market then return false, "Invalid market tier" end
    
    -- Execute transaction
    company.points.money = company.points.money - cost
    market.money = market.money + cost
    addItemToCompany(companyID, itemID, quantity)
    
    -- Update company in DB
    dbExec(db, "UPDATE companies SET money = ? WHERE id = ?", company.points.money, companyID)
    
    -- Log transaction
    logMarketTransaction("PURCHASE", marketTier, cost, "TO_MARKET", companyID, nil, {[itemID] = quantity},
        "Bought " .. quantity .. " " .. itemID .. " from " .. marketTier .. " market")
    
    saveEconomyState()
    
    return true, "Bought " .. quantity .. " items for $" .. cost
end

--------------------------------------------------------------------------------
-- SECTION 7: UTILITY FUNCTIONS
--------------------------------------------------------------------------------

--- Get item economy data
function getItemEconomyData(itemID)
    if not db then return nil end
    
    local query = dbQuery(db, "SELECT * FROM economy_items WHERE item_id = ?", itemID)
    local result = dbPoll(query, -1)
    
    if result and result[1] then
        local row = result[1]
        return {
            itemID = row.item_id,
            laborCost = row.labor_cost,
            isMarketItem = row.is_market_item == 1,
            marketTiers = fromJSON(row.market_tiers) or {},
            basePrice = row.base_price,
            logisticsWeight = row.logistics_weight
        }
    end
    
    return nil
end

--- Set item economy data
function setItemEconomyData(itemID, laborCost, isMarketItem, marketTiers, basePrice, logisticsWeight)
    if not db then return false end
    
    local tiersJSON = toJSON(marketTiers or {})
    
    dbExec(db, [[
        INSERT OR REPLACE INTO economy_items (item_id, labor_cost, is_market_item, market_tiers, base_price, logistics_weight)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], itemID, laborCost or 1.0, isMarketItem and 1 or 0, tiersJSON, basePrice or 10, logisticsWeight or 1.0)
    
    return true
end

--- Get helper function to find player from account ID
function getPlayerFromAccountID(accountID)
    for _, player in ipairs(getElementsByType("player")) do
        local acc = AccountManager and AccountManager:getAccount(player)
        if acc and acc.id == accountID then
            return player
        end
    end
    return nil
end

--- Format money for display
function formatMoney(amount)
    if amount >= 1000000000000 then
        return string.format("$%.2fT", amount / 1000000000000)
    elseif amount >= 1000000000 then
        return string.format("$%.2fB", amount / 1000000000)
    elseif amount >= 1000000 then
        return string.format("$%.2fM", amount / 1000000)
    elseif amount >= 1000 then
        return string.format("$%.2fK", amount / 1000)
    else
        return string.format("$%.2f", amount)
    end
end

--------------------------------------------------------------------------------
-- SECTION 8: RESOURCE INITIALIZATION
--------------------------------------------------------------------------------

addEventHandler("onResourceStart", resourceRoot, function()
    db = database
    if not db then
        outputServerLog("ERROR: Could not access database for economic system")
        return
    end
    
    initializeEconomyTables()
    loadEconomyState()
    loadAllCompanies()
    loadAllDeals()
    startCycleTimer()
    
    outputServerLog("Economic system initialized - Cycle " .. GlobalEconomy.currentCycle)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    saveEconomyState()
    saveAllCompanies()
    
    if GlobalEconomy.cycleTimer and isTimer(GlobalEconomy.cycleTimer) then
        killTimer(GlobalEconomy.cycleTimer)
    end
end)

outputServerLog("===== ECONOMIC_SYSTEM.LUA LOADED (Part 1) =====")
