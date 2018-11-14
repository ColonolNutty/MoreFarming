require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"
require "/scripts/MFM/ingredientStoreAPI.lua"

if(RecipeStoreCNAPI == nil) then
  RecipeStoreCNAPI = {};
end
local rsCNApi = {};

RECIPE_CONFIGURATION_PATH = "/recipeCrafterMFM/";

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
  
  logger.logDebug("Loading recipes for: " .. methodName)
  local recipeConfigPath = RECIPE_CONFIGURATION_PATH .. methodName .. "Recipes.config"
  logger.logDebug("Looking for recipe configuration at path: " .. recipeConfigPath)
  
  local methodRecipes = rsCNApi.loadMethodRecipes(root.assetJson(recipeConfigPath));
  storage.methodStore[methodName] = methodRecipes
  return methodRecipes;
end

function rsCNApi.loadMethodRecipes(methodRecipes)
   local methodFilter = {
    recipesCraftFrom = {},
    recipesCraftTo = {}
  };
  if(methodRecipes == nil) then
    return methodFilter;
  end
  if(methodRecipes.recipesCraftFrom ~= nil) then
    methodFilter.recipesCraftFrom = methodRecipes.recipesCraftFrom;
  end
  if(methodRecipes.recipesToCraft ~= nil) then
    for itemName, itemData in pairs(methodRecipes.recipesToCraft) do
      methodFilter.recipesCraftTo[itemName] = IngredientStoreCNAPI.loadIngredient(itemName, itemData);
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
    logger.logDebug("Method name or ingredients null");
    return {};
  end
  logger.logDebug("Getting recipes for method " .. methodName);
  local methodStore = rsCNApi.getMethodStore(methodName);
  local recipesContainingIngredients = {};
  for slot, ingredient1 in pairs(ingredients) do
    local ingredientRecipes = methodStore.recipesCraftFrom[ingredient1.name];
    if(ingredientRecipes == nil) then
      break;
    end
    for idx, recipeOutputName in ipairs(ingredientRecipes) do
      local outputRecipes = methodStore.recipesCraftTo[recipeOutputName];
      if(outputRecipes ~= nil) then
        local matchingRecipes = {};
        for idx, recipe in ipairs(outputRecipes.recipes) do
          logger.logDebug("Checking recipe");
          local recipeMatches = true;
          for inputName, inputInfo in pairs(recipe.input) do
            logger.logDebug("Matching input: " .. inputName);
            local inputMatches = false;
            for slot, ingredient in pairs(ingredients) do
              if(ingredient.name == inputName) then
                if(ingredient.count >= inputInfo.count) then
                  logger.logDebug("Ingredient matched!")
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
          end
          if(recipeMatches) then
              logger.logDebug("Recipe matched");
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