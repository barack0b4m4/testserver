-- client_crafting.lua (CLIENT)
-- Crafting GUI for players AND DM Recipe Editor
-- Combined into single file for easier management

local craftingWindow = nil
local editorWindow = nil
local elements = {}
local editorElements = {}
local currentRecipes = {}
local selectedRecipe = nil
local currentEditRecipe = nil
local allItems = {}
local materialItems = {}
local toolItems = {}

-- Quality colors for display
local QUALITY_COLORS = {
    Common = {200, 200, 200},
    common = {200, 200, 200},
    Uncommon = {100, 255, 100},
    uncommon = {100, 255, 100},
    Rare = {100, 100, 255},
    rare = {100, 100, 255},
    Epic = {200, 100, 255},
    epic = {200, 100, 255},
    Legendary = {255, 165, 0},
    legendary = {255, 165, 0}
}

--------------------------------------------------------------------------------
-- PLAYER CRAFTING MENU GUI
--------------------------------------------------------------------------------

function createCraftingWindow(recipes)
    if craftingWindow and isElement(craftingWindow) then
        destroyElement(craftingWindow)
    end
    
    currentRecipes = recipes or {}
    selectedRecipe = nil
    
    local sw, sh = guiGetScreenSize()
    local w, h = 700, 500
    
    craftingWindow = guiCreateWindow((sw - w) / 2, (sh - h) / 2, w, h, "Crafting", false)
    guiWindowSetSizable(craftingWindow, false)
    
    -- Left panel: Recipe list
    guiCreateLabel(15, 30, 200, 20, "Available Recipes:", false, craftingWindow)
    
    elements.recipeList = guiCreateGridList(15, 55, 250, 380, false, craftingWindow)
    guiGridListAddColumn(elements.recipeList, "Item", 0.7)
    guiGridListAddColumn(elements.recipeList, "Qty", 0.25)
    
    -- Populate recipe list
    for i, recipe in ipairs(currentRecipes) do
        local row = guiGridListAddRow(elements.recipeList)
        guiGridListSetItemText(elements.recipeList, row, 1, recipe.resultName or recipe.resultItemID, false, false)
        guiGridListSetItemText(elements.recipeList, row, 2, "x" .. (recipe.resultQuantity or 1), false, false)
        
        local color = QUALITY_COLORS[recipe.resultQuality] or QUALITY_COLORS.Common
        guiGridListSetItemColor(elements.recipeList, row, 1, color[1], color[2], color[3])
        guiGridListSetItemColor(elements.recipeList, row, 2, color[1], color[2], color[3])
        
        guiGridListSetItemData(elements.recipeList, row, 1, recipe.resultItemID)
    end
    
    -- Right panel: Recipe details
    guiCreateLabel(280, 30, 200, 20, "Recipe Details:", false, craftingWindow)
    
    elements.detailsLabel = guiCreateLabel(280, 55, 400, 25, "Select a recipe to view details", false, craftingWindow)
    guiSetFont(elements.detailsLabel, "default-bold-small")
    
    elements.toolLabel = guiCreateLabel(280, 85, 400, 20, "", false, craftingWindow)
    guiLabelSetColor(elements.toolLabel, 255, 200, 100)
    
    guiCreateLabel(280, 115, 200, 20, "Required Materials:", false, craftingWindow)
    
    elements.ingredientsList = guiCreateGridList(280, 140, 400, 200, false, craftingWindow)
    guiGridListAddColumn(elements.ingredientsList, "Material", 0.5)
    guiGridListAddColumn(elements.ingredientsList, "Need", 0.2)
    guiGridListAddColumn(elements.ingredientsList, "Have", 0.25)
    
    elements.statusLabel = guiCreateLabel(280, 350, 400, 40, "", false, craftingWindow)
    guiLabelSetColor(elements.statusLabel, 200, 200, 200)
    
    guiCreateLabel(280, 400, 60, 25, "Quantity:", false, craftingWindow)
    elements.quantityEdit = guiCreateEdit(345, 398, 50, 28, "1", false, craftingWindow)
    guiSetEnabled(elements.quantityEdit, false)
    
    elements.craftBtn = guiCreateButton(410, 395, 120, 35, "Craft", false, craftingWindow)
    guiSetEnabled(elements.craftBtn, false)
    
    elements.closeBtn = guiCreateButton(550, 395, 120, 35, "Close", false, craftingWindow)
    
    -- Event handlers
    addEventHandler("onClientGUIClick", elements.recipeList, function()
        local row = guiGridListGetSelectedItem(elements.recipeList)
        if row ~= -1 then
            local itemID = guiGridListGetItemData(elements.recipeList, row, 1)
            if itemID then
                triggerServerEvent("crafting:requestRecipe", localPlayer, itemID)
            end
        end
    end, false)
    
    addEventHandler("onClientGUIClick", elements.craftBtn, function()
        if selectedRecipe and selectedRecipe.canCraft then
            local quantity = tonumber(guiGetText(elements.quantityEdit)) or 1
            triggerServerEvent("crafting:craft", localPlayer, selectedRecipe.resultItemID, quantity)
        end
    end, false)
    
    addEventHandler("onClientGUIClick", elements.closeBtn, function()
        closeCraftingWindow()
    end, false)
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
end

