require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"
require "/scripts/MFM/ingredientStoreAPI.lua"

if(RecipeStoreCNAPI == nil) then
  RecipeStoreCNAPI = {};
end
local rsCNApi = {};

RECIPE_CONFIGURATION_PATH = "/recipeCrafterMFM/";
RECIPE_FILTER_FRIENDLY_NAMES = "/recipeCrafterMFM/methodFriendlyNamesMFM.json"

local logger = nil;

function RecipeStoreCNAPI.init(virtual)
  logger = DebugUtilsCN.init("[CNRSAPI]");
  IngredientStoreCNAPI.init(virtual);
  message.setHandler("getRecipesContainingIngredientCounts", rsCNApi.getRecipesContainingIngredientCounts);
  message.setHandler("initializeRecipeStore", rsCNApi.initializeRecipeStore);
  message.setHandler("getRecipesForMethodName", rsCNApi.getRecipesForMethodName);
  message.setHandler("getRecipesForMethodNames", rsCNApi.getRecipesForMethodNames);
  message.setHandler("refreshRecipes", rsCNApi.refreshRecipes);
  
  if(virtual) then
    RecipeStoreCNAPI.rsCNApi = rsCNApi;
  end
  
  storage.methodStore = nil;
end

function rsCNApi.getMethodStore(methodName, recipeStore)
  if(methodName == nil) then
    return nil;
  end
  if(storage.methodStore ~= nil and storage.methodStore[methodName] ~= nil) then
    return storage.methodStore[methodName];
  end
  if(storage.methodStore == nil) then
    storage.methodStore = { };
  end
  if(recipeStore ~= nil) then
    storage.methodStore[methodName] = recipeStore
    return recipeStore;
  end
  
  local methodRecipes = rsCNApi.loadMethodRecipes(methodName);
  storage.methodStore[methodName] = methodRecipes
  return methodRecipes;
end

function rsCNApi.loadMethodRecipes(methodName)
  local filterFriendlyNames = root.assetJson(RECIPE_FILTER_FRIENDLY_NAMES);
  logger.logDebug("Loading recipes for: " .. methodName);
  local recipeConfigPath = RECIPE_CONFIGURATION_PATH .. methodName .. "Recipes.config";
  logger.logDebug("Looking for recipe configuration at path: " .. recipeConfigPath);
  local recipeConfigData = root.assetJson(recipeConfigPath);
  local methodFilter = {
    recipesCraftFrom = {},
    recipesCraftTo = {}
  };
  if(recipeConfigData == nil) then
    return methodFilter;
  end
  local possibleCraftItems = recipeConfigData.possibleOutput;
  local displayMethod = filterFriendlyNames[methodName];
  for recipeOutputNameIdx, recipeOutputName in pairs(possibleCraftItems) do
    local recipeDataList = root.recipesForItem(recipeOutputName);
    if (recipeDataList ~= nil) then
      local outputItemData = root.itemConfig({ name = recipeOutputName });
      local newRecipes = {
        recipes = {},
        displayName = outputItemData.config.shortdescription,
        methods = {},
        displayNameWithMethods = outputItemData.config.shortdescription .. "(" .. displayMethod .. ")",
        icon = outputItemData.config.inventoryIcon
      }
      newRecipes.methods[methodName] = displayMethod;
      for recipeIdx, recipeData in pairs(recipeDataList) do
        local recipe = {
          output = {},
          displayMethods = " " .. "(" .. displayMethod .. ")",
          excludeFromRecipeBook = false,
          input = {},
          methods = {},
          groups = {}
        };
        recipe.methods[methodName] = displayMethod;
        table.insert(recipe.groups, methodName);
        local recipeInputs = recipeData.input;
        local recipeOutput = recipeData.output;
        local recipeOutputItemCount = recipeOutput.count;
        recipe.output.name = recipeOutputName;
        recipe.output.count = recipeOutputItemCount;
      
        local recipeIngredients = {};
        for ingredientIdx, ingredient in pairs(recipeInputs) do
          local ingredientName = ingredient.name;
          local ingredientCount = ingredient.count;
          local ingredientItemData = root.itemConfig({ name = ingredientName });
          recipeIngredients[ingredientName] = {
            displayName = ingredientItemData.config.shortdescription,
            count = ingredientCount,
            icon = ingredientItemData.config.inventoryIcon,
            id = ingredientName
          };
          if (methodFilter.recipesCraftFrom[ingredientName] == nil) then
            methodFilter.recipesCraftFrom[ingredientName] = {};
          end
          table.insert(methodFilter.recipesCraftFrom[ingredientName], recipeOutputName); 
        end
        recipe.input = recipeIngredients;
        table.insert(newRecipes.recipes, recipe);
      end
      methodFilter.recipesCraftTo[recipeOutputName] = IngredientStoreCNAPI.loadIngredient(recipeOutputName, newRecipes);
    end
  end
  return methodFilter;
end

