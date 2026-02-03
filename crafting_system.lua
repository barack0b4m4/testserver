-- crafting_system.lua (SERVER)
-- Crafting system with recipes, material requirements, and tool requirements
-- Integrates with inventory_system.lua

outputServerLog("===== CRAFTING_SYSTEM.LUA LOADING =====")

local db = nil

-- Global recipes cache
CraftingRecipes = CraftingRecipes or {}

--------------------------------------------------------------------------------
-- DATABASE INITIALIZATION
--------------------------------------------------------------------------------

local function initializeCraftingTables()
    if not db then return end
    
    -- Add craftable column to item_definitions if it doesn't exist
    -- We check if column exists first to avoid errors
    local checkQuery = dbQuery(db, "PRAGMA table_info(item_definitions)")
    local columns = dbPoll(checkQuery, -1)
    
    local hasCraftable = false
    if columns then
        for _, col in ipairs(columns) do
            if col.name == "craftable" then
                hasCraftable = true
                break
            end
        end
    end
    
    if not hasCraftable then
        dbExec(db, "ALTER TABLE item_definitions ADD COLUMN craftable INTEGER DEFAULT 0")
        outputServerLog("Added craftable column to item_definitions")
    end
    
    -- Recipes table - stores what item is crafted and requirements
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS crafting_recipes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            result_item_id TEXT NOT NULL,
            result_quantity INTEGER DEFAULT 1,
            required_tool_id TEXT DEFAULT NULL,
            crafting_time INTEGER DEFAULT 0,
            required_skill TEXT DEFAULT NULL,
            required_skill_level INTEGER DEFAULT 0,
            created_by TEXT,
            created_date INTEGER,
            UNIQUE(result_item_id)
        )
    ]])
    
    -- Recipe ingredients table - materials needed for each recipe
    dbExec(db, [[
        CREATE TABLE IF NOT EXISTS recipe_ingredients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recipe_id INTEGER NOT NULL,
            material_item_id TEXT NOT NULL,
            quantity INTEGER DEFAULT 1,
            FOREIGN KEY (recipe_id) REFERENCES crafting_recipes(id),
            UNIQUE(recipe_id, material_item_id)
        )
    ]])
    
    outputServerLog("Crafting database tables initialized")
end

addEventHandler("onResourceStart", resourceRoot, function()
    db = database
    if not db then
        outputServerLog("ERROR: Could not access database for crafting system")
        return
    end
    
    outputServerLog("Crafting system connected to database")
    initializeCraftingTables()
    loadAllRecipes()
end)

--------------------------------------------------------------------------------
-- RECIPE MANAGEMENT
--------------------------------------------------------------------------------

