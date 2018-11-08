require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"

METHOD_FILTER_NAMES_PATH = "/recipeCrafterMFM/methodFilterNamesMFM.json"
RECIPE_METHOD_FRIENDLY_NAMES = "/recipeCrafterMFM/methodFriendlyNamesMFM.json"
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
---

--- Handlers ---
-- getDataStore
-- setDataStore
-- updateSelectedFilters
-- storeIngredient
-- updateSelectedId
---

local logger = nil

local recipeFilters = { 
  groupFilters = { }
}

function init()
  logger = DebugUtilsCN.init("[CNRB]");
  message.setHandler("getDataStore", getDataStore);
  message.setHandler("setDataStore", setDataStore);
  message.setHandler("updateSelectedFilters", updateSelectedFilters);
  message.setHandler("storeIngredient", storeIngredient);
  message.setHandler("updateSelectedId", updateSelectedId);
  message.setHandler("getRecipesForFilter", getRecipesForFilter);
  table.insert(recipeFilters.groupFilters, hasFriendlyNamefilter)
  
  storage.rbDataStore = nil
  initializeDataStore()
end

function update()
end

function uninit()
end

function initializeDataStore()
  if(storage.rbDataStore ~= nil) then
    return;
  end
  storage.rbDataStore = {
    selectedItemId = nil,
    ingredientStore = {},
    methodFilters = {},
    sortedMethodFilters = {},
    methodFilterNames = root.assetJson(METHOD_FILTER_NAMES_PATH).filterNames,
    methodFriendlyNames = root.assetJson(RECIPE_METHOD_FRIENDLY_NAMES),
    recipeBookExists = true
  };
  if(#storage.rbDataStore.methodFilterNames == 0) then
    return
  end
  for i, methodFilterName in ipairs(storage.rbDataStore.methodFilterNames) do
     logger.logDebug("Storing filter: " .. methodFilterName)
     local methodFilter = {
      id = methodFilterName,
      name = storage.rbDataStore.methodFriendlyNames[methodFilterName],
      isSelected = false,
      items = {}
    };
    
    local recipeConfigPath = RECIPE_CONFIGURATION_PATH .. methodFilterName .. "Recipes.config"
    logger.logDebug("Looking for recipe configuration at path: " .. recipeConfigPath)
    
    local recipeNames = root.assetJson(recipeConfigPath)
    if(recipeNames ~= nil) then
      logger.logDebug("Storing recipe names for filter: " .. methodFilterName)
      methodFilter.items = loadRecipes(methodFilterName, methodFilter.name, recipeNames.recipesToCraft)
    end
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
  return true
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

function getRecipesForFilter(id, name, filterName)
  if(filterName == nil) then
    return {}
  end
  
  local dataStore = getDataStore()
  if(dataStore.methodFilters and dataStore.methodFilters[filterName]) then
    return dataStore.methodFilters[filterName].items
  end
  return {}
end
---------------------------------------------------------

function loadRecipes(methodName, methodFriendlyName, itemDatas)
  local items = {}
  for itemId, itemInfo in pairs(itemDatas) do
    local item = nil;
    if(storage.rbDataStore.ingredientStore[itemId] ~= nil) then
      item = storage.rbDataStore.ingredientStore[itemId]
    else
      local itemData = root.itemConfig({ name = itemId })
      if(itemData ~= nil) then
        if type(itemData.config.inventoryIcon) == 'table' then
          itemData.config.inventoryIcon = itemData.config.inventoryIcon[1].image
        end
        logger.logDebug("Item data found: icon " .. itemData.config.inventoryIcon .. " directory " .. itemData.directory);
        local itemIcon = UtilsCN.resizeImageToIconSize(itemData.config.inventoryIcon, itemData.directory);
        item = { id = itemId, displayName = itemData.config.shortdescription .. itemInfo.displayMethods, name = itemData.config.shortdescription, icon = itemIcon, recipes = {}, methods = itemInfo.methods };
        storage.rbDataStore.ingredientStore[itemId] = item
        table.insert(items, item)
      else
        logger.logDebug("No item data found: " .. itemId)
        item = nil;
      end
    end
    if(item ~= nil) then
      for idx, recipe in ipairs(itemInfo.recipes) do
        if(not recipe.excludeFromRecipeBook) then
          if(recipe.methods == nil) then
            recipe.methods = {}
          end
          table.insert(item.recipes, recipe);
        end
      end
    end
  end
  return items
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