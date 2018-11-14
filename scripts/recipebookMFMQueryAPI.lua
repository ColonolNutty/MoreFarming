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

function RecipeBookMFMQueryAPI.init(virtual)
  logger = DebugUtilsCN.init("[RBMFMQAPI]")
  EntityQueryAPI.init(virtual)
  message.setHandler("getSelectedItem", getSelectedItemHook);
  message.setHandler("selectItem", selectItemHook);
  
  RecipeBookMFMQueryAPI.isInitialized = true;
end

function RecipeBookMFMQueryAPI.initializeRecipeBook(methodName, onCompleteCallback)
  local recipeBookId = rbAPI.getRecipeBookEntityId()
  if(recipeBookId == nil) then
    if(onCompleteCallback ~= nil) then
      return onCompleteCallback(nil)
    end
    return;
  end
  local handle = function(rbId, mName)
    return function()
      return EntityQueryAPI.requestData(rbId, "initializeRecipeStore", 0, nil, mName);
    end
  end
  local onComplete = function(mName, onCompleteCB)
    return function(result)
      if(onCompleteCb ~= nil) then
        onCompleteCb(mName, result);
      end
    end
  end
  EntityQueryAPI.addRequest("requestInitializeRecipeStore", handle(recipeBookId, methodName), onComplete(methodName, onCompleteCallback))
end

function RecipeBookMFMQueryAPI.update(dt)
  EntityQueryAPI.update(dt);
end

function RecipeBookMFMQueryAPI.getRecipesForMethodName(recipeGroup)
  return rbAPI.queryRecipeBook("getRecipesForMethodName", 0, nil, recipeGroup)
end

function getSelectedItemHook(id)
  return rbAPI.queryRecipeBook("getSelectedItem", id, false, nil)
end

function selectItemHook(id, name, itemId)
  return rbAPI.queryRecipeBook("selectItem", id, false, itemId)
end

function rbAPI.getRecipeBookEntityId()
  local foundRecipeBookIds = world.objectQuery(object.position(), 5000, { name = "recipebookMFM" })
  if(#foundRecipeBookIds == 0) then
    --logger.logDebug("No recipe book found nearby")
    return nil
  end
  return foundRecipeBookIds[1]
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
  return EntityQueryAPI.requestData(recipeBookId, requestName, requestId, defaultResponse, data);
end