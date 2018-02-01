require "/scripts/utilsCN.lua"

----------------------- Properties ------------------------------

--- Should format requests as following ---
-- { active = boolean, handle = function() (return isDone, result), onCompleted = function(result) }
---
local filters = {
    nameFilter = nil,
    inputNameFilter = nil,
    ingredientsAvailable = false,
    recipeFilters = {}
  }
local requestIdentifiers = {}
local requests = {}
local requestsToObject = {}
local completedInitialSetup = false
local enableDebug = nil
local methodFilterListItemIds = nil
local foodListItemIds = nil

-----------------------------------------------------------------

------------------------- Basic ---------------------------------

local ignoreFoodSelected = false
local ignoreFilterSelected = false
local dataStore = nil
local hasError = false
-- Since the filter activates for every keystroke (twice for some reason), this is here to reduce lag experienced when filtering by name (In other words, there is a 1 second delay before results will filter)
local updateBuffer = 1
local currentTime = 0
local enableDelayedRecipeUpdate = false
local debugStateUpdated = false

function init()
  filters.clear = function()
    widget.setText("filterByName", "")
    filters.nameFilter = nil;
    widget.setText("filterByInput", "")
    filters.inputNameFilter = nil;
    widget.setChecked("filterByHasIngredients", false)
    filters.ingredientsAvailable = false;
  end
  requestsToObject = {}
  completedInitialSetup = false
  enableDebug = nil
  currentTime = 0
  table.insert(filters.recipeFilters, hasRecipesFilter)
  table.insert(filters.recipeFilters, nameMatchesFilter)
  table.insert(filters.recipeFilters, inputNameMatchesFilter)
  table.insert(filters.recipeFilters, hasAvailableIngredients)
end

function uninit()
end

function update(dt)
  if(player == nil or player.id() == nil) then
    logDebug("No player, returning")
    return
  end
  ensureInitialSetup()
  updateRequests()
  applyFilters(dt)
end

------------------------- Initial Setup ---------------------------

function ensureInitialSetup()
  if(completedInitialSetup) then
    return;
  end
  
  updateDebugState();
  if(dataStore == nil) then
    local dataStoreResult = requestData("getDataStore", 0, nil);
    if(dataStoreResult ~= nil) then
      dataStore = dataStoreResult;
      updateIngredientCraftable();
      setupInitialFilterList();
      setupInitialIngredientList();
      setupInitialFoodList();
      logDebug("Initial load complete")
      completedInitialSetup = true;
    end
  end
end

function updateIngredientCraftable()
  for name,ingredient in pairs(dataStore.ingredientStore) do
    updateIsCraftable(ingredient)
  end
end

function setupInitialFilterList()
  ignoreFilterSelected = true
  methodFilterListItemIds = {}
  widget.clearListItems(FILTER_LIST_NAME)
  
  local hasFilters = false
  for idx,methodFilter in pairs(dataStore.sortedMethodFilters) do
    logDebug("Loading filter with id: " .. methodFilter.id .. " and name " .. methodFilter.name)
    local methodId, methodPath = addToList(FILTER_LIST_NAME, methodFilter)
    setFilterColor(methodPath, dataStore.methodFilters[methodFilter.id].isSelected)
    methodFilter.listId = methodId
    methodFilterListItemIds[methodFilter.id] = methodId
    hasFilters = true
  end
  
  if(hasFilters) then
    logDebug("Setting up hidden filter")
    --- Hidden filter for deselection ---
      local hiddenItem = { id = "hidden", name = "" }
      local hiddenId, hiddenPath = addToList(FILTER_LIST_NAME, hiddenItem)
      widget.setVisible(hiddenPath, false)
      methodFilterListItemIds[hiddenItem.id] = hiddenId
    ---
  end
  
  widget.setVisible(FILTER_LIST_EMPTY, not hasFilters)
  ignoreFilterSelected = false
end

