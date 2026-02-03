--[[
================================================================================
    CLIENT_ECONOMY.LUA - Economic System Client GUI
================================================================================
    Provides player interface for company management, deals, and production.
    DMs get an enhanced interface to manage all companies including NPCs.
    
    KEYBIND: F6 to open company management
    COMMANDS: /company, /acceptjob, /declinejob
================================================================================
]]

local screenW, screenH = guiGetScreenSize()

-- GUI State
local economyWindow = nil
local economyElements = {}
local playerCompanies = {}
local allCompanies = {}
local selectedCompany = nil
local selectedCompanyData = nil
local currentTab = "dashboard"
local isDMView = false
local marketData = nil

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

local function formatMoney(amount)
    if not amount then return "$0" end
    if amount >= 1000000000000 then
        return string.format("$%.2fT", amount / 1000000000000)
    elseif amount >= 1000000000 then
        return string.format("$%.2fB", amount / 1000000000)
    elseif amount >= 1000000 then
        return string.format("$%.2fM", amount / 1000000)
    elseif amount >= 1000 then
        return string.format("$%.2fK", amount / 1000)
    else
        return string.format("$%.0f", amount)
    end
end

local function formatNumber(num)
    if not num then return "0" end
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(math.floor(num))
    end
end

local function isPlayerDM()
    return getElementData(localPlayer, "isDungeonMaster") == true
end

--------------------------------------------------------------------------------
-- WINDOW MANAGEMENT
--------------------------------------------------------------------------------

local function closeEconomyWindow()
    if economyWindow and isElement(economyWindow) then
        destroyElement(economyWindow)
        economyWindow = nil
        economyElements = {}
        showCursor(false)
        guiSetInputMode("allow_binds")
    end
end

local function clearContentPanel()
    if economyElements.contentPanel and isElement(economyElements.contentPanel) then
        for _, child in ipairs(getElementChildren(economyElements.contentPanel)) do
            destroyElement(child)
        end
    end
end

--------------------------------------------------------------------------------
-- TAB CONTENT BUILDERS (Forward declarations)
--------------------------------------------------------------------------------

local buildDashboardTab, buildEmployeesTab, buildProductionTab, buildInventoryTab, buildDealsTab, buildPerksTab
local buildDMOverviewTab, buildDMMarketsTab

local function updateTabContent()
    clearContentPanel()
    
    -- DM overview tabs don't need a selected company
    if currentTab == "overview" then buildDMOverviewTab() return end
    if currentTab == "markets" then buildDMMarketsTab() return end
    
    if not selectedCompanyData then return end
    
    if currentTab == "dashboard" then buildDashboardTab()
    elseif currentTab == "employees" then buildEmployeesTab()
    elseif currentTab == "production" then buildProductionTab()
    elseif currentTab == "inventory" then buildInventoryTab()
    elseif currentTab == "deals" then buildDealsTab()
    elseif currentTab == "perks" then buildPerksTab()
    end
end

--------------------------------------------------------------------------------
-- DM ECONOMY WINDOW
--------------------------------------------------------------------------------

