require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"
require "/scripts/MFM/entityQueryAPI.lua"

RBMFMGui = {}


------------------------- Bread Crumb ---------------------------

-- TODO: Implement a bread crumb thing here
local breadCrumb = {}

----------------------- Properties ------------------------------

local logger = nil

local filters = {
    nameFilter = nil,
    inputNameFilter = nil,
    methodNameFilter = nil,
    ingredientsAvailable = false,
    recipeFilters = {}
  }
local methodFilterListItemIds = nil
local itemListItemIds = nil
local sourceEntityId = nil
local ignoreFilterSelected = false
local ignoreItemSelected = false
local ignoreIngredientSelected = false
local dataStore = nil;

local initialized = false;
local filterData = nil;
local selectedItem = nil;

RECIPE_BOOK_FRAME_NAME = "recipeBookFrame"

FILTER_BY_NAME_NAME = RECIPE_BOOK_FRAME_NAME .. ".filterByName"
FILTER_BY_INPUT_NAME = RECIPE_BOOK_FRAME_NAME .. ".filterByInput"
FILTER_BY_HAS_INGREDIENTS_NAME = RECIPE_BOOK_FRAME_NAME .. ".filterByHasIngredients"

TOGGLE_DEBUG_NAME = "toggleDebug"

FILTER_LIST_NAME = RECIPE_BOOK_FRAME_NAME .. ".filterList.filterItemList"
FILTER_LIST_EMPTY = RECIPE_BOOK_FRAME_NAME .. ".filterList.empty"

ITEM_LIST_NAME = RECIPE_BOOK_FRAME_NAME .. ".itemList.itemList"
ITEM_LIST_EMPTY = RECIPE_BOOK_FRAME_NAME .. ".itemList.empty"
ITEM_LIST_NO_RECIPE_BOOK = RECIPE_BOOK_FRAME_NAME .. ".itemList.norecipebook"

INGREDIENT_HEADER_BACKGROUD = "/interface/scripted/shared/MFM/craftableheaderbackgroundMFM.png"

INGREDIENTS_LIST_NAME = RECIPE_BOOK_FRAME_NAME .. ".ingredientList.ingredientItemList"
INGREDIENTS_LIST_EMPTY = RECIPE_BOOK_FRAME_NAME .. ".ingredientList.empty"
INGREDIENTS_LIST_NO_RECIPE_BOOK = RECIPE_BOOK_FRAME_NAME .. ".ingredientList.norecipebook"

-----------------------------------------------------------------


------------------------- Debug ---------------------------------

function toggleDebug()
  if(sourceEntityId == nil) then
    logger.logError("Failed to toggle debug, sourceEntityId is nil")
    return
  end
  local toEnable = widget.getChecked(TOGGLE_DEBUG_NAME)
  logger.setDebugState(toEnable)
  world.sendEntityMessage(sourceEntityId, "setDebugState", toEnable)
end

function RBMFMGui.updateDebugState()
  local handle = function()
    local result = EntityQueryAPI.requestData(sourceEntityId, "getDebugState", 0, nil)
    if(result ~= nil) then
      return true, result
    end
    return false, nil
  end
  
  local onCompleted = function(result)
    local debugState = result.debugState
    logger.setDebugState(debugState)
    widget.setChecked(TOGGLE_DEBUG_NAME, debugState)
  end
  
  EntityQueryAPI.addRequest("RGMFMGui.updateDebugState", handle, onCompleted)
end

-------------------------------------------------------------------

------------------------- Vanilla hooks ---------------------------

function init()
  if(pane.containerEntityId) then
    RBMFMGui.init(pane.containerEntityId())
  elseif(pane.sourceEntity) then
    RBMFMGui.init(pane.sourceEntity())
  else
    RBMFMGui.init(nil)
  end
end

function uninit()
  EntityQueryAPI.uninit()
end

function update(dt)
  RBMFMGui.update(dt)
end

