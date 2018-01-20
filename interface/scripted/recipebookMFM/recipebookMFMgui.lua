local recipeListNeedsUpdate = true
local requests = {}
local enableDebug = true
local forceUpdate = false

local ingredientStore = nil
local selectedFilters = nil
local recipeFilters = nil
local recipeFilterStore = nil
local recipeSelectionItems = {}
local selectedRecipeId = nil
local filters = { nameFilter = nil }
local ignoreSelected = false
-- Implement a bread crumb thing here
local breadCrumb = {}

INGREDIENT_HEADER_BACKGROUD = "/interface/crafting/MFM/shared/craftableheaderbackgroundMFM.png"

RECIPE_LIST_NAME = "recipeList.itemList"
RECIPE_LIST_EMPTY = "recipeList.empty"
INGREDIENTS_LIST_NAME = "ingredientList.ingredientItemList"
INGREDIENTS_LIST_EMPTY = "ingredientList.empty"

function init()
end

function update()
  if(forceUpdate) then
    ingredientStore = nil
    recipeFilterStore = nil
    recipeFilters = nil
    selectedFilters = nil
    forceUpdate = false
  end
  if(ingredientStore == nil or recipeFilterStore == nil or recipeFilters == nil or selectedFilters == nil) then
    local ingredientStoreResult = updateStore("getIngredientStore", {})
    if(ingredientStoreResult ~= nil) then
      ingredientStore = ingredientStoreResult
    end
    local filterStoreResult = updateStore("getRecipeFilterStore", {})
    if(filterStoreResult ~= nil) then
      recipeFilterStore = filterStoreResult
    end
    local recipeFiltersResult = updateStore("getRecipeFilters", {})
    if(recipeFiltersResult ~= nil) then
      recipeFilters = recipeFiltersResult
    end
    local selectedFiltersResult = updateStore("getSelectedFilters", {})
    if(selectedFiltersResult ~= nil) then
      selectedFilters = selectedFiltersResult
      updateSelectedFilters()
    end
    recipeListNeedsUpdate = true
    return
  end
  if(selectedRecipeId == nil) then
    local recipeIdResult = updateStore("getSelectedRecipeId", "")
    if(recipeIdResult ~= nil) then
      selectedRecipeId = recipeIdResult
    end
    recipeListNeedsUpdate = true
    return
  end
  if(recipeListNeedsUpdate) then
    updateRecipeList()
    recipeListNeedsUpdate = false
  end
  world.sendEntityMessage(pane.sourceEntity(), "setSelectedFilters", selectedFilters)
end

function updateSelectedFilters()
  for name,isSelected in pairs(selectedFilters) do
    widget.setChecked(name .. "chkbox", isSelected)
  end
end

function updateRecipeList()
  ignoreSelected = true
  widget.clearListItems(RECIPE_LIST_NAME)
  recipeSelectionItems = {}
  widget.setVisible(RECIPE_LIST_EMPTY, false)
  
  logInfo("Updating recipe list")
  local recipeListItems = {}
  for filterName, isSelected in pairs(selectedFilters) do
    logInfo("Using filter: " .. filterName)
    if(isSelected and recipeFilterStore[filterName] ~= nil) then
      for recipeName, recipeItem in pairs(recipeFilterStore[filterName]) do
        logInfo("Looking at recipe: " .. recipeName)
        table.insert(recipeListItems, recipeItem)
      end
    end
  end
  
  table.sort(recipeListItems, function(a, b)
		if a.name < b.name then return true end
		if a.name > b.name then return false end
		return a.id < b.id
	end)
  
  local hasRecipes = false
  for idx,recipeItem in ipairs(recipeListItems) do
    logInfo("Loading recipe with name: " .. recipeItem.name)
    local listItemId = widget.addListItem(RECIPE_LIST_NAME)
    local path = string.format("%s.%s", RECIPE_LIST_NAME, listItemId)
    widget.setText(path .. ".itemName", recipeItem.name .. " " .. formatMethods(recipeItem.methods))
    widget.setImage(path .. ".itemIcon", recipeItem.icon)
    widget.setData(path, { id = recipeItem.id, recipes = recipeItem.recipes})
    widget.setVisible(path .. ".itemName", true)
    widget.setVisible(path .. ".itemIcon", true)
    recipeSelectionItems[recipeItem.id] = listItemId
    hasRecipes = true
  end
  
  widget.setVisible(RECIPE_LIST_EMPTY, not hasRecipes)
  ignoreSelected = false
  
  if(selectedRecipeId ~= nil and recipeSelectionItems[selectedRecipeId] ~= nil) then
    logInfo("Selecting recipe with id: " .. selectedRecipeId)
    widget.setListSelected(RECIPE_LIST_NAME, recipeSelectionItems[selectedRecipeId])
  end
end

function formatMethods(methods)
  if(isEmpty(methods)) then
    return "Unknown"
  end
  local formatted = ""
  for method,friendlyMethod in pairs(methods) do
    formatted = formatted .. "(" .. friendlyMethod .. ")"
  end
  if(formatted == "") then
    return "Unknown"
  end
  return formatted
end

