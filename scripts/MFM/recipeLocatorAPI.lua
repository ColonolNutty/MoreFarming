require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"
require "/scripts/recipebookMFMQueryAPI.lua"

if(RecipeLocatorAPI == nil) then
  RecipeLocatorAPI = {
    debugMsgPrefix = "[RLAPI]",
    loadedRecipes = false,
    reloadingRecipeBook = false,
    reloadedRecipeBook = false,
    initialized = false;
  };
end

local rlUtils = {};
local logger = nil;

function RecipeLocatorAPI.init()
  logger = DebugUtilsCN.init(RecipeLocatorAPI.debugMsgPrefix)
  rlUtils.loadPossibleOutputs();
  
  if(storage.previouslyFoundRecipe == nil) then
    storage.previouslyFoundRecipe = nil;
  end
end

function RecipeLocatorAPI.update()
  rlUtils.loadRecipeBookRecipes()
end

function rlUtils.loadPossibleOutputs(defaultPossibleOutputs)
  local defaultValue = defaultPossibleOutputs or {};
  if(not config) then
    storage.possibleOutputs = defaultValue;
    return;
  end
  local outputConfigPath = config.getParameter("outputConfig");
  if outputConfigPath == nil then
    storage.possibleOutputs = defaultValue;
  else
    storage.possibleOutputs = root.assetJson(outputConfigPath).possibleOutput;
  end
end

function RecipeLocatorAPI.hasIngredientsForRecipe(recipe, ingredients)
  if(recipe == nil or recipe.output == nil or ingredients == nil) then
    return false;
  end
  local outputName = recipe.output.name;
  logger.logDebug("Verifying ingredients are available for recipe: " .. outputName)
  -- Check the recipe inputs to verify ingredients match with all inputs
  local indent = 1
  local recipeIngredients = {}
  local allIngredientsAreRecipeIngredients = true
  for idx,input in ipairs(recipe.input) do
    local inputName = input.name;
    local inputCount = input.count;
    logger.logDebug("Attempting to locate ingredient '" .. inputName .. "' in container", indent + 1)
    local matchFound = false
    for slot,ingred in pairs(ingredients) do
      local ingredName = ingred.name;
      local ingredCount = ingred.count;
      logger.logDebug("Checking '" .. ingredName .. "' in slot " .. slot, indent + 2)
      if (ingredName ~= outputName) then
        if (ingredName == inputName) then
          logger.logDebug("Name matched, Verifying count...", indent + 3)
          if(inputCount <= ingredCount) then
            matchFound = true
            logger.logDebug("Count matched, found ingredient", indent + 4)
            table.insert(recipeIngredients, ingredName)
            break
          else
            logger.logDebug("Count did not match, Expected: " .. inputCount .. " Actual: " .. ingredCount, indent + 4)
          end
        else
          logger.logDebug("Name did not match", indent + 3)
        end
      end
    end
    if not matchFound then
      logger.logDebug("Could not find at least " .. inputCount .. " of ingredient '" .. inputName .. "'", indent + 1)
      allIngredientsAreRecipeIngredients = false
      break;
    end
  end
  if(not allIngredientsAreRecipeIngredients) then
    logger.logDebug("Failed to locate some or all required ingredients for recipe: " .. outputName, indent)
    return false;
  end
  logger.logDebug("Verifying all container ingredients are used in recipe: " .. outputName)
  -- All ingredients in the container should be used, even the ones not being used by the recipe
  for slot,ingred in pairs(ingredients) do
    local ingredName = ingred.name
    if (ingredName ~= outputName) then
      local matches = false
      for _,recipeIngredient in ipairs(recipeIngredients) do
        logger.logDebug("Checking ingredient '" .. ingredName .. "'", indent + 1)
        if ingredName == recipeIngredient then
          matches = true
          logger.logDebug("Success: '" .. recipeIngredient .. "' is being used in the recipe", indent + 2)
          break
        end
      end
      if not matches then
        logger.logDebug("Failure: '" .. ingredName .. "' is not being used the recipe", indent + 3)
        allIngredientsAreRecipeIngredients = false
        break;
      end
    end
  end
  return allIngredientsAreRecipeIngredients
end

