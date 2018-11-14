require "/scripts/debugUtilsCN.lua"
require "/scripts/MFM/recipeStoreAPI.lua"
require "/scripts/MFM/ingredientStoreAPI.lua"

FILTER_NAMES_PATH = "/recipeCrafterMFM/methodFilterNamesMFM.json"
RECIPE_FILTER_FRIENDLY_NAMES = "/recipeCrafterMFM/methodFriendlyNamesMFM.json"

local logger = nil;
local initialized = false;

function init(virtual)
  logger = DebugUtilsCN.init("[CNRB]");
  RecipeStoreCNAPI.init(virtual);
  IngredientStoreCNAPI.init(virtual);
  message.setHandler("toggleFilterSelected", toggleFilterSelectedHook);
  message.setHandler("setSelectedFilters", setSelectedFiltersHook);
  message.setHandler("getFilterData", getFilterDataHook);
  message.setHandler("getSelectedItem", getSelectedItemHook);
  message.setHandler("selectItem", selectItemHook);
  
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

function setSelectedFiltersHook(id, name, filterNames)
  if(filterNames == nil) then
    return getFilterDataHook();
  end
  local filterData = getFilterDataHook();
  for filterId, filterInfo in pairs(filterData) do
    filterInfo.isSelected = false;
  end
  for idx, filterName in ipairs(filterNames) do
    toggleFilterSelected(filterName);
  end
  return getFilterDataHook();
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
end

function getSelectedItemHook()
  if(storage.selectedItem == nil) then
    return;
  end
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
    return;
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
