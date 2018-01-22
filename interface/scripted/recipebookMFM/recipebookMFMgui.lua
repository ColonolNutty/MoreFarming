------------------------- Basic -------------------------------

local ignoreRecipeSelected = false
local ignoreFilterSelected = false
local refreshIngredients = false
local needsUpdate = true
local enableDebug = true
local requests = {}
local dataStore = nil
local ready = false

function init()
end

function uninit()
end

function update()

  if(dataStore == nil) then
    local dataStoreResult = updateStore("getDataStore", nil)
    if(dataStoreResult ~= nil) then
      dataStore = dataStoreResult
      updateFilterList()
      needsUpdate = true
      refreshIngredients = false
    end
    ready = false
    return
  end
  if(refreshIngredients and reloadIngredientStore()) then
    refreshIngredients = false
    onRecipeSelected()
  end
  if(needsUpdate) then
    updateRecipeList()
    needsUpdate = false
    ready = true
  end
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

-----------------------------------------------------------------



------------------------- Bread Crumb ---------------------------

-- Implement a bread crumb thing here
local breadCrumb = {}

-----------------------------------------------------------------



------------------------- Method Filters ------------------------

local filterSelectionItems = {}
-- Finish adding support for this
local filters = { nameFilter = nil }

FILTER_LIST_NAME = "filterList.filterItemList"
FILTER_LIST_EMPTY = "filterList.empty"

function onFilterSelected()
  if(ignoreFilterSelected) then
    logInfo("Ignoring Filter Selection Change")
    return
  end
  local id, data = getSelectedItemData(FILTER_LIST_NAME)
  if(id == nil or data == nil or data.id == "hidden") then
    return
  end
  local isSelected = toggleFilter(data.id)
  updateFilterColor(id, isSelected)
  selectHiddenFilter()
  updateDataStore()
  updateRecipeList()
end

function updateFilterColor(filterPath, isSelected)
  widget.setVisible(filterPath .. ".backgroundSelected", isSelected)
  widget.setVisible(filterPath .. ".backgroundUnselected", not isSelected)
  widget.setFontColor(filterPath .. ".itemName", isSelected and {0, 0, 0, 255} or {255, 255, 255, 255})
end

function toggleFilter(filterId)
  local oldValue = dataStore.selectedFilters[filterId]
  if(oldValue == nil) then
    oldValue = false
  end
  dataStore.selectedFilters[filterId] = not oldValue
  return dataStore.selectedFilters[filterId]
end

function selectHiddenFilter()
  widget.setListSelected(FILTER_LIST_NAME, filterSelectionItems["hidden"])
end

function updateFilterList()
  ignoreFilterSelected = true
  widget.clearListItems(FILTER_LIST_NAME)
  recipeSelectionItems = {}
  widget.setVisible(FILTER_LIST_EMPTY, false)
  
  -- Do thing
  local filterListItems = {}
  for idx,recipeFilter in ipairs(dataStore.methodFilterNames) do
    local friendlyName = dataStore.methodFriendlyNames[recipeFilter]
    if(friendlyName ~= nil) then
      table.insert(filterListItems, { id = recipeFilter, name = friendlyName, isSelected = dataStore.selectedFilters[recipeFilter] })
    end
  end
  
  table.sort(filterListItems, function(a, b)
		if a.name < b.name then return true end
		if a.name > b.name then return false end
		return a.id < b.id
	end)
  
  local hasFilters = false
  for idx,filterItem in ipairs(filterListItems) do
    logInfo("Loading filter with name: " .. filterItem.name)
    local listItemId = widget.addListItem(FILTER_LIST_NAME)
    local path = string.format("%s.%s", FILTER_LIST_NAME, listItemId)
    widget.setText(path .. ".itemName", filterItem.name)
    widget.setData(path, { id = filterItem.id })
    widget.setVisible(path .. ".itemName", true)
    filterSelectionItems[filterItem.id] = listItemId
    hasFilters = true
  end
  
  if(hasFilters) then
    --- Hidden filter for deselection ---
      local hiddenListItemId = widget.addListItem(FILTER_LIST_NAME)
      local hiddenPath = string.format("%s.%s", FILTER_LIST_NAME, hiddenListItemId)
      widget.setText(hiddenPath .. ".itemName", "")
      widget.setData(hiddenPath, { id = "hidden" })
      widget.setVisible(hiddenPath, false)
      filterSelectionItems["hidden"] = hiddenListItemId
    ---
  end
  
  updateFilterSelections()
  
  widget.setVisible(FILTER_LIST_EMPTY, not hasFilters)
  ignoreFilterSelected = false
end

function updateFilterSelections()
  for name,isSelected in pairs(dataStore.selectedFilters) do
    if(filterSelectionItems[name] ~= nil) then
      local filterItemId = filterSelectionItems[name]
      local path = string.format("%s.%s", FILTER_LIST_NAME, filterItemId)
      updateFilterColor(path, isSelected)
    end
  end
