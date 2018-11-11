require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"
require "/scripts/recipebookMFMQueryAPI.lua"
require "/scripts/MFM/recipeStoreAPI.lua"

if(RecipeLocatorAPI == nil) then
  RecipeLocatorAPI = {
    debugMsgPrefix = "[RLAPI]",
    initialized = false;
  };
end

local rlUtils = {};
local logger = nil;

function RecipeLocatorAPI.init(virtual)
  logger = DebugUtilsCN.init(RecipeLocatorAPI.debugMsgPrefix)
  RecipeStoreCNAPI.init(virtual)
  
  if(virtual) then
    RecipeLocatorAPI.rlUtils = rlUtils;
  end
  
  if(storage.previouslyFoundRecipe == nil) then
    storage.previouslyFoundRecipe = nil;
  end
end

function RecipeLocatorAPI.update()
  rlUtils.initializeRecipeStore()
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
  return RecipeStoreCNAPI.getRecipesContainingIngredientCounts(recipeGroup, ingredients);
end

function rlUtils.initializeRecipeStore()
  if(RecipeLocatorAPI.initialized) then
    return;
  end
  logger.logDebug("Initializing Recipe Store");
  local handle = function()
    local result = RecipeBookMFMQueryAPI.getRecipesForFilter(storage.recipeGroup, nil, storage.recipeGroup)
    if(result ~= nil) then
      return true, result;
    end
    return false, nil;
  end
  
  local onComplete = function(result)
    RecipeStoreCNAPI.initializeRecipeStore(methodName, result);
    logger.logDebug("Recipes initialized");
    RecipeLocatorAPI.initialized = true;
  end
  EntityQueryAPI.addRequest("initializeRecipeStore", handle, onComplete)
end
