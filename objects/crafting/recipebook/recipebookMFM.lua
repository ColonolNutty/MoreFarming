require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"
require "/scripts/MFM/recipeStoreAPI.lua"
require "/scripts/MFM/ingredientStoreAPI.lua"

FILTER_NAMES_PATH = "/recipeCrafterMFM/methodFilterNamesMFM.json"
RECIPE_FILTER_FRIENDLY_NAMES = "/recipeCrafterMFM/methodFriendlyNamesMFM.json"
RECIPE_CONFIGURATION_PATH = "/recipeCrafterMFM/"

-- Storage Property Names --
-- rbDataStore
---- selectedItemId (Int) (ItemId)
---- ingredientStore (Table) (ItemId, Item)
------ id (String) (ItemId)
------ name (String)
------ icon (String)
------ recipes (Table Array) (Idx, RecipeItem)
-------- input (Table Array) (Idx, ItemDescriptor)
---------- name (String) (ItemId)
---------- count (Int)
-------- output (Table Array) (Idx, ItemDescriptor)
---------- name (String) (ItemId)
---------- count (Int)
-------- groups (String Array)
-------- methods (Table) (MethodName, MethodFriendlyName)
------ methods (Table) (MethodName, MethodFriendlyName)
---- methodFilters (Table) (MethodName, MethodItem)
------ id (String)
------ name (String)
------ isSelected (Boolean)
------ items (Table) (ItemId, Item)
---- methodFilterNames (String Array)
---- methodFriendlyNames (String Array)

--- Handlers ---
-- getDataStore
-- setDataStore
-- updateSelectedFilters
-- storeIngredient
-- updateSelectedId
---

local logger = nil;
local initialized = false;

local recipeFilters = { 
  groupFilters = { }
};

function init(virtual)
  logger = DebugUtilsCN.init("[CNRB]");
  logger.enableDebug();
  RecipeStoreCNAPI.init(virtual);
  IngredientStoreCNAPI.init(virtual);
  message.setHandler("toggleFilterSelected", toggleFilterSelectedHook);
  message.setHandler("getFilterData", getFilterDataHook);
  message.setHandler("getSelectedItem", getSelectedItemHook);
  message.setHandler("selectItem", selectItemHook);
  
  message.setHandler("getDataStore", getDataStore);
  message.setHandler("setDataStore", setDataStore);
  message.setHandler("updateSelectedFilters", updateSelectedFilters);
  message.setHandler("updateSelectedId", updateSelectedId);
  table.insert(recipeFilters.groupFilters, hasFriendlyNamefilter)
  
  initializeRecipeBook();
end

function getFilterIds()
  if(storage.filterIds ~= nil) then
    return storage.filterIds;
  end
  storage.filterIds = root.assetJson(FILTER_NAMES_PATH).filterNames;
  return storage.filterIds;
end

function getFilterFriendlyName(filterId)
  if(storage.filterFriendlyNames == nil) then
    storage.filterFriendlyNames = root.assetJson(RECIPE_FILTER_FRIENDLY_NAMES);
  end
  if(storage.filterFriendlyNames[filterId] == nil) then
    return filterId;
  end
  return storage.filterFriendlyNames[filterId];
end

function getFilterDataHook()
  if(storage.filters ~= nil) then
    return storage.filters;
  end
  storage.filters = {};
  local filterIds = getFilterIds();
  for idx, filterId in ipairs(filterIds) do
    storage.filters[filterId] = initializeFilter(filterId);
  end
  return storage.filters;
end

function initializeFilter(filterId)
  local filter = {
    id = filterId,
    name = getFilterFriendlyName(filterId),
    isSelected = false
  };
  RecipeStoreCNAPI.initializeRecipeStore(filterId);
  return filter;
end

function toggleFilterSelectedHook(id, name, filterId)
  return toggleFilterSelected(filterId);
end

function toggleFilterSelected(filterId)
  local filterData = getFilterDataHook();
  if(filterData[filterId] == nil) then
    filterData[filterId] = initializeFilter(filterId);
  end
  filterData[filterId].isSelected = not filterData[filterId].isSelected;
  return true;
end

function getSelectedItemHook()
  return storage.selectedItem;
end

function selectItemHook(id, name, itemId)
  if(itemId == nil) then
    logger.logDebug("Item Id was nil!");
  else
    logger.logDebug("Selecting item with id: " .. itemId);
  end
  return selectItem(itemId);
end

function selectItem(itemId)
  if(itemId == nil) then
    storage.selectedItem = nil;
    return true;
  else
    storage.selectedItem = {
      id = itemId,
      data = IngredientStoreCNAPI.loadIngredient(itemId)
    };
  end
  return storage.selectedItem;
end

function initializeRecipeBook()
  local filterData = getFilterDataHook()
  local filterIds = getFilterIds();
  local firstFilterId = filterIds[1];
  if(filterData[firstFilterId] ~= nil) then
    filterData[firstFilterId].isSelected = true;
  end
  return filterData;
