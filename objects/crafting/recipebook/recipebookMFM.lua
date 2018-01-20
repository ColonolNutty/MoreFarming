require "/scripts/debugUtilsCN.lua"

currentPage = 1

RECIPE_FILTERS_PATH = "/recipeCrafterMFM/recipeFiltersMFM.json"
RECIPE_GROUP_FRIENDLY_NAMES = "/recipeCrafterMFM/recipeGroupFriendlyNamesMFM.json"
RECIPE_CONFIGURATION_PATH = "/recipeCrafterMFM/"

update = nil
uninit = nil

function init()
  DebugUtilsCN.init("[CNRB]")
  DebugUtilsCN.enableDebug()
  message.setHandler("storeIngredient", storeIngredient)
  message.setHandler("storeSelectedRecipeId", storeSelectedRecipeId)
  message.setHandler("getSelectedRecipeId", getSelectedRecipeId)
  message.setHandler("getIngredientStore", getIngredientStore)
  message.setHandler("getRecipeFilterStore", getRecipeFilterStore)
  message.setHandler("getRecipeFilters", getRecipeFilters)
  message.setHandler("getSelectedFilters", getSelectedFilters)
  message.setHandler("setSelectedFilters", setSelectedFilters)
  
  if(storage.selectedFilters ~= nil and storage.recipeFilters ~= nil and storage.recipeFilterStore ~= nil and storage.recipeStore ~= nil) then
    DebugUtilsCN.logDebug("Recipe already loaded, skipping load")
    return
  end
  
  if(storage.ingredientStore == nil) then
    storage.ingredientStore = {}
  end
  
  storage.recipeFilterStore = {}
  storage.ingredientStore = {}
  storage.selectedFilters = {}
  storage.recipeFilters = root.assetJson(RECIPE_FILTERS_PATH).recipeFilters
  storage.recipeMethodFriendlyNames = root.assetJson(RECIPE_GROUP_FRIENDLY_NAMES)
  if(#storage.recipeFilters == 0) then
    return
  end
  for i, recipeFilter in ipairs(storage.recipeFilters) do
    storage.selectedFilters[recipeFilter] = false
    local recipeConfigPath = RECIPE_CONFIGURATION_PATH .. recipeFilter .. "Recipes.config"
    DebugUtilsCN.logDebug("Looking for recipe configuration at path: " .. recipeConfigPath)
    local recipeNames = root.assetJson(recipeConfigPath)
    if(recipeNames ~= nil) then
      DebugUtilsCN.logDebug("Storing recipe names for filter: " .. recipeFilter)
      storage.recipeFilterStore[recipeFilter] = updateRecipeStore(recipeNames.possibleOutput)
    end
  end
  storage.selectedFilters[storage.recipeFilters[1]] = true
end

function updateRecipeStore(itemsArray)
  local itemsList = {}
  for idx,itemName in ipairs(itemsArray) do
    if(storage.ingredientStore[itemName] == nil) then
      itemsList[itemName] = loadItem(itemName)
    end
  end
  return itemsList
end

function loadItem(itemId)
  if(storage.ingredientStore[itemId] ~= nil) then
    return storage.ingredientStore[itemId]
  end
  local item = nil
  local itemData = root.itemConfig({ name = itemId })
  if(itemData ~= nil) then
    if type(itemData.config.inventoryIcon) == 'table' then
      itemData.config.inventoryIcon = itemData.config.inventoryIcon[1].image
    end
    local recipes = filterNonRecipeBookRecipes(root.recipesForItem(itemId))
    item = { id = itemId, name = itemData.config.shortdescription, icon = rescale(canonicalise(itemData.config.inventoryIcon, itemData.directory), 16, 16), recipes = recipes, methods = getMethods(recipes) }
    storage.ingredientStore[itemId] = item
  end
  return item
end

function filterNonRecipeBookRecipes(recipes)
  if(recipes == nil) then
    return {}
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
      local friendlyName = storage.recipeMethodFriendlyNames[group]
      if(friendlyName ~= nil and recipe.methods[group] == nil) then
        recipe.methods[group] = friendlyName
      end
    end
    if(include) then
      table.insert(result, recipe)
    end
  end
  return result
end

function getMethods(recipes)
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

function storeIngredient(id, name, itemName)
  loadItem(itemName)
end

function storeSelectedRecipeId(id, name, recipeId)
  storage.selectedRecipeId = recipeId
end

function getSelectedRecipeId(id, name, recipeId)
  return storage.selectedRecipeId
end

function getIngredientStore()
  return storage.ingredientStore
end

function getRecipeFilterStore()
  return storage.recipeFilterStore
end

function getRecipeFilters()
  return storage.recipeFilters
end

function getSelectedFilters()
  return storage.selectedFilters
end

function setSelectedFilters(id, name, filters)
  storage.selectedFilters = filters
end