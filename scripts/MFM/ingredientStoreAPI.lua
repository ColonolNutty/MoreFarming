require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"

if(IngredientStoreCNAPI == nil) then
  IngredientStoreCNAPI = {};
end

local METHOD_FILTER_NAMES_PATH = "/recipeCrafterMFM/methodFilterNamesMFM.json"
local RECIPE_METHOD_FRIENDLY_NAMES = "/recipeCrafterMFM/methodFriendlyNamesMFM.json"
local RECIPE_CONFIGURATION_PATH = "/recipeCrafterMFM/"

local isCNAPI = {};

local methodFriendlyNames = nil;
local ingredientStore = nil;
local logger = nil;

local recipeFilters = { 
  groupFilters = { }
};

function IngredientStoreCNAPI.init(virtual)
  logger = DebugUtilsCN.init("[CNISCNAPI]");
  if(virtual) then
    IngredientStoreCNAPI.isCNAPI = isCNAPI;
  end
  message.setHandler("loadIngredient", isCNAPI.loadIngredient);
  table.insert(recipeFilters.groupFilters, isCNAPI.hasFriendlyNamefilter)
  
  if(storage) then
    if(storage.methodFriendlyNames == nil) then
      storage.methodFriendlyNames = root.assetJson(RECIPE_METHOD_FRIENDLY_NAMES);
    end
    if(storage.ingredientStore == nil) then
      storage.ingredientStore = {};
    end
  else
    if(methodFriendlyNames == nil) then
      methodFriendlyNames = root.assetJson(RECIPE_METHOD_FRIENDLY_NAMES);
    end
    if(ingredientStore == nil) then
      ingredientStore = {};
    end
  end
end

function isCNAPI.getIngredientStore()
  if(not storage) then
    if(ingredientStore == nil) then
      ingredientStore = {};
    end
    return ingredientStore;
  else  
    if(storage.ingredientStore ~= nil) then
      return storage.ingredientStore;
    end
    storage.ingredientStore = {};
    return storage.ingredientStore;
  end
end

function isCNAPI.getMethodFriendlyName(group)
  if(storage) then
    return storage.methodFriendlyNames[group];
  else
    return methodFriendlyNames[group];
  end
end

--------------------------------------------------------------------
function IngredientStoreCNAPI.loadIngredient(ingredientId, ingredientInfo)
  return isCNAPI.load(ingredientId, ingredientInfo);
end

--- ingredientId (string) (ex. banana)
function isCNAPI.loadIngredient(id, name, ingredientId, ingredientInfo)
  return IngredientStoreCNAPI.loadIngredient(ingredientId, ingredientInfo);
end

function isCNAPI.formatMethods(methods)
  if(UtilsCN.isEmpty(methods)) then
    return " (Unknown)";
  end
  local formatted = "";
  for method, friendlyMethod in pairs(methods) do
    formatted = formatted .. " (" .. friendlyMethod .. ")";
  end
  if(formatted == "") then
    return " (ShouldNotAppearIfDoesTellColonolNutty)";
  end
  return formatted;
end