end

function changeSelectedMethods(methods)
  if(isEmpty(methods)) then
    return false
  end
  for name,val in pairs(dataStore.selectedFilters) do
    if(name ~= "hidden") then
      dataStore.selectedFilters[name] = false
    end
  end
  for methodName,fn in pairs(methods) do
    dataStore.selectedFilters[methodName] = true
  end
  updateDataStore()
  updateFilterSelections()
  return true
end

function selectAllFilters()
  changeAllFilters(true)
end

function unselectAllFilters()
  changeAllFilters(false)
end

function changeAllFilters(allSelected)
  if(not ready) then
    return
  end
  for idx,name in ipairs(dataStore.methodFilterNames) do
    dataStore.selectedFilters[name] = allSelected
  end
  updateDataStore()
  updateFilterSelections()
  needsUpdate = true
end

-----------------------------------------------------------------



------------------------- Name Filters --------------------------

function filterByName(id)
  local nameFilter = widget.getText(filterByName)
  logInfo("Text thing: " .. nameFilter)
end

-----------------------------------------------------------------



------------------------- Recipes -------------------------------

local recipeSelectionItems = {}

RECIPE_LIST_NAME = "recipeList.recipeItemList"
RECIPE_LIST_EMPTY = "recipeList.empty"


function onRecipeSelected()
  if(ignoreRecipeSelected) then
    logInfo("Ignoring Recipe Selection Change")
    return
  end
  logInfo("Not ignoring recipe change")
  local id, data = getSelectedItemData(RECIPE_LIST_NAME)
  if(id == nil or data == nil) then
    setSelectedRecipeId(nil)
    return
  end
  if(data.recipes ~= nil) then
    setSelectedRecipeId(data.id)
    updateIngredientList(data.recipes)
  end
end

function updateRecipeList()
  ignoreRecipeSelected = true
  widget.clearListItems(RECIPE_LIST_NAME)
  recipeSelectionItems = {}
  widget.setVisible(RECIPE_LIST_EMPTY, false)
  
  local addedRecipes = {}
  logInfo("Updating recipe list")
  local recipeListItems = {}
  for filterName, isSelected in pairs(dataStore.selectedFilters) do
    logInfo("Using filter: " .. filterName)
    if(isSelected and dataStore.recipeFilterStore[filterName] ~= nil) then
      for recipeName, recipeItem in pairs(dataStore.recipeFilterStore[filterName]) do
        logInfo("Looking at recipe: " .. recipeName)
        if(addedRecipes[recipeName] == nil) then
          table.insert(recipeListItems, recipeItem)
          addedRecipes[recipeName] = true
        end
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
    widget.setText(path .. ".itemName", recipeItem.name .. formatMethods(recipeItem.methods))
    widget.setImage(path .. ".itemIcon", recipeItem.icon)
    widget.setData(path, { id = recipeItem.id, recipes = recipeItem.recipes})
    widget.setVisible(path .. ".itemName", true)
    widget.setVisible(path .. ".itemIcon", true)
    recipeSelectionItems[recipeItem.id] = listItemId
    hasRecipes = true
  end
  
  widget.setVisible(RECIPE_LIST_EMPTY, not hasRecipes)
  ignoreRecipeSelected = false
  
  if(not hasRecipes) then
    setSelectedRecipeId(nil)
    updateIngredientList(nil)
    return
  end
  
  if(dataStore.selectedRecipeId ~= nil and recipeSelectionItems[dataStore.selectedRecipeId] ~= nil) then
    selectRecipeById(dataStore.selectedRecipeId)
    --widget.focus(string.format("%s.%s", RECIPE_LIST_NAME, recipeSelectionItems[dataStore.selectedRecipeId]))
  end
end

function formatMethods(methods)
  if(isEmpty(methods)) then
    return " (Unknown)"
  end
  local formatted = ""
  for method,friendlyMethod in pairs(methods) do
    formatted = formatted .. " (" .. friendlyMethod .. ")"
  end
  if(formatted == "") then
    return " (No)"
  end
  return formatted
end

function setSelectedRecipeId(id)
  dataStore.selectedRecipeId = id
  updateDataStore()
end

function selectRecipeById(recipeId)
  if(recipeSelectionItems[recipeId] ~= nil) then
    logInfo("Selecting recipe with id: " .. recipeId)
    widget.setListSelected(RECIPE_LIST_NAME, recipeSelectionItems[recipeId])
    return true
  end
  return false
end

-----------------------------------------------------------------



----------------------- Ingredients -----------------------------


INGREDIENT_HEADER_BACKGROUD = "/interface/crafting/MFM/shared/craftableheaderbackgroundMFM.png"

INGREDIENTS_LIST_NAME = "ingredientList.ingredientItemList"
INGREDIENTS_LIST_EMPTY = "ingredientList.empty"