function setupInitialFoodList()
  ignoreFoodSelected = true
  foodListItemIds = {}
  widget.clearListItems(FOOD_LIST_NAME)
  
  logDebug("Updating food list")
  local sortedFoodItems = sortedFoodItemsFromMethodFilters()
  
  local hasFoods = addToFoodItemsList(sortedFoodItems)
  widget.setVisible(FOOD_LIST_EMPTY, not hasFoods)
  ignoreFoodSelected = false
  
  if(not hasFoods) then
    setSelectedFoodId(nil)
    return
  end
  
  if(dataStore.selectedFoodId ~= nil) then
    if(not selectRecipeById(dataStore.selectedFoodId)) then
      logDebug("Selecting recipe with id: " .. dataStore.selectedFoodId)
      requestIngredientListUpdate()
    else
      logDebug("Failed to select recipe with id: " .. dataStore.selectedFoodId)
    end
  else
    logDebug("No selected recipe")
  end
end

function sortedFoodItemsFromMethodFilters()
  local recipeListItems = {}
  for filterName,methodFilter in pairs(dataStore.methodFilters) do
    logDebug("Using filter: " .. filterName)
    if(methodFilter.isSelected) then
      for foodName,foodItem in pairs(methodFilter.foods) do
        if(recipeListItems[foodName] == nil) then
          updateIsCraftable(foodItem)
          local passesFilters = true
          for idx,filter in ipairs(filters.recipeFilters) do
            if(not filter(foodItem)) then
              passesFilters = false
              break;
            end
          end
          if(passesFilters) then
            recipeListItems[foodName] = foodItem
          end
        end
      end
    end
  end
  return UtilsCN.sortByValueNameId(recipeListItems)
end

function addToFoodItemsList(sortedFoodItems)
  local hasFoods = false
  for idx,foodItem in ipairs(sortedFoodItems) do
    logDebug("Loading recipe with name: " .. foodItem.name)
    local itemId, itemPath = addToList(FOOD_LIST_NAME, foodItem, function(item) return item.displayName end)
    widget.setImage(itemPath .. ".itemIcon", foodItem.icon)
    widget.setData(itemPath, { id = foodItem.id })
    if(foodItem.isCraftable ~= nil and foodItem.isCraftable()) then
      widget.setVisible(itemPath .. ".notcraftableoverlay", false)
    else
      widget.setVisible(itemPath .. ".notcraftableoverlay", true)
    end
    foodListItemIds[foodItem.id] = itemId
    hasFoods = true
  end
  return hasFoods
end

function setupInitialIngredientList()
  widget.clearListItems(INGREDIENTS_LIST_NAME)
  widget.setVisible(INGREDIENTS_LIST_EMPTY, true)
end

function addToList(listName, item, getNameFunc)
  local name = nil;
  if(getNameFunc ~= nil) then
    name = getNameFunc(item)
  else
    name = item.name
  end
  if(name == nil and item.name == nil) then
    logDebug("Null name " .. item.id)
    return nil, nil
  end
  logDebug("Adding item " .. item.id)
  local listId = widget.addListItem(listName)
  local path = string.format("%s.%s", listName, listId)
  widget.setText(path .. ".itemName", name)
  widget.setData(path, { id = item.id })
  return listId, path
end

-----------------------------------------------------------------



--------------------------- Handlers ----------------------------