-- Find Recipe matching ingredients
function RecipeLocatorAPI.findRecipeForIngredients(ingredients, recipeGroup)
  logger.logDebug("Locating recipe for ingredients")
  -- A shortcircuit to searching the entire recipe list, just to the find the same recipe
  if(storage.previouslyFoundRecipe ~= nil) then
    local matches = RecipeLocatorAPI.hasIngredientsForRecipe(storage.previouslyFoundRecipe, ingredients);
    if(matches) then
      logger.logDebug("Previous recipe matches current ingredients, using it")
      return storage.previouslyFoundRecipe;
    end
  end

  local foundRecipe = nil;
  
  if(storage.recipeBookRecipes ~= nil) then
    -- Recipe book is nearby, so we take a faster route by utilizing the recipes already discovered by the recipe book
    logger.logDebug("Using Recipe Book Recipes")
    for itemName,item in pairs(storage.recipeBookRecipes) do
      local recipesForItem = item.recipes
      if recipesForItem ~= nil and #recipesForItem > 0 then
        foundRecipe = rlUtils.findRecipe(recipesForItem, ingredients, recipeGroup)
        if foundRecipe then
          logger.logDebug("Found recipe with output name: " .. foundRecipe.output.name)
          break;
        end
      end
    end
  else
    -- No recipe book was found nearby, search for your own dang recipes!
    for _,itemName in ipairs(storage.possibleOutputs) do
      local recipesForItem = root.recipesForItem(itemName)
      if recipesForItem ~= nil and #recipesForItem > 0 then
        foundRecipe = rlUtils.findRecipe(recipesForItem, ingredients, recipeGroup)
        if foundRecipe then
          logger.logDebug("Found recipe with output name: " .. foundRecipe.output.name)
          break;
        end
      end
    end
  end
  storage.previouslyFoundRecipe = foundRecipe;
  return foundRecipe;
end

function rlUtils.recipeHasMatchingGroup(recipe, recipeGroup)
  local canBeCrafted = false
  for _,group in ipairs(recipe.groups) do
    if group == recipeGroup then
      canBeCrafted = true
      break
    end
  end
  return canBeCrafted
end

function rlUtils.findRecipe(recipesForItem, ingredients, recipeGroup)
  if recipeGroup == nil then
    logger.logDebug("No Recipe Group specified")
    return nil;
  end
  logger.logDebug("Recipe group specified: " .. recipeGroup)
  local recipeFound = nil
  for _,recipe in ipairs(recipesForItem) do
    if (rlUtils.recipeHasMatchingGroup(recipe, recipeGroup) and RecipeLocatorAPI.hasIngredientsForRecipe(recipe, ingredients)) then
      recipeFound = recipe
      break;
    else
      logger.logDebug("Recipe cannot be crafted: " .. recipe.output.name)
    end
  end
  return recipeFound
end

function rlUtils.reloadRecipeBook()
  if(not RecipeLocatorAPI.reloadingRecipeBook) then
    RecipeLocatorAPI.loadedRecipes = false
    rlUtils.loadRecipeBookRecipes()
  end
  return RecipeLocatorAPI.reloadedRecipeBook;
end

function rlUtils.loadRecipeBookRecipes()
  if(RecipeLocatorAPI.loadedRecipes or RecipeLocatorAPI.reloadingRecipeBook) then
    return
  end
  RecipeLocatorAPI.reloadingRecipeBook = true;
  RecipeLocatorAPI.reloadedRecipeBook = false;
  local handle = function()
    local result = RecipeBookMFMQueryAPI.getRecipesForFilter(storage.recipeGroup, nil, storage.recipeGroup)
    if(result ~= nil) then
      return true, result;
    end
    return false, nil;
  end
  
  local onComplete = function(result)
    -- Results are checked using the "next" function to see if any recipes came back
    if(next(result) == nil) then
      storage.recipeBookRecipes = nil
      logger.logDebug("Recipe Book Not Found")
    else
      storage.recipeBookRecipes = result;
      logger.logDebug("Loaded Recipe Book Recipes")
    end
    RecipeLocatorAPI.loadedRecipes = true
    RecipeLocatorAPI.reloadingRecipeBook = false
    RecipeLocatorAPI.reloadedRecipeBook = true;
  end
  EntityQueryAPI.addRequest("loadRecipeBookRecipes", handle, onComplete)
end
