--[[
================================================================================
    ECONOMIC_CYCLE.LUA - Cycle Processing & Deal System
================================================================================
    Handles the 24-hour economic cycle including:
    - Labor power deposit
    - Production processing
    - Deal execution
    - Retail sales
    - Wage payment
    - NPC profit return
    
    This file extends economic_system.lua
================================================================================
]]

outputServerLog("===== ECONOMIC_CYCLE.LUA LOADING =====")

--------------------------------------------------------------------------------
-- SECTION 1: DEAL MANAGEMENT
--------------------------------------------------------------------------------

--- Create a new deal between two companies
-- @param companyAID string First company ID
-- @param companyBID string Second company ID
-- @param companyAProvides table What company A provides {items={}, money=0, efficiency=0, innovation=0, logistics=0}
-- @param companyBProvides table What company B provides
-- @param duration string|number "infinite" or number of cycles
-- @return string|nil Deal ID or nil on failure
-- @return string Error message if failed
function createDeal(companyAID, companyBID, companyAProvides, companyBProvides, duration)
    local companyA = Companies[companyAID]
    local companyB = Companies[companyBID]
    
    if not companyA then return nil, "Company A not found" end
    if not companyB then return nil, "Company B not found" end
    if companyAID == companyBID then return nil, "Cannot create deal with self" end
    
    -- Check deal capacity for both companies
    local aCapacity = getCompanyDealCapacity(companyA)
    local bCapacity = getCompanyDealCapacity(companyB)
    
    if #companyA.deals >= aCapacity then
        return nil, companyA.name .. " has reached deal capacity"
    end
    if #companyB.deals >= bCapacity then
        return nil, companyB.name .. " has reached deal capacity"
    end
    
    -- Calculate logistics cost
    local logisticsCost = calculateLogisticsCost(companyAProvides, companyBProvides)
    
    -- Generate deal ID
    local dealID = "deal_" .. getRealTime().timestamp .. "_" .. math.random(1000, 9999)
    
    -- Create deal object
    local deal = {
        id = dealID,
        companyAID = companyAID,
        companyBID = companyBID,
        companyAProvides = companyAProvides,
        companyBProvides = companyBProvides,
        logisticsCost = logisticsCost,
        duration = duration,
        cyclesRemaining = (duration ~= "infinite") and tonumber(duration) or nil,
        status = DEAL_STATUS.PENDING,
        createdCycle = GlobalEconomy.currentCycle
    }
    
    -- Save to database
    local success = dbExec(database, [[
        INSERT INTO deals (id, company_a_id, company_b_id, company_a_provides, company_b_provides, logistics_cost, duration, cycles_remaining, status, created_cycle)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], dealID, companyAID, companyBID, toJSON(companyAProvides), toJSON(companyBProvides), 
        logisticsCost, tostring(duration), deal.cyclesRemaining, deal.status, deal.createdCycle)
    
    if not success then return nil, "Database error" end
    
    -- Add to memory
    Deals[dealID] = deal
    table.insert(companyA.deals, dealID)
    table.insert(companyB.deals, dealID)
    
    outputServerLog("Deal created: " .. dealID .. " between " .. companyA.name .. " and " .. companyB.name)
    
    return dealID
end

--- Accept a pending deal
-- @param dealID string Deal ID
-- @param companyID string Company accepting (must be party to deal)
-- @return boolean Success
function acceptDeal(dealID, companyID)
    local deal = Deals[dealID]
    if not deal then return false, "Deal not found" end
    if deal.status ~= DEAL_STATUS.PENDING then return false, "Deal is not pending" end
    
    if deal.companyAID ~= companyID and deal.companyBID ~= companyID then
        return false, "Company is not party to this deal"
    end
    
    deal.status = DEAL_STATUS.ACTIVE
    dbExec(database, "UPDATE deals SET status = ? WHERE id = ?", DEAL_STATUS.ACTIVE, dealID)
    
    return true, "Deal accepted"
end

--- Cancel a deal
-- @param dealID string Deal ID
-- @param companyID string Company canceling (must be party to deal)
-- @return boolean Success
function cancelDeal(dealID, companyID)
    local deal = Deals[dealID]
    if not deal then return false, "Deal not found" end
    
    if deal.companyAID ~= companyID and deal.companyBID ~= companyID then
        return false, "Company is not party to this deal"
    end
    
    deal.status = DEAL_STATUS.FAILED
    dbExec(database, "UPDATE deals SET status = ? WHERE id = ?", DEAL_STATUS.FAILED, dealID)
    
    -- Remove from company deal lists
    local companyA = Companies[deal.companyAID]
    local companyB = Companies[deal.companyBID]
    
    if companyA then
        for i, did in ipairs(companyA.deals) do
            if did == dealID then table.remove(companyA.deals, i) break end
        end
    end
    if companyB then
        for i, did in ipairs(companyB.deals) do
            if did == dealID then table.remove(companyB.deals, i) break end
        end
    end
    
    return true, "Deal cancelled"
end

--- Calculate logistics cost for a deal
-- @param providesA table What company A provides
-- @param providesB table What company B provides
-- @return number Total logistics cost
function calculateLogisticsCost(providesA, providesB)
    local cost = 0
    
    -- Helper to calculate cost for one side
    local function calcSide(provides)
        local sideCost = 0
        
        -- Items cost the most
        if provides.items then
            for itemID, quantity in pairs(provides.items) do
                local itemEcon = getItemEconomyData(itemID)
                local weight = itemEcon and itemEcon.logisticsWeight or 1.0
                sideCost = sideCost + (quantity * weight * EconomyConfig.LOGISTICS_PER_ITEM_WEIGHT)
            end
        end
        
        -- Currency costs moderate amount
        if provides.money and provides.money > 0 then
            sideCost = sideCost + (provides.money / 10000) * EconomyConfig.LOGISTICS_PER_10K_MONEY
        end
        
        -- Points cost minimal
        local points = (provides.efficiency or 0) + (provides.innovation or 0)
        sideCost = sideCost + (points * EconomyConfig.LOGISTICS_PER_POINT)
        
        return sideCost
    end
    
    cost = calcSide(providesA) + calcSide(providesB)
    
    -- Special case: logistics trades require 0 logistics
    local isLogisticsDeal = (providesA.logistics and providesA.logistics > 0) or 
                           (providesB.logistics and providesB.logistics > 0)
    local onlyLogistics = true
    
    if providesA.items and next(providesA.items) then onlyLogistics = false end
    if providesB.items and next(providesB.items) then onlyLogistics = false end
    if (providesA.money or 0) > 0 then onlyLogistics = false end
    if (providesB.money or 0) > 0 then onlyLogistics = false end
    if (providesA.efficiency or 0) > 0 then onlyLogistics = false end
    if (providesB.efficiency or 0) > 0 then onlyLogistics = false end
    if (providesA.innovation or 0) > 0 then onlyLogistics = false end
    if (providesB.innovation or 0) > 0 then onlyLogistics = false end
    
    if isLogisticsDeal and onlyLogistics then
        cost = 0
    end
    
    return cost
end

--- Get company's maximum deal capacity
-- @param company table Company data
-- @return number Maximum simultaneous deals
function getCompanyDealCapacity(company)
    local capacity = EconomyConfig.BASE_DEAL_SLOTS
    
    -- Count professional employees
    for _, emp in pairs(company.employees) do
        if emp.type == EMPLOYEE_TYPE.PROFESSIONAL then
            capacity = capacity + EconomyConfig.DEAL_SLOTS_PER_PROFESSIONAL
        end
    end
    
    -- Add perk bonuses
    if company.perks.extra_deal_slot_1 then capacity = capacity + 1 end
    if company.perks.extra_deal_slot_2 then capacity = capacity + 2 end
    
    return capacity
end

--- Check if company has resources for deal
-- @param company table Company data
-- @param provides table What the company must provide
-- @return boolean Has all required resources
function companyHasResources(company, provides)
    -- Check items
    if provides.items then
        for itemID, quantity in pairs(provides.items) do
            if (company.inventory[itemID] or 0) < quantity then
                return false
            end
        end
    end
    
    -- Check money
    if (provides.money or 0) > company.points.money then
        return false
    end
    
    -- Check efficiency
    if (provides.efficiency or 0) > company.points.efficiency then
        return false
    end
    
    -- Check innovation
    if (provides.innovation or 0) > company.points.innovation then
        return false
    end
    
    -- Check logistics
    if (provides.logistics or 0) > company.points.logistics then
        return false
    end
    
    return true
end

--- Deduct resources from company
-- @param company table Company data
-- @param provides table Resources to deduct
function deductResources(company, provides)
    -- Deduct items
    if provides.items then
        for itemID, quantity in pairs(provides.items) do
            removeItemFromCompany(company.id, itemID, quantity)
        end
    end
    
    -- Deduct points
    company.points.money = company.points.money - (provides.money or 0)
    company.points.efficiency = company.points.efficiency - (provides.efficiency or 0)
    company.points.innovation = company.points.innovation - (provides.innovation or 0)
    company.points.logistics = company.points.logistics - (provides.logistics or 0)
end

--- Add resources to company
-- @param company table Company data
-- @param provides table Resources to add
function addResources(company, provides)
    -- Add items
    if provides.items then
        for itemID, quantity in pairs(provides.items) do
            addItemToCompany(company.id, itemID, quantity)
        end
    end
    
    -- Add points
    company.points.money = company.points.money + (provides.money or 0)
    company.points.efficiency = company.points.efficiency + (provides.efficiency or 0)
    company.points.innovation = company.points.innovation + (provides.innovation or 0)
    company.points.logistics = company.points.logistics + (provides.logistics or 0)
end

--------------------------------------------------------------------------------
-- SECTION 2: PRODUCTION SYSTEM
--------------------------------------------------------------------------------

--- Get a recipe by ID
-- @param recipeID string Recipe ID
-- @return table|nil Recipe data
function getRecipe(recipeID)
    if not database then return nil end
    
    local query = dbQuery(database, "SELECT * FROM economy_recipes WHERE id = ?", recipeID)
    local result = dbPoll(query, -1)
    
    if result and result[1] then
        local row = result[1]
        return {
            id = row.id,
            name = row.name,
            companyType = row.company_type,
            inputs = fromJSON(row.inputs) or {},
            outputs = fromJSON(row.outputs) or {},
            laborRequired = row.labor_required,
            processingCycles = row.processing_cycles
        }
    end
    
    return nil
end

--- Create a new recipe
-- @param id string Recipe ID
-- @param name string Recipe name
-- @param companyType string Which company type can use this
-- @param inputs table Map of itemID -> quantity needed
-- @param outputs table Map of itemID -> quantity produced
-- @param laborRequired number LP needed per batch
-- @return boolean Success
function createRecipe(id, name, companyType, inputs, outputs, laborRequired)
    if not database then return false end
    
    dbExec(database, [[
        INSERT OR REPLACE INTO economy_recipes (id, name, company_type, inputs, outputs, labor_required)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], id, name, companyType or "manufacturing", toJSON(inputs), toJSON(outputs), laborRequired or 8)
    
    return true
end

--- Calculate efficiency multiplier for a company
-- @param company table Company data
-- @return number Multiplier (1.0 = no bonus)
function calculateEfficiencyMultiplier(company)
    local baseEfficiency = company.points.efficiency
    local employeeCount = 0
    for _ in pairs(company.employees) do employeeCount = employeeCount + 1 end
    local companyAge = GlobalEconomy.currentCycle - company.creationCycle
    
    -- Cap based on company maturity
    -- Formula: sqrt(employees) * log(age + 1) * 50
    local efficiencyCap = math.sqrt(employeeCount) * math.log(companyAge + 2) * 50
    
    -- Add perk bonuses to cap
    if company.perks.efficiency_boost_1 then efficiencyCap = efficiencyCap + 5 end
    if company.perks.efficiency_boost_2 then efficiencyCap = efficiencyCap + 10 end
    if company.perks.efficiency_boost_3 then efficiencyCap = efficiencyCap + 20 end
    
    local effectiveEfficiency = math.min(baseEfficiency, efficiencyCap)
    local multiplier = 1.0 + (effectiveEfficiency / 100)
    
    -- Add production perk bonuses
    if company.perks.production_speed_1 then multiplier = multiplier + 0.10 end
    if company.perks.production_speed_2 then multiplier = multiplier + 0.20 end
    
    return multiplier
end

--- Set company's production target (for resource companies)
-- @param companyID string Company ID
-- @param itemID string Item to produce
-- @return boolean Success
function setResourceProduction(companyID, itemID)
    local company = Companies[companyID]
    if not company then return false end
    if company.type ~= COMPANY_TYPE.RESOURCE then return false end
    
    -- Verify item has economy data (labor cost)
    local itemEcon = getItemEconomyData(itemID)
    if not itemEcon then return false end
    
    company.production.autoProduceItem = itemID
    dbExec(database, "UPDATE companies SET auto_produce_item = ? WHERE id = ?", itemID, companyID)
    
    return true
end

--- Set company's active recipe (for manufacturing companies)
-- @param companyID string Company ID
-- @param recipeID string Recipe ID
-- @return boolean Success
function setManufacturingRecipe(companyID, recipeID)
    local company = Companies[companyID]
    if not company then return false end
    if company.type ~= COMPANY_TYPE.MANUFACTURING then return false end
    
    -- Verify recipe exists
    local recipe = getRecipe(recipeID)
    if not recipe then return false end
    
    company.production.currentRecipe = recipeID
    dbExec(database, "UPDATE companies SET current_recipe_id = ? WHERE id = ?", recipeID, companyID)
    
    return true
end

--------------------------------------------------------------------------------
-- SECTION 3: CYCLE PROCESSING
--------------------------------------------------------------------------------

--- Start the cycle timer
function startCycleTimer()
    -- Calculate time until next cycle
    local now = getRealTime().timestamp
    local timeUntilCycle = GlobalEconomy.nextCycleTime - now
    
    if timeUntilCycle <= 0 then
        -- Cycle is overdue, process immediately
        processEndOfCycle()
        timeUntilCycle = EconomyConfig.CYCLE_DURATION_HOURS * 3600
    end
    
    -- Set timer (convert seconds to milliseconds)
    GlobalEconomy.cycleTimer = setTimer(function()
        processEndOfCycle()
        -- Restart timer for next cycle
        startCycleTimer()
    end, timeUntilCycle * 1000, 1)
    
    outputServerLog("Economy cycle timer started - Next cycle in " .. math.floor(timeUntilCycle / 3600) .. " hours")
end

--- Force end of cycle (DM command)
function forceCycleEnd()
    processEndOfCycle()
    outputServerLog("Cycle forcefully ended by DM")
end

--- Main end-of-cycle processing
function processEndOfCycle()
    outputServerLog("========== PROCESSING CYCLE " .. GlobalEconomy.currentCycle .. " ==========")
    
    local startTime = getTickCount()
    
    -- Phase 1: Labor Deposit
    outputServerLog("Phase 1: Depositing labor power...")
    for companyID, company in pairs(Companies) do
        processLaborDeposit(company)
    end
    
    -- Phase 2: Production
    outputServerLog("Phase 2: Processing production...")
    for companyID, company in pairs(Companies) do
        processProduction(company)
    end
    
    -- Phase 3: Deal Execution
    outputServerLog("Phase 3: Executing deals...")
    for dealID, deal in pairs(Deals) do
        if deal.status == DEAL_STATUS.ACTIVE then
            executeDeal(deal)
        end
    end
    
    -- Phase 4: Retail Sales
    outputServerLog("Phase 4: Processing retail sales...")
    for companyID, company in pairs(Companies) do
        if company.type == COMPANY_TYPE.RETAIL then
            processRetailSales(company)
        end
    end
    
    -- Phase 5: Wage Payment
    outputServerLog("Phase 5: Paying wages...")
    for companyID, company in pairs(Companies) do
        payEmployeeWages(company)
    end
    
    -- Phase 6: NPC Profit Return
    outputServerLog("Phase 6: Returning NPC profits...")
    for companyID, company in pairs(Companies) do
        if company.ownerType == "npc" then
            returnNPCProfit(company)
        end
    end
    
    -- Increment cycle
    GlobalEconomy.currentCycle = GlobalEconomy.currentCycle + 1
    GlobalEconomy.nextCycleTime = getRealTime().timestamp + (EconomyConfig.CYCLE_DURATION_HOURS * 3600)
    
    -- Save state
    saveEconomyState()
    saveAllCompanies()
    
    local elapsed = getTickCount() - startTime
    outputServerLog("========== CYCLE " .. (GlobalEconomy.currentCycle - 1) .. " COMPLETE (" .. elapsed .. "ms) ==========")
    
    -- Notify all players
    for _, player in ipairs(getElementsByType("player")) do
        triggerClientEvent(player, "economy:cycleComplete", player, GlobalEconomy.currentCycle - 1)
    end
end

--- Process labor deposit for a company
-- @param company table Company data
function processLaborDeposit(company)
    -- Reset labor pool
    company.laborPool = {
        items = 0,
        logistics = 0,
        efficiency = 0,
        innovation = 0
    }
    
    for empID, employee in pairs(company.employees) do
        if employee.status == "active" then
            local baseLaborPower = EconomyConfig.BASE_LABOR_POWER
            
            -- Player employees produce slightly more
            if employee.isPlayer then
                baseLaborPower = baseLaborPower + EconomyConfig.PLAYER_LABOR_BONUS
            end
            
            -- Skilled workers have efficiency modifier for item/logistics work
            if employee.type == EMPLOYEE_TYPE.SKILLED then
                if employee.laborAllocation == LABOR_ALLOCATION.ITEMS or 
                   employee.laborAllocation == LABOR_ALLOCATION.LOGISTICS then
                    baseLaborPower = baseLaborPower * employee.efficiencyModifier
                end
            end
            
            -- Allocate labor based on assignment
            if employee.laborAllocation == LABOR_ALLOCATION.ITEMS then
                company.laborPool.items = company.laborPool.items + baseLaborPower
            elseif employee.laborAllocation == LABOR_ALLOCATION.LOGISTICS then
                company.points.logistics = company.points.logistics + baseLaborPower
            elseif employee.laborAllocation == LABOR_ALLOCATION.EFFICIENCY then
                company.points.efficiency = company.points.efficiency + baseLaborPower
            elseif employee.laborAllocation == LABOR_ALLOCATION.INNOVATION then
                company.points.innovation = company.points.innovation + baseLaborPower
            end
        end
    end
end

--- Process production for a company
-- @param company table Company data
function processProduction(company)
    local totalLaborPower = company.laborPool.items
    if totalLaborPower <= 0 then return end
    
    local efficiencyMult = calculateEfficiencyMultiplier(company)
    
    if company.type == COMPANY_TYPE.RESOURCE then
        -- Resource companies produce items without recipes
        local targetItem = company.production.autoProduceItem
        if not targetItem then return end
        
        local itemEcon = getItemEconomyData(targetItem)
        if not itemEcon then return end
        
        local itemsProduced = math.floor((totalLaborPower / itemEcon.laborCost) * efficiencyMult)
        if itemsProduced > 0 then
            addItemToCompany(company.id, targetItem, itemsProduced)
            outputServerLog("  " .. company.name .. " produced " .. itemsProduced .. " " .. targetItem)
        end
        
    elseif company.type == COMPANY_TYPE.MANUFACTURING then
        -- Manufacturing companies use recipes
        local recipeID = company.production.currentRecipe
        if not recipeID then return end
        
        local recipe = getRecipe(recipeID)
        if not recipe then return end
        
        -- Calculate max batches from labor
        local maxBatches = math.floor(totalLaborPower / recipe.laborRequired)
        
        -- Limit by available inputs
        for inputItem, inputQty in pairs(recipe.inputs) do
            local available = company.inventory[inputItem] or 0
            local possibleBatches = math.floor(available / inputQty)
            maxBatches = math.min(maxBatches, possibleBatches)
        end
        
        if maxBatches <= 0 then return end
        
        -- Consume inputs
        for inputItem, inputQty in pairs(recipe.inputs) do
            removeItemFromCompany(company.id, inputItem, inputQty * maxBatches)
        end
        
        -- Produce outputs (with efficiency bonus)
        for outputItem, outputQty in pairs(recipe.outputs) do
            local produced = math.floor(outputQty * maxBatches * efficiencyMult)
            addItemToCompany(company.id, outputItem, produced)
            outputServerLog("  " .. company.name .. " produced " .. produced .. " " .. outputItem)
        end
        
    elseif company.type == COMPANY_TYPE.TECH then
        -- Tech companies generate efficiency/innovation from labor
        -- Already handled in labor deposit for professional workers
    end
end

--- Execute a deal
-- @param deal table Deal data
function executeDeal(deal)
    local companyA = Companies[deal.companyAID]
    local companyB = Companies[deal.companyBID]
    
    if not companyA or not companyB then
        deal.status = DEAL_STATUS.FAILED
        return
    end
    
    -- Validation Phase
    if not companyHasResources(companyA, deal.companyAProvides) then
        outputServerLog("  Deal " .. deal.id .. " failed: " .. companyA.name .. " lacks resources")
        return  -- Skip this cycle, don't fail permanently
    end
    
    if not companyHasResources(companyB, deal.companyBProvides) then
        outputServerLog("  Deal " .. deal.id .. " failed: " .. companyB.name .. " lacks resources")
        return
    end
    
    -- Check logistics (unless trading logistics itself)
    local isLogisticsOnly = (deal.companyAProvides.logistics or 0) > 0 or (deal.companyBProvides.logistics or 0) > 0
    -- ... (simplified check)
    
    if deal.logisticsCost > 0 then
        if companyA.points.logistics < deal.logisticsCost then
            outputServerLog("  Deal " .. deal.id .. " failed: " .. companyA.name .. " lacks logistics")
            return
        end
        if companyB.points.logistics < deal.logisticsCost then
            outputServerLog("  Deal " .. deal.id .. " failed: " .. companyB.name .. " lacks logistics")
            return
        end
    end
    
    -- Execution Phase (atomic swap)
    deductResources(companyA, deal.companyAProvides)
    deductResources(companyB, deal.companyBProvides)
    addResources(companyA, deal.companyBProvides)
    addResources(companyB, deal.companyAProvides)
    
    outputServerLog("  Deal executed: " .. companyA.name .. " <-> " .. companyB.name)
    
    -- Update deal status
    if deal.duration ~= "infinite" and deal.cyclesRemaining then
        deal.cyclesRemaining = deal.cyclesRemaining - 1
        if deal.cyclesRemaining <= 0 then
            deal.status = DEAL_STATUS.COMPLETED
            dbExec(database, "UPDATE deals SET status = ?, cycles_remaining = ? WHERE id = ?", 
                deal.status, deal.cyclesRemaining, deal.id)
        end
    end
end

--- Process retail sales to state market
-- @param company table Company data
function processRetailSales(company)
    for itemID, quantity in pairs(company.inventory) do
        local itemEcon = getItemEconomyData(itemID)
        if itemEcon and itemEcon.isMarketItem then
            -- Check if state market is a valid tier for this item
            local canSellToState = false
            for _, tier in ipairs(itemEcon.marketTiers) do
                if tier == MARKET_TIER.STATE then canSellToState = true break end
            end
            
            if canSellToState and quantity > 0 then
                -- Random consumption between 5-15% per cycle
                local consumptionRate = EconomyConfig.RETAIL_MIN_CONSUMPTION + 
                    (math.random() * (EconomyConfig.RETAIL_MAX_CONSUMPTION - EconomyConfig.RETAIL_MIN_CONSUMPTION))
                local unitsToSell = math.floor(quantity * consumptionRate)
                
                if unitsToSell > 0 then
                    local revenue = unitsToSell * itemEcon.basePrice
                    
                    -- Check if state market has funds
                    if GlobalEconomy.markets.state.money >= revenue then
                        removeItemFromCompany(company.id, itemID, unitsToSell)
                        company.points.money = company.points.money + revenue
                        GlobalEconomy.markets.state.money = GlobalEconomy.markets.state.money - revenue
                        
                        logMarketTransaction("RETAIL_SALE", MARKET_TIER.STATE, revenue, "FROM_MARKET", 
                            company.id, nil, {[itemID] = unitsToSell}, 
                            "Retail sale: " .. unitsToSell .. " " .. itemID)
                        
                        outputServerLog("  " .. company.name .. " sold " .. unitsToSell .. " " .. itemID .. " for $" .. revenue)
                    end
                end
            end
        end
    end
end

--- Pay employee wages
-- @param company table Company data
function payEmployeeWages(company)
    local totalWages = 0
    
    -- Calculate total wages (with perk reductions)
    local wageReduction = 0
    if company.perks.wage_reduction_1 then wageReduction = wageReduction + 0.05 end
    if company.perks.wage_reduction_2 then wageReduction = wageReduction + 0.10 end
    
    for empID, employee in pairs(company.employees) do
        local wage = employee.wage * (1 - wageReduction)
        totalWages = totalWages + wage
    end
    
    if company.points.money >= totalWages then
        -- Pay all employees
        for empID, employee in pairs(company.employees) do
            local wage = employee.wage * (1 - wageReduction)
            company.points.money = company.points.money - wage
            
            if employee.isPlayer then
                -- Pay player
                local player = getPlayerFromAccountID(employee.playerID)
                if player then
                    givePlayerMoney(player, math.floor(wage))
                end
            else
                -- Return NPC wages to state market
                GlobalEconomy.markets.state.money = GlobalEconomy.markets.state.money + wage
                logMarketTransaction("WAGE_RETURN", MARKET_TIER.STATE, wage, "TO_MARKET", company.id, nil, nil, "NPC wage return")
            end
        end
    else
        -- Insufficient funds - employees may strike
        outputServerLog("  " .. company.name .. " cannot afford wages! ($" .. totalWages .. " needed, $" .. company.points.money .. " available)")
        
        for empID, employee in pairs(company.employees) do
            if math.random() < 0.3 then  -- 30% chance to strike
                employee.status = "on_strike"
                dbExec(database, "UPDATE company_employees SET status = 'on_strike' WHERE id = ?", empID)
            end
        end
    end
end

--- Return NPC company profit to state market
-- @param company table Company data
function returnNPCProfit(company)
    -- NPC companies keep a small reserve, return excess to market
    local reserve = 10000  -- Keep $10k minimum
    local excess = company.points.money - reserve
    
    if excess > 0 then
        company.points.money = company.points.money - excess
        GlobalEconomy.markets.state.money = GlobalEconomy.markets.state.money + excess
        logMarketTransaction("NPC_PROFIT_RETURN", MARKET_TIER.STATE, excess, "TO_MARKET", company.id, nil, nil, "NPC profit redistribution")
    end
end

--------------------------------------------------------------------------------
-- SECTION 4: DATA PERSISTENCE
--------------------------------------------------------------------------------

--- Load all companies from database
function loadAllCompanies()
    if not database then return end
    
    local query = dbQuery(database, "SELECT * FROM companies")
    local result = dbPoll(query, -1)
    
    if not result then return end
    
    for _, row in ipairs(result) do
        local company = {
            id = row.id,
            name = row.name,
            type = row.type,
            ownerType = row.owner_type,
            ownerID = row.owner_id,
            creationCycle = row.creation_cycle,
            points = {
                money = row.money,
                efficiency = row.efficiency,
                innovation = row.innovation,
                logistics = row.logistics
            },
            inventory = {},
            employees = {},
            deals = {},
            perks = fromJSON(row.perks) or {},
            production = {
                currentRecipe = row.current_recipe_id,
                autoProduceItem = row.auto_produce_item
            },
            laborPool = { items = 0, logistics = 0, efficiency = 0, innovation = 0 }
        }
        
        -- Load inventory
        local invQuery = dbQuery(database, "SELECT * FROM company_inventory WHERE company_id = ?", row.id)
        local invResult = dbPoll(invQuery, -1)
        if invResult then
            for _, invRow in ipairs(invResult) do
                company.inventory[invRow.item_id] = invRow.quantity
            end
        end
        
        -- Load employees
        local empQuery = dbQuery(database, "SELECT * FROM company_employees WHERE company_id = ?", row.id)
        local empResult = dbPoll(empQuery, -1)
        if empResult then
            for _, empRow in ipairs(empResult) do
                local employee = {
                    id = empRow.id,
                    companyID = empRow.company_id,
                    type = empRow.type,
                    isPlayer = empRow.is_player == 1,
                    playerID = empRow.player_id,
                    characterID = empRow.character_id,
                    wage = empRow.wage,
                    laborAllocation = empRow.labor_allocation,
                    hireCycle = empRow.hire_cycle,
                    efficiencyModifier = empRow.efficiency_modifier,
                    status = empRow.status
                }
                company.employees[empRow.id] = employee
                Employees[empRow.id] = employee
            end
        end
        
        Companies[row.id] = company
    end
    
    outputServerLog("Loaded " .. #result .. " companies")
end

--- Load all deals from database
function loadAllDeals()
    if not database then return end
    
    local query = dbQuery(database, "SELECT * FROM deals WHERE status IN ('pending', 'active')")
    local result = dbPoll(query, -1)
    
    if not result then return end
    
    for _, row in ipairs(result) do
        local deal = {
            id = row.id,
            companyAID = row.company_a_id,
            companyBID = row.company_b_id,
            companyAProvides = fromJSON(row.company_a_provides) or {},
            companyBProvides = fromJSON(row.company_b_provides) or {},
            logisticsCost = row.logistics_cost,
            duration = row.duration,
            cyclesRemaining = row.cycles_remaining,
            status = row.status,
            createdCycle = row.created_cycle
        }
        
        Deals[row.id] = deal
        
        -- Add to company deal lists
        local companyA = Companies[row.company_a_id]
        local companyB = Companies[row.company_b_id]
        if companyA then table.insert(companyA.deals, row.id) end
        if companyB then table.insert(companyB.deals, row.id) end
    end
    
    outputServerLog("Loaded " .. #result .. " active deals")
end

--- Save all companies to database
function saveAllCompanies()
    if not database then return end
    
    for companyID, company in pairs(Companies) do
        dbExec(database, [[
            UPDATE companies SET 
                money = ?, efficiency = ?, innovation = ?, logistics = ?,
                current_recipe_id = ?, auto_produce_item = ?, perks = ?
            WHERE id = ?
        ]], company.points.money, company.points.efficiency, company.points.innovation, company.points.logistics,
            company.production.currentRecipe, company.production.autoProduceItem, toJSON(company.perks), companyID)
    end
end

--------------------------------------------------------------------------------
-- SECTION 6: CLIENT EVENT HANDLERS
--------------------------------------------------------------------------------

-- Request player's companies
addEvent("economy:requestPlayerCompanies", true)
addEventHandler("economy:requestPlayerCompanies", root, function()
    sendPlayerCompanies(client)
end)

-- Open company creator (just sends back to client to show the GUI)
addEvent("economy:openCompanyCreator", true)
addEventHandler("economy:openCompanyCreator", root, function()
    -- Client handles the GUI, this just acknowledges the request
    triggerClientEvent(client, "economy:showCompanyCreator", client)
end)

-- Helper function to verify company ownership
-- Returns true if player owns the company or is a DM
function verifyCompanyOwnership(player, company, allowDM)
    if not company then return false end
    
    -- DM bypass
    if allowDM and isDungeonMaster and isDungeonMaster(player) then
        return true
    end
    
    -- Must be player-owned
    if company.ownerType ~= "player" then return false end
    
    -- Get character ID
    local char = AccountManager and AccountManager:getActiveCharacter(player)
    if not char then return false end
    
    -- Compare with company owner (character ID)
    return company.ownerID == tostring(char.id)
end

-- Open hire dialog
addEvent("economy:openHireDialog", true)
addEventHandler("economy:openHireDialog", root, function(companyID)
    local company = Companies[companyID]
    if not company then return end
    
    -- Verify ownership
    if not verifyCompanyOwnership(client, company, true) then
        return
    end
    
    triggerClientEvent(client, "economy:showHireDialog", client, companyID)
end)

-- Open deal creator
addEvent("economy:openDealCreator", true)
addEventHandler("economy:openDealCreator", root, function(companyID)
    local company = Companies[companyID]
    if not company then return end
    
    -- Verify ownership
    if not verifyCompanyOwnership(client, company, true) then
        return
    end
    
    -- Get list of all other companies for deal partner selection
    local otherCompanies = {}
    for id, comp in pairs(Companies) do
        if id ~= companyID then
            table.insert(otherCompanies, {
                id = comp.id,
                name = comp.name,
                type = comp.type
            })
        end
    end
    
    triggerClientEvent(client, "economy:showDealCreator", client, companyID, otherCompanies)
end)

-- Request company list (for deal creation)
addEvent("economy:requestCompanyList", true)
addEventHandler("economy:requestCompanyList", root, function()
    local companies = {}
    for id, company in pairs(Companies) do
        table.insert(companies, {
            id = company.id,
            name = company.name,
            type = company.type
        })
    end
    
    triggerClientEvent(client, "economy:companyList", client, companies)
end)

-- Set production (resource or manufacturing)
addEvent("economy:setProduction", true)
addEventHandler("economy:setProduction", root, function(companyID, productionType, targetID)
    local company = Companies[companyID]
    if not company then return end
    
    -- Verify ownership
    if not verifyCompanyOwnership(client, company, true) then
        return
    end
    
    local success = false
    if productionType == "resource" then
        success = setResourceProduction(companyID, targetID)
    elseif productionType == "manufacturing" then
        success = setManufacturingRecipe(companyID, targetID)
    end
    
    if success then
        triggerClientEvent(client, "economy:message", client, "Production updated")
    else
        triggerClientEvent(client, "economy:message", client, "Failed to update production", true)
    end
end)

-- Request full company data
addEvent("economy:requestCompanyData", true)
addEventHandler("economy:requestCompanyData", root, function(companyID)
    local company = Companies[companyID]
    if not company then return end
    
    -- Verify ownership or DM
    if not verifyCompanyOwnership(client, company, true) then
        return
    end
    
    -- Build company data for client
    local data = {
        id = company.id,
        name = company.name,
        type = company.type,
        ownerType = company.ownerType,
        points = {
            money = company.points.money,
            efficiency = company.points.efficiency,
            innovation = company.points.innovation,
            logistics = company.points.logistics
        },
        inventory = company.inventory,
        employees = company.employees,
        deals = {},
        perks = company.perks,
        autoProduceItem = company.production.autoProduceItem,
        currentRecipe = company.production.currentRecipe,
        availableResources = {},
        availableRecipes = {}
    }
    
    -- Get available resource items (for resource companies)
    if company.type == "resource" then
        data.availableResources = getAvailableResourceItems()
    end
    
    -- Get available recipes (for manufacturing companies)
    if company.type == "manufacturing" then
        data.availableRecipes = getAvailableRecipes()
    end
    
    -- Add deal info with full details
    for _, dealID in ipairs(company.deals) do
        local deal = Deals[dealID]
        if deal then
            local companyAName = Companies[deal.companyAID] and Companies[deal.companyAID].name or "Unknown"
            local companyBName = Companies[deal.companyBID] and Companies[deal.companyBID].name or "Unknown"
            table.insert(data.deals, {
                id = deal.id,
                companyAID = deal.companyAID,
                companyBID = deal.companyBID,
                companyAName = companyAName,
                companyBName = companyBName,
                companyAProvides = deal.companyAProvides,
                companyBProvides = deal.companyBProvides,
                status = deal.status,
                duration = deal.duration
            })
        end
    end
    
    triggerClientEvent(client, "economy:companyData", client, data)
end)

-- Get available resource items from economy_items table
function getAvailableResourceItems()
    local items = {}
    
    -- First check economy_items for items with labor cost set
    if database then
        local query = dbQuery(database, "SELECT * FROM economy_items WHERE labor_cost > 0")
        local result = dbPoll(query, -1)
        if result then
            for _, row in ipairs(result) do
                table.insert(items, {
                    id = row.item_id,
                    name = row.item_id,  -- Will be replaced with actual name if available
                    laborCost = row.labor_cost
                })
            end
        end
    end
    
    -- Also check ItemRegistry for resource category items
    if ItemRegistry and ItemRegistry.items then
        for itemID, item in pairs(ItemRegistry.items) do
            if item.category == "resource" then
                -- Check if not already in list
                local found = false
                for _, existing in ipairs(items) do
                    if existing.id == itemID then found = true break end
                end
                if not found then
                    table.insert(items, {
                        id = itemID,
                        name = item.name or itemID,
                        laborCost = 1.0  -- Default labor cost
                    })
                end
            end
        end
    end
    
    return items
end

-- Get available recipes
function getAvailableRecipes()
    local recipes = {}
    
    if database then
        local query = dbQuery(database, "SELECT id, name FROM economy_recipes WHERE company_type = 'manufacturing'")
        local result = dbPoll(query, -1)
        if result then
            for _, row in ipairs(result) do
                table.insert(recipes, {
                    id = row.id,
                    name = row.name
                })
            end
        end
    end
    
    return recipes
end

-- Hire NPC employee
addEvent("economy:hireNPC", true)
addEventHandler("economy:hireNPC", root, function(companyID, empType, wage, allocation)
    local company = Companies[companyID]
    if not company then
        triggerClientEvent(client, "economy:message", client, "Company not found", true)
        return
    end
    
    -- Verify ownership (allow DM)
    if not verifyCompanyOwnership(client, company, true) then
        triggerClientEvent(client, "economy:message", client, "You don't own this company", true)
        return
    end
    
    local empID, err = hireNPCEmployee(companyID, empType, wage, allocation)
    
    if empID then
        triggerClientEvent(client, "economy:message", client, "Employee hired successfully")
    else
        triggerClientEvent(client, "economy:message", client, err or "Failed to hire employee", true)
    end
end)

-- Fire employee
addEvent("economy:fireEmployee", true)
addEventHandler("economy:fireEmployee", root, function(companyID, empID)
    local company = Companies[companyID]
    if not company then return end
    
    -- Verify ownership (allow DM)
    if not verifyCompanyOwnership(client, company, true) then
        return
    end
    
    if fireEmployee(companyID, empID) then
        triggerClientEvent(client, "economy:message", client, "Employee fired")
    else
        triggerClientEvent(client, "economy:message", client, "Failed to fire employee", true)
    end
end)

-- Buy perk
addEvent("economy:buyPerk", true)
addEventHandler("economy:buyPerk", root, function(companyID, perkID)
    local company = Companies[companyID]
    if not company then return end
    
    -- Verify ownership (allow DM)
    if not verifyCompanyOwnership(client, company, true) then
        return
    end
    
    local perk = CompanyPerks[perkID]
    if not perk then
        triggerClientEvent(client, "economy:message", client, "Invalid perk", true)
        return
    end
    
    -- Check if already owned
    if company.perks[perkID] then
        triggerClientEvent(client, "economy:message", client, "Already owned", true)
        return
    end
    
    -- Check requirements
    if perk.requires and not company.perks[perk.requires] then
        triggerClientEvent(client, "economy:message", client, "Requires " .. perk.requires, true)
        return
    end
    
    -- Check cost
    if company.points.innovation < perk.cost then
        triggerClientEvent(client, "economy:message", client, "Not enough Innovation points", true)
        return
    end
    
    -- Purchase
    company.points.innovation = company.points.innovation - perk.cost
    company.perks[perkID] = true
    
    -- Save
    dbExec(database, "UPDATE companies SET innovation = ?, perks = ? WHERE id = ?",
        company.points.innovation, toJSON(company.perks), companyID)
    
    triggerClientEvent(client, "economy:message", client, "Purchased " .. perk.name)
end)

-- Create player company
addEvent("economy:createPlayerCompany", true)
addEventHandler("economy:createPlayerCompany", root, function(name, companyType)
    local acc = AccountManager and AccountManager:getAccount(client)
    if not acc then return end
    
    local char = AccountManager:getActiveCharacter(client)
    if not char then
        triggerClientEvent(client, "economy:message", client, "No active character", true)
        return
    end
    
    -- Check if player has enough money
    local playerMoney = getPlayerMoney(client)
    if playerMoney < EconomyConfig.COMPANY_STARTING_CAPITAL then
        triggerClientEvent(client, "economy:message", client, "You need $" .. EconomyConfig.COMPANY_STARTING_CAPITAL .. " to start a company", true)
        return
    end
    
    -- Use character ID as owner, not account ID
    local companyID, err = createCompany(name, companyType, "player", tostring(char.id), EconomyConfig.COMPANY_STARTING_CAPITAL)
    
    if companyID then
        takePlayerMoney(client, EconomyConfig.COMPANY_STARTING_CAPITAL)
        triggerClientEvent(client, "economy:message", client, "Company created: " .. name)
        -- Send updated company list to client
        sendPlayerCompanies(client)
    else
        triggerClientEvent(client, "economy:message", client, err or "Failed to create company", true)
    end
end)

-- Sell to market
addEvent("economy:sellToMarket", true)
addEventHandler("economy:sellToMarket", root, function(companyID, itemID, quantity, marketTier)
    local company = Companies[companyID]
    if not company then return end
    
    -- Verify ownership
    if not verifyCompanyOwnership(client, company, true) then
        return
    end
    
    local success, msg = sellToMarket(companyID, itemID, quantity, marketTier)
    triggerClientEvent(client, "economy:message", client, msg, not success)
end)

-- Cancel deal
addEvent("economy:cancelDeal", true)
addEventHandler("economy:cancelDeal", root, function(dealID, companyID)
    local success, msg = cancelDeal(dealID, companyID)
    triggerClientEvent(client, "economy:message", client, msg, not success)
end)

-- Accept job offer
addEvent("economy:acceptJob", true)
addEventHandler("economy:acceptJob", root, function(offerData)
    local acc = AccountManager and AccountManager:getAccount(client)
    if not acc then return end
    
    local char = AccountManager:getActiveCharacter(client)
    if not char then return end
    
    local company = Companies[offerData.companyID]
    if not company then
        triggerClientEvent(client, "economy:message", client, "Company no longer exists", true)
        return
    end
    
    -- Create player employee
    local employeeID = "emp_" .. getRealTime().timestamp .. "_" .. math.random(1000, 9999)
    
    local efficiencyMod = 1.0
    if offerData.employeeType == EMPLOYEE_TYPE.SKILLED then
        efficiencyMod = EconomyConfig.SKILLED_EFFICIENCY_BONUS
    end
    
    local success = dbExec(database, [[
        INSERT INTO company_employees (id, company_id, type, is_player, player_id, character_id, wage, labor_allocation, hire_cycle, efficiency_modifier, status)
        VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?, ?, 'active')
    ]], employeeID, offerData.companyID, offerData.employeeType, tostring(acc.id), char.id, offerData.wage, offerData.laborAllocation, GlobalEconomy.currentCycle, efficiencyMod)
    
    if success then
        local employee = {
            id = employeeID,
            companyID = offerData.companyID,
            type = offerData.employeeType,
            isPlayer = true,
            playerID = tostring(acc.id),
            characterID = char.id,
            wage = offerData.wage,
            laborAllocation = offerData.laborAllocation,
            hireCycle = GlobalEconomy.currentCycle,
            efficiencyModifier = efficiencyMod,
            status = "active"
        }
        
        company.employees[employeeID] = employee
        Employees[employeeID] = employee
        
        triggerClientEvent(client, "economy:message", client, "You are now employed at " .. company.name)
    else
        triggerClientEvent(client, "economy:message", client, "Failed to accept job", true)
    end
end)

-- Create deal between companies
addEvent("economy:createDeal", true)
addEventHandler("economy:createDeal", root, function(companyAID, companyBID, companyAProvides, companyBProvides, duration)
    local companyA = Companies[companyAID]
    if not companyA then
        triggerClientEvent(client, "economy:message", client, "Your company not found", true)
        return
    end
    
    -- Verify ownership of company A
    if not verifyCompanyOwnership(client, companyA, true) then
        triggerClientEvent(client, "economy:message", client, "You don't own this company", true)
        return
    end
    
    local dealID, err = createDeal(companyAID, companyBID, companyAProvides, companyBProvides, duration)
    
    if dealID then
        -- If company B is NPC, auto-accept the deal
        local companyB = Companies[companyBID]
        if companyB and companyB.ownerType == "npc" then
            acceptDeal(dealID, companyBID)
            triggerClientEvent(client, "economy:message", client, "Deal created and accepted by " .. companyB.name)
        else
            triggerClientEvent(client, "economy:message", client, "Deal proposal sent to " .. (companyB and companyB.name or "company"))
        end
    else
        triggerClientEvent(client, "economy:message", client, err or "Failed to create deal", true)
    end
end)

--------------------------------------------------------------------------------
-- SECTION 7: DM COMMANDS (continued)
--------------------------------------------------------------------------------

-- Force cycle end
addCommandHandler("forcecycle", function(player)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    forceCycleEnd()
    outputChatBox("Economic cycle forced to end", player, 0, 255, 0)
end)

-- DM force cycle via GUI
addEvent("economy:dmForceCycle", true)
addEventHandler("economy:dmForceCycle", root, function()
    if not isDungeonMaster or not isDungeonMaster(client) then return end
    forceCycleEnd()
    triggerClientEvent(client, "economy:message", client, "Cycle ended. Now on cycle " .. GlobalEconomy.currentCycle)
end)

-- Request DM economy data (all companies + market data)
addEvent("economy:requestDMData", true)
addEventHandler("economy:requestDMData", root, function()
    if not isDungeonMaster or not isDungeonMaster(client) then
        -- Fall back to player view
        outputChatBox("DM access required for economy management panel", client, 255, 100, 100)
        sendPlayerCompanies(client)
        return
    end
    
    sendDMEconomyData(client)
end)

-- Unified request - server decides if DM or player view
addEvent("economy:requestEconomyGUI", true)
addEventHandler("economy:requestEconomyGUI", root, function()
    -- Check if player is a DM
    if isDungeonMaster and isDungeonMaster(client) then
        sendDMEconomyData(client)
    else
        sendPlayerCompanies(client)
    end
end)

-- Helper function to send DM economy data
function sendDMEconomyData(player)
    -- Build company list with summary data
    local companies = {}
    for id, company in pairs(Companies) do
        local empCount = 0
        for _ in pairs(company.employees) do empCount = empCount + 1 end
        
        table.insert(companies, {
            id = company.id,
            name = company.name,
            type = company.type,
            ownerType = company.ownerType,
            ownerID = company.ownerID,
            money = company.points.money,
            employeeCount = empCount
        })
    end
    
    -- Sort by name
    table.sort(companies, function(a, b) return a.name < b.name end)
    
    -- Build market data
    local markets = {
        global = GlobalEconomy.markets.global.money,
        national = GlobalEconomy.markets.national.money,
        state = GlobalEconomy.markets.state.money,
        currentCycle = GlobalEconomy.currentCycle,
        nextCycleTime = GlobalEconomy.nextCycleTime
    }
    
    triggerClientEvent(player, "economy:dmEconomyData", player, companies, markets)
end

-- Helper function to send player companies
function sendPlayerCompanies(player)
    local acc = AccountManager and AccountManager:getAccount(player)
    if not acc then return end
    
    local char = AccountManager:getActiveCharacter(player)
    if not char then return end
    
    local companies = {}
    for id, company in pairs(Companies) do
        if company.ownerType == "player" and company.ownerID == tostring(char.id) then
            table.insert(companies, {
                id = company.id,
                name = company.name,
                type = company.type
            })
        end
    end
    
    triggerClientEvent(player, "economy:playerCompanies", player, companies)
end

-- DM create NPC company
addEvent("economy:dmCreateNPCCompany", true)
addEventHandler("economy:dmCreateNPCCompany", root, function(name, companyType, capital)
    if not isDungeonMaster or not isDungeonMaster(client) then
        triggerClientEvent(client, "economy:message", client, "DM required", true)
        return
    end
    
    local companyID, err = createCompany(name, companyType, "npc", nil, capital or 50000)
    
    if companyID then
        triggerClientEvent(client, "economy:message", client, "NPC Company created: " .. name)
        -- Refresh DM view
        sendDMEconomyData(client)
    else
        triggerClientEvent(client, "economy:message", client, err or "Failed to create company", true)
    end
end)

-- DM delete company
addEvent("economy:deleteCompany", true)
addEventHandler("economy:deleteCompany", root, function(companyID)
    local company = Companies[companyID]
    if not company then
        triggerClientEvent(client, "economy:message", client, "Company not found", true)
        return
    end
    
    -- Check permission: DM can delete any, player can only delete their own
    local isDM = isDungeonMaster and isDungeonMaster(client)
    
    if not verifyCompanyOwnership(client, company, true) then
        triggerClientEvent(client, "economy:message", client, "You don't own this company", true)
        return
    end
    
    local companyName = company.name
    local success, msg = deleteCompany(companyID)
    
    if success then
        triggerClientEvent(client, "economy:message", client, "Deleted: " .. companyName)
        -- Clear selection and refresh
        if isDM then
            sendDMEconomyData(client)
        else
            sendPlayerCompanies(client)
        end
    else
        triggerClientEvent(client, "economy:message", client, msg or "Failed to delete", true)
    end
end)

-- DM add money to company
addEvent("economy:dmAddMoney", true)
addEventHandler("economy:dmAddMoney", root, function(companyID, amount)
    if not isDungeonMaster or not isDungeonMaster(client) then
        triggerClientEvent(client, "economy:message", client, "DM required", true)
        return
    end
    
    local company = Companies[companyID]
    if not company then
        triggerClientEvent(client, "economy:message", client, "Company not found", true)
        return
    end
    
    -- Deduct from state market
    if GlobalEconomy.markets.state.money < amount then
        triggerClientEvent(client, "economy:message", client, "State market has insufficient funds", true)
        return
    end
    
    GlobalEconomy.markets.state.money = GlobalEconomy.markets.state.money - amount
    company.points.money = company.points.money + amount
    
    -- Save
    dbExec(database, "UPDATE companies SET money = ? WHERE id = ?", company.points.money, companyID)
    saveEconomyState()
    
    logMarketTransaction("DM_GRANT", MARKET_TIER.STATE, amount, "FROM_MARKET", companyID, nil, nil, "DM added money to " .. company.name)
    
    triggerClientEvent(client, "economy:message", client, "Added " .. formatMoney(amount) .. " to " .. company.name)
end)

-- DM add item to company
addEvent("economy:dmAddItem", true)
addEventHandler("economy:dmAddItem", root, function(companyID, itemID, quantity)
    if not isDungeonMaster or not isDungeonMaster(client) then
        triggerClientEvent(client, "economy:message", client, "DM required", true)
        return
    end
    
    local company = Companies[companyID]
    if not company then
        triggerClientEvent(client, "economy:message", client, "Company not found", true)
        return
    end
    
    addItemToCompany(companyID, itemID, quantity)
    triggerClientEvent(client, "economy:message", client, "Added " .. quantity .. "x " .. itemID .. " to " .. company.name)
end)

-- View economy status
addCommandHandler("economystatus", function(player)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    outputChatBox("=== Economy Status ===", player, 255, 255, 0)
    outputChatBox("Current Cycle: " .. GlobalEconomy.currentCycle, player, 200, 200, 200)
    outputChatBox("Global Market: " .. formatMoney(GlobalEconomy.markets.global.money), player, 200, 200, 200)
    outputChatBox("National Market: " .. formatMoney(GlobalEconomy.markets.national.money), player, 200, 200, 200)
    outputChatBox("State Market: " .. formatMoney(GlobalEconomy.markets.state.money), player, 200, 200, 200)
    
    local companyCount = 0
    for _ in pairs(Companies) do companyCount = companyCount + 1 end
    outputChatBox("Active Companies: " .. companyCount, player, 200, 200, 200)
    
    local dealCount = 0
    for _, deal in pairs(Deals) do
        if deal.status == DEAL_STATUS.ACTIVE then dealCount = dealCount + 1 end
    end
    outputChatBox("Active Deals: " .. dealCount, player, 200, 200, 200)
end)

-- Create NPC company
addCommandHandler("createcompany", function(player, cmd, name, companyType, startingCapital)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    if not name then
        outputChatBox("Usage: /createcompany \"Name\" type [capital]", player, 255, 255, 0)
        outputChatBox("Types: resource, manufacturing, retail, tech, special", player, 200, 200, 200)
        return
    end
    
    companyType = companyType or COMPANY_TYPE.RESOURCE
    startingCapital = tonumber(startingCapital) or EconomyConfig.COMPANY_STARTING_CAPITAL
    
    local companyID, err = createCompany(name, companyType, "npc", nil, startingCapital)
    
    if companyID then
        outputChatBox("Company created: " .. name .. " (" .. companyID .. ")", player, 0, 255, 0)
    else
        outputChatBox("Error: " .. err, player, 255, 0, 0)
    end
end)

-- List companies
addCommandHandler("listcompanies", function(player)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    outputChatBox("=== Companies ===", player, 255, 255, 0)
    for companyID, company in pairs(Companies) do
        local owner = company.ownerType == "npc" and "NPC" or company.ownerID
        outputChatBox(company.name .. " [" .. company.type .. "] - " .. formatMoney(company.points.money) .. " - " .. owner, player, 200, 200, 200)
    end
end)

-- Create economy resource item (for resource companies to produce)
addCommandHandler("createresource", function(player, cmd, itemID, laborCost, basePrice, ...)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    if not itemID then
        outputChatBox("Usage: /createresource itemID [laborCost] [basePrice] [name...]", player, 255, 255, 0)
        outputChatBox("  laborCost: LP needed to produce 1 unit (default: 1.0)", player, 200, 200, 200)
        outputChatBox("  basePrice: Market value per unit (default: 10)", player, 200, 200, 200)
        return
    end
    
    laborCost = tonumber(laborCost) or 1.0
    basePrice = tonumber(basePrice) or 10
    local name = table.concat({...}, " ")
    if name == "" then name = itemID end
    
    -- Create in ItemRegistry if available
    if ItemRegistry and ItemRegistry.register then
        ItemRegistry:register({
            id = itemID,
            name = name,
            category = "resource",
            weight = 1.0,
            value = basePrice,
            stackable = true,
            maxStack = 999,
            description = "Raw resource material"
        }, "SYSTEM")
    end
    
    -- Create economy data
    setItemEconomyData(itemID, laborCost, true, {"state", "national", "global"}, basePrice, 1.0)
    
    outputChatBox("Resource created: " .. name .. " (" .. itemID .. ")", player, 0, 255, 0)
    outputChatBox("  Labor Cost: " .. laborCost .. " LP | Base Price: $" .. basePrice, player, 200, 200, 200)
end)

-- List economy resources
addCommandHandler("listresources", function(player)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    outputChatBox("=== Economy Resources ===", player, 255, 255, 0)
    
    if database then
        local query = dbQuery(database, "SELECT * FROM economy_items ORDER BY item_id")
        local result = dbPoll(query, -1)
        if result and #result > 0 then
            for _, item in ipairs(result) do
                outputChatBox(item.item_id .. " - Labor: " .. item.labor_cost .. " LP | Price: $" .. item.base_price, player, 200, 200, 200)
            end
        else
            outputChatBox("No resources defined. Use /createresource to add some.", player, 200, 200, 200)
        end
    end
end)

-- Create economy recipe
-- Create economy recipe (for manufacturing companies)
addCommandHandler("createeconrecipe", function(player, cmd, recipeID, resultItem, resultQty, laborCost)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    if not recipeID or not resultItem then
        outputChatBox("Usage: /createeconrecipe recipeID resultItem [resultQty] [laborCost]", player, 255, 255, 0)
        outputChatBox("  Then use /addeconingredient to add required inputs", player, 200, 200, 200)
        return
    end
    
    resultQty = tonumber(resultQty) or 1
    laborCost = tonumber(laborCost) or 8
    
    local success = createRecipe(recipeID, recipeID, "manufacturing", {}, {[resultItem] = resultQty}, laborCost)
    
    if success then
        outputChatBox("Economy recipe created: " .. recipeID .. " -> " .. resultQty .. "x " .. resultItem, player, 0, 255, 0)
        outputChatBox("Use /addeconingredient " .. recipeID .. " itemID qty to add inputs", player, 255, 255, 0)
    else
        outputChatBox("Failed to create recipe", player, 255, 0, 0)
    end
end)

-- Add ingredient to economy recipe
addCommandHandler("addeconingredient", function(player, cmd, recipeID, ingredientID, qty)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    if not recipeID or not ingredientID then
        outputChatBox("Usage: /addeconingredient recipeID ingredientID [qty]", player, 255, 255, 0)
        return
    end
    
    qty = tonumber(qty) or 1
    
    -- Get existing recipe
    local recipe = getRecipe(recipeID)
    if not recipe then
        outputChatBox("Recipe not found: " .. recipeID, player, 255, 0, 0)
        return
    end
    
    recipe.inputs[ingredientID] = qty
    
    -- Update in database
    dbExec(database, "UPDATE economy_recipes SET inputs = ? WHERE id = ?", toJSON(recipe.inputs), recipeID)
    
    outputChatBox("Added ingredient: " .. qty .. "x " .. ingredientID .. " to " .. recipeID, player, 0, 255, 0)
end)

-- List economy recipes
addCommandHandler("listeconrecipes", function(player)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("DM required", player, 255, 0, 0)
        return
    end
    
    outputChatBox("=== Economy Recipes (Manufacturing) ===", player, 255, 255, 0)
    
    if database then
        local query = dbQuery(database, "SELECT * FROM economy_recipes ORDER BY id")
        local result = dbPoll(query, -1)
        if result and #result > 0 then
            for _, recipe in ipairs(result) do
                local inputs = fromJSON(recipe.inputs) or {}
                local outputs = fromJSON(recipe.outputs) or {}
                
                local inputStr = ""
                for itemID, qty in pairs(inputs) do
                    inputStr = inputStr .. qty .. "x" .. itemID .. " "
                end
                if inputStr == "" then inputStr = "(no inputs)" end
                
                local outputStr = ""
                for itemID, qty in pairs(outputs) do
                    outputStr = outputStr .. qty .. "x" .. itemID .. " "
                end
                
                outputChatBox(recipe.id .. ": " .. inputStr .. "-> " .. outputStr, player, 200, 200, 200)
            end
        else
            outputChatBox("No economy recipes defined. Use /createeconrecipe to add some.", player, 200, 200, 200)
        end
    end
end)

outputServerLog("===== ECONOMIC_CYCLE.LUA LOADED =====")
