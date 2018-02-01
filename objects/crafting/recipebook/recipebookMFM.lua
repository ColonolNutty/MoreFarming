require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"

currentPage = 1

METHOD_FILTER_NAMES_PATH = "/recipeCrafterMFM/methodFilterNamesMFM.json"
RECIPE_METHOD_FRIENDLY_NAMES = "/recipeCrafterMFM/methodFriendlyNamesMFM.json"
RECIPE_CONFIGURATION_PATH = "/recipeCrafterMFM/"

local completedInitialSetup = false

-- Storage Property Names --
-- rbDataStore
---- ingredientStore (Table) (FoodId, FoodItem)
------ id (String) (FoodId)
------ name (String)
------ icon (String)
------ recipes (Table Array) (Idx, RecipeItem)
-------- input (Table Array) (Idx, ItemDescriptor)
---------- name (String) (FoodId)
---------- count (Int)
-------- output (Table Array) (Idx, ItemDescriptor)
---------- name (String) (FoodId)
---------- count (Int)
-------- groups (String Array)
-------- methods (Table) (MethodName, MethodFriendlyName)
------ methods (Table) (MethodName, MethodFriendlyName)
---- methodFilters (Table) (MethodName, MethodItem)
------ id (String)
------ name (String)
------ isSelected (Boolean)
------ foods (Table) (FoodId, FoodItem)
---- methodFilterNames (String Array)
---- methodFriendlyNames (String Array)
---

--- Handlers ---
-- getDataStore
-- setDataStore
-- storeIngredient
-- updateSelectedId
---

local recipeFilters = { 
  groupFilters = { }
}

function init()
  DebugUtilsCN.init("[CNRB]");
  message.setHandler("getDataStore", getDataStore);
  message.setHandler("setDataStore", setDataStore);
  message.setHandler("updateSelectedFilters", updateSelectedFilters);
  message.setHandler("storeIngredient", storeIngredient);
  message.setHandler("updateSelectedId", updateSelectedId);
  table.insert(recipeFilters.groupFilters, doesNotContainNoRecipeBookfilter)
  table.insert(recipeFilters.groupFilters, hasFriendlyNamefilter)
  
  doInitialSetup();
end

function update()
  loadRecipeIngredients();
end

function uninit()
  
end

function doInitialSetup()
  if(completedInitialSetup) then
    return;
  end
  
  initializeDataStore()
  
  completedInitialSetup = true;
end

function initializeDataStore()
  if(storage.rbDataStore ~= nil) then
    return;
  end
  storage.rbDataStore = {
    selectedFoodId = nil,
    ingredientStore = {},
    methodFilters = {},
    methodFilterNames = root.assetJson(METHOD_FILTER_NAMES_PATH).filterNames,
    methodFriendlyNames = root.assetJson(RECIPE_METHOD_FRIENDLY_NAMES)
  };
  if(#storage.rbDataStore.methodFilterNames == 0) then
    return
  end
  for i, methodFilterName in ipairs(storage.rbDataStore.methodFilterNames) do
     DebugUtilsCN.logDebug("Storing filter: " .. methodFilterName)
     local methodFilter = {
      id = methodFilterName,
      name = storage.rbDataStore.methodFriendlyNames[methodFilterName],
      isSelected = false,
      foods = {}
    };
    
    local recipeConfigPath = RECIPE_CONFIGURATION_PATH .. methodFilterName .. "Recipes.config"
    DebugUtilsCN.logDebug("Looking for recipe configuration at path: " .. recipeConfigPath)
    
    local recipeNames = root.assetJson(recipeConfigPath)
    if(recipeNames ~= nil) then
      DebugUtilsCN.logDebug("Storing recipe names for filter: " .. methodFilterName)
      methodFilter.foods = loadFoods(recipeNames.possibleOutput)
    end
    storage.rbDataStore.methodFilters[methodFilterName] = methodFilter
  end
  storage.rbDataStore.methodFilters[storage.rbDataStore.methodFilterNames[1]].isSelected = true
  
  storage.rbDataStore.sortedMethodFilters = UtilsCN.sortByValueNameId(storage.rbDataStore.methodFilters)
end

function doesNotContainNoRecipeBookfilter(recipeGroup)
  return not string.match(recipeGroup, "NoRecipeBook");
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
    DebugUtilsCN.logDebug("Looking at recipe " .. recipe.output.name)
    for idx, group in ipairs(recipe.groups) do
      DebugUtilsCN.logDebug("Looking at recipe group: " .. group)
      if(passesAllFilters(recipeFilters.groupFilters, group)) then
        DebugUtilsCN.logDebug("Recipe group passes filters: " .. group)
        -- Include recipe if at least one group passes all filters
        includeRecipe = true
        -- If the group matches the filters, there must be a friendly name for it, set it
        recipe.methods[group] = storage.rbDataStore.methodFriendlyNames[group]
        allMethods[group] = recipe.methods[group]
      end
    end
    if(includeRecipe) then
      table.insert(result, recipe)
    end
  end
  return allMethods, result
end

-- Currently I load the recipe inputs as you look at recipes, so we load only what we need to (Faster? Safer? Less taxing? or should we load all at the beginning?) --
function loadRecipeIngredients()
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
  storage.rbDataStore.selectedFoodId = newId;
  return true
end

function updateSelectedFilters(id, name, filterData)
  storage.rbDataStore.methodFilters[filterData.id].isSelected = filterData.isSelected
  return true
end

function storeIngredient(id, name, foodId)
  return loadFood(foodId)
end

---------------------------------------------------------

function loadFoods(foodsArray)
  local foodsList = {}
  for idx,foodId in ipairs(foodsArray) do
    local food = loadFood(foodId)
    if(food ~= nil) then
      foodsList[foodId] = food
    end
  end
  return foodsList
end

function loadFood(foodId)
  if(storage.rbDataStore.ingredientStore[foodId] ~= nil) then
    return storage.rbDataStore.ingredientStore[foodId]
  end
  local foodItemData = root.itemConfig({ name = foodId })
  if(foodItemData == nil) then
    DebugUtilsCN.logDebug("No food data found: " .. foodId)
    return nil
  end
  if type(foodItemData.config.inventoryIcon) == 'table' then
    foodItemData.config.inventoryIcon = foodItemData.config.inventoryIcon[1].image
  end
  local foodCookMethods, filteredRecipes = filterRecipes(root.recipesForItem(foodId))
  DebugUtilsCN.logDebug("Food data found: icon " .. foodItemData.config.inventoryIcon .. " directory " .. foodItemData.directory)
  local itemIcon = UtilsCN.resizeImageToIconSize(foodItemData.config.inventoryIcon, foodItemData.directory)
  local foodItem = { id = foodId, name = foodItemData.config.shortdescription, icon = itemIcon, recipes = filteredRecipes, methods = foodCookMethods }
  foodItem.displayName = foodItem.name .. formatMethods(foodItem.methods)
  storage.rbDataStore.ingredientStore[foodId] = foodItem
  return foodItem
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