local function buildDMEconomyWindow(companies, markets)
    if economyWindow then closeEconomyWindow() end
    
    allCompanies = companies or {}
    marketData = markets
    isDMView = true
    
    local w, h = 900, 620
    economyWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "DM Economy Management", false)
    guiWindowSetSizable(economyWindow, false)
    
    local y = 28
    
    -- Top row: DM-specific tabs
    guiCreateLabel(15, y, 100, 20, "Economy:", false, economyWindow)
    
    local overviewBtn = guiCreateButton(100, y - 2, 90, 26, "Overview", false, economyWindow)
    local marketsBtn = guiCreateButton(195, y - 2, 90, 26, "Markets", false, economyWindow)
    
    addEventHandler("onClientGUIClick", overviewBtn, function()
        currentTab = "overview"
        selectedCompanyData = nil
        guiComboBoxSetSelected(economyElements.companySelector, 0)
        updateTabContent()
    end, false)
    
    addEventHandler("onClientGUIClick", marketsBtn, function()
        currentTab = "markets"
        selectedCompanyData = nil
        guiComboBoxSetSelected(economyElements.companySelector, 0)
        updateTabContent()
    end, false)
    
    -- Create NPC Company button
    local createNPCBtn = guiCreateButton(w - 185, y - 2, 170, 26, "+ Create NPC Company", false, economyWindow)
    guiSetProperty(createNPCBtn, "NormalTextColour", "FF66FF66")
    addEventHandler("onClientGUIClick", createNPCBtn, function()
        openNPCCompanyCreatorGUI()
    end, false)
    
    y = y + 35
    
    -- Company selector
    guiCreateLabel(15, y, 120, 20, "Manage Company:", false, economyWindow)
    economyElements.companySelector = guiCreateComboBox(135, y - 2, 350, 300, "-- Select a company --", false, economyWindow)
    guiComboBoxAddItem(economyElements.companySelector, "-- Economy Overview --")
    
    for i, company in ipairs(allCompanies) do
        local ownerTag = company.ownerType == "npc" and "[NPC]" or "[Player]"
        guiComboBoxAddItem(economyElements.companySelector, ownerTag .. " " .. company.name .. " (" .. company.type .. ")")
    end
    guiComboBoxSetSelected(economyElements.companySelector, 0)
    
    addEventHandler("onClientGUIComboBoxAccepted", economyElements.companySelector, function()
        local idx = guiComboBoxGetSelected(source)
        if idx <= 0 then
            selectedCompany = nil
            selectedCompanyData = nil
            currentTab = "overview"
            updateTabContent()
        else
            selectedCompany = allCompanies[idx]
            if selectedCompany then
                triggerServerEvent("economy:requestCompanyData", localPlayer, selectedCompany.id)
            end
        end
    end, false)
    
    -- Force Cycle button
    local forceCycleBtn = guiCreateButton(w - 185, y - 2, 170, 26, "Force End Cycle", false, economyWindow)
    guiSetProperty(forceCycleBtn, "NormalTextColour", "FFFFA500")
    addEventHandler("onClientGUIClick", forceCycleBtn, function()
        triggerServerEvent("economy:dmForceCycle", localPlayer)
    end, false)
    
    y = y + 35
    
    -- Company-specific tabs
    local companyTabs = {"Dashboard", "Employees", "Production", "Inventory", "Deals", "Perks"}
    for i, tabName in ipairs(companyTabs) do
        local btn = guiCreateButton(15 + ((i-1) * 100), y, 95, 26, tabName, false, economyWindow)
        addEventHandler("onClientGUIClick", btn, function()
            if selectedCompanyData then
                currentTab = tabName:lower()
                updateTabContent()
            else
                outputChatBox("Select a company first", 255, 200, 100)
            end
        end, false)
    end
    
    -- Delete company button
    local deleteBtn = guiCreateButton(w - 130, y, 115, 26, "Delete Company", false, economyWindow)
    guiSetProperty(deleteBtn, "NormalTextColour", "FFFF6666")
    addEventHandler("onClientGUIClick", deleteBtn, function()
        if selectedCompanyData then
            openDeleteConfirmation(selectedCompanyData.id, selectedCompanyData.name)
        else
            outputChatBox("Select a company first", 255, 100, 100)
        end
    end, false)
    
    y = y + 35
    
    -- Content panel
    economyElements.contentPanel = guiCreateScrollPane(15, y, w - 30, h - y - 50, false, economyWindow)
    
    -- Close button
    local closeBtn = guiCreateButton(w - 100, h - 40, 85, 30, "Close", false, economyWindow)
    addEventHandler("onClientGUIClick", closeBtn, closeEconomyWindow, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
    
    -- Start with overview
    currentTab = "overview"
    updateTabContent()
end

--------------------------------------------------------------------------------
-- PLAYER ECONOMY WINDOW
--------------------------------------------------------------------------------

local function buildPlayerEconomyWindow(companies)
    if economyWindow then closeEconomyWindow() end
    
    playerCompanies = companies or {}
    isDMView = false
    
    local w, h = 800, 550
    economyWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "Company Management", false)
    guiWindowSetSizable(economyWindow, false)
    
    -- No companies
    if #playerCompanies == 0 then
        guiCreateLabel(250, 200, 300, 30, "You don't own any companies yet.", false, economyWindow)
        local createBtn = guiCreateButton(300, 250, 200, 40, "Create Company ($50,000)", false, economyWindow)
        addEventHandler("onClientGUIClick", createBtn, function()
            closeEconomyWindow()
            openCompanyCreatorGUI()
        end, false)
        local closeBtn = guiCreateButton(300, 310, 200, 40, "Close", false, economyWindow)
        addEventHandler("onClientGUIClick", closeBtn, closeEconomyWindow, false)
        showCursor(true)
        return
    end
    
    local tabY = 30
    
    -- Company selector (if multiple)
    if #playerCompanies > 1 then
        guiCreateLabel(15, 30, 100, 20, "Company:", false, economyWindow)
        economyElements.companySelector = guiCreateComboBox(100, 28, 250, 200, "", false, economyWindow)
        for i, company in ipairs(playerCompanies) do
            guiComboBoxAddItem(economyElements.companySelector, company.name)
        end
        guiComboBoxSetSelected(economyElements.companySelector, 0)
        addEventHandler("onClientGUIComboBoxAccepted", economyElements.companySelector, function()
            local idx = guiComboBoxGetSelected(source)
            if idx >= 0 then
                selectedCompany = playerCompanies[idx + 1]
                triggerServerEvent("economy:requestCompanyData", localPlayer, selectedCompany.id)
            end
        end, false)
        tabY = 60
    end
    
    selectedCompany = playerCompanies[1]
    
    -- Tab buttons
    local tabs = {"Dashboard", "Employees", "Production", "Inventory", "Deals", "Perks"}
    for i, tabName in ipairs(tabs) do
        local btn = guiCreateButton(15 + ((i-1) * 125), tabY, 120, 30, tabName, false, economyWindow)
        addEventHandler("onClientGUIClick", btn, function()
            currentTab = tabName:lower()
            updateTabContent()
        end, false)
    end
    
    -- Content panel
    economyElements.contentPanel = guiCreateScrollPane(15, tabY + 40, w - 30, h - tabY - 90, false, economyWindow)
    
    -- Close button
    local closeBtn = guiCreateButton(w - 100, h - 40, 85, 30, "Close", false, economyWindow)
    addEventHandler("onClientGUIClick", closeBtn, closeEconomyWindow, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
    
    triggerServerEvent("economy:requestCompanyData", localPlayer, selectedCompany.id)
end

--------------------------------------------------------------------------------
-- DM TAB BUILDERS
--------------------------------------------------------------------------------

buildDMOverviewTab = function()
    local panel = economyElements.contentPanel
    local y = 10
    
    -- Title
    local titleLabel = guiCreateLabel(10, y, 500, 25, "Economy Overview", false, panel)
    guiSetFont(titleLabel, "default-bold-small")
    y = y + 35
    
    -- Market summary
    guiCreateLabel(10, y, 400, 20, "=== Market Pools ===", false, panel)
    y = y + 25
    
    if marketData then
        guiCreateLabel(10, y, 200, 20, "Global Market:", false, panel)
        guiCreateLabel(200, y, 200, 20, formatMoney(marketData.global), false, panel)
        y = y + 22
        guiCreateLabel(10, y, 200, 20, "National Market:", false, panel)
        guiCreateLabel(200, y, 200, 20, formatMoney(marketData.national), false, panel)
        y = y + 22
        guiCreateLabel(10, y, 200, 20, "State Market:", false, panel)
        guiCreateLabel(200, y, 200, 20, formatMoney(marketData.state), false, panel)
        y = y + 22
        guiCreateLabel(10, y, 200, 20, "Current Cycle:", false, panel)
        guiCreateLabel(200, y, 200, 20, tostring(marketData.currentCycle or 0), false, panel)
    else
        guiCreateLabel(10, y, 300, 20, "Market data not available", false, panel)
    end
    y = y + 35
    
    -- Company summary
    guiCreateLabel(10, y, 400, 20, "=== Companies ===", false, panel)
    y = y + 25
    
    local npcCount, playerCount = 0, 0
    for _, company in ipairs(allCompanies) do
        if company.ownerType == "npc" then npcCount = npcCount + 1
        else playerCount = playerCount + 1 end
    end
    
    guiCreateLabel(10, y, 200, 20, "NPC Companies: " .. npcCount, false, panel)
    y = y + 22
    guiCreateLabel(10, y, 200, 20, "Player Companies: " .. playerCount, false, panel)
    y = y + 22
    guiCreateLabel(10, y, 200, 20, "Total: " .. #allCompanies, false, panel)
    y = y + 35
    
    -- Company list
    guiCreateLabel(10, y, 400, 20, "=== All Companies ===", false, panel)
    y = y + 25
    
    -- Headers
    guiCreateLabel(10, y, 150, 20, "Name", false, panel)
    guiCreateLabel(170, y, 80, 20, "Type", false, panel)
    guiCreateLabel(260, y, 60, 20, "Owner", false, panel)
    guiCreateLabel(330, y, 100, 20, "Money", false, panel)
    guiCreateLabel(440, y, 80, 20, "Employees", false, panel)
    y = y + 22
    
    for _, company in ipairs(allCompanies) do
        guiCreateLabel(10, y, 150, 20, company.name or "?", false, panel)
        guiCreateLabel(170, y, 80, 20, company.type or "?", false, panel)
        guiCreateLabel(260, y, 60, 20, company.ownerType == "npc" and "NPC" or "Player", false, panel)
        guiCreateLabel(330, y, 100, 20, formatMoney(company.money or 0), false, panel)
        guiCreateLabel(440, y, 80, 20, tostring(company.employeeCount or 0), false, panel)
        y = y + 20
    end
end

buildDMMarketsTab = function()
    local panel = economyElements.contentPanel
    local y = 10
    
    local titleLabel = guiCreateLabel(10, y, 500, 25, "Market Management", false, panel)
    guiSetFont(titleLabel, "default-bold-small")
    y = y + 35
    
    if marketData then
        -- Global Market
        guiCreateLabel(10, y, 150, 20, "Global Market:", false, panel)
        local globalLabel = guiCreateLabel(170, y, 200, 20, formatMoney(marketData.global), false, panel)
        guiLabelSetColor(globalLabel, 100, 200, 255)
        y = y + 25
        guiCreateLabel(30, y, 400, 20, "For bulk international trade (100,000+ units)", false, panel)
        y = y + 30
        
        -- National Market
        guiCreateLabel(10, y, 150, 20, "National Market:", false, panel)
        local nationalLabel = guiCreateLabel(170, y, 200, 20, formatMoney(marketData.national), false, panel)
        guiLabelSetColor(nationalLabel, 100, 255, 100)
        y = y + 25
        guiCreateLabel(30, y, 400, 20, "For nationwide trade (1,000+ units)", false, panel)
        y = y + 30
        
        -- State Market
        guiCreateLabel(10, y, 150, 20, "State Market:", false, panel)
        local stateLabel = guiCreateLabel(170, y, 200, 20, formatMoney(marketData.state), false, panel)
        guiLabelSetColor(stateLabel, 255, 200, 100)
        y = y + 25
        guiCreateLabel(30, y, 400, 20, "For local/retail trade (any quantity)", false, panel)
        y = y + 40
        
        -- Cycle info
        guiCreateLabel(10, y, 400, 20, "=== Cycle Information ===", false, panel)
        y = y + 25
        guiCreateLabel(10, y, 200, 20, "Current Cycle: " .. (marketData.currentCycle or 0), false, panel)
        y = y + 22
        
        if marketData.nextCycleTime then
            local timeLeft = marketData.nextCycleTime - getRealTime().timestamp
            local hoursLeft = math.max(0, math.floor(timeLeft / 3600))
            local minsLeft = math.max(0, math.floor((timeLeft % 3600) / 60))
            guiCreateLabel(10, y, 300, 20, "Next Cycle In: " .. hoursLeft .. "h " .. minsLeft .. "m", false, panel)
        end
    else
        guiCreateLabel(10, y, 300, 20, "Market data not loaded", false, panel)
    end
end

--------------------------------------------------------------------------------
-- COMPANY TAB BUILDERS
--------------------------------------------------------------------------------

buildDashboardTab = function()
    local panel = economyElements.contentPanel
    local company = selectedCompanyData
    local y = 10
    
    local nameLabel = guiCreateLabel(10, y, 500, 25, company.name .. " (" .. (company.type or "?"):upper() .. ")", false, panel)
    guiSetFont(nameLabel, "default-bold-small")
    
    if isDMView then
        local ownerLabel = guiCreateLabel(400, y, 150, 20, company.ownerType == "npc" and "[NPC Company]" or "[Player Company]", false, panel)
        guiLabelSetColor(ownerLabel, 255, 200, 100)
    end
    y = y + 35
    
    guiCreateLabel(10, y, 150, 20, "Money: " .. formatMoney(company.points.money), false, panel)
    y = y + 22
    guiCreateLabel(10, y, 150, 20, "Efficiency: " .. formatNumber(company.points.efficiency), false, panel)
    y = y + 22
    guiCreateLabel(10, y, 150, 20, "Innovation: " .. formatNumber(company.points.innovation), false, panel)
    y = y + 22
    guiCreateLabel(10, y, 150, 20, "Logistics: " .. formatNumber(company.points.logistics), false, panel)
    y = y + 35
    
    local empCount = 0
    if company.employees then for _ in pairs(company.employees) do empCount = empCount + 1 end end
    guiCreateLabel(10, y, 200, 20, "Employees: " .. empCount, false, panel)
    y = y + 22
    
    local dealCount = company.deals and #company.deals or 0
    guiCreateLabel(10, y, 200, 20, "Active Deals: " .. dealCount, false, panel)
    y = y + 30
    
    -- Production status
    if company.type == "resource" then
        guiCreateLabel(10, y, 300, 20, "Producing: " .. (company.autoProduceItem or "Not set"), false, panel)
    elseif company.type == "manufacturing" then
        guiCreateLabel(10, y, 300, 20, "Recipe: " .. (company.currentRecipe or "Not set"), false, panel)
    end
    
    -- DM: Add money button
    if isDMView then
        y = y + 40
        guiCreateLabel(10, y, 400, 20, "=== DM Controls ===", false, panel)
        y = y + 25
        
        guiCreateLabel(10, y, 80, 20, "Add Money:", false, panel)
        local moneyEdit = guiCreateEdit(100, y - 2, 100, 24, "10000", false, panel)
        local addMoneyBtn = guiCreateButton(210, y - 2, 80, 24, "Add", false, panel)
        
        local companyID = company.id
        addEventHandler("onClientGUIClick", addMoneyBtn, function()
            local amount = tonumber(guiGetText(moneyEdit))
            if amount and amount > 0 then
                triggerServerEvent("economy:dmAddMoney", localPlayer, companyID, amount)
            end
        end, false)
    end
end

buildEmployeesTab = function()
    local panel = economyElements.contentPanel
    local company = selectedCompanyData
    local y = 10
    
    local companyID = company.id
    local hireBtn = guiCreateButton(10, y, 150, 30, "Hire NPC Employee", false, panel)
    addEventHandler("onClientGUIClick", hireBtn, function()
        openHireDialogGUI(companyID)
    end, false)
    y = y + 45
    
    guiCreateLabel(10, y, 100, 20, "Type", false, panel)
    guiCreateLabel(110, y, 90, 20, "Allocation", false, panel)
    guiCreateLabel(210, y, 70, 20, "Wage", false, panel)
    guiCreateLabel(290, y, 70, 20, "Status", false, panel)
    y = y + 22
    
    if company.employees then
        for empID, emp in pairs(company.employees) do
            guiCreateLabel(10, y, 100, 20, emp.type or "?", false, panel)
            guiCreateLabel(110, y, 90, 20, emp.laborAllocation or "?", false, panel)
            guiCreateLabel(210, y, 70, 20, "$" .. (emp.wage or 0), false, panel)
            guiCreateLabel(290, y, 70, 20, emp.status or "active", false, panel)
            
            local capturedEmpID = empID
            local fireBtn = guiCreateButton(370, y - 2, 55, 22, "Fire", false, panel)
            addEventHandler("onClientGUIClick", fireBtn, function()
                triggerServerEvent("economy:fireEmployee", localPlayer, companyID, capturedEmpID)
            end, false)
            y = y + 26
        end
    end
    
    if not company.employees or not next(company.employees) then
        guiCreateLabel(10, y, 300, 20, "No employees. Hire some!", false, panel)
    end
end

buildProductionTab = function()
    local panel = economyElements.contentPanel
    local company = selectedCompanyData
    local y = 10
    
    if company.type == "resource" then
        guiCreateLabel(10, y, 500, 20, "Resource companies extract raw materials using labor power.", false, panel)
        y = y + 30
        guiCreateLabel(10, y, 500, 20, "Current production: " .. (company.autoProduceItem or "Not set"), false, panel)
        y = y + 30
        
        if isDMView then
            guiCreateLabel(10, y, 100, 20, "Set Item ID:", false, panel)
            local itemEdit = guiCreateEdit(120, y - 2, 150, 24, company.autoProduceItem or "", false, panel)
            local setBtn = guiCreateButton(280, y - 2, 60, 24, "Set", false, panel)
            local companyID = company.id
            addEventHandler("onClientGUIClick", setBtn, function()
                local itemID = guiGetText(itemEdit)
                if itemID and itemID ~= "" then
                    triggerServerEvent("economy:setProduction", localPlayer, companyID, "resource", itemID)
                end
            end, false)
        end
        
    elseif company.type == "manufacturing" then
        guiCreateLabel(10, y, 500, 20, "Manufacturing companies process materials using recipes.", false, panel)
        y = y + 30
        guiCreateLabel(10, y, 500, 20, "Active recipe: " .. (company.currentRecipe or "Not set"), false, panel)
        y = y + 30
        
        if isDMView then
            guiCreateLabel(10, y, 100, 20, "Set Recipe ID:", false, panel)
            local recipeEdit = guiCreateEdit(120, y - 2, 150, 24, company.currentRecipe or "", false, panel)
            local setBtn = guiCreateButton(280, y - 2, 60, 24, "Set", false, panel)
            local companyID = company.id
            addEventHandler("onClientGUIClick", setBtn, function()
                local recipeID = guiGetText(recipeEdit)
                if recipeID and recipeID ~= "" then
                    triggerServerEvent("economy:setProduction", localPlayer, companyID, "manufacturing", recipeID)
                end
            end, false)
        end
        
    elseif company.type == "tech" then
        guiCreateLabel(10, y, 550, 20, "Tech companies generate Efficiency and Innovation from professional employees.", false, panel)
    elseif company.type == "retail" then
        guiCreateLabel(10, y, 550, 20, "Retail companies sell inventory to State Market (5-15% consumed per cycle).", false, panel)
    end
end

buildInventoryTab = function()
    local panel = economyElements.contentPanel
    local company = selectedCompanyData
    local y = 10
    
    if isDMView then
        -- Add item controls
        guiCreateLabel(10, y, 60, 20, "Item ID:", false, panel)
        local itemEdit = guiCreateEdit(75, y - 2, 120, 24, "", false, panel)
        guiCreateLabel(205, y, 30, 20, "Qty:", false, panel)
        local qtyEdit = guiCreateEdit(240, y - 2, 60, 24, "100", false, panel)
        local addBtn = guiCreateButton(310, y - 2, 60, 24, "Add", false, panel)
        
        local companyID = company.id
        addEventHandler("onClientGUIClick", addBtn, function()
            local itemID = guiGetText(itemEdit)
            local qty = tonumber(guiGetText(qtyEdit))
            if itemID and itemID ~= "" and qty and qty > 0 then
                triggerServerEvent("economy:dmAddItem", localPlayer, companyID, itemID, qty)
            end
        end, false)
        y = y + 35
    end
    
    guiCreateLabel(10, y, 200, 20, "Item", false, panel)
    guiCreateLabel(280, y, 100, 20, "Quantity", false, panel)
    y = y + 22
    
    if company.inventory and next(company.inventory) then
        for itemID, quantity in pairs(company.inventory) do
            guiCreateLabel(10, y, 260, 20, itemID, false, panel)
            guiCreateLabel(280, y, 100, 20, formatNumber(quantity), false, panel)
            y = y + 22
        end
    else
        guiCreateLabel(10, y, 300, 20, "Inventory is empty.", false, panel)
    end
end

buildDealsTab = function()
    local panel = economyElements.contentPanel
    local company = selectedCompanyData
    local y = 10
    
    local companyID = company.id
    local createBtn = guiCreateButton(10, y, 140, 28, "Create New Deal", false, panel)
    addEventHandler("onClientGUIClick", createBtn, function()
        triggerServerEvent("economy:openDealCreator", localPlayer, companyID)
    end, false)
    y = y + 40
    
    guiCreateLabel(10, y, 140, 20, "Partner", false, panel)
    guiCreateLabel(160, y, 80, 20, "Status", false, panel)
    guiCreateLabel(250, y, 120, 20, "Duration", false, panel)
    y = y + 22
    
    if company.deals and #company.deals > 0 then
        for _, deal in ipairs(company.deals) do
            local partner = (deal.companyAID == company.id) and (deal.companyBName or "?") or (deal.companyAName or "?")
            guiCreateLabel(10, y, 140, 20, partner, false, panel)
            guiCreateLabel(160, y, 80, 20, deal.status or "?", false, panel)
            guiCreateLabel(250, y, 120, 20, tostring(deal.duration or "infinite"), false, panel)
            y = y + 22
        end
    else
        guiCreateLabel(10, y, 300, 20, "No active deals.", false, panel)
    end
end

buildPerksTab = function()
    local panel = economyElements.contentPanel
    local company = selectedCompanyData
    local y = 10
    
    guiCreateLabel(10, y, 350, 22, "Innovation Points: " .. formatNumber(company.points.innovation), false, panel)
    y = y + 30
    
    local perks = {
        {id = "efficiency_boost_1", name = "Efficiency I", cost = 100, desc = "+5% efficiency cap"},
        {id = "extra_deal_slot_1", name = "Trade Network I", cost = 200, desc = "+1 deal slot"},
        {id = "wage_reduction_1", name = "HR Optimization I", cost = 300, desc = "-5% wages"},
        {id = "logistics_boost_1", name = "Logistics I", cost = 250, desc = "+10 logistics"},
        {id = "production_speed_1", name = "Automation I", cost = 400, desc = "+10% production"},
    }
    
    local companyID = company.id
    for _, perk in ipairs(perks) do
        local owned = company.perks and company.perks[perk.id]
        local canBuy = not owned and company.points.innovation >= perk.cost
        
        local label = guiCreateLabel(10, y, 320, 20, perk.name .. " (" .. perk.cost .. " IP) - " .. perk.desc, false, panel)
        
        if owned then
            guiLabelSetColor(label, 100, 255, 100)
            guiCreateLabel(400, y, 60, 20, "OWNED", false, panel)
        elseif canBuy then
            local perkID = perk.id
            local buyBtn = guiCreateButton(400, y - 2, 55, 22, "Buy", false, panel)
            addEventHandler("onClientGUIClick", buyBtn, function()
                triggerServerEvent("economy:buyPerk", localPlayer, companyID, perkID)
            end, false)
        else
            guiLabelSetColor(label, 150, 150, 150)
        end
        y = y + 26
    end
end

--------------------------------------------------------------------------------
-- DIALOG WINDOWS
--------------------------------------------------------------------------------

local npcCreatorWindow = nil

function openNPCCompanyCreatorGUI()
    if npcCreatorWindow then destroyElement(npcCreatorWindow) end
    
    local w, h = 400, 320
    npcCreatorWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "Create NPC Company", false)
    guiWindowSetSizable(npcCreatorWindow, false)
    
    local y = 30
    
    guiCreateLabel(15, y, 100, 20, "Company Name:", false, npcCreatorWindow)
    local nameEdit = guiCreateEdit(120, y - 2, 260, 25, "", false, npcCreatorWindow)
    y = y + 35
    
    guiCreateLabel(15, y, 100, 20, "Company Type:", false, npcCreatorWindow)
    local typeCombo = guiCreateComboBox(120, y - 2, 200, 150, "", false, npcCreatorWindow)
    guiComboBoxAddItem(typeCombo, "Resource (extract materials)")
    guiComboBoxAddItem(typeCombo, "Manufacturing (process items)")
    guiComboBoxAddItem(typeCombo, "Retail (sell to market)")
    guiComboBoxAddItem(typeCombo, "Tech (generate points)")
    guiComboBoxSetSelected(typeCombo, 0)
    y = y + 35
    
    guiCreateLabel(15, y, 120, 20, "Starting Capital:", false, npcCreatorWindow)
    local capitalEdit = guiCreateEdit(140, y - 2, 100, 25, "50000", false, npcCreatorWindow)
    y = y + 35
    
    guiCreateLabel(15, y, 350, 40, "Note: NPC companies don't cost player money.\nCapital is deducted from State Market.", false, npcCreatorWindow)
    y = y + 55
    
    local createBtn = guiCreateButton(15, y, 175, 40, "Create Company", false, npcCreatorWindow)
    guiSetProperty(createBtn, "NormalTextColour", "FF66FF66")
    
    local cancelBtn = guiCreateButton(210, y, 175, 40, "Cancel", false, npcCreatorWindow)
    
    addEventHandler("onClientGUIClick", createBtn, function()
        local name = guiGetText(nameEdit)
        local typeIdx = guiComboBoxGetSelected(typeCombo)
        local capital = tonumber(guiGetText(capitalEdit)) or 50000
        
        if not name or name == "" then
            outputChatBox("Enter a company name", 255, 100, 100)
            return
        end
        
        local types = {"resource", "manufacturing", "retail", "tech"}
        local companyType = types[typeIdx + 1]
        
        triggerServerEvent("economy:dmCreateNPCCompany", localPlayer, name, companyType, capital)
        destroyElement(npcCreatorWindow)
        npcCreatorWindow = nil
    end, false)
    
    addEventHandler("onClientGUIClick", cancelBtn, function()
        destroyElement(npcCreatorWindow)
        npcCreatorWindow = nil
    end, false)
end

local companyCreatorWindow = nil

function openCompanyCreatorGUI()
    if companyCreatorWindow then destroyElement(companyCreatorWindow) end
    
    local w, h = 400, 300
    companyCreatorWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "Create Company", false)
    guiWindowSetSizable(companyCreatorWindow, false)
    
    local y = 30
    
    guiCreateLabel(15, y, 370, 40, "Starting a company costs $50,000 which will be\ndeducted from your character's money.", false, companyCreatorWindow)
    y = y + 50
    
    guiCreateLabel(15, y, 100, 20, "Company Name:", false, companyCreatorWindow)
    local nameEdit = guiCreateEdit(120, y - 2, 260, 25, "", false, companyCreatorWindow)
    y = y + 40
    
    guiCreateLabel(15, y, 100, 20, "Company Type:", false, companyCreatorWindow)
    local typeCombo = guiCreateComboBox(120, y - 2, 200, 150, "", false, companyCreatorWindow)
    guiComboBoxAddItem(typeCombo, "Resource (extract materials)")
    guiComboBoxAddItem(typeCombo, "Manufacturing (process items)")
    guiComboBoxAddItem(typeCombo, "Retail (sell to market)")
    guiComboBoxAddItem(typeCombo, "Tech (generate points)")
    guiComboBoxSetSelected(typeCombo, 0)
    y = y + 60
    
    local createBtn = guiCreateButton(15, y, 175, 40, "Create Company", false, companyCreatorWindow)
    guiSetProperty(createBtn, "NormalTextColour", "FF66FF66")
    
    local cancelBtn = guiCreateButton(210, y, 175, 40, "Cancel", false, companyCreatorWindow)
    
    addEventHandler("onClientGUIClick", createBtn, function()
        local name = guiGetText(nameEdit)
        local typeIdx = guiComboBoxGetSelected(typeCombo)
        
        if not name or name == "" then
            outputChatBox("Enter a company name", 255, 100, 100)
            return
        end
        
        local types = {"resource", "manufacturing", "retail", "tech"}
        local companyType = types[typeIdx + 1]
        
        triggerServerEvent("economy:createPlayerCompany", localPlayer, name, companyType)
        destroyElement(companyCreatorWindow)
        companyCreatorWindow = nil
        showCursor(false)
    end, false)
    
    addEventHandler("onClientGUIClick", cancelBtn, function()
        destroyElement(companyCreatorWindow)
        companyCreatorWindow = nil
        showCursor(false)
    end, false)
    
    showCursor(true)
