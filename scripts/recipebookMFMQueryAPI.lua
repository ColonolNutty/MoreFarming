require "/scripts/debugUtilsCN.lua"
require "/scripts/MFM/entityQueryAPI.lua"

if(RecipeBookMFMQueryAPI == nil) then
  RecipeBookMFMQueryAPI = {
    isInitialized = false
};
end

local rbAPI = {
        hasError = false,
        requestsToObject = {}
      };

local logger = nil;

function RecipeBookMFMQueryAPI.init()
  logger = DebugUtilsCN.init("[RBMFMQAPI]")
  EntityQueryAPI.init()
  message.setHandler("getDataStore", rbAPI.getDataStore);
  message.setHandler("setDataStore", rbAPI.setDataStore);
  message.setHandler("updateSelectedFilters", rbAPI.updateSelectedFilters);
  message.setHandler("storeIngredient", rbAPI.storeIngredient);
  message.setHandler("updateSelectedId", rbAPI.updateSelectedId);
  message.setHandler("getRecipesForFilter", RecipeBookMFMQueryAPI.getRecipesForFilter);
  RecipeBookMFMQueryAPI.isInitialized = true;
end

function RecipeBookMFMQueryAPI.update(dt)
  EntityQueryAPI.update(dt);
end

function rbAPI.getDefaultDataStore()
  return {
    selectedItemId = nil,
    ingredientStore = {},
    methodFilters = {},
    sortedMethodFilters = {},
    methodFilterNames = {},
    methodFriendlyNames = {},
    recipeBookExists = false
  };
end

function rbAPI.getDefaultItem(itemId)
  return { id = itemId, name = itemId, icon = "", recipes = {}, methods = {} }
end

function rbAPI.getRecipeBookEntityId()
  local foundRecipeBookIds = world.objectQuery(object.position(), 5000, { name = "recipebookMFM" })
  if(#foundRecipeBookIds == 0) then
    --logger.logDebug("No recipe book found nearby")
    return nil
  end
  return foundRecipeBookIds[1]
end

function RecipeBookMFMQueryAPI.getRecipesForFilter(id, name, filterName)
  return rbAPI.queryRecipeBook("getRecipesForFilter", id or filterName, {}, filterName)
end

function rbAPI.queryRecipeBook(requestName, requestId, defaultResponse, data)
  if(not RecipeBookMFMQueryAPI.isInitialized) then
    logger.logError("RecipeBookMFMQueryAPI not initialized")
    return defaultResponse
  end
  local recipeBookId = rbAPI.getRecipeBookEntityId()
  if(recipeBookId == nil) then
    return defaultResponse
  end
  return EntityQueryAPI.requestData(recipeBookId, requestName, requestId, defaultResponse, data)
end

function rbAPI.getDataStore(id)
    return rbAPI.queryRecipeBook("getDataStore", id, rbAPI.getDefaultDataStore(), nil)
end

function rbAPI.setDataStore(id, name, newDataStore)
    return rbAPI.queryRecipeBook("setDataStore", id, false, newDataStore)
end

function rbAPI.updateSelectedFilters(id, name, filterData)
    return rbAPI.queryRecipeBook("updateSelectedFilters", id, false, filterData)
end

function rbAPI.storeIngredient(id, name, itemId)
    return rbAPI.queryRecipeBook("storeIngredient", id, rbAPI.getDefaultItem(itemId), itemId)
end

function rbAPI.updateSelectedId(id, name, newId)
    return rbAPI.queryRecipeBook("updateSelectedId", id, false, newId)
end