function RBMFMGui.init(entityId)
  logger = DebugUtilsCN.init("[RBMFMGUI]")
  EntityQueryAPI.init()
  sourceEntityId = entityId
  filters.clear = function()
    widget.setText(FILTER_BY_NAME_NAME, "")
    filters.nameFilter = nil;
    widget.setText(FILTER_BY_INPUT_NAME, "")
    filters.inputNameFilter = nil;
    filters.methodNameFilter = nil
    widget.setChecked(FILTER_BY_HAS_INGREDIENTS_NAME, false)
    filters.ingredientsAvailable = false;
  end
  table.insert(filters.recipeFilters, hasRecipesFilter)
  table.insert(filters.recipeFilters, nameMatchesFilter)
  table.insert(filters.recipeFilters, methodNamesMatchFilters)
  table.insert(filters.recipeFilters, inputNameMatchesFilter)
  table.insert(filters.recipeFilters, hasAvailableIngredients)
end

function RBMFMGui.update(dt)
  if(not EntityQueryAPI.update(dt)) then
    return
  end
  if(player == nil or player.id() == nil) then
    logger.logDebug("No player, returning")
    return
  end
  if(not initialized) then
    requestFilterData();
    RBMFMGui.updateDebugState();
    initialized = true;
  end
end

-------------------------------------------------------------------

-------------------------------------------------------------------

function requestFilterData()
  local handle = function()
    local result = EntityQueryAPI.requestData(sourceEntityId, "getFilterData", 0)
    if(result ~= nil) then
      logger.logDebug("Loaded filter data")
      return true, result
    end
    return false, nil
  end
  local onComplete = function(result)
    if(result == nil) then
      logger.logDebug("No filter data, so returning")
      return;
    end
    updateFilterDisplay(result);
    requestSelectedItem()
  end
  EntityQueryAPI.addRequest("requestFilterData", handle, onComplete)
end

function requestSelectedItem()
  logger.logDebug("Requesting selected item")
  local handle = function()
    local result = EntityQueryAPI.requestData(sourceEntityId, "getSelectedItem", 0, nil)
    if(result == true) then
      return true, nil;
    elseif(result ~= nil) then
      logger.logDebug("Loaded selected item: " .. result.id);
      return true, result;
    end
    return false, nil;
  end
  local onComplete = function(result)
    selectedItem = result;
    requestRecipesForSelectedFilters();
  end
  EntityQueryAPI.addRequest("requestSelectedItem", handle, onComplete)
end

function getSelectedFilterIds()
  local selectedFilterIds = {};
  for filterName, filterData in pairs(filterData) do
    if(filterData.isSelected) then
      table.insert(selectedFilterIds, filterName);
    end
  end
  return selectedFilterIds;
end

function requestRecipesForSelectedFilters()
  local selectedFilterIds = getSelectedFilterIds();
  logger.logDebug("Requesting recipes for selected filters")
  local handle = function()
    local result = EntityQueryAPI.requestData(sourceEntityId, "getRecipesForMethodNames", 0, nil, selectedFilterIds)
    if(result ~= nil) then
      logger.logDebug("Loaded selected filter data")
      return true, result;
    end
    return false, nil;
  end
  local onComplete = function(result)
    if(result == nil) then
      return;
    end
    updateRecipeBookDisplay(result)
  end
  EntityQueryAPI.addRequest("requestRecipesForSelectedFilters", handle, onComplete)
end

function updateFilterDisplay(filterDisplayData)
  filterData = filterDisplayData;
  ignoreFilterSelected = true
  methodFilterListItemIds = {}
  widget.clearListItems(FILTER_LIST_NAME)
  
  local hasFilters = false
  for filterName, filterInfo in pairs(filterDisplayData) do
    logger.logDebug("Loading filter with id: " .. filterInfo.id .. " and name " .. filterInfo.name)
    local methodId, methodPath = addToList(FILTER_LIST_NAME, filterInfo)
    setFilterColor(methodPath, filterInfo.isSelected)
    filterInfo.listId = methodId
    methodFilterListItemIds[filterInfo.id] = methodId
    hasFilters = true
  end
  
  if(hasFilters) then
    logger.logDebug("Setting up hidden filter")
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