end

local hireDialogWindow = nil

function openHireDialogGUI(companyID)
    if hireDialogWindow then destroyElement(hireDialogWindow) end
    
    local w, h = 350, 260
    hireDialogWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "Hire NPC Employee", false)
    guiWindowSetSizable(hireDialogWindow, false)
    
    local y = 30
    
    guiCreateLabel(15, y, 100, 20, "Type:", false, hireDialogWindow)
    local typeCombo = guiCreateComboBox(120, y - 2, 200, 150, "", false, hireDialogWindow)
    guiComboBoxAddItem(typeCombo, "Unskilled ($100+)")
    guiComboBoxAddItem(typeCombo, "Skilled ($250+)")
    guiComboBoxAddItem(typeCombo, "Professional ($500+)")
    guiComboBoxSetSelected(typeCombo, 0)
    y = y + 35
    
    guiCreateLabel(15, y, 100, 20, "Assignment:", false, hireDialogWindow)
    local allocCombo = guiCreateComboBox(120, y - 2, 200, 150, "", false, hireDialogWindow)
    guiComboBoxAddItem(allocCombo, "Items (production)")
    guiComboBoxAddItem(allocCombo, "Logistics")
    guiComboBoxSetSelected(allocCombo, 0)
    y = y + 35
    
    addEventHandler("onClientGUIComboBoxAccepted", typeCombo, function()
        local idx = guiComboBoxGetSelected(typeCombo)
        guiComboBoxClear(allocCombo)
        if idx == 2 then
            guiComboBoxAddItem(allocCombo, "Efficiency")
            guiComboBoxAddItem(allocCombo, "Innovation")
        else
            guiComboBoxAddItem(allocCombo, "Items (production)")
            guiComboBoxAddItem(allocCombo, "Logistics")
        end
        guiComboBoxSetSelected(allocCombo, 0)
    end, false)
    
    guiCreateLabel(15, y, 100, 20, "Wage:", false, hireDialogWindow)
    local wageEdit = guiCreateEdit(120, y - 2, 100, 25, "100", false, hireDialogWindow)
    y = y + 50
    
    local hireBtn = guiCreateButton(15, y, 150, 35, "Hire", false, hireDialogWindow)
    guiSetProperty(hireBtn, "NormalTextColour", "FF66FF66")
    local cancelBtn = guiCreateButton(185, y, 150, 35, "Cancel", false, hireDialogWindow)
    
    addEventHandler("onClientGUIClick", hireBtn, function()
        local typeIdx = guiComboBoxGetSelected(typeCombo)
        local allocIdx = guiComboBoxGetSelected(allocCombo)
        local wage = tonumber(guiGetText(wageEdit))
        
        if not wage or wage < 1 then
            outputChatBox("Invalid wage", 255, 100, 100)
            return
        end
        
        local empTypes = {"unskilled", "skilled", "professional"}
        local allocations = (typeIdx == 2) and {"efficiency", "innovation"} or {"items", "logistics"}
        
        triggerServerEvent("economy:hireNPC", localPlayer, companyID, empTypes[typeIdx + 1], wage, allocations[allocIdx + 1])
        destroyElement(hireDialogWindow)
        hireDialogWindow = nil
    end, false)
    
    addEventHandler("onClientGUIClick", cancelBtn, function()
        destroyElement(hireDialogWindow)
        hireDialogWindow = nil
    end, false)