function updateRecipeDetails(recipeData)
    if not craftingWindow or not isElement(craftingWindow) then return end
    
    selectedRecipe = recipeData
    
    local qualityColor = QUALITY_COLORS[recipeData.resultQuality] or QUALITY_COLORS.Common
    guiSetText(elements.detailsLabel, recipeData.resultName .. " (x" .. recipeData.resultQuantity .. ")")
    guiLabelSetColor(elements.detailsLabel, qualityColor[1], qualityColor[2], qualityColor[3])
    
    if recipeData.requiredToolID then
        local toolStatus = recipeData.playerHasTool and " [HAVE]" or " [MISSING]"
        local toolColor = recipeData.playerHasTool and {100, 255, 100} or {255, 100, 100}
        guiSetText(elements.toolLabel, "Requires: " .. (recipeData.requiredToolName or recipeData.requiredToolID) .. toolStatus)
        guiLabelSetColor(elements.toolLabel, toolColor[1], toolColor[2], toolColor[3])
    else
        guiSetText(elements.toolLabel, "No tool required")
        guiLabelSetColor(elements.toolLabel, 150, 150, 150)
    end
    
    guiGridListClear(elements.ingredientsList)
    
    for _, ing in ipairs(recipeData.ingredients) do
        local row = guiGridListAddRow(elements.ingredientsList)
        guiGridListSetItemText(elements.ingredientsList, row, 1, ing.name or ing.itemID, false, false)
        guiGridListSetItemText(elements.ingredientsList, row, 2, tostring(ing.quantity), false, false)
        guiGridListSetItemText(elements.ingredientsList, row, 3, tostring(ing.playerHas or 0), false, false)
        
        local hasEnough = (ing.playerHas or 0) >= ing.quantity
        local color = hasEnough and {100, 255, 100} or {255, 100, 100}
        guiGridListSetItemColor(elements.ingredientsList, row, 1, color[1], color[2], color[3])
        guiGridListSetItemColor(elements.ingredientsList, row, 2, 200, 200, 200)
        guiGridListSetItemColor(elements.ingredientsList, row, 3, color[1], color[2], color[3])
    end
    
    if recipeData.canCraft then
        guiSetText(elements.statusLabel, "Ready to craft!")
        guiLabelSetColor(elements.statusLabel, 100, 255, 100)
        guiSetEnabled(elements.craftBtn, true)
        guiSetEnabled(elements.quantityEdit, true)
    else
        guiSetText(elements.statusLabel, recipeData.craftReason or "Cannot craft")
        guiLabelSetColor(elements.statusLabel, 255, 100, 100)
        guiSetEnabled(elements.craftBtn, false)
        guiSetEnabled(elements.quantityEdit, false)
    end
end

function closeCraftingWindow()
    if craftingWindow and isElement(craftingWindow) then
        destroyElement(craftingWindow)
        craftingWindow = nil
        elements = {}
        selectedRecipe = nil
        showCursor(false)
        guiSetInputMode("allow_binds")
    end
end

--------------------------------------------------------------------------------
-- DM RECIPE EDITOR GUI
--------------------------------------------------------------------------------