function updateRecipeBookDisplay(recipes)
  ignoreItemSelected = true
  widget.clearListItems(INGREDIENTS_LIST_NAME)
  widget.setVisible(INGREDIENTS_LIST_EMPTY, true)
  itemListItemIds = {}
  widget.clearListItems(ITEM_LIST_NAME)
  local sortedItems = sortFilterRecipes(recipes);
  
  local hasItems = false
  for itemName, itemData in pairs(sortedItems) do
    logger.logDebug("Adding item to UI: " .. itemData.id);
    local itemId, itemPath = addToList(ITEM_LIST_NAME, itemData, function(item) return item.displayName end)
    widget.setImage(itemPath .. ".itemIcon", itemData.icon)
    widget.setData(itemPath, { id = itemData.id })
    if(itemData.isCraftable ~= nil and itemData.isCraftable()) then
      widget.setVisible(itemPath .. ".notcraftableoverlay", false)
    else
      widget.setVisible(itemPath .. ".notcraftableoverlay", true)
    end
    itemListItemIds[itemData.id] = itemId
    hasItems = true
  end
  
  widget.setVisible(ITEM_LIST_EMPTY, not hasItems)
  ignoreItemSelected = false
  if(not hasItems or (selectedItem ~= nil and itemListItemIds[selectedItem.id] == nil)) then
    selectedItem = nil;
  end
  
  if(hasItems) then
    if(selectedItem ~= nil) then
      widget.setListSelected(ITEM_LIST_NAME, itemListItemIds[selectedItem.id] .. "")
    end
  end
  
  if(not hasItems or selectedItem == nil) then
    selectItem(nil);
    return
  end
end

function sortFilterRecipes(recipes)
  local recipeListItems = {}
  for filterName, filterRecipes in pairs(recipes) do
    for itemName, itemInfo in pairs(filterRecipes.recipesCraftTo) do
      logger.logDebug("Checking item: " .. itemName)
      if(recipeListItems[itemName] == nil) then
        updateIsCraftable(itemInfo)
        local passesFilters = true
        for idx,filter in ipairs(filters.recipeFilters) do
          if(not filter(itemInfo)) then
            logger.logDebug("Item does not match filters: " .. idx .. "  " .. itemName)
            passesFilters = false
            break;
          end
        end
        if(passesFilters) then
          logger.logDebug("Item passed")
          recipeListItems[itemName] = itemInfo
        end
      else
        logger.logDebug("Already checked item")
      end
    end
  end
  return UtilsCN.sortByValueNameId(recipeListItems)
end

function onFilterSelected()
  if(ignoreFilterSelected) then
    logger.logDebug("Ignoring Filter Selection Change")
    return
  end
  local id, data = getSelectedItemData(FILTER_LIST_NAME)
  if(id == nil or data == nil or data.id == "hidden") then
    if(data.id == "hidden") then
      logger.logDebug("Id was hidden")
    end
      logger.logDebug("No data")
    return
  end
  logger.logDebug("Filtering things: " .. data.id)
  requestToggleFilterSelected(data.id);
  selectHiddenFilter();
end

function requestToggleFilterSelected(filterId)
  local handle = function(id)
    return function()
      local result = EntityQueryAPI.requestData(sourceEntityId, "toggleFilterSelected", id, nil, id)
      if(result ~= nil) then
        logger.logDebug("Toggled filter: " .. id)
        return true, result
      end
      return false, result
    end
  end
  local onComplete = function(result)
    requestFilterData();
  end
  EntityQueryAPI.addRequest("requestToggleFilterSelected", handle(filterId), onComplete)
end

function setFilterColor(filterPath, isSelected)
  widget.setVisible(filterPath .. ".backgroundSelected", isSelected)
  widget.setVisible(filterPath .. ".backgroundUnselected", not isSelected)
  widget.setFontColor(filterPath .. ".itemName", isSelected and {0, 0, 0, 255} or {255, 255, 255, 255})
end