end

function openDeleteConfirmation(companyID, companyName)
    local w, h = 320, 150
    local confirmWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "Confirm Delete", false)
    guiWindowSetSizable(confirmWindow, false)
    
    guiCreateLabel(15, 30, 290, 40, "Delete " .. companyName .. "?\nAll assets return to market.", false, confirmWindow)
    
    local yesBtn = guiCreateButton(15, 90, 135, 35, "Yes, Delete", false, confirmWindow)
    local noBtn = guiCreateButton(170, 90, 135, 35, "Cancel", false, confirmWindow)
    guiSetProperty(yesBtn, "NormalTextColour", "FFFF6666")
    
    addEventHandler("onClientGUIClick", yesBtn, function()
        triggerServerEvent("economy:deleteCompany", localPlayer, companyID)
        destroyElement(confirmWindow)
    end, false)
    
    addEventHandler("onClientGUIClick", noBtn, function()
        destroyElement(confirmWindow)
    end, false)
end

local dealCreatorWindow = nil

function openDealCreatorGUI(companyID, otherCompanies)
    if dealCreatorWindow then destroyElement(dealCreatorWindow) end
    
    local w, h = 450, 380
    dealCreatorWindow = guiCreateWindow((screenW - w) / 2, (screenH - h) / 2, w, h, "Create Deal", false)
    guiWindowSetSizable(dealCreatorWindow, false)
    
    local y = 30
    
    guiCreateLabel(15, y, 120, 20, "Partner:", false, dealCreatorWindow)
    local partnerCombo = guiCreateComboBox(120, y - 2, 300, 200, "", false, dealCreatorWindow)
    for _, c in ipairs(otherCompanies or {}) do
        guiComboBoxAddItem(partnerCombo, c.name .. " (" .. c.type .. ")")
    end
    if #(otherCompanies or {}) > 0 then guiComboBoxSetSelected(partnerCombo, 0) end
    y = y + 35
    
    guiCreateLabel(15, y, 420, 20, "--- You Provide ---", false, dealCreatorWindow)
    y = y + 22
    guiCreateLabel(15, y, 60, 20, "Money:", false, dealCreatorWindow)
    local myMoneyEdit = guiCreateEdit(80, y - 2, 80, 22, "0", false, dealCreatorWindow)
    guiCreateLabel(175, y, 60, 20, "Effic:", false, dealCreatorWindow)
    local myEffEdit = guiCreateEdit(230, y - 2, 60, 22, "0", false, dealCreatorWindow)
    y = y + 30
    
    guiCreateLabel(15, y, 420, 20, "--- They Provide ---", false, dealCreatorWindow)
    y = y + 22
    guiCreateLabel(15, y, 60, 20, "Money:", false, dealCreatorWindow)
    local theirMoneyEdit = guiCreateEdit(80, y - 2, 80, 22, "0", false, dealCreatorWindow)
    guiCreateLabel(175, y, 60, 20, "Effic:", false, dealCreatorWindow)
    local theirEffEdit = guiCreateEdit(230, y - 2, 60, 22, "0", false, dealCreatorWindow)
    y = y + 35
    
    guiCreateLabel(15, y, 80, 20, "Duration:", false, dealCreatorWindow)
    local durCombo = guiCreateComboBox(100, y - 2, 130, 100, "", false, dealCreatorWindow)
    guiComboBoxAddItem(durCombo, "Infinite")
    guiComboBoxAddItem(durCombo, "10 cycles")
    guiComboBoxAddItem(durCombo, "20 cycles")
    guiComboBoxSetSelected(durCombo, 0)
    y = y + 45
    
    local createBtn = guiCreateButton(15, y, 200, 38, "Propose Deal", false, dealCreatorWindow)
    guiSetProperty(createBtn, "NormalTextColour", "FF66FF66")
    local cancelBtn = guiCreateButton(235, y, 200, 38, "Cancel", false, dealCreatorWindow)
    
    addEventHandler("onClientGUIClick", createBtn, function()
        local pIdx = guiComboBoxGetSelected(partnerCombo)
        if pIdx < 0 or not otherCompanies or #otherCompanies == 0 then
            outputChatBox("Select a partner", 255, 100, 100)
            return
        end
        
        local partnerID = otherCompanies[pIdx + 1].id
        local myProvides = { money = tonumber(guiGetText(myMoneyEdit)) or 0, efficiency = tonumber(guiGetText(myEffEdit)) or 0, items = {} }
        local theirProvides = { money = tonumber(guiGetText(theirMoneyEdit)) or 0, efficiency = tonumber(guiGetText(theirEffEdit)) or 0, items = {} }
        local durIdx = guiComboBoxGetSelected(durCombo)
        local durations = {"infinite", 10, 20}
        
        triggerServerEvent("economy:createDeal", localPlayer, companyID, partnerID, myProvides, theirProvides, durations[durIdx + 1])
        destroyElement(dealCreatorWindow)
        dealCreatorWindow = nil
    end, false)
    
    addEventHandler("onClientGUIClick", cancelBtn, function()
        destroyElement(dealCreatorWindow)
        dealCreatorWindow = nil
    end, false)