function isCNAPI.load(ingredientId, ingredientInfo)
  local ingredientStorage = isCNAPI.getIngredientStore();
  if(ingredientStorage[ingredientId] ~= nil) then
    --if(ingredientInfo ~= nil) then
    --  local existingIngredient = ingredientStorage[ingredientId];
    --  for idx, recipe in ipairs(ingredientInfo.recipes) do
    --    table.insert(existingIngredient.recipes, recipe);
    --  end
    --  ingredientStorage[ingredientId] = existingIngredient;
    --end
    return ingredientStorage[ingredientId]
  end
  local ingredientData = root.itemConfig({ name = ingredientId })
  if(ingredientData == nil) then
    logger.logDebug("No ingredient data found: " .. ingredientId)
    return nil
  end
  local ingredient = nil;
  if(ingredientInfo == nil or ingredientInfo.recipes == nil) then
    local craftMethods, filteredRecipes = isCNAPI.filterRecipes(root.recipesForItem(ingredientId))
    logger.logDebug("Ingredient data found: icon " .. ingredientData.config.inventoryIcon .. " directory " .. ingredientData.directory)
    if type(ingredientData.config.inventoryIcon) == 'table' then
      ingredientData.config.inventoryIcon = ingredientData.config.inventoryIcon[1].image
    end
    local ingredientIcon = UtilsCN.resizeImageToIconSize(ingredientData.config.inventoryIcon, ingredientData.directory)
    ingredient = { id = ingredientId, name = ingredientData.config.shortdescription, icon = ingredientIcon, recipes = filteredRecipes, methods = craftMethods }
    ingredient.displayName = ingredient.name
    ingredient.displayNameWithMethods = ingredient.displayName .. isCNAPI.formatMethods(ingredient.methods);
  else
    local ingredientIcon = UtilsCN.resizeImageToIconSize(ingredientInfo.icon, ingredientData.directory)
    ingredient = { id = ingredientId, name = ingredientData.config.shortdescription, displayName = ingredientInfo.displayName, displayNameWithMethods = ingredientInfo.displayNameWithMethods, icon = ingredientIcon, recipes = {}, methods = ingredientInfo.methods }
    for idx, recipe in ipairs(ingredientInfo.recipes) do
      if(not recipe.excludeFromRecipeBook) then
        if(recipe.methods == nil) then
          recipe.methods = {}
        end
        local newInput = {};
        for inputName, inputData in pairs(recipe.input) do
          local loadedItem = isCNAPI.load(inputName, inputData);
          local newItem = { id = loadedItem.id, displayName = loadedItem.name, icon = loadedItem.icon, recipes = loadedItem.recipes, methods = loadedItem.methods, count = inputData.count };
          newInput[inputName] = newItem;
        end
        recipe.input = newInput;
        table.insert(ingredient.recipes, recipe);
      end
    end
  end
  ingredientStorage[ingredientId] = ingredient
  return ingredient
end

function isCNAPI.filterRecipes(recipes)
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
      if(isCNAPI.isExcludedFromRecipeBook(group)) then
        excludeRecipe = true
        includeRecipe = false
      end
      if(not excludeRecipe and isCNAPI.passesAllFilters(recipeFilters.groupFilters, group)) then
        logger.logDebug("Recipe group passes filters: " .. group)
        -- Include recipe if at least one group passes all filters
        includeRecipe = true
        -- If the group matches the filters, there must be a friendly name for it, set it
        recipe.methods[group] = isCNAPI.getMethodFriendlyName(group)
        allMethods[group] = recipe.methods[group]
      end
    end
    if(includeRecipe and not excludeRecipe) then
      table.insert(result, isCNAPI.updateRecipeFormat(recipe))
    end
  end
  return allMethods, result
end

function isCNAPI.updateRecipeFormat(recipe)
  local newRecipe = {};
  local input = {};
  for idx, inputData in ipairs(recipe.input) do
    input[inputData.name] = { id = inputData.name, displayName = inputData.name, count = inputData.count };
  end
  newRecipe.input = input;
  newRecipe.output = recipe.output;
  newRecipe.groups = recipe.groups;
  newRecipe.methods = recipe.methods;
  newRecipe.displayMethods = isCNAPI.formatMethods(recipe.methods)
  return newRecipe;
end

function isCNAPI.isExcludedFromRecipeBook(recipeGroup)
  return recipeGroup == "ExcludeFromRecipeBook";
end

function isCNAPI.hasFriendlyNamefilter(recipeGroup)
  return isCNAPI.getMethodFriendlyName(recipeGroup) ~= nil;
end

function isCNAPI.passesAllFilters(filters, val)
  local passesFilters = true;
  for idx, filter in ipairs(filters) do
    if(not filter(val)) then
      passesFilters = false;
      break;
    end
  end
  return passesFilters;
end