require "/scripts/debugUtilsCN.lua"

currentPage = 1

METHOD_FILTER_NAMES_PATH = "/recipeCrafterMFM/methodFilterNamesMFM.json"
RECIPE_METHOD_FRIENDLY_NAMES = "/recipeCrafterMFM/methodFriendlyNamesMFM.json"
RECIPE_CONFIGURATION_PATH = "/recipeCrafterMFM/"

update = nil
uninit = nil

local dataStore = nil

function init()
  DebugUtilsCN.init("[CNRB]")
  --DebugUtilsCN.enableDebug()
  message.setHandler("getDataStore", getDataStore)
  message.setHandler("setDataStore", setDataStore)
  message.setHandler("storeIngredient", storeIngredient)
  
  if(storage.recipeBookDataStorage ~= nil) then
    dataStore = storage.recipeBookDataStore
    DebugUtilsCN.logDebug("Recipe already loaded, skipping load")
    return
  end
  
  initializeDataStore()
end

function updateRecipeStore(itemsArray)
  local itemsList = {}
  for idx,itemName in ipairs(itemsArray) do
    local item = loadItem(itemName)
    if(item ~= nil) then
      itemsList[itemName] = item
    end
  end
  return itemsList
end

function loadItem(itemId)
  if(dataStore.ingredientStore[itemId] ~= nil) then
    return dataStore.ingredientStore[itemId]
  end
  local item = nil
  local itemData = root.itemConfig({ name = itemId })
  if(itemData ~= nil) then
    if type(itemData.config.inventoryIcon) == 'table' then
      itemData.config.inventoryIcon = itemData.config.inventoryIcon[1].image
    end
    local recipes = filterNonRecipeBookRecipes(root.recipesForItem(itemId))
    item = { id = itemId, name = itemData.config.shortdescription, icon = rescale(canonicalise(itemData.config.inventoryIcon, itemData.directory), 16, 16), recipes = recipes, methods = getMethods(recipes) }
    dataStore.ingredientStore[itemId] = item
    if(isArrEmpty(recipes)) then
      return nil
    end
  end
  return item
end

function filterNonRecipeBookRecipes(recipes)
  if(isArrEmpty(recipes)) then
    return nil
  end
  local result = {}
  for idx,recipe in ipairs(recipes) do
    if(recipe.methods == nil) then
      recipe.methods = {}
    end
    local include = false
    DebugUtilsCN.logDebug("Looking at recipe " .. recipe.output.name)
    local groups = recipe.groups
    for idx,group in ipairs(groups) do
      DebugUtilsCN.logDebug("Looking at recipe group: " .. group)
      if(not string.match(group, "NoRecipeBook")) then
        DebugUtilsCN.logDebug("Including recipe " .. recipe.output.name)
        include = true
      end
      local friendlyName = dataStore.methodFriendlyNames[group]
      if(friendlyName ~= nil and recipe.methods[group] == nil) then
        recipe.methods[group] = friendlyName
      end
    end
    if(include and not isEmpty(recipe.methods)) then
      table.insert(result, recipe)
    end
  end
  return result
end

function getMethods(recipes)
  if(isArrEmpty(recipes)) then
    return nil
  end
  local allMethods = {}
  for idx,recipe in ipairs(recipes) do
    for methodName,friendlyName in pairs(recipe.methods) do
      allMethods[methodName] = friendlyName
    end
  end
  return allMethods
end

function canonicalise(file, directory)
	if string.sub(file, 1, 1) == '/' then return file end
	return directory .. file
end

function rescale(image, x, y)
	local size = root.imageSize(image)
	if size[1] <= x and size[2] <= y then return image end
	return image .. '?scalebilinear=' .. math.min(x / size[1], y / size[2])
end

function getDataStore()
  if(dataStore == nil) then
    initializeDataStore()
  end
  return dataStore
end

function setDataStore(id, name, newDataStore)
  dataStore = newDataStore
  storage.recipeBookDataStorage = dataStore
end

function storeIngredient(id, name, itemName)
  loadItem(itemName)
end

function initializeDataStore()
  dataStore = {
    recipeFilterStore = {},
    ingredientStore = {},
    selectedFilters = {},
    methodFilterNames = root.assetJson(METHOD_FILTER_NAMES_PATH).filterNames,
    methodFriendlyNames = root.assetJson(RECIPE_METHOD_FRIENDLY_NAMES)
  };
  if(#dataStore.methodFilterNames == 0) then
    return
  end
  for i, methodFilterName in ipairs(dataStore.methodFilterNames) do
    dataStore.selectedFilters[methodFilterName] = false
    local recipeConfigPath = RECIPE_CONFIGURATION_PATH .. methodFilterName .. "Recipes.config"
    DebugUtilsCN.logDebug("Looking for recipe configuration at path: " .. recipeConfigPath)
    local recipeNames = root.assetJson(recipeConfigPath)
    if(recipeNames ~= nil) then
      DebugUtilsCN.logDebug("Storing recipe names for filter: " .. methodFilterName)
      dataStore.recipeFilterStore[methodFilterName] = updateRecipeStore(recipeNames.possibleOutput)
    end
  end
  dataStore.selectedFilters[dataStore.methodFilterNames[1]] = true
  storage.recipeBookDataStorage = dataStore
end

function isArrEmpty(ipairTable)
  if(ipairTable == nil) then
    return true
  end
  local empty = true;
  for one,two in ipairs(ipairTable) do
    empty = false
    break;
  end
  return empty
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