end

--------------------------------------------------------------------------------
-- SERVER EVENTS
--------------------------------------------------------------------------------

addEvent("economy:playerCompanies", true)
addEventHandler("economy:playerCompanies", root, function(companies)
    buildPlayerEconomyWindow(companies)
end)

addEvent("economy:dmEconomyData", true)
addEventHandler("economy:dmEconomyData", root, function(companies, markets)
    buildDMEconomyWindow(companies, markets)
end)

addEvent("economy:companyData", true)
addEventHandler("economy:companyData", root, function(companyData)
    selectedCompanyData = companyData
    currentTab = "dashboard"
    updateTabContent()
end)

addEvent("economy:cycleComplete", true)
addEventHandler("economy:cycleComplete", root, function(cycleNum)
    outputChatBox("[Economy] Cycle " .. cycleNum .. " complete!", 255, 200, 100)
    if economyWindow and selectedCompanyData then
        triggerServerEvent("economy:requestCompanyData", localPlayer, selectedCompanyData.id)
    end
end)

addEvent("economy:message", true)
addEventHandler("economy:message", root, function(message, isError)
    local r, g, b = 100, 255, 100
    if isError then r, g, b = 255, 100, 100 end
    outputChatBox("[Economy] " .. message, r, g, b)
    -- Refresh company data
    if selectedCompanyData then
        triggerServerEvent("economy:requestCompanyData", localPlayer, selectedCompanyData.id)
    end
    -- Refresh DM view if applicable
    if isDMView then
        triggerServerEvent("economy:requestDMData", localPlayer)
    end
end)