function updateIngredientList(recipes)
  widget.clearListItems(INGREDIENTS_LIST_NAME)
  if(selectedRecipeId == nil) then
    widget.setVisible(INGREDIENTS_LIST_EMPTY, true)
    return
  end
  widget.setVisible(INGREDIENTS_LIST_EMPTY, false)
  
  local hasIngredients = false
  
  local allListItems = {}
  local currentRecipeIdx = 1
  for idx,recipe in ipairs(recipes) do
    local ingredientListItems = {}
    
    local headerIcon = nil
    if(ingredientStore[recipe.output.name] ~= nil) then
      headerIcon = ingredientStore[recipe.output.name].icon
    end
    
    table.insert(allListItems, { id = recipe.output.name, name = "RECIPE " .. currentRecipeIdx .. ": " .. formatMethods(recipe.methods), isHeader = true, count = recipe.output.count, icon = headerIcon, methods = ingredientStore[recipe.output.name].methods })
    currentRecipeIdx = currentRecipeIdx + 1
    
    for idx,inputItem in ipairs(recipe.input) do
      local item = getItem(inputItem.name)
      item.count = inputItem.count
      item.isHeader = false
      hasIngredients = true
      if(ingredientStore[item.id] ~= nil) then
        item.methods = ingredientStore[item.id].methods
      else
        item.methods = {}
      end
      table.insert(ingredientListItems, item)
    end
  
    table.sort(ingredientListItems, function(a, b)
      return a.id < b.id
    end)
    
    for idx,ingredListItem in ipairs(ingredientListItems) do
      table.insert(allListItems, ingredListItem)
    end
  end
  
  for idx,listItem in ipairs(allListItems) do
    local isHeader = listItem.isHeader
    local path = string.format("%s.%s", INGREDIENTS_LIST_NAME, widget.addListItem(INGREDIENTS_LIST_NAME))
    if(isHeader) then
      widget.setImage(path .. ".background", INGREDIENT_HEADER_BACKGROUD)
    end
    widget.setText(path .. ".itemName", listItem.name)
    widget.setVisible(path .. ".itemName", true)
    widget.setText(path .. ".countLabel", (isHeader and "Output: " or "Input: ") .. listItem.count)
    if(listItem.icon ~= nil) then
      widget.setImage(path .. ".itemIcon", listItem.icon)
      widget.setVisible(path .. ".itemIcon", true)
    else
      widget.setVisible(path .. ".itemIcon", false)
    end
    widget.setData(path, { id = listItem.id, methods = listItem.methods, isHeader = isHeader })
  end
  
  widget.setVisible(INGREDIENTS_LIST_EMPTY, not hasIngredients)
end

function getItem(itemId)
  if(ingredientStore[itemId] ~= nil) then
    return ingredientStore[itemId]
  end
  local item = { id = itemId, name = itemId, icon = nil }
  world.sendEntityMessage(pane.sourceEntity(), "storeIngredient", itemId)
  forceUpdate = true
  return item
end

function toggleFilter(id, data)
  local newValue = widget.getChecked(id)
  if(newValue) then
    logInfo("New value is true")
  end
  selectedFilters[data.filterName] = newValue
  updateRecipeList()
end

function filterByName(id, data)
  logInfo("Filtering: " .. id)
  logInfo("Filtering 2: " .. data)
end

function btnFilterHaveMaterials(id, data)
  logInfo("Filter has Mats")
end

function updateStore(requestName, defaultValue, data)
  local updatedName = requestName .. "Updated"
  if(requests[updatedName] ~= nil and not requests[updatedName]) then
    return nil
  end
  local request = requests[requestName]
  if(request == nil) then
    requests[requestName] = world.sendEntityMessage(pane.sourceEntity(), requestName, data)
    request = requests[requestName]
  end
  if(not request:finished()) then
    return nil
  end
  if(not request:succeeded()) then
    local errorMsg = request:error()
    if(errorMsg ~= nil) then
      sb.logError(errorMsg)
    end
    requests[updatedName] = true
    return defaultValue
  end
  local result = request:result()
  if(not result) then
    requests[updatedName] = true
    return defaultValue
  end
  logInfo("Loaded store: " .. requestName)
  requests[updatedName] = true
  requests[requestName] = nil
  return result
end

function logInfo(msg)
  if(enableDebug) then
    sb.logInfo(msg)
  end
end

function onRecipeSelected()
  if(ignoreSelected) then
    logInfo("Ignoring Selection Change")
    return
  end
  local selectedItem = widget.getListSelected(RECIPE_LIST_NAME)
  if(selectedItem == nil) then
    logInfo("Clearing selected")
    selectedRecipeId = nil
    return
  end
  local id = string.format("%s.%s", RECIPE_LIST_NAME, selectedItem)
  local data = widget.getData(id)
  if(data.recipes ~= nil) then
    selectedRecipeId = data.id
    world.sendEntityMessage(pane.sourceEntity(), "storeSelectedRecipeId", selectedRecipeId)
    updateIngredientList(data.recipes)
  end
end

function onIngredientSelected()
  if(ignoreSelected) then
    logInfo("Ignoring Selection Change")
    return
  end
  local selectedItem = widget.getListSelected(INGREDIENTS_LIST_NAME)
  if(selectedItem == nil) then
    logInfo("Clearing selected")
    selectedRecipeId = nil
    return
  end
  local id = string.format("%s.%s", INGREDIENTS_LIST_NAME, selectedItem)
  local data = widget.getData(id)
  local failedToSelectMethods = ensureSelectedMethods(data.methods)
  if(failedToSelectMethods) then
    return
  end
  selectedRecipeId = data.id
  world.sendEntityMessage(pane.sourceEntity(), "storeSelectedRecipeId", selectedRecipeId)
  forceUpdate = true
end

function ensureSelectedMethods(methods)
  if(isEmpty(methods)) then
    return true
  end
  for name,val in pairs(selectedFilters) do
    selectedFilters[name] = false
  end
  for methodName,fn in pairs(methods) do
    selectedFilters[methodName] = true
  end
  world.sendEntityMessage(pane.sourceEntity(), "setSelectedFilters", selectedFilters)
  updateSelectedFilters()
  return false
end

function isEmpty(pairTable)
  if(pairTable == nil) then
    return true
  end
  local empty = true;
  for one,two in pairs(pairTable) do
    empty = false
    break;
  end
  return empty
end

function uninit()
end