function loadAllRecipes()
    if not db then return end
    
    local query = dbQuery(db, "SELECT * FROM crafting_recipes")
    local result = dbPoll(query, -1)
    
    if not result then return end
    
    for _, row in ipairs(result) do
        local recipe = {
            id = row.id,
            resultItemID = row.result_item_id,
            resultQuantity = row.result_quantity or 1,
            requiredToolID = row.required_tool_id,
            craftingTime = row.crafting_time or 0,
            requiredSkill = row.required_skill,
            requiredSkillLevel = row.required_skill_level or 0,
            ingredients = {},
            createdBy = row.created_by,
            createdDate = row.created_date
        }
        
        -- Load ingredients for this recipe
        local ingQuery = dbQuery(db, "SELECT * FROM recipe_ingredients WHERE recipe_id = ?", row.id)
        local ingResult = dbPoll(ingQuery, -1)
        
        if ingResult then
            for _, ing in ipairs(ingResult) do
                table.insert(recipe.ingredients, {
                    itemID = ing.material_item_id,
                    quantity = ing.quantity
                })
            end
        end
        
        CraftingRecipes[recipe.resultItemID] = recipe
    end
    
    outputServerLog("Loaded " .. #result .. " crafting recipes")
end

function createRecipe(resultItemID, resultQuantity, ingredients, requiredToolID, craftingTime, createdBy)
    if not db then return false, "Database not available" end
    
    -- Verify result item exists
    if not ItemRegistry or not ItemRegistry:exists(resultItemID) then
        return false, "Result item does not exist: " .. resultItemID
    end
    
    -- Verify all ingredients exist
    for _, ing in ipairs(ingredients) do
        if not ItemRegistry:exists(ing.itemID) then
            return false, "Ingredient does not exist: " .. ing.itemID
        end
        if not ing.quantity or ing.quantity < 1 then
            return false, "Invalid quantity for: " .. ing.itemID
        end
    end
    
    -- Verify tool exists if specified
    if requiredToolID and requiredToolID ~= "" then
        if not ItemRegistry:exists(requiredToolID) then
            return false, "Required tool does not exist: " .. requiredToolID
        end
    else
        requiredToolID = nil
    end
    
    -- Check if recipe already exists
    if CraftingRecipes[resultItemID] then
        return false, "Recipe already exists for: " .. resultItemID
    end
    
    resultQuantity = resultQuantity or 1
    craftingTime = craftingTime or 0
    
    -- Insert recipe
    local success = dbExec(db, [[
        INSERT INTO crafting_recipes (result_item_id, result_quantity, required_tool_id, crafting_time, created_by, created_date)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], resultItemID, resultQuantity, requiredToolID, craftingTime, createdBy, getRealTime().timestamp)
    
    if not success then return false, "Database error creating recipe" end
    
    -- Get the recipe ID
    local idQuery = dbQuery(db, "SELECT last_insert_rowid() AS id")
    local idResult = dbPoll(idQuery, -1)
    if not idResult or not idResult[1] then return false, "Failed to get recipe ID" end
    
    local recipeID = idResult[1].id
    
    -- Insert ingredients
    for _, ing in ipairs(ingredients) do
        dbExec(db, [[
            INSERT INTO recipe_ingredients (recipe_id, material_item_id, quantity)
            VALUES (?, ?, ?)
        ]], recipeID, ing.itemID, ing.quantity)
    end
    
    -- Mark item as craftable
    dbExec(db, "UPDATE item_definitions SET craftable = 1 WHERE id = ?", resultItemID)
    if ItemRegistry and ItemRegistry.items[resultItemID] then
        ItemRegistry.items[resultItemID].craftable = true
    end
    
    -- Cache recipe
    CraftingRecipes[resultItemID] = {
        id = recipeID,
        resultItemID = resultItemID,
        resultQuantity = resultQuantity,
        requiredToolID = requiredToolID,
        craftingTime = craftingTime,
        ingredients = ingredients,
        createdBy = createdBy,
        createdDate = getRealTime().timestamp
    }
    
    local itemName = ItemRegistry:get(resultItemID).name
    outputServerLog("Recipe created for: " .. itemName .. " (" .. resultItemID .. ")")
    
    return true, "Recipe created for: " .. itemName
end

function deleteRecipe(resultItemID)
    if not db then return false, "Database not available" end
    
    local recipe = CraftingRecipes[resultItemID]
    if not recipe then return false, "Recipe not found" end
    
    -- Delete ingredients first
    dbExec(db, "DELETE FROM recipe_ingredients WHERE recipe_id = ?", recipe.id)
    
    -- Delete recipe
    dbExec(db, "DELETE FROM crafting_recipes WHERE id = ?", recipe.id)
    
    -- Mark item as not craftable
    dbExec(db, "UPDATE item_definitions SET craftable = 0 WHERE id = ?", resultItemID)
    if ItemRegistry and ItemRegistry.items[resultItemID] then
        ItemRegistry.items[resultItemID].craftable = false
    end
    
    CraftingRecipes[resultItemID] = nil
    
    outputServerLog("Recipe deleted for: " .. resultItemID)
    return true, "Recipe deleted"
end

function updateRecipeIngredients(resultItemID, ingredients)
    if not db then return false, "Database not available" end
    
    local recipe = CraftingRecipes[resultItemID]
    if not recipe then return false, "Recipe not found" end
    
    -- Verify all new ingredients exist
    for _, ing in ipairs(ingredients) do
        if not ItemRegistry:exists(ing.itemID) then
            return false, "Ingredient does not exist: " .. ing.itemID
        end
    end
    
    -- Delete old ingredients
    dbExec(db, "DELETE FROM recipe_ingredients WHERE recipe_id = ?", recipe.id)
    
    -- Insert new ingredients
    for _, ing in ipairs(ingredients) do
        dbExec(db, [[
            INSERT INTO recipe_ingredients (recipe_id, material_item_id, quantity)
            VALUES (?, ?, ?)
        ]], recipe.id, ing.itemID, ing.quantity)
    end
    
    recipe.ingredients = ingredients
    
    return true, "Recipe ingredients updated"
end

function setRecipeTool(resultItemID, toolItemID)
    if not db then return false, "Database not available" end
    
    local recipe = CraftingRecipes[resultItemID]
    if not recipe then return false, "Recipe not found" end
    
    if toolItemID and toolItemID ~= "" and not ItemRegistry:exists(toolItemID) then
        return false, "Tool does not exist: " .. toolItemID
    end
    
    if toolItemID == "" then toolItemID = nil end
    
    dbExec(db, "UPDATE crafting_recipes SET required_tool_id = ? WHERE id = ?", toolItemID, recipe.id)
    recipe.requiredToolID = toolItemID
    
    return true, "Recipe tool updated"
end

function getRecipe(resultItemID)
    return CraftingRecipes[resultItemID]
end

function getRecipeForClient(resultItemID)
    local recipe = CraftingRecipes[resultItemID]
    if not recipe then return nil end
    
    local data = {
        resultItemID = recipe.resultItemID,
        resultQuantity = recipe.resultQuantity,
        requiredToolID = recipe.requiredToolID,
        craftingTime = recipe.craftingTime,
        ingredients = {}
    }
    
    -- Get result item info
    local resultItem = ItemRegistry:get(recipe.resultItemID)
    if resultItem then
        data.resultName = resultItem.name
        data.resultQuality = resultItem.quality.name
    end
    
    -- Get tool info
    if recipe.requiredToolID then
        local toolItem = ItemRegistry:get(recipe.requiredToolID)
        if toolItem then
            data.requiredToolName = toolItem.name
        end
    end
    
    -- Get ingredient info
    for _, ing in ipairs(recipe.ingredients) do
        local ingItem = ItemRegistry:get(ing.itemID)
        if ingItem then
            table.insert(data.ingredients, {
                itemID = ing.itemID,
                name = ingItem.name,
                quantity = ing.quantity,
                category = ingItem.category,
                quality = ingItem.quality.name
            })
        end
    end
    
    return data
end

function getAllRecipesForClient()
    local recipes = {}
    
    for resultItemID, recipe in pairs(CraftingRecipes) do
        local data = getRecipeForClient(resultItemID)
        if data then
            table.insert(recipes, data)
        end
    end
    
    -- Sort by result name
    table.sort(recipes, function(a, b) return a.resultName < b.resultName end)
    
    return recipes
end

--------------------------------------------------------------------------------
-- CRAFTING SYSTEM
--------------------------------------------------------------------------------

function canPlayerCraft(player, resultItemID)
    local recipe = CraftingRecipes[resultItemID]
    if not recipe then return false, "No recipe exists for this item" end
    
    local inv = getPlayerInventory(player)
    if not inv then return false, "No inventory" end
    
    -- Check for required tool
    if recipe.requiredToolID then
        local hasTool = false
        for _, item in ipairs(inv.items) do
            if item.id == recipe.requiredToolID then
                hasTool = true
                break
            end
        end
        if not hasTool then
            local toolName = recipe.requiredToolID
            if ItemRegistry:exists(recipe.requiredToolID) then
                toolName = ItemRegistry:get(recipe.requiredToolID).name
            end
            return false, "Requires tool: " .. toolName
        end
    end
    
    -- Check for all ingredients
    local missingIngredients = {}
    for _, ing in ipairs(recipe.ingredients) do
        local hasQuantity = 0
        for _, item in ipairs(inv.items) do
            if item.id == ing.itemID then
                hasQuantity = hasQuantity + (item.quantity or 1)
            end
        end
        
        if hasQuantity < ing.quantity then
            local ingName = ing.itemID
            if ItemRegistry:exists(ing.itemID) then
                ingName = ItemRegistry:get(ing.itemID).name
            end
            table.insert(missingIngredients, {
                name = ingName,
                have = hasQuantity,
                need = ing.quantity
            })
        end
    end
    
    if #missingIngredients > 0 then
        local msg = "Missing materials: "
        for i, missing in ipairs(missingIngredients) do
            if i > 1 then msg = msg .. ", " end
            msg = msg .. missing.name .. " (" .. missing.have .. "/" .. missing.need .. ")"
        end
        return false, msg
    end
    
    -- Check inventory space for result
    local resultItem = ItemRegistry:get(recipe.resultItemID)
    if resultItem then
        local resultWeight = (resultItem.weight or 1) * recipe.resultQuantity
        -- Calculate weight that will be freed by consuming materials
        local freedWeight = 0
        for _, ing in ipairs(recipe.ingredients) do
            local ingItem = ItemRegistry:get(ing.itemID)
            if ingItem then
                freedWeight = freedWeight + ((ingItem.weight or 1) * ing.quantity)
            end
        end
        
        local netWeight = resultWeight - freedWeight
        if netWeight > 0 and inv:getCurrentWeight() + netWeight > inv.maxWeight then
            return false, "Not enough inventory space"
        end
    end
    
    return true, "Can craft"
end

function craftItem(player, resultItemID, quantity)
    quantity = quantity or 1
    
    local recipe = CraftingRecipes[resultItemID]
    if not recipe then return false, "No recipe exists for this item" end
    
    local inv = getPlayerInventory(player)
    if not inv then return false, "No inventory" end
    
    -- Verify player can craft (checks tool and materials)
    local canCraft, reason = canPlayerCraft(player, resultItemID)
    if not canCraft then
        return false, reason
    end
    
    -- For multiple crafts, check if we have enough materials for all
    for _, ing in ipairs(recipe.ingredients) do
        local hasQuantity = 0
        for _, item in ipairs(inv.items) do
            if item.id == ing.itemID then
                hasQuantity = hasQuantity + (item.quantity or 1)
            end
        end
        
        local totalNeeded = ing.quantity * quantity
        if hasQuantity < totalNeeded then
            local ingName = ItemRegistry:get(ing.itemID).name
            return false, "Not enough " .. ingName .. " for " .. quantity .. "x craft"
        end
    end
    
    -- Remove ingredients from inventory
    for _, ing in ipairs(recipe.ingredients) do
        local toRemove = ing.quantity * quantity
        
        -- Find and remove from inventory items
        for i = #inv.items, 1, -1 do
            if toRemove <= 0 then break end
            
            local item = inv.items[i]
            if item.id == ing.itemID then
                local removeFromThis = math.min(item.quantity or 1, toRemove)
                
                if removeFromThis >= (item.quantity or 1) then
                    -- Remove entire stack
                    inv:removeItem(item.instanceID, item.quantity or 1)
                else
                    -- Remove partial
                    inv:removeItem(item.instanceID, removeFromThis)
                end
                
                toRemove = toRemove - removeFromThis
            end
        end
    end
    
    -- Add crafted item(s) to inventory
    local totalResult = recipe.resultQuantity * quantity
    local success, msg = inv:addItem(recipe.resultItemID, totalResult)
    
    if not success then
        -- This shouldn't happen if we checked properly, but handle it
        return false, "Failed to add crafted item: " .. msg
    end
    
    -- Get item name for message
    local resultItem = ItemRegistry:get(recipe.resultItemID)
    local itemName = resultItem and resultItem.name or recipe.resultItemID
    local charName = getElementData(player, "character.name") or getPlayerName(player)
    
    outputServerLog("Crafted: " .. charName .. " crafted " .. totalResult .. "x " .. itemName)
    
    return true, "Crafted " .. totalResult .. "x " .. itemName
end

--------------------------------------------------------------------------------
-- CLIENT EVENTS
--------------------------------------------------------------------------------

-- Player requests crafting menu
addEvent("crafting:requestMenu", true)
addEventHandler("crafting:requestMenu", root, function()
    local player = client
    local recipes = getAllRecipesForClient()
    triggerClientEvent(player, "crafting:openMenu", player, recipes)
end)

-- Player requests recipe details
addEvent("crafting:requestRecipe", true)
addEventHandler("crafting:requestRecipe", root, function(resultItemID)
    local player = client
    local recipeData = getRecipeForClient(resultItemID)
    
    if recipeData then
        -- Add player-specific info (can they craft it?)
        local canCraft, reason = canPlayerCraft(player, resultItemID)
        recipeData.canCraft = canCraft
        recipeData.craftReason = reason
        
        -- Check how many they have of each ingredient
        local inv = getPlayerInventory(player)
        if inv then
            for _, ing in ipairs(recipeData.ingredients) do
                local hasQuantity = 0
                for _, item in ipairs(inv.items) do
                    if item.id == ing.itemID then
                        hasQuantity = hasQuantity + (item.quantity or 1)
                    end
                end
                ing.playerHas = hasQuantity
            end
            
            -- Check if player has required tool
            if recipeData.requiredToolID then
                recipeData.playerHasTool = false
                for _, item in ipairs(inv.items) do
                    if item.id == recipeData.requiredToolID then
                        recipeData.playerHasTool = true
                        break
                    end
                end
            end
        end
        
        triggerClientEvent(player, "crafting:recipeDetails", player, recipeData)
    else
        triggerClientEvent(player, "crafting:message", player, "Recipe not found", true)
    end
end)

-- Player attempts to craft
addEvent("crafting:craft", true)
addEventHandler("crafting:craft", root, function(resultItemID, quantity)
    local player = client
    quantity = tonumber(quantity) or 1
    
    local success, msg = craftItem(player, resultItemID, quantity)
    
    triggerClientEvent(player, "crafting:message", player, msg, not success)
    
    if success then
        -- Refresh the recipe details to update material counts
        local recipeData = getRecipeForClient(resultItemID)
        if recipeData then
            local canCraft, reason = canPlayerCraft(player, resultItemID)
            recipeData.canCraft = canCraft
            recipeData.craftReason = reason
            
            local inv = getPlayerInventory(player)
            if inv then
                for _, ing in ipairs(recipeData.ingredients) do
                    local hasQuantity = 0
                    for _, item in ipairs(inv.items) do
                        if item.id == ing.itemID then
                            hasQuantity = hasQuantity + (item.quantity or 1)
                        end
                    end
                    ing.playerHas = hasQuantity
                end
            end
            
            triggerClientEvent(player, "crafting:recipeDetails", player, recipeData)
        end
    end
end)

--------------------------------------------------------------------------------
-- DM COMMANDS
--------------------------------------------------------------------------------

-- Create a recipe: /createrecipe resultItemID [resultQty]
addCommandHandler("createrecipe", function(player, cmd, resultItemID, resultQty)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not resultItemID then
        outputChatBox("Usage: /createrecipe itemID [resultQuantity]", player, 255, 255, 0)
        outputChatBox("Then use /addingredient to add materials", player, 200, 200, 200)
        return
    end
    
    if not ItemRegistry or not ItemRegistry:exists(resultItemID) then
        outputChatBox("Item does not exist: " .. resultItemID, player, 255, 0, 0)
        return
    end
    
    if CraftingRecipes[resultItemID] then
        outputChatBox("Recipe already exists. Use /deleterecipe first.", player, 255, 0, 0)
        return
    end
    
    resultQty = tonumber(resultQty) or 1
    local createdBy = getElementData(player, "character.name") or getPlayerName(player)
    
    -- Create empty recipe (ingredients added separately)
    local success, msg = createRecipe(resultItemID, resultQty, {}, nil, 0, createdBy)
    
    if success then
        outputChatBox("Recipe shell created for: " .. resultItemID, player, 0, 255, 0)
        outputChatBox("Now add ingredients with: /addingredient " .. resultItemID .. " materialID quantity", player, 200, 200, 200)
        outputChatBox("Set required tool with: /setrecipetool " .. resultItemID .. " toolID", player, 200, 200, 200)
    else
        outputChatBox("Failed: " .. msg, player, 255, 0, 0)
    end
end)

-- Add ingredient to recipe: /addingredient resultItemID materialID quantity
addCommandHandler("addingredient", function(player, cmd, resultItemID, materialID, quantity)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not resultItemID or not materialID then
        outputChatBox("Usage: /addingredient recipeItemID materialItemID [quantity]", player, 255, 255, 0)
        return
    end
    
    local recipe = CraftingRecipes[resultItemID]
    if not recipe then
        outputChatBox("Recipe not found. Create it first with /createrecipe", player, 255, 0, 0)
        return
    end
    
    if not ItemRegistry:exists(materialID) then
        outputChatBox("Material item does not exist: " .. materialID, player, 255, 0, 0)
        return
    end
    
    quantity = tonumber(quantity) or 1
    
    -- Check if ingredient already exists
    for _, ing in ipairs(recipe.ingredients) do
        if ing.itemID == materialID then
            outputChatBox("Material already in recipe. Use /removeingredient first.", player, 255, 0, 0)
            return
        end
    end
    
    -- Add ingredient
    table.insert(recipe.ingredients, {itemID = materialID, quantity = quantity})
    
    dbExec(db, [[
        INSERT INTO recipe_ingredients (recipe_id, material_item_id, quantity)
        VALUES (?, ?, ?)
    ]], recipe.id, materialID, quantity)
    
    local materialName = ItemRegistry:get(materialID).name
    outputChatBox("Added ingredient: " .. quantity .. "x " .. materialName, player, 0, 255, 0)
end)

-- Remove ingredient: /removeingredient resultItemID materialID
addCommandHandler("removeingredient", function(player, cmd, resultItemID, materialID)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not resultItemID or not materialID then
        outputChatBox("Usage: /removeingredient recipeItemID materialItemID", player, 255, 255, 0)
        return
    end
    
    local recipe = CraftingRecipes[resultItemID]
    if not recipe then
        outputChatBox("Recipe not found", player, 255, 0, 0)
        return
    end
    
    for i, ing in ipairs(recipe.ingredients) do
        if ing.itemID == materialID then
            table.remove(recipe.ingredients, i)
            dbExec(db, "DELETE FROM recipe_ingredients WHERE recipe_id = ? AND material_item_id = ?",
                recipe.id, materialID)
            outputChatBox("Ingredient removed", player, 0, 255, 0)
            return
        end
    end
    
    outputChatBox("Ingredient not found in recipe", player, 255, 0, 0)
end)

-- Set required tool: /setrecipetool resultItemID toolID
addCommandHandler("setrecipetool", function(player, cmd, resultItemID, toolID)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not resultItemID then
        outputChatBox("Usage: /setrecipetool recipeItemID [toolItemID]", player, 255, 255, 0)
        outputChatBox("Leave toolItemID blank to remove tool requirement", player, 200, 200, 200)
        return
    end
    
    local success, msg = setRecipeTool(resultItemID, toolID or "")
    outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
end)

-- Delete recipe: /deleterecipe resultItemID
addCommandHandler("deleterecipe", function(player, cmd, resultItemID)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    if not resultItemID then
        outputChatBox("Usage: /deleterecipe itemID", player, 255, 255, 0)
        return
    end
    
    local success, msg = deleteRecipe(resultItemID)
    outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
end)

-- List all recipes: /listrecipes [search]
addCommandHandler("listrecipes", function(player, cmd, search)
    outputChatBox("=== Crafting Recipes ===", player, 255, 255, 0)
    
    local count = 0
    for resultItemID, recipe in pairs(CraftingRecipes) do
        local item = ItemRegistry:get(resultItemID)
        local name = item and item.name or resultItemID
        
        if not search or name:lower():find(search:lower(), 1, true) or resultItemID:lower():find(search:lower(), 1, true) then
            local ingCount = #recipe.ingredients
            local toolInfo = recipe.requiredToolID and " [Tool: " .. recipe.requiredToolID .. "]" or ""
            
            outputChatBox(string.format("%s (%s) - %d ingredients%s",
                name, resultItemID, ingCount, toolInfo), player, 200, 200, 200)
            count = count + 1
        end
    end
    
    if count == 0 then
        outputChatBox("No recipes found", player, 200, 200, 200)
    else
        outputChatBox("Total: " .. count .. " recipes", player, 255, 255, 0)
    end
end)

-- View recipe details: /recipeinfo resultItemID
addCommandHandler("recipeinfo", function(player, cmd, resultItemID)
    if not resultItemID then
        outputChatBox("Usage: /recipeinfo itemID", player, 255, 255, 0)
        return
    end
    
    local recipe = CraftingRecipes[resultItemID]
    if not recipe then
        outputChatBox("Recipe not found", player, 255, 0, 0)
        return
    end
    
    local resultItem = ItemRegistry:get(resultItemID)
    local resultName = resultItem and resultItem.name or resultItemID
    
    outputChatBox("=== Recipe: " .. resultName .. " ===", player, 255, 255, 0)
    outputChatBox("Result: " .. recipe.resultQuantity .. "x " .. resultName, player, 200, 200, 200)
    
    if recipe.requiredToolID then
        local toolItem = ItemRegistry:get(recipe.requiredToolID)
        local toolName = toolItem and toolItem.name or recipe.requiredToolID
        outputChatBox("Required Tool: " .. toolName, player, 255, 200, 100)
    end
    
    outputChatBox("Ingredients:", player, 200, 200, 200)
    for _, ing in ipairs(recipe.ingredients) do
        local ingItem = ItemRegistry:get(ing.itemID)
        local ingName = ingItem and ingItem.name or ing.itemID
        outputChatBox("  - " .. ing.quantity .. "x " .. ingName .. " (" .. ing.itemID .. ")", player, 180, 180, 180)
    end
end)

--------------------------------------------------------------------------------
-- PLAYER COMMANDS
--------------------------------------------------------------------------------

-- Open crafting menu: /craft
addCommandHandler("craft", function(player, cmd, itemID, quantity)
    local char = AccountManager and AccountManager:getActiveCharacter(player)
    if not char then
        outputChatBox("You must have an active character", player, 255, 0, 0)
        return
    end
    
    -- If item specified, try to craft directly
    if itemID then
        quantity = tonumber(quantity) or 1
        local success, msg = craftItem(player, itemID, quantity)
        outputChatBox(msg, player, success and 0 or 255, success and 255 or 0, 0)
        return
    end
    
    -- Otherwise open crafting GUI
    triggerClientEvent(player, "crafting:openMenu", player, getAllRecipesForClient())
end)

-- List what player can craft: /craftable
addCommandHandler("craftable", function(player)
    local char = AccountManager and AccountManager:getActiveCharacter(player)
    if not char then
        outputChatBox("You must have an active character", player, 255, 0, 0)
        return
    end
    
    outputChatBox("=== Items You Can Craft ===", player, 255, 255, 0)
    
    local count = 0
    for resultItemID, recipe in pairs(CraftingRecipes) do
        local canCraft, _ = canPlayerCraft(player, resultItemID)
        if canCraft then
            local item = ItemRegistry:get(resultItemID)
            local name = item and item.name or resultItemID
            outputChatBox("- " .. name .. " (/craft " .. resultItemID .. ")", player, 0, 255, 0)
            count = count + 1
        end
    end
    
    if count == 0 then
        outputChatBox("You don't have materials to craft anything", player, 200, 200, 200)
    end
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onResourceStop", resourceRoot, function()
    CraftingRecipes = {}
end)

--------------------------------------------------------------------------------
-- DM RECIPE EDITOR GUI EVENTS
--------------------------------------------------------------------------------

-- Get all items for the editor dropdowns
function getAllItemsForEditor()
    local items = {}
    
    if ItemRegistry and ItemRegistry.items then
        for id, item in pairs(ItemRegistry.items) do
            table.insert(items, {
                id = id,
                name = item.name,
                category = item.category,
                quality = item.quality and item.quality.name or "Common"
            })
        end
    end
    
    -- Sort by name
    table.sort(items, function(a, b) return a.name < b.name end)
    
    return items
end

-- DM opens recipe editor GUI
addCommandHandler("recipegui", function(player)
    if not isDungeonMaster or not isDungeonMaster(player) then
        outputChatBox("You must be a Dungeon Master", player, 255, 0, 0)
        return
    end
    
    local recipes = getAllRecipesForClient()
    local items = getAllItemsForEditor()
    
    triggerClientEvent(player, "recipe:openEditor", player, recipes, items)
end)

-- DM requests recipe data for editing
addEvent("recipe:requestEdit", true)
addEventHandler("recipe:requestEdit", root, function(resultItemID)
    local player = client
    
    if not isDungeonMaster or not isDungeonMaster(player) then
        triggerClientEvent(player, "recipe:message", player, "DM required", true)
        return
    end
    
    local recipeData = getRecipeForClient(resultItemID)
    if recipeData then
        triggerClientEvent(player, "recipe:editData", player, recipeData)
    else
        triggerClientEvent(player, "recipe:message", player, "Recipe not found", true)
    end
end)

-- DM creates new recipe via GUI
addEvent("recipe:create", true)
addEventHandler("recipe:create", root, function(resultItemID, resultQty, ingredients, toolID)
    local player = client
    
    if not isDungeonMaster or not isDungeonMaster(player) then
        triggerClientEvent(player, "recipe:saved", player, false, "DM required")
        return
    end
    
    -- Check if recipe already exists
    if CraftingRecipes[resultItemID] then
        triggerClientEvent(player, "recipe:saved", player, false, "Recipe already exists for this item")
        return
    end
    
    local createdBy = getElementData(player, "character.name") or getPlayerName(player)
    
    local success, msg = createRecipe(resultItemID, resultQty, ingredients, toolID, 0, createdBy)
    
    if success then
        local recipes = getAllRecipesForClient()
        triggerClientEvent(player, "recipe:saved", player, true, msg, recipes)
        outputServerLog("Recipe created via GUI: " .. resultItemID .. " by " .. createdBy)
    else
        triggerClientEvent(player, "recipe:saved", player, false, msg)
    end
end)

-- DM updates existing recipe via GUI
addEvent("recipe:update", true)
addEventHandler("recipe:update", root, function(resultItemID, resultQty, ingredients, toolID)
    local player = client
    
    if not isDungeonMaster or not isDungeonMaster(player) then
        triggerClientEvent(player, "recipe:saved", player, false, "DM required")
        return
    end
    
    local recipe = CraftingRecipes[resultItemID]
    if not recipe then
        triggerClientEvent(player, "recipe:saved", player, false, "Recipe not found")
        return
    end
    
    -- Update result quantity
    recipe.resultQuantity = resultQty
    dbExec(db, "UPDATE crafting_recipes SET result_quantity = ? WHERE id = ?", resultQty, recipe.id)
    
    -- Update tool
    recipe.requiredToolID = (toolID and toolID ~= "") and toolID or nil
    dbExec(db, "UPDATE crafting_recipes SET required_tool_id = ? WHERE id = ?", recipe.requiredToolID, recipe.id)
    
    -- Update ingredients - delete all and re-add
    dbExec(db, "DELETE FROM recipe_ingredients WHERE recipe_id = ?", recipe.id)
    recipe.ingredients = {}
    
    for _, ing in ipairs(ingredients) do
        table.insert(recipe.ingredients, {itemID = ing.itemID, quantity = ing.quantity})
        dbExec(db, "INSERT INTO recipe_ingredients (recipe_id, material_item_id, quantity) VALUES (?, ?, ?)",
            recipe.id, ing.itemID, ing.quantity)
    end
    
    local recipes = getAllRecipesForClient()
    local itemName = ItemRegistry:get(resultItemID) and ItemRegistry:get(resultItemID).name or resultItemID
    triggerClientEvent(player, "recipe:saved", player, true, "Recipe updated: " .. itemName, recipes)
    
    local editorName = getElementData(player, "character.name") or getPlayerName(player)
    outputServerLog("Recipe updated via GUI: " .. resultItemID .. " by " .. editorName)
end)

-- DM deletes recipe via GUI
addEvent("recipe:delete", true)
addEventHandler("recipe:delete", root, function(resultItemID)
    local player = client
    
    if not isDungeonMaster or not isDungeonMaster(player) then
        triggerClientEvent(player, "recipe:deleted", player, false, "DM required")
        return
    end
    
    local success, msg = deleteRecipe(resultItemID)
    
    if success then
        local recipes = getAllRecipesForClient()
        triggerClientEvent(player, "recipe:deleted", player, true, msg, recipes)
        
        local editorName = getElementData(player, "character.name") or getPlayerName(player)
        outputServerLog("Recipe deleted via GUI: " .. resultItemID .. " by " .. editorName)
    else
        triggerClientEvent(player, "recipe:deleted", player, false, msg)
    end
end)

outputServerLog("===== CRAFTING_SYSTEM.LUA LOADED =====")