addEvent("economy:showDealCreator", true)
addEventHandler("economy:showDealCreator", root, function(companyID, otherCompanies)
    openDealCreatorGUI(companyID, otherCompanies)
end)

addEvent("economy:jobOffer", true)
addEventHandler("economy:jobOffer", root, function(offerData)
    outputChatBox("=== Job Offer ===", 255, 255, 0)
    outputChatBox("Company: " .. offerData.companyName, 200, 200, 200)
    outputChatBox("Position: " .. offerData.employeeType .. " | Wage: $" .. offerData.wage .. "/cycle", 200, 200, 200)
    outputChatBox("Type /acceptjob or /declinejob", 255, 255, 0)
    setElementData(localPlayer, "pendingJobOffer", offerData)
end)

--------------------------------------------------------------------------------
-- COMMANDS & KEYBINDS
--------------------------------------------------------------------------------

local function openEconomyWindow()
    if economyWindow then
        closeEconomyWindow()
        return
    end
    
    -- DMs get the full management interface
    if isPlayerDM() then
        triggerServerEvent("economy:requestDMData", localPlayer)
    else
        triggerServerEvent("economy:requestPlayerCompanies", localPlayer)
    end
end

bindKey("F6", "down", openEconomyWindow)
addCommandHandler("company", openEconomyWindow)

addCommandHandler("acceptjob", function()
    local offer = getElementData(localPlayer, "pendingJobOffer")
    if offer then
        triggerServerEvent("economy:acceptJob", localPlayer, offer)
        setElementData(localPlayer, "pendingJobOffer", nil)
    else outputChatBox("No pending job offer", 255, 100, 100) end
end)

addCommandHandler("declinejob", function()
    if getElementData(localPlayer, "pendingJobOffer") then
        outputChatBox("Job offer declined", 255, 255, 0)
        setElementData(localPlayer, "pendingJobOffer", nil)
    else outputChatBox("No pending job offer", 255, 100, 100) end
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeEconomyWindow()
    if npcCreatorWindow then destroyElement(npcCreatorWindow) end
    if companyCreatorWindow then destroyElement(companyCreatorWindow) end
    if hireDialogWindow then destroyElement(hireDialogWindow) end
    if dealCreatorWindow then destroyElement(dealCreatorWindow) end
end)

outputChatBox("Economy system loaded. Press F6 for company management.", 200, 200, 200)