function selectItem(itemId)
  local handle = function(id)
    return function()
      local result = EntityQueryAPI.requestData(sourceEntityId, "selectItem", 0, nil, id)
      if(result == true) then
        logger.logDebug("Item selected, returning")
        return true, result;
      elseif(result ~= nil) then
        logger.logDebug("Selected item with id: " .. result.id)
        return true, result;
      end
      return false, nil
    end
  end
  local onComplete = function(id)
    return function(result)
      if(result == true) then
        logger.logDebug("Selected item was true")
        updateIngredientDisplay(nil);
        return;
      end
      if(result == nil) then
        logger.logDebug("No selected item data, so returning")
        return;
      end
      ignoreItemSelected = true;
      if(id ~= nil and itemListItemIds[id] ~= nil) then
        widget.setListSelected(ITEM_LIST_NAME, itemListItemIds[id] .. "");
      end
      ignoreItemSelected = false;
      updateIngredientDisplay(result);
    end
  end
  EntityQueryAPI.addRequest("requestSelectItem" .. (itemId or "none"), handle(itemId), onComplete(itemId))
end

function updateIngredientDisplay(itemData)
  widget.clearListItems(INGREDIENTS_LIST_NAME)
  widget.setVisible(INGREDIENTS_LIST_EMPTY, true)
  selectedItem = itemData;
  if(selectedItem == nil) then
    widget.setVisible(INGREDIENTS_LIST_EMPTY, true)
    return;
  end
  local selectedItemData = selectedItem.data;
  updateIsCraftable(selectedItemData)
  if(selectedItemData == nil or selectedItemData.recipes == nil) then
    logger.logDebug("No recipes found: " .. (selectedItem.id or "none"))
    widget.setVisible(INGREDIENTS_LIST_EMPTY, true)
    return
  end
  logger.logDebug("Selected item was: " .. selectedItem.id)
  
  widget.setVisible(INGREDIENTS_LIST_EMPTY, false)
  
  local hasIngredients = false
  local recipeHeaderItems = {}
  local currentRecipeIdx = 1
  
  for idx,recipe in ipairs(selectedItemData.recipes) do
    local outputItem = recipe.output
    local recipeHeaderItem = { id = outputItem.id, displayName = "RECIPE " .. currentRecipeIdx .. ":" .. recipe.displayMethods, isHeader = true, isCraftable = recipe.isCraftable, count = outputItem.count, icon = "", methods = outputItem.methods }
    local headerChildren = {}
    local methodMatches = false
    if(filters.methodNameFilter == nil) then
      methodMatches = true
    else
      for methodName,methodFriendlyName in ipairs(recipe.methods) do
        if(containsSubString(methodName, filters.methodNameFilter)) then
          methodMatches = true
        end
      end
    end
    if(methodMatches) then
      for inputName,inputData in pairs(recipe.input) do
        if(inputData.icon == nil) then
          requestRefreshRecipes(outputItem.name);
        end
        local item = {
          id = (inputData.id or inputName),
          displayName = inputData.displayName,
          count = inputData.count,
          icon = inputData.icon,
          methods = inputData.methods,
          isHeader = false,
          isCraftable = inputData.isCraftable,
          craftableCount = inputData.craftableCount
        };
        logger.logDebug("Has ingredient " .. item.id)
        table.insert(headerChildren, item)
        hasIngredients = true
      end
    
      table.sort(headerChildren, function(a, b)
        if a.displayName < b.displayName then return true end
        if a.displayName > b.displayName then return false end
        return a.id < b.id
      end)
      
      recipeHeaderItem.children = headerChildren
      
      if(hasIngredients) then
        table.insert(recipeHeaderItems, recipeHeaderItem)
        currentRecipeIdx = currentRecipeIdx + 1
      end
    end
  end

  local itemHeader = {
    id = "itemHeader",
    displayName = selectedItemData.displayName,
    icon = selectedItemData.icon,
    isCraftable = true,
    isHeader = true,
    children = {}
  };
  table.insert(recipeHeaderItems, 1, itemHeader)
  
  for idx,recipeHeader in ipairs(recipeHeaderItems) do
    logger.logDebug("Has header: " .. idx)
    logger.logDebug("Checking item with id " .. (recipeHeader.id or recipeHeader.displayName))
    local headerId, headerPath = addToList(INGREDIENTS_LIST_NAME, recipeHeader, function(item) return item.displayName end)
    
    widget.setImage(headerPath .. ".selectedBackground", "")
    widget.setImage(headerPath .. ".unselectedBackground", INGREDIENT_HEADER_BACKGROUD)
    widget.setVisible(headerPath .. ".selectedBackground", false)
    widget.setVisible(headerPath .. ".unselectedBackground", true)
    if(recipeHeader.count ~= nil) then
      widget.setText(headerPath .. ".countLabel", "Output:\n" .. recipeHeader.count)
    end
    
    widget.setData(headerPath, { id = recipeHeader.id, methods = recipeHeader.methods, isHeader = true })
    if(recipeHeader.icon ~= nil) then
      widget.setImage(headerPath .. ".itemIcon", recipeHeader.icon)
    end
    
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
      widget.setText(path .. ".itemName", headerChildItem.displayName)
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
        logger.logDebug("No icon: " .. headerChildItem.displayName)
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
    logger.logDebug("Has ingredients")
  else
    logger.logDebug("No ingredients")
    widget.clearListItems(INGREDIENTS_LIST_NAME)
  end
  
  widget.setVisible(INGREDIENTS_LIST_EMPTY, not hasIngredients)