function onIngredientSelected()
  if(ignoreRecipeSelected) then
    logInfo("Ignoring Ingredient Selection Change")
    return
  end
  local id, data = getSelectedItemData(INGREDIENTS_LIST_NAME)
  if(id == nil or data == nil or data.isHidden) then
    return
  end
  --- Selected a recipe header, deselect by selecting hidden list item
  if(data.isHeader) then
    selectHiddenIngredient()
    return
  end
  --- Recipe to select has already been selected
  if(dataStore.selectedRecipeId == data.id) then
    logInfo("Recipe already selected, skipping reload")
    return
  end
  setSelectedRecipeId(data.id)
  --- Select recipe if it is already visible
  if(selectRecipeById(data.id)) then
    return
  end
  --- Recipe wasn't visible, so change filters to ensure it is and update recipe list
  local success = changeSelectedMethods(data.methods)
  if(not success) then
    return
  end
  needsUpdate = true
end

function updateIngredientList(recipes)
  widget.clearListItems(INGREDIENTS_LIST_NAME)
  hiddenIngredientListItemId = nil
  if(recipes == nil or dataStore.selectedRecipeId == nil) then
    widget.setVisible(INGREDIENTS_LIST_EMPTY, true)
    return
  end
  widget.setVisible(INGREDIENTS_LIST_EMPTY, false)
  
  local hasIngredients = false
  
  local allListItems = {}
  local currentRecipeIdx = 1
  for idx,recipe in ipairs(recipes) do
    local recipeIngredientListItems = {}
    
    local headerIcon = nil
    if(dataStore.ingredientStore[recipe.output.name] ~= nil) then
      headerIcon = dataStore.ingredientStore[recipe.output.name].icon
    end
    
    table.insert(allListItems, { id = recipe.output.name, name = "RECIPE " .. currentRecipeIdx .. ":" .. formatMethods(recipe.methods), isHeader = true, isHidden = false, count = recipe.output.count, icon = headerIcon, methods = dataStore.ingredientStore[recipe.output.name].methods })
    currentRecipeIdx = currentRecipeIdx + 1
    
    for idx,inputItem in ipairs(recipe.input) do
      local item = getItem(inputItem.name)
      item.count = inputItem.count
      item.isHeader = false
      item.isHidden = false
      hasIngredients = true
      if(dataStore.ingredientStore[item.id] ~= nil) then
        item.methods = dataStore.ingredientStore[item.id].methods
      else
        item.methods = {}
      end
      table.insert(recipeIngredientListItems, item)
    end
  
    table.sort(recipeIngredientListItems, function(a, b)
      return a.id < b.id
    end)
    
    for idx,ingredListItem in ipairs(recipeIngredientListItems) do
      table.insert(allListItems, ingredListItem)
    end
  end
  
  for idx,listItem in ipairs(allListItems) do
    local isHeader = listItem.isHeader
    local path = string.format("%s.%s", INGREDIENTS_LIST_NAME, widget.addListItem(INGREDIENTS_LIST_NAME))
    widget.setVisible(path .. ".selectedBackground", false)
    widget.setVisible(path .. ".unselectedBackground", true)
    if(isHeader) then
      widget.setImage(path .. ".selectedBackground", "")
      widget.setVisible(path .. ".selectedBackground", false)
      widget.setImage(path .. ".unselectedBackground", INGREDIENT_HEADER_BACKGROUD)
      widget.setVisible(path .. ".unselectedBackground", true)
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
    widget.setData(path, { id = listItem.id, methods = listItem.methods, isHeader = isHeader, isHidden = listItem.isHidden })
  end
  
  widget.setVisible(INGREDIENTS_LIST_EMPTY, not hasIngredients)
end

function getItem(itemId)
  if(dataStore.ingredientStore[itemId] ~= nil) then
    return dataStore.ingredientStore[itemId]
  end
  local item = { id = itemId, name = itemId, icon = nil }
  world.sendEntityMessage(pane.sourceEntity(), "storeIngredient", itemId)
  refreshIngredients = true
  return item
end

-----------------------------------------------------------------



------------------------- Utility -------------------------------

function reloadIngredientStore()
  local dataStoreResult = updateStore("getDataStore", nil)
  if(dataStoreResult ~= nil) then
    dataStore.ingredientStore = dataStoreResult.ingredientStore
    return true
  end
  return false
end

function updateDataStore()
  world.sendEntityMessage(pane.sourceEntity(), "setDataStore", dataStore)
end

function getSelectedItemData(listName)
  local selectedItem = widget.getListSelected(listName)
  if(selectedItem == nil) then
    return nil, nil
  end
  local id = string.format("%s.%s", listName, selectedItem)
  return id, widget.getData(id)
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


function logInfo(msg)
  if(enableDebug) then
    sb.logInfo("[RBGUI] " .. msg)
  end
end
-----------------------------------------------------------------