function createRecipeEditorWindow(recipes, items)
    if editorWindow and isElement(editorWindow) then
        destroyElement(editorWindow)
    end
    
    allItems = items or {}
    materialItems = {}
    toolItems = {}
    currentEditRecipe = nil
    
    for _, item in ipairs(allItems) do
        if item.category == "material" then
            table.insert(materialItems, item)
        elseif item.category == "tool" then
            table.insert(toolItems, item)
        end
    end
    
    local sw, sh = guiGetScreenSize()
    local w, h = 850, 550
    
    editorWindow = guiCreateWindow((sw - w) / 2, (sh - h) / 2, w, h, "DM Recipe Editor", false)
    guiWindowSetSizable(editorWindow, false)
    
    -- === LEFT PANEL: Recipe List ===
    guiCreateLabel(15, 30, 200, 20, "Existing Recipes:", false, editorWindow)
    
    editorElements.recipeList = guiCreateGridList(15, 55, 250, 350, false, editorWindow)
    guiGridListAddColumn(editorElements.recipeList, "Item", 0.65)
    guiGridListAddColumn(editorElements.recipeList, "Ing.", 0.30)
    
    if recipes then
        for _, recipe in ipairs(recipes) do
            local row = guiGridListAddRow(editorElements.recipeList)
            guiGridListSetItemText(editorElements.recipeList, row, 1, recipe.resultName or recipe.resultItemID, false, false)
            guiGridListSetItemText(editorElements.recipeList, row, 2, tostring(#recipe.ingredients), false, false)
            guiGridListSetItemData(editorElements.recipeList, row, 1, recipe.resultItemID)
            
            local color = QUALITY_COLORS[recipe.resultQuality] or QUALITY_COLORS.common
            guiGridListSetItemColor(editorElements.recipeList, row, 1, color[1], color[2], color[3])
        end
    end
    
    editorElements.editBtn = guiCreateButton(15, 415, 120, 30, "Edit Selected", false, editorWindow)
    editorElements.deleteBtn = guiCreateButton(145, 415, 120, 30, "Delete", false, editorWindow)
    guiSetProperty(editorElements.deleteBtn, "NormalTextColour", "FFFF6666")
    
    editorElements.newBtn = guiCreateButton(15, 455, 250, 35, "Create New Recipe", false, editorWindow)
    guiSetProperty(editorElements.newBtn, "NormalTextColour", "FF66FF66")
    
    -- === RIGHT PANEL: Recipe Editor ===
    guiCreateLabel(285, 30, 200, 20, "Recipe Editor:", false, editorWindow)
    
    guiCreateLabel(285, 60, 100, 20, "Result Item:", false, editorWindow)
    editorElements.resultCombo = guiCreateComboBox(390, 58, 250, 300, "", false, editorWindow)
    
    for _, item in ipairs(allItems) do
        local displayName = item.name .. " [" .. item.category .. "]"
        guiComboBoxAddItem(editorElements.resultCombo, displayName)
    end
    guiSetEnabled(editorElements.resultCombo, false)
    
    guiCreateLabel(650, 60, 50, 20, "ID:", false, editorWindow)
    editorElements.resultIDLabel = guiCreateLabel(680, 60, 150, 20, "-", false, editorWindow)
    guiLabelSetColor(editorElements.resultIDLabel, 150, 150, 150)
    
    guiCreateLabel(285, 95, 100, 20, "Result Qty:", false, editorWindow)
    editorElements.resultQtyEdit = guiCreateEdit(390, 93, 60, 25, "1", false, editorWindow)
    guiSetEnabled(editorElements.resultQtyEdit, false)
    
    guiCreateLabel(470, 95, 100, 20, "Required Tool:", false, editorWindow)
    editorElements.toolCombo = guiCreateComboBox(570, 93, 200, 250, "", false, editorWindow)
    guiComboBoxAddItem(editorElements.toolCombo, "(None)")
    for _, item in ipairs(toolItems) do
        guiComboBoxAddItem(editorElements.toolCombo, item.name .. " [" .. item.id .. "]")
    end
    guiComboBoxSetSelected(editorElements.toolCombo, 0)
    guiSetEnabled(editorElements.toolCombo, false)
    
    -- === Ingredients Section ===
    guiCreateLabel(285, 130, 200, 20, "Required Ingredients:", false, editorWindow)
    
    editorElements.ingredientList = guiCreateGridList(285, 155, 350, 200, false, editorWindow)
    guiGridListAddColumn(editorElements.ingredientList, "Material", 0.55)
    guiGridListAddColumn(editorElements.ingredientList, "Qty", 0.2)
    guiGridListAddColumn(editorElements.ingredientList, "ID", 0.2)
    
    editorElements.removeIngBtn = guiCreateButton(645, 155, 120, 30, "Remove Selected", false, editorWindow)
    guiSetEnabled(editorElements.removeIngBtn, false)
    
    guiCreateLabel(285, 365, 100, 20, "Add Material:", false, editorWindow)
    editorElements.addMatCombo = guiCreateComboBox(385, 363, 200, 300, "", false, editorWindow)
    
    for _, item in ipairs(materialItems) do
        guiComboBoxAddItem(editorElements.addMatCombo, item.name .. " [" .. item.id .. "]")
    end
    guiSetEnabled(editorElements.addMatCombo, false)
    
    guiCreateLabel(595, 365, 30, 20, "Qty:", false, editorWindow)
    editorElements.addMatQtyEdit = guiCreateEdit(630, 363, 50, 25, "1", false, editorWindow)
    guiSetEnabled(editorElements.addMatQtyEdit, false)
    
    editorElements.addIngBtn = guiCreateButton(690, 360, 80, 30, "Add", false, editorWindow)
    guiSetEnabled(editorElements.addIngBtn, false)
    
    guiCreateLabel(285, 400, 100, 20, "Or Any Item:", false, editorWindow)
    editorElements.addAnyCombo = guiCreateComboBox(385, 398, 200, 300, "", false, editorWindow)
    for _, item in ipairs(allItems) do
        guiComboBoxAddItem(editorElements.addAnyCombo, item.name .. " [" .. item.id .. "]")
    end
    guiSetEnabled(editorElements.addAnyCombo, false)
    
    guiCreateLabel(595, 400, 30, 20, "Qty:", false, editorWindow)
    editorElements.addAnyQtyEdit = guiCreateEdit(630, 398, 50, 25, "1", false, editorWindow)
    guiSetEnabled(editorElements.addAnyQtyEdit, false)
    
    editorElements.addAnyBtn = guiCreateButton(690, 395, 80, 30, "Add", false, editorWindow)
    guiSetEnabled(editorElements.addAnyBtn, false)
    
    -- === Bottom Buttons ===
    editorElements.saveBtn = guiCreateButton(285, 450, 150, 40, "Save Recipe", false, editorWindow)
    guiSetProperty(editorElements.saveBtn, "NormalTextColour", "FF66FF66")
    guiSetEnabled(editorElements.saveBtn, false)
    
    editorElements.cancelEditBtn = guiCreateButton(445, 450, 150, 40, "Cancel Edit", false, editorWindow)
    guiSetEnabled(editorElements.cancelEditBtn, false)
    
    editorElements.closeBtn = guiCreateButton(700, 500, 120, 35, "Close", false, editorWindow)
    
    editorElements.statusLabel = guiCreateLabel(285, 500, 400, 20, "Select a recipe to edit or create a new one", false, editorWindow)
    guiLabelSetColor(editorElements.statusLabel, 200, 200, 200)
    
    setupEditorEventHandlers()
    
    showCursor(true)
    guiSetInputMode("no_binds_when_editing")
end

function setupEditorEventHandlers()
    addEventHandler("onClientGUIClick", editorElements.editBtn, function()
        local row = guiGridListGetSelectedItem(editorElements.recipeList)
        if row ~= -1 then
            local itemID = guiGridListGetItemData(editorElements.recipeList, row, 1)
            if itemID then
                triggerServerEvent("recipe:requestEdit", localPlayer, itemID)
            end
        else
            setEditorStatus("Select a recipe first", true)
        end
    end, false)
    
    addEventHandler("onClientGUIClick", editorElements.deleteBtn, function()
        local row = guiGridListGetSelectedItem(editorElements.recipeList)
        if row ~= -1 then
            local itemID = guiGridListGetItemData(editorElements.recipeList, row, 1)
            if itemID then
                triggerServerEvent("recipe:delete", localPlayer, itemID)
            end
        else
            setEditorStatus("Select a recipe first", true)
        end
    end, false)
    
    addEventHandler("onClientGUIClick", editorElements.newBtn, function()
        startNewRecipe()
    end, false)
    
    addEventHandler("onClientGUIComboBoxAccepted", editorElements.resultCombo, function()
        local idx = guiComboBoxGetSelected(editorElements.resultCombo)
        if idx >= 0 and allItems[idx + 1] then
            local item = allItems[idx + 1]
            guiSetText(editorElements.resultIDLabel, item.id)
        end
    end, false)
    
    addEventHandler("onClientGUIClick", editorElements.removeIngBtn, function()
        local row = guiGridListGetSelectedItem(editorElements.ingredientList)
        if row ~= -1 then
            guiGridListRemoveRow(editorElements.ingredientList, row)
            setEditorStatus("Ingredient removed (save to apply)", false)
        end
    end, false)
    
    addEventHandler("onClientGUIClick", editorElements.addIngBtn, function()
        local idx = guiComboBoxGetSelected(editorElements.addMatCombo)
        if idx >= 0 and materialItems[idx + 1] then
            local item = materialItems[idx + 1]
            local qty = tonumber(guiGetText(editorElements.addMatQtyEdit)) or 1
            addIngredientToEditorList(item.id, item.name, qty)
        else
            setEditorStatus("Select a material first", true)
        end
    end, false)
    
    addEventHandler("onClientGUIClick", editorElements.addAnyBtn, function()
        local idx = guiComboBoxGetSelected(editorElements.addAnyCombo)
        if idx >= 0 and allItems[idx + 1] then
            local item = allItems[idx + 1]
            local qty = tonumber(guiGetText(editorElements.addAnyQtyEdit)) or 1
            addIngredientToEditorList(item.id, item.name, qty)
        else
            setEditorStatus("Select an item first", true)
        end
    end, false)
    
    addEventHandler("onClientGUIClick", editorElements.saveBtn, function()
        saveCurrentEditRecipe()
    end, false)
    
    addEventHandler("onClientGUIClick", editorElements.cancelEditBtn, function()
        cancelRecipeEdit()
    end, false)
    
    addEventHandler("onClientGUIClick", editorElements.closeBtn, function()
        closeRecipeEditor()
    end, false)
end

function addIngredientToEditorList(itemID, itemName, quantity)
    for row = 0, guiGridListGetRowCount(editorElements.ingredientList) - 1 do
        local existingID = guiGridListGetItemText(editorElements.ingredientList, row, 3)
        if existingID == itemID then
            setEditorStatus("Material already in recipe", true)
            return
        end
    end
    
    local row = guiGridListAddRow(editorElements.ingredientList)
    guiGridListSetItemText(editorElements.ingredientList, row, 1, itemName, false, false)
    guiGridListSetItemText(editorElements.ingredientList, row, 2, tostring(quantity), false, false)
    guiGridListSetItemText(editorElements.ingredientList, row, 3, itemID, false, false)
    
    setEditorStatus("Ingredient added (save to apply)", false)
end

function startNewRecipe()
    currentEditRecipe = nil
    
    guiSetEnabled(editorElements.resultCombo, true)
    guiSetEnabled(editorElements.resultQtyEdit, true)
    guiSetEnabled(editorElements.toolCombo, true)
    guiSetEnabled(editorElements.addMatCombo, true)
    guiSetEnabled(editorElements.addMatQtyEdit, true)
    guiSetEnabled(editorElements.addIngBtn, true)
    guiSetEnabled(editorElements.addAnyCombo, true)
    guiSetEnabled(editorElements.addAnyQtyEdit, true)
    guiSetEnabled(editorElements.addAnyBtn, true)
    guiSetEnabled(editorElements.removeIngBtn, true)
    guiSetEnabled(editorElements.saveBtn, true)
    guiSetEnabled(editorElements.cancelEditBtn, true)
    
    guiComboBoxSetSelected(editorElements.resultCombo, -1)
    guiSetText(editorElements.resultIDLabel, "-")
    guiSetText(editorElements.resultQtyEdit, "1")
    guiComboBoxSetSelected(editorElements.toolCombo, 0)
    guiGridListClear(editorElements.ingredientList)
    
    setEditorStatus("Creating new recipe - select result item and add ingredients", false)
end

function loadRecipeForEdit(recipeData)
    currentEditRecipe = recipeData
    
    guiSetEnabled(editorElements.resultCombo, false)
    guiSetEnabled(editorElements.resultQtyEdit, true)
    guiSetEnabled(editorElements.toolCombo, true)
    guiSetEnabled(editorElements.addMatCombo, true)
    guiSetEnabled(editorElements.addMatQtyEdit, true)
    guiSetEnabled(editorElements.addIngBtn, true)
    guiSetEnabled(editorElements.addAnyCombo, true)
    guiSetEnabled(editorElements.addAnyQtyEdit, true)
    guiSetEnabled(editorElements.addAnyBtn, true)
    guiSetEnabled(editorElements.removeIngBtn, true)
    guiSetEnabled(editorElements.saveBtn, true)
    guiSetEnabled(editorElements.cancelEditBtn, true)
    
    for i, item in ipairs(allItems) do
        if item.id == recipeData.resultItemID then
            guiComboBoxSetSelected(editorElements.resultCombo, i - 1)
            break
        end
    end
    guiSetText(editorElements.resultIDLabel, recipeData.resultItemID)
    guiSetText(editorElements.resultQtyEdit, tostring(recipeData.resultQuantity or 1))
    
    if recipeData.requiredToolID then
        local found = false
        for i, item in ipairs(toolItems) do
            if item.id == recipeData.requiredToolID then
                guiComboBoxSetSelected(editorElements.toolCombo, i)
                found = true
                break
            end
        end
        if not found then
            guiComboBoxSetSelected(editorElements.toolCombo, 0)
        end
    else
        guiComboBoxSetSelected(editorElements.toolCombo, 0)
    end
    
    guiGridListClear(editorElements.ingredientList)
    for _, ing in ipairs(recipeData.ingredients or {}) do
        local row = guiGridListAddRow(editorElements.ingredientList)
        guiGridListSetItemText(editorElements.ingredientList, row, 1, ing.name or ing.itemID, false, false)
        guiGridListSetItemText(editorElements.ingredientList, row, 2, tostring(ing.quantity), false, false)
        guiGridListSetItemText(editorElements.ingredientList, row, 3, ing.itemID, false, false)
    end
    
    setEditorStatus("Editing: " .. (recipeData.resultName or recipeData.resultItemID), false)
end

function saveCurrentEditRecipe()
    local resultItemID
    if currentEditRecipe then
        resultItemID = currentEditRecipe.resultItemID
    else
        local idx = guiComboBoxGetSelected(editorElements.resultCombo)
        if idx < 0 or not allItems[idx + 1] then
            setEditorStatus("Select a result item first", true)
            return
        end
        resultItemID = allItems[idx + 1].id
    end
    
    local resultQty = tonumber(guiGetText(editorElements.resultQtyEdit)) or 1
    
    local toolID = nil
    local toolIdx = guiComboBoxGetSelected(editorElements.toolCombo)
    if toolIdx > 0 and toolItems[toolIdx] then
        toolID = toolItems[toolIdx].id
    end
    
    local ingredients = {}
    for row = 0, guiGridListGetRowCount(editorElements.ingredientList) - 1 do
        local itemID = guiGridListGetItemText(editorElements.ingredientList, row, 3)
        local qty = tonumber(guiGridListGetItemText(editorElements.ingredientList, row, 2)) or 1
        table.insert(ingredients, {itemID = itemID, quantity = qty})
    end
    
    if #ingredients == 0 then
        setEditorStatus("Add at least one ingredient", true)
        return
    end
    
    if currentEditRecipe then
        triggerServerEvent("recipe:update", localPlayer, resultItemID, resultQty, ingredients, toolID)
    else
        triggerServerEvent("recipe:create", localPlayer, resultItemID, resultQty, ingredients, toolID)
    end
end

function cancelRecipeEdit()
    currentEditRecipe = nil
    
    guiSetEnabled(editorElements.resultCombo, false)
    guiSetEnabled(editorElements.resultQtyEdit, false)
    guiSetEnabled(editorElements.toolCombo, false)
    guiSetEnabled(editorElements.addMatCombo, false)
    guiSetEnabled(editorElements.addMatQtyEdit, false)
    guiSetEnabled(editorElements.addIngBtn, false)
    guiSetEnabled(editorElements.addAnyCombo, false)
    guiSetEnabled(editorElements.addAnyQtyEdit, false)
    guiSetEnabled(editorElements.addAnyBtn, false)
    guiSetEnabled(editorElements.removeIngBtn, false)
    guiSetEnabled(editorElements.saveBtn, false)
    guiSetEnabled(editorElements.cancelEditBtn, false)
    
    guiComboBoxSetSelected(editorElements.resultCombo, -1)
    guiSetText(editorElements.resultIDLabel, "-")
    guiSetText(editorElements.resultQtyEdit, "1")
    guiComboBoxSetSelected(editorElements.toolCombo, 0)
    guiGridListClear(editorElements.ingredientList)
    
    setEditorStatus("Edit cancelled", false)
end

function setEditorStatus(message, isError)
    if editorElements.statusLabel and isElement(editorElements.statusLabel) then
        guiSetText(editorElements.statusLabel, message)
        if isError then
            guiLabelSetColor(editorElements.statusLabel, 255, 100, 100)
        else
            guiLabelSetColor(editorElements.statusLabel, 100, 255, 100)
        end
    end
end

function refreshEditorRecipeList(recipes)
    if not editorElements.recipeList or not isElement(editorElements.recipeList) then return end
    
    guiGridListClear(editorElements.recipeList)
    
    if recipes then
        for _, recipe in ipairs(recipes) do
            local row = guiGridListAddRow(editorElements.recipeList)
            guiGridListSetItemText(editorElements.recipeList, row, 1, recipe.resultName or recipe.resultItemID, false, false)
            guiGridListSetItemText(editorElements.recipeList, row, 2, tostring(#recipe.ingredients), false, false)
            guiGridListSetItemData(editorElements.recipeList, row, 1, recipe.resultItemID)
            
            local color = QUALITY_COLORS[recipe.resultQuality] or QUALITY_COLORS.common
            guiGridListSetItemColor(editorElements.recipeList, row, 1, color[1], color[2], color[3])
        end
    end
end

function closeRecipeEditor()
    if editorWindow and isElement(editorWindow) then
        destroyElement(editorWindow)
        editorWindow = nil
        editorElements = {}
        currentEditRecipe = nil
        showCursor(false)
        guiSetInputMode("allow_binds")
    end
end

--------------------------------------------------------------------------------
-- SERVER EVENTS - PLAYER CRAFTING
--------------------------------------------------------------------------------

addEvent("crafting:openMenu", true)
addEventHandler("crafting:openMenu", root, function(recipes)
    createCraftingWindow(recipes)
end)

addEvent("crafting:recipeDetails", true)
addEventHandler("crafting:recipeDetails", root, function(recipeData)
    updateRecipeDetails(recipeData)
end)

addEvent("crafting:message", true)
addEventHandler("crafting:message", root, function(message, isError)
    if isError then
        outputChatBox("[Crafting] " .. message, 255, 100, 100)
    else
        outputChatBox("[Crafting] " .. message, 100, 255, 100)
    end
end)

--------------------------------------------------------------------------------
-- SERVER EVENTS - DM RECIPE EDITOR
--------------------------------------------------------------------------------

addEvent("recipe:openEditor", true)
addEventHandler("recipe:openEditor", root, function(recipes, items)
    createRecipeEditorWindow(recipes, items)
end)

addEvent("recipe:editData", true)
addEventHandler("recipe:editData", root, function(recipeData)
    loadRecipeForEdit(recipeData)
end)

addEvent("recipe:saved", true)
addEventHandler("recipe:saved", root, function(success, message, updatedRecipes)
    if success then
        setEditorStatus(message, false)
        cancelRecipeEdit()
        if updatedRecipes then
            refreshEditorRecipeList(updatedRecipes)
        end
    else
        setEditorStatus(message, true)
    end
end)

addEvent("recipe:deleted", true)
addEventHandler("recipe:deleted", root, function(success, message, updatedRecipes)
    if success then
        setEditorStatus(message, false)
        if updatedRecipes then
            refreshEditorRecipeList(updatedRecipes)
        end
    else
        setEditorStatus(message, true)
    end
end)

addEvent("recipe:message", true)
addEventHandler("recipe:message", root, function(message, isError)
    setEditorStatus(message, isError)
    if isError then
        outputChatBox("[Recipe Editor] " .. message, 255, 100, 100)
    else
        outputChatBox("[Recipe Editor] " .. message, 100, 255, 100)
    end
end)

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeCraftingWindow()
    closeRecipeEditor()
end)

-- Player keybind to open crafting
bindKey("F5", "down", function()
    if craftingWindow and isElement(craftingWindow) then
        closeCraftingWindow()
    elseif editorWindow and isElement(editorWindow) then
        closeRecipeEditor()
    else
        triggerServerEvent("crafting:requestMenu", localPlayer)
    end
end)

outputChatBox("Crafting system loaded. Press F5 or /craft to open. DMs: /recipegui", 200, 200, 200)