end

function onItemSelected()
  if(ignoreItemSelected) then
    logger.logDebug("Ignoring Item Selection Change")
    return
  end
  logger.logDebug("Not ignoring item selection change")
  local id, data = getSelectedItemData(ITEM_LIST_NAME)
  if(id == nil or data == nil or data.id == nil) then
    logger.logDebug("No data or id found")
    selectItem(nil)
    return
  end
  selectItem(data.id)
end

function addToList(listName, item, getNameFunc)
  local name = nil;
  if(getNameFunc ~= nil) then
    name = getNameFunc(item)
  else
    name = item.name
  end
  if(name == nil) then
    if(item.id ~= nil) then
      logger.logDebug("Null name " .. item.id)
    end
    return nil, nil
  end
  logger.logDebug("Adding item " .. name)
  local listId = widget.addListItem(listName)
  local path = string.format("%s.%s", listName, listId)
  widget.setText(path .. ".itemName", name)
  widget.setData(path, { id = item.id })
  return listId, path
end

function requestRefreshRecipes(itemId)
  local handle = function(id)
    return function()
      local result = EntityQueryAPI.requestData(sourceEntityId, "refreshRecipes", 0, nil, id)
      if(result ~= nil or result == true) then
        logger.logDebug("Refreshed item recipes with id: " .. id)
        return true, result;
      end
      return false, nil
    end
  end
  local onComplete = function(result)
    if(result == nil) then
      logger.logDebug("Failed to return.")
      return;
    end
    if(result == true) then
      requestRecipesForSelectedFilters();
    end
  end
  EntityQueryAPI.addRequest("requestRefreshRecipes" .. (itemId or "none"), handle(itemId), onComplete)
end

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

function updateIsCraftable(item)
  if(item == nil or item.recipes == nil) then
    return
  end
  for idx,recipe in ipairs(item.recipes) do
    local canCraftRecipe = true
    for inputName,inputData in pairs(recipe.input) do
      local isCraftable, craftableCount = playerHasItems({ name = inputName, count = inputData.count })
      inputData.isCraftable = isCraftable
      inputData.craftableCount = craftableCount
      if(not inputData.isCraftable) then
        canCraftRecipe = false
      end
    end
    recipe.isCraftable = canCraftRecipe;
  end
  item.isCraftable = function()
    local canCraftItem = false
    for idx,recipe in ipairs(item.recipes) do
      if(recipe.isCraftable) then
        canCraftItem = true
        break;
      end
    end
    return canCraftItem
  end
end

function playerHasItems(item)
  local result = player.hasCountOfItem(item)
  return result >= item.count, result
end

-----------------------------------------------------------------

function onIngredientSelected()
  if(ignoreItemSelected or ignoreIngredientSelected) then
    logger.logDebug("Ignoring Ingredient Selection Change")
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
  if(selectedItem ~= nil and selectedItem.id == data.id) then
    logger.logDebug("Recipe already selected, skipping reload")
    return
  end
  if(data.methods == nil) then
    return;
  end
  local methods = {};
  for methodName, methodData in pairs(data.methods) do
    table.insert(methods, methodName);
  end
  requestSetSelectFilters(methods)
  selectItem(data.id)
end