end

--------------------------------------------------------------------

function initializeDataStore()
  if(storage.rbDataStore ~= nil) then
    return;
  end
  storage.rbDataStore = {
    selectedItemId = nil,
    ingredientStore = {},
    methodFilters = {},
    sortedMethodFilters = {},
    methodFriendlyNames = root.assetJson(RECIPE_FILTER_FRIENDLY_NAMES),
    recipeBookExists = true
  };
  if(#storage.rbDataStore.methodFilterNames == 0) then
    return
  end
  local methodFilterNames = storage.rbDataStore.methodFilterNames;
  
  for i, methodFilterName in ipairs(methodFilterNames) do
     logger.logDebug("Loading method filter: " .. methodFilterName)
     local methodFilter = {
      id = methodFilterName,
      name = storage.rbDataStore.methodFriendlyNames[methodFilterName],
      isSelected = false,
      recipeStore = {}
    };
    methodFilter.recipeStore = RecipeStoreCNAPI.initializeRecipeStore(methodFilterName);
    storage.rbDataStore.methodFilters[methodFilterName] = methodFilter
  end
  storage.rbDataStore.methodFilters[storage.rbDataStore.methodFilterNames[1]].isSelected = true
  
  storage.rbDataStore.sortedMethodFilters = UtilsCN.sortByValueNameId(storage.rbDataStore.methodFilters)
end

------------------------- Handlers ----------------------

function getDataStore()
  if(storage.rbDataStore == nil) then
    initializeDataStore()
  end
  return storage.rbDataStore
end

function setDataStore(id, name, newDataStore)
  storage.rbDataStore = newDataStore;
  return true
end

function updateSelectedId(id, name, newId)
  storage.rbDataStore.selectedItemId = newId;
  local itemData = IngredientStoreCNAPI.loadIngredient(newId);
  storage.rbDataStore.selectedItemData = itemData;
  return true;
end

function updateSelectedFilters(id, name, filterData)
  if(filterData.isSelected) then
    logger.logDebug("Selecting filter " .. filterData.id)
  else
    logger.logDebug("Deselecting filter " .. filterData.id)
  end
  storage.rbDataStore.methodFilters[filterData.id].isSelected = filterData.isSelected
  return true
end

------------------------------SoonToBeObsolete--------------------------------------

function storeIngredient(id, name, itemId)
  return loadItem(itemId)
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

function loadItem(itemId)
  if(storage.rbDataStore.ingredientStore[itemId] ~= nil) then
    return storage.rbDataStore.ingredientStore[itemId]
  end
  local itemData = root.itemConfig({ name = itemId })
  if(itemData == nil) then
    logger.logDebug("No item data found: " .. itemId)
    return nil
  end
  if type(itemData.config.inventoryIcon) == 'table' then
    itemData.config.inventoryIcon = itemData.config.inventoryIcon[1].image
  end
  local craftMethods, filteredRecipes = filterRecipes(root.recipesForItem(itemId))
  logger.logDebug("Item data found: icon " .. itemData.config.inventoryIcon .. " directory " .. itemData.directory)
  local itemIcon = UtilsCN.resizeImageToIconSize(itemData.config.inventoryIcon, itemData.directory)
  local item = { id = itemId, name = itemData.config.shortdescription, icon = itemIcon, recipes = filteredRecipes, methods = craftMethods }
  item.displayName = item.name .. formatMethods(item.methods)
  storage.rbDataStore.ingredientStore[itemId] = item
  return item
end

function filterRecipes(recipes)
  if(UtilsCN.isEmpty(recipes)) then
    return nil
  end
  local allMethods = {}
  local result = {}
  for idx, recipe in ipairs(recipes) do
    if(recipe.methods == nil) then
      recipe.methods = {}
    end
    local includeRecipe = false
    local excludeRecipe = false
    logger.logDebug("Looking at recipe " .. recipe.output.name)
    for idx, group in ipairs(recipe.groups) do
      logger.logDebug("Looking at recipe group: " .. group)
      if(isExcludedFromRecipeBook(group)) then
        excludeRecipe = true
        includeRecipe = false
      end
      if(not excludeRecipe and passesAllFilters(recipeFilters.groupFilters, group)) then
        logger.logDebug("Recipe group passes filters: " .. group)
        -- Include recipe if at least one group passes all filters
        includeRecipe = true
        -- If the group matches the filters, there must be a friendly name for it, set it
        recipe.methods[group] = storage.rbDataStore.methodFriendlyNames[group]
        allMethods[group] = recipe.methods[group]
      end
    end
    if(includeRecipe and not excludeRecipe) then
      table.insert(result, recipe)
    end
  end
  return allMethods, result
end

function isExcludedFromRecipeBook(recipeGroup)
  return recipeGroup == "ExcludeFromRecipeBook";
end

function hasFriendlyNamefilter(recipeGroup)
  return storage.rbDataStore.methodFriendlyNames[recipeGroup] ~= nil;
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