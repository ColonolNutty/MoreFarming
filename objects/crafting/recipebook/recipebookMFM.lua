require "/scripts/debugUtilsCN.lua"

currentPage = 1

RECIPE_FILTERS_PATH = "/recipeCrafterMFM/recipeFiltersMFM.json"
RECIPE_CONFIGURATION_PATH = "/recipeCrafterMFM/"

update = nil
uninit = nil

function init()
  DebugUtilsCN.init("[CNRB]")
  DebugUtilsCN.enableDebug()
  message.setHandler("hasRecipeFor", hasRecipeFor)
  message.setHandler("getRecipeStore", getRecipeStore)
  message.setHandler("getRecipeFilters", getRecipeFilters)
  message.setHandler("getSelectedFilters", getSelectedFilters)
  message.setHandler("setSelectedFilters", setSelectedFilters)
  
  if(storage.selectedFilters ~= nil and storage.recipeFilters ~= nil and storage.recipeFilterStore ~= nil and storage.recipeStore ~= nil) then
    DebugUtilsCN.logDebug("Recipe already loaded, skipping load")
    return
  end
  
  
  storage.recipeFilters = root.assetJson(RECIPE_FILTERS_PATH).recipeFilters
  storage.selectedFilters = { storage.recipeFilters[1] }
  storage.recipeFilterStore = {}
  storage.recipeStore = {}
  for i, v in ipairs(storage.recipeFilters) do
    local recipePath = RECIPE_CONFIGURATION_PATH .. v .. "Recipes.config"
    local recipeNames = root.assetJson(recipePath)
    if(recipeNames ~= nil) then
      DebugUtilsCN.logDebug("Storing recipe names for filter: " .. v)
      storage.recipeFilterStore[v] = recipeNames.possibleOutput
      storage.recipeStore[v] = getIngredientsFor(recipeNames.possibleOutput)
    end
  end
end

function getIngredientsFor(recipeNames)
  local ingredients = {}
  for i,recipeName in ipairs(recipeNames) do
    DebugUtilsCN.logDebug("Finding recipe for: " .. recipeName)
    local recipesForItem = root.recipesForItem(recipeName)
    local recipe = getFirstRecipe(recipesForItem)
    if(recipe ~= nil) then
      for idx,recipeInput in ipairs(recipe.input) do
        DebugUtilsCN.logDebug("ingredFound: " .. recipeInput.name)
        table.insert(ingredients, recipeInput)
      end
    end
  end
  return recipes
end

function getFirstRecipe(recipes)
  local firstRecipe = nil
  for i,recipe in ipairs(recipes) do
    local groups = recipe.groups
    local isValid = false
    for idx,group in ipairs(groups) do
      if(not string.match(group, "NoRecipeBook")) then
        isValid = true
        break
      end
    end
    if(isValid) then
      firstRecipe = recipe
      break
    end
  end
  return firstRecipe
end

function hasRecipeFor(id, name, itemName)
  
end

function getRecipeStore()
  return storage.recipeStore
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