function requestSetSelectFilters(filterIds)
  local handle = function(fIds)
    return function()
      local result = EntityQueryAPI.requestData(sourceEntityId, "setSelectedFilters", 0, nil, fIds)
      if(result ~= nil) then
        logger.logDebug("Set Selected Filters")
        return true, result;
      end
      return false, nil
    end
  end
  local onComplete = function(result)
    if(result == nil) then
      logger.logDebug("Failed to return filter data.")
      return;
    end
    updateFilterDisplay(result);
    requestSelectedItem()
  end
  EntityQueryAPI.addRequest("requestSetSelectFilters", handle(filterIds), onComplete)
end

function selectHiddenFilter()
  if(methodFilterListItemIds["hidden"] == nil) then
    logger.logDebug("Attempted to select hidden filter, but it wasn't setup")
    return
  end
  widget.setListSelected(FILTER_LIST_NAME, methodFilterListItemIds["hidden"])
end

function selectAllFilters()
  local filterIds = {};
  for filterName, filterInfo in pairs(filterData) do
    table.insert(filterIds, filterName);
  end
  requestSetSelectFilters(filterIds);
end

function unselectAllFilters()
  requestSetSelectFilters({});
end


------------------------ Filters --------------------------

function hasRecipesFilter(item)
  return not UtilsCN.isEmpty(item.recipes)
end

function nameMatchesFilter(item)
  if(filters.nameFilter == nil) then
    return true;
  end
  --logger.logDebug("Filtering name with value: " .. filters.nameFilter)
  return containsSubString(item.displayName, filters.nameFilter) or containsSubString(item.id, filters.nameFilter)
end

function inputNameMatchesFilter(item)
  if(item.recipes == nil) then
    logger.logDebug("No recipes!")
    return false;
  end
  if(filters.inputNameFilter == nil) then
    logger.logDebug("Input name filter was nil")
    return true;
  end
  local matches = false;
  for idx,recipe in ipairs(item.recipes) do
    for inputName,inputData in pairs(recipe.input) do
      logger.logDebug("Matching input with name: " .. inputData.displayName .. " and " .. inputName);
      if(inputData ~= nil and (containsSubString(inputData.displayName, filters.inputNameFilter) or containsSubString(inputName, filters.inputNameFilter))) then
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

function methodNamesMatchFilters(item)
  if(item.methods == nil) then
    return false;
  end
  if(filters.methodNameFilter == nil) then
    return true;
  end
  local methodMatches = false
  for methodId,methodName in pairs(item.methods) do
    if(containsSubString(methodId, filters.methodNameFilter)) then
      methodMatches = true
    end
  end
  return methodMatches
end

function hasAvailableIngredients(item)
  if(filters.ingredientsAvailable == false) then
    return true;
  end
  if(item.isCraftable ~= nil and item.isCraftable()) then
    logger.logDebug("Is Craft " .. item.id)
  else
    logger.logDebug("No craft " .. item.id)
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

function filterByName()
  local nameFilter = widget.getText(FILTER_BY_NAME_NAME)
  if(nameFilter == nil or nameFilter == "") then
    filters.nameFilter = nil
  else
    filters.nameFilter = nameFilter
    logger.logDebug("Filtering by name: '" .. filters.nameFilter .. "'")
  end
  logger.logDebug("Filtering by name")
  requestRecipesForSelectedFilters()
end

function filterByInput(id)
  local inputNameFilter = widget.getText(FILTER_BY_INPUT_NAME)
  if(inputNameFilter == nil or inputNameFilter == "") then
    filters.inputNameFilter = nil
  else
    filters.inputNameFilter = inputNameFilter;
    logger.logDebug("Filtering by input name: '" .. filters.inputNameFilter .. "'")
  end
  logger.logDebug("Filtering by input name")
  requestRecipesForSelectedFilters()
end

function filterByHasIngredients()
  local enableFilter = widget.getChecked(FILTER_BY_HAS_INGREDIENTS_NAME)
  if(enableFilter) then
    logger.logDebug("Doing filter")
  else
    logger.logDebug("Not doing filter")
  end
  filters.ingredientsAvailable = enableFilter
  requestRecipesForSelectedFilters()
end

-----------------------------------------------------------------

function dummy()
end