--- methodName (string) (ex. bakingMFM)
--- ingredients (object) (ex. { "ingredientOne": 5, "ingredientTwo": 3 }
function rsCNApi.getRecipesContainingIngredientCounts(id, name, methodName, ingredients)
  return RecipeStoreCNAPI.getRecipesContainingIngredientCounts(methodName, ingredients);
end

function RecipeStoreCNAPI.getRecipesContainingIngredientCounts(methodName, ingredients)
  if(methodName == nil or ingredients == nil) then
    if(methodName == nil) then
      logger.logDebug("Method name is null")
    end
    if(ingredients == nil) then
      logger.logDebug("Ingredients null")
    end
    return {};
  end
  logger.logDebug("Getting recipes for method " .. methodName);
  local methodStore = rsCNApi.getMethodStore(methodName);
  local recipesContainingIngredients = {};
  for slot, containerIngredient in pairs(ingredients) do
    local ingredientRecipes = methodStore.recipesCraftFrom[containerIngredient.name];
    if(ingredientRecipes == nil) then
      break;
    end
    local outputRecipes = nil;
    for idx, recipeOutputName in ipairs(ingredientRecipes) do
      logger.logDebug("Checking recipeOutputName: " .. recipeOutputName);
      outputRecipes = methodStore.recipesCraftTo[recipeOutputName];
      if(outputRecipes ~= nil) then
        local matchingRecipes = {};
        for idx, recipe in ipairs(outputRecipes.recipes) do
          if (RecipeStoreCNAPI.ingredientsMatchRecipe(recipe, ingredients)) then
            logger.logDebug("Recipe matched " .. recipe.output.name);
            table.insert(matchingRecipes, recipe);
          end
        end
        if(#matchingRecipes > 0) then
          recipesContainingIngredients[recipeOutputName] = matchingRecipes;
        end
      end
    end
    break;
  end
  return recipesContainingIngredients;
end

function RecipeStoreCNAPI.ingredientsMatchRecipe(recipe, ingredients)
  logger.logDebug("Checking recipe " .. recipe.output.name);
  local checkedIngredients = {};
  local recipeMatches = true;
  local inputMatches = false;
  for slot, ingredient in pairs(ingredients) do
    logger.logDebug("Matching input: " .. ingredient.name);
    inputMatches = false;
    for inputName, inputInfo in pairs(recipe.input) do
      if(ingredient.name == inputName) then
        if(ingredient.count >= inputInfo.count) then
          logger.logDebug("Ingredient matched!");
          inputMatches = true;
          break;
        else
          logger.logDebug("Counts didnt match: (" .. ingredient.count .. ", " .. inputInfo.count .. ")");
        end
      else
        logger.logDebug("Names didnt match: (" .. ingredient.name .. ", " .. inputName .. ")");
      end
    end
    if(not inputMatches) then
      recipeMatches = false;
      break;
    end
    table.insert(checkedIngredients, ingredient.name);
  end
  if(recipeMatches) then
    logger.logDebug("Checking recipe inputs match all ingredients in container");
    local ingredientMatches = false;
    for inputName, inputInfo in pairs(recipe.input) do
      logger.logDebug("Verifying input is in container: " .. inputName);
      ingredientMatches = false;
      for idx, ingredientName in ipairs(checkedIngredients) do
        if(inputName == ingredientName) then
          ingredientMatches = true;
          break;
        else
          logger.logDebug("Found container ingredient that was not part of the recipe " .. ingredientName);
        end
      end
      if(not ingredientMatches) then
        logger.logDebug("Ingredients not found in container");
        recipeMatches = false;
        break;
      end
    end
  end
  return recipeMatches;
end

--- methodName (string)
function rsCNApi.getRecipesForMethodName(id, name, methodName)
  if(methodName == nil) then
    return {};
  end
  
  return rsCNApi.getMethodStore(methodName);
end

--- methodNames (string array)
function rsCNApi.getRecipesForMethodNames(id, name, methodNames)
  local recipes = {};
  if(methodNames == nil) then
    return recipes;
  end
  
  for idx, methodName in ipairs(methodNames) do
    local methodStore = rsCNApi.getMethodStore(methodName);
    if(methodStore ~= nil) then
      recipes[methodName] = methodStore;
    end
  end
  return recipes;
end

--- methodName (string) (ex. bakingMFM)
--- recipeStore (object) ({ recipesCraftTo, recipesCraftFrom })
function RecipeStoreCNAPI.initializeRecipeStore(methodName, recipeStore)
  return rsCNApi.getMethodStore(methodName, recipeStore);
end

--- methodName (string) (ex. bakingMFM)
--- recipeStore (object) ({ recipesCraftTo, recipesCraftFrom })
function rsCNApi.initializeRecipeStore(id, name, methodName, recipeStore)
  return RecipeStoreCNAPI.initializeRecipeStore(methodName, recipeStore);
end

function rsCNApi.refreshRecipes(id, name, itemId)
  for methodName, methodStore in pairs(storage.methodStore) do
    if(methodStore.recipesCraftTo[itemId] ~= nil) then
      local itemData = methodStore.recipesCraftTo[itemId];
      local newRecipes = {};
      for idx, recipe in ipairs(itemData.recipes) do
        for ingredientName, ingredientData in pairs(recipe.input) do
          if(ingredientData.icon == nil) then
            local ingredientInfo = IngredientStoreCNAPI.loadIngredient(ingredientName);
            recipe.input[ingredientName] = { id = ingredientName, displayName = ingredientInfo.displayName, icon = ingredientInfo.icon, methods = ingredientInfo.methods, count = ingredientData.count }
          end
        end
        table.insert(newRecipes, recipe)
      end
      itemData.recipes = newRecipes;
      methodStore.recipesCraftTo[itemId] = itemData;
    end
  end
  return true
end
---------------------------------------------------------