function updateRequests()
  if(not completedInitialSetup) then
    logDebug("Cannot update requests, initial setup not complete")
    return
  end
  if(#requests == 0) then
    return
  end
  
  logDebug("Requests found, handling")
  local activeRequests = {}
  for i = 1, #requests do
    if(requests[i] ~= nil and requests[i].active) then
      local isDone, result = requests[i].handle();
      if(isDone) then
        requests[i].active = false;
        requests[i].onCompleted(result);
      else
        table.insert(activeRequests, requests[i])
      end
    end
  end
  requests = activeRequests
  logDebug("Done with requests")
end

function applyFilters(dt)
  if(not completedInitialSetup) then
    logDebug("Cannot apply filters, initial setup not complete")
    return
  end
  if(not enableDelayedRecipeUpdate) then
    return
  end
  
  if(currentTime < updateBuffer) then
    currentTime = currentTime + dt
  else
    updateFoodList()
    currentTime = 0
    enableDelayedRecipeUpdate = false
  end
end

-----------------------------------------------------------------

function updateIsCraftable(foodItem)
  if(foodItem == nil or foodItem.recipes == nil) then
    return
  end
  for idx,recipe in ipairs(foodItem.recipes) do
    local canCraftRecipe = true
    for idx,input in ipairs(recipe.input) do
      local isCraftable, craftableCount = playerHasItems(input)
      input.isCraftable = isCraftable
      input.craftableCount = craftableCount
      if(not input.isCraftable) then
        canCraftRecipe = false
      end
    end
    recipe.isCraftable = canCraftRecipe;
  end
  foodItem.isCraftable = function()
    local canCraftFood = false
    for idx,recipe in ipairs(foodItem.recipes) do
      if(recipe.isCraftable) then
        canCraftFood = true
        break;
      end
    end
    return canCraftFood
  end
end

function playerHasItems(item)
  local result = player.hasCountOfItem(item)
  return result >= item.count, result
end

------------------------- Bread Crumb ---------------------------

-- TODO: Implement a bread crumb thing here
local breadCrumb = {}

-----------------------------------------------------------------



------------------------- Method Filters ------------------------

function hasRecipesFilter(item)
  return not UtilsCN.isEmpty(item.recipes)
end

function nameMatchesFilter(item)
  logDebug("Filtering name")
  if(filters.nameFilter == nil) then
    return true;
  end
  return containsSubString(item.name, filters.nameFilter) or containsSubString(item.id, filters.nameFilter)
end

function inputNameMatchesFilter(item)
  if(item.recipes == nil) then
    return false;
  end
  if(filters.inputNameFilter == nil) then
    return true;
  end
  local matches = false;
  for idx,recipe in ipairs(item.recipes) do
    for idxTwo,inputItem in ipairs(recipe.input) do
      local input = getItem(inputItem.name)
      if(input ~= nil and (containsSubString(input.name, filters.inputNameFilter) or containsSubString(input.id, filters.inputNameFilter))) then
        matches = true
        break;
      end
    end
    if(matches) then
      break;
    end
  end
  return matches;
end

function hasAvailableIngredients(item)
  if(filters.ingredientsAvailable == false) then
    return true;
  end
  if(item.isCraftable ~= nil and item.isCraftable()) then
    logDebug("Is Craft " .. item.id)
  else
    logDebug("No craft " .. item.id)
  end
  return item.isCraftable ~= nil and item.isCraftable()
end

function passesAllFilters(filters, val)
  local passesFilters = true;
  for idx, filter in ipairs(filters) do
    if(not filter(val)) then
      passesFilters = false;
      break;
    end
  end
  return passesFilters;
end


FILTER_LIST_NAME = "filterList.filterItemList"
FILTER_LIST_EMPTY = "filterList.empty"

function onFilterSelected()
  if(ignoreFilterSelected) then
    logDebug("Ignoring Filter Selection Change")
    return
  end
  local id, data = getSelectedItemData(FILTER_LIST_NAME)
  if(id == nil or data == nil or data.id == "hidden") then
    if(data.id == "hidden") then
      logDebug("Id was hidden")
    end
      logDebug("No data")
    return
  end
  logDebug("Filtering things: " .. data.id)
  local isSelected = toggleFilter(data.id)
  requestFilterSelectedUpdate(data.id, isSelected, nil)
  setFilterColor(id, isSelected)
  selectHiddenFilter()
  requestFoodListUpdate()
end

function setFilterColor(filterPath, isSelected)
  widget.setVisible(filterPath .. ".backgroundSelected", isSelected)
  widget.setVisible(filterPath .. ".backgroundUnselected", not isSelected)
  widget.setFontColor(filterPath .. ".itemName", isSelected and {0, 0, 0, 255} or {255, 255, 255, 255})
end

function toggleFilter(filterId)
  dataStore.methodFilters[filterId].isSelected = not dataStore.methodFilters[filterId].isSelected
  return dataStore.methodFilters[filterId].isSelected
end

function selectHiddenFilter()
  if(methodFilterListItemIds["hidden"] == nil) then
    logDebug("Attempted to select hidden filter, but it wasn't setup")
    return
  end
  widget.setListSelected(FILTER_LIST_NAME, methodFilterListItemIds["hidden"])
end

function updateFilterSelections()
  local bundledSelections = {}
  for name,methodFilter in pairs(dataStore.methodFilters) do
    if(methodFilterListItemIds[methodFilter.id] ~= nil) then
      local filterItemId = methodFilterListItemIds[methodFilter.id]
      local path = string.format("%s.%s", FILTER_LIST_NAME, filterItemId)
      table.insert(bundledSelections, { id = methodFilter.id, isSelected = methodFilter.isSelected })
      setFilterColor(path, methodFilter.isSelected)
    end
  end
  local handle = function(bundles)
    local done = {}
    return function()
      for idx,bundle in ipairs(bundles) do
        local result = requestData("updateSelectedFilters", bundle.id, nil, { id = bundle.id, isSelected = bundle.selected })
        if(result ~= nil) then
          table.insert(done, bundle)
        end
      end
      if(#done == #bundles) then
        return true, nil
      end
      return false, nil
    end
  end
  local onComplete = function(result)
    requestFoodListUpdate()
  end
  addRequest(handle(bundledSelections), onComplete)
end

function changeSelectedMethods(methods)
  if(UtilsCN.isEmpty(methods)) then
    return false
  end
  for name,methodFilter in pairs(dataStore.methodFilters) do
    if(methodFilter.id ~= "hidden") then
      methodFilter.isSelected = false
    end
  end
  for methodName,fn in pairs(methods) do
    dataStore.methodFilters[methodName].isSelected = true
  end
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
  if(not completedInitialSetup) then
    return
  end
  local didChange = false
  for name,methodFilter in pairs(dataStore.methodFilters) do
    if(methodFilter.isSelected ~= allSelected) then
      methodFilter.isSelected = allSelected
      didChange = true
    end
  end
  if(didChange) then
    updateFilterSelections()
    requestFoodListUpdate()
  end
end

-----------------------------------------------------------------



------------------------- Recipes -------------------------------

FOOD_LIST_NAME = "foodList.foodItemList"
FOOD_LIST_EMPTY = "foodList.empty"


function onFoodSelected()
  if(ignoreFoodSelected) then
    logDebug("Ignoring Recipe Selection Change")
    return
  end
  logDebug("Not ignoring recipe change")
  local id, data = getSelectedItemData(FOOD_LIST_NAME)
  if(id == nil or data == nil or data.id == nil) then
    logDebug("No data or id found")
    setSelectedFoodId(nil)
    requestIngredientListUpdate()
    return
  end
  setSelectedFoodId(data.id)
  requestIngredientListUpdate()
end

function updateFoodList()
  ignoreFoodSelected = true
  foodListItemIds = {}
  widget.clearListItems(FOOD_LIST_NAME)
  widget.setVisible(FOOD_LIST_EMPTY, false)
  
  logDebug("Updating food list")
  local sortedFoodItems = sortedFoodItemsFromMethodFilters()
  
  local hasFoods = addToFoodItemsList(sortedFoodItems)
  widget.setVisible(FOOD_LIST_EMPTY, not hasFoods)
  ignoreFoodSelected = false
  
  if(not hasFoods) then
    setSelectedFoodId(nil)
    requestIngredientListUpdate()
    return
  end
  
  if(dataStore.selectedFoodId ~= nil) then
    if(not selectRecipeById(dataStore.selectedFoodId)) then
      logDebug("Selecting recipe with id: " .. dataStore.selectedFoodId)
      requestIngredientListUpdate()
    else
      logDebug("Failed to select recipe with id: " .. dataStore.selectedFoodId)
    end
  else
    logDebug("No selected recipe")
  end
end

function formatMethods(methods)
  if(UtilsCN.isEmpty(methods)) then
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

function setSelectedFoodId(id)
  dataStore.selectedFoodId = id
  requestSelectedIdUpdate(id)
end

function selectRecipeById(foodId)
  if(foodListItemIds[foodId] ~= nil) then
    logDebug("Selecting food with id: " .. foodId)
    widget.setListSelected(FOOD_LIST_NAME, foodListItemIds[foodId])
    return true
  end
  return false
end

-----------------------------------------------------------------



----------------------- Ingredients -----------------------------

local ignoreIngredientSelected = false

INGREDIENT_HEADER_BACKGROUD = "/interface/crafting/MFM/shared/craftableheaderbackgroundMFM.png"

INGREDIENTS_LIST_NAME = "ingredientList.ingredientItemList"
INGREDIENTS_LIST_EMPTY = "ingredientList.empty"

function onIngredientSelected()
  if(ignoreFoodSelected or ignoreIngredientSelected) then
    logDebug("Ignoring Ingredient Selection Change")
    return
  end
  local id, data = getSelectedItemData(INGREDIENTS_LIST_NAME)
  if(id == nil or data == nil) then
    return
  end
  --- Selected a recipe header, deselect by selecting hidden list item
  if(data.isHeader) then
    return
  end
  --- Recipe to select has already been selected
  if(dataStore.selectedFoodId == data.id) then
    logDebug("Recipe already selected, skipping reload")
    return
  end
  requestFoodSelect(data.id, data.methods)
end

function updateIngredientList()
  logDebug("Updating ingredient list")
  ignoreIngredientSelected = true
  widget.clearListItems(INGREDIENTS_LIST_NAME)
  local selectedFoodId = dataStore.selectedFoodId
  if(selectedFoodId == nil) then
    widget.setVisible(INGREDIENTS_LIST_EMPTY, true)
    ignoreIngredientSelected = false
    return
  end
  logDebug("Selected food was: " .. selectedFoodId)
  local selectedFood = dataStore.ingredientStore[selectedFoodId]
  if(selectedFood == nil or selectedFood.recipes == nil) then
    logDebug("No recipes found: " .. (selectedFoodId or "none"))
    widget.setVisible(INGREDIENTS_LIST_EMPTY, true)
    ignoreIngredientSelected = false
    return
  end
  widget.setVisible(INGREDIENTS_LIST_EMPTY, false)
  
  local hasIngredients = false
  local recipeHeaderItems = {}
  local currentRecipeIdx = 1
  
  for idx,recipe in ipairs(selectedFood.recipes) do
    if(recipe ~= nil) then
      printTable(recipe)
    end
    
    local outputFoodItem = getItem(recipe.output.name)
    local recipeHeaderItem = { id = outputFoodItem.id, name = "RECIPE " .. currentRecipeIdx .. ":" .. formatMethods(recipe.methods), isHeader = true, isCraftable = recipe.isCraftable, count = recipe.output.count, icon = "", methods = outputFoodItem.methods }
    currentRecipeIdx = currentRecipeIdx + 1
    local headerChildren = {}
    
    for idxTwo,inputItem in ipairs(recipe.input) do
      local item = getItem(inputItem.name)
      item.count = inputItem.count
      item.isHeader = false
      item.isCraftable = inputItem.isCraftable
      item.craftableCount = inputItem.craftableCount
      logDebug("Has ingredient " .. item.id)
      if(dataStore.ingredientStore[item.id] ~= nil) then
        item.methods = dataStore.ingredientStore[item.id].methods
      else
        item.methods = {}
      end
      table.insert(headerChildren, item)
      hasIngredients = true
    end
  
    table.sort(headerChildren, function(a, b)
      if a.name < b.name then return true end
      if a.name > b.name then return false end
      return a.id < b.id
    end)
    
    local recipeHeaderChildren = {}
    
    for idxThree,ingredListItem in ipairs(headerChildren) do
      table.insert(recipeHeaderChildren, ingredListItem)
    end
    
    recipeHeaderItem.children = recipeHeaderChildren
    
    if(hasIngredients) then
      table.insert(recipeHeaderItems, recipeHeaderItem)
    end
  end
  
  --table.sort(recipeHeaderItems, function(a, b)
  --  return a.count > b.count
  --end)

  local itemHeader = {
    id = "itemHeader",
    name = selectedFood.displayName,
    icon = selectedFood.icon,
    isCraftable = true,
    isHeader = true,
    children = {}
  }
  table.insert(recipeHeaderItems, 1, itemHeader)
  
  for idx,recipeHeader in ipairs(recipeHeaderItems) do
    logDebug("Has header")
    local headerId, headerPath = addToList(INGREDIENTS_LIST_NAME, recipeHeader)
    
    widget.setImage(headerPath .. ".selectedBackground", "")
    widget.setImage(headerPath .. ".unselectedBackground", INGREDIENT_HEADER_BACKGROUD)
    widget.setVisible(headerPath .. ".selectedBackground", false)
    widget.setVisible(headerPath .. ".unselectedBackground", true)
    if(recipeHeader.count ~= nil) then
      widget.setText(headerPath .. ".countLabel", "Output:\n" .. recipeHeader.count)
    end
    
    widget.setData(headerPath, { id = recipeHeader.id, methods = recipeHeader.methods, isHeader = true })
    widget.setImage(headerPath .. ".itemIcon", recipeHeader.icon)
    
    if(recipeHeader.isCraftable) then
      widget.setVisible(headerPath .. ".notcraftableoverlay", false)
    else
      widget.setVisible(headerPath .. ".notcraftableoverlay", true)
    end
    
    local path
    for idxTwo,headerChildItem in ipairs(recipeHeader.children) do
      path = string.format("%s.%s", INGREDIENTS_LIST_NAME, widget.addListItem(INGREDIENTS_LIST_NAME))
      widget.setVisible(path .. ".selectedBackground", false)
      widget.setVisible(path .. ".unselectedBackground", true)
      widget.setText(path .. ".itemName", headerChildItem.name)
      local countText = ""
      if(headerChildItem.craftableCount ~= nil) then
        countText = headerChildItem.craftableCount .. "/" .. headerChildItem.count
      else
        countText =  "0/" .. headerChildItem.count
      end
      widget.setText(path .. ".countLabel", "Input:\n" .. countText)
      widget.setData(path, { id = headerChildItem.id, methods = headerChildItem.methods, isHeader = false })
      if(headerChildItem.icon ~= nil) then
        widget.setImage(path .. ".itemIcon", headerChildItem.icon)
        widget.setVisible(path .. ".itemIcon", true)
      else
        logDebug("No icon: " .. headerChildItem.name)
        widget.setVisible(path .. ".itemIcon", false)
      end
      if(headerChildItem.isCraftable) then
        widget.setVisible(path .. ".notcraftableoverlay", false)
      else
        widget.setVisible(path .. ".notcraftableoverlay", true)
      end
    end
  end
  
  if(hasIngredients) then
    logDebug("Has ingredients")
  else
    logDebug("No ingredients")
    widget.clearListItems(INGREDIENTS_LIST_NAME)
  end
  
  widget.setVisible(INGREDIENTS_LIST_EMPTY, not hasIngredients)
  ignoreIngredientSelected = false
end

function getItem(itemId)
  if(dataStore.ingredientStore[itemId] ~= nil) then
    return dataStore.ingredientStore[itemId]
  end
  local item = { id = itemId, name = itemId, icon = "", recipes = {}, isCraftable = function() end }
  requestStoreIngredient(itemId, item)
  return item
end

-----------------------------------------------------------------



------------------------- Filters --------------------------

function filterByName(id)
  local nameFilter = widget.getText(id)
  if(nameFilter == nil or nameFilter == "") then
    filters.nameFilter = nil
  else
    
    filters.nameFilter = nameFilter
  end
  logDebug("Filtering by name")
  currentTime = 0
  enableDelayedRecipeUpdate = true
end

function filterByInput(id)
  local inputNameFilter = widget.getText(id)
  if(inputNameFilter == nil or inputNameFilter == "") then
    filters.inputNameFilter = nil
  else
    filters.inputNameFilter = inputNameFilter;
  end
  logDebug("Filtering by input name")
  currentTime = 0;
  enableDelayedRecipeUpdate = true
end

function filterByHasIngredients(id)
  local enableFilter = widget.getChecked(id)
  if(enableFilter) then
    logDebug("Doing filter")
  else
    logDebug("Not doing filter")
  end
  filters.ingredientsAvailable = enableFilter
  requestFoodListUpdate()
end

-----------------------------------------------------------------



------------------------- Debug ---------------------------------

function logDebug(msg)
  if(enableDebug) then
    sb.logInfo("[RBGUI] " .. msg)
  end
end

function toggleDebug()
  local toEnable = widget.getChecked("toggleDebug")
  enableDebug = toEnable
  world.sendEntityMessage(pane.sourceEntity(), "setDebugState", toEnable)
  if(toEnable) then
    sb.logInfo("[RBGUI] Debug is enabled")
  else
    sb.logInfo("[RBGUI] Debug is disabled")
  end
end

function updateDebugState()
  if(debugStateUpdated or enableDebug ~= nil) then
    return
  end
  local enableDebugResult = requestData("getDebugState", 0, nil)
  if(enableDebugResult ~= nil) then
    enableDebug = enableDebugResult.debugState
    widget.setChecked("toggleDebug", enableDebug)
    debugStateUpdated = true
  end
end

function printTable(tabVal, previousName)
  if(not enableDebug) then
    return
  end
  for name,val in pairs(tabVal) do
    if(type(val) == "table") then
      printTable(val, (previousName or "") .. " " .. name)
    else
      if (val == true) then
        logDebug((previousName or "") .. " Name " .. name .. " val true")
      elseif (val == false) then
        logDebug((previousName or "") .. " Name " .. name .. " val false")
      else
        logDebug((previousName or "") .. " Name " .. name .. " val " .. val)
      end
    end
  end
end

-----------------------------------------------------------------



------------------------- Requests ------------------------------

function requestFoodSelect(id, methods)
  setSelectedFoodId(id)
  if(id == nil or methods == nil) then
    return
  end
  --- Select recipe if it is already visible
  if(selectRecipeById(id)) then
    return
  end
  --- Recipe wasn't visible, so change filters to ensure it is and update recipe list
  local success = changeSelectedMethods(methods)
  if(not success) then
    return
  end
  filters.clear()
  requestFoodListUpdate()
end

function requestFoodListUpdate()
  updateFoodList()
end

function requestIngredientListUpdate()
  updateIngredientList()
end

function requestStoreIngredient(itemId, defaultItem)
  local handle = function(id, defaultIt)
    return function()
      local result = requestData("storeIngredient", id, defaultIt, id)
      if(result ~= nil) then
        logDebug("Loaded item: " .. id)
        return true, result
      end
      return false, nil
    end
  end
  local onComplete = function(id, defaultIt)
    return function(result)
      if(result == nil) then
        logDebug("No result, so returning")
        return;
      end
      logDebug("Updating ingredient store with: " .. id)
      dataStore.ingredientStore[id] = (result or defaultIt)
      updateIsCraftable(dataStore.ingredientStore[id])
      requestIngredientListUpdate()
    end
  end
  addRequest(handle(itemId, defaultItem), onComplete(itemId, defaultItem))
end

function requestFilterSelectedUpdate(filterId, isSelected)
  local handle = function(id, selected)
    return function()
      local result = requestData("updateSelectedFilters", id, nil, { id = id, isSelected = selected })
      if(result ~= nil) then
        logDebug("Loaded item: " .. id)
        return true, nil
      end
      return false, nil
    end
  end
  addRequest(handle(filterId, isSelected), nil)
end

function requestSelectedIdUpdate(foodId)
  local handle = function(id)
    return function()
      id = id or "none"
      local result = requestData("updateSelectedId", id, nil, id)
      if(result ~= nil) then
        logDebug("Selected item: " .. id)
        return true, nil
      end
      return false, nil
    end
  end
  local onComplete = function(id)
    return function(result)
      selectRecipeById(id)
    end
  end
  addRequest(handle(foodId), onComplete(foodId))
end

function addRequest(handle, onCompleted)
  if(onCompleted == nil) then
    onCompleted = function(result) end
  end
  table.insert(requests, {
    active = true,
    handle = handle,
    onCompleted = onCompleted
  });
end

-----------------------------------------------------------------



------------------------- Utility -------------------------------

function getSelectedItemData(listName)
  local selectedItem = widget.getListSelected(listName)
  if(selectedItem == nil) then
    return nil, nil
  end
  local id = string.format("%s.%s", listName, selectedItem)
  return id, widget.getData(id)
end

function containsSubString(one, two)
  return string.match(string.lower(one), string.lower(two))
end

function requestData(requestName, requestId, defaultResponse, data)
  local requestIdentifier = requestName .. requestId
  local request = requestsToObject[requestIdentifier]
  if(request == nil) then
    if(data ~= nil) then
      requestsToObject[requestIdentifier] = world.sendEntityMessage(pane.sourceEntity(), requestName, data)
    else
      requestsToObject[requestIdentifier] = world.sendEntityMessage(pane.sourceEntity(), requestName)
    end
    request = requestsToObject[requestIdentifier]
  end
  if(not request:finished()) then
    logDebug("Request not finished: " .. requestIdentifier)
    return nil
  end
  if(not request:succeeded()) then
    local errorMsg = request:error()
    if(errorMsg ~= nil) then
      sb.logError(errorMsg .. " the message was '" .. requestIdentifier .. "'")
      hasError = true
    end
    logDebug("Request failed: " .. requestIdentifier)
    requestsToObject[requestIdentifier] = nil
    return defaultResponse
  end
  local result = request:result()
  if(not result) then
    return defaultResponse
  end
  logDebug("Finished request: " .. requestIdentifier)
  requestsToObject[requestIdentifier] = nil
  return result
end

-----------------------------------------------------------------
