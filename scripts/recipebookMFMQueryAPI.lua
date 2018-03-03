RecipeBookMFMAPI = {}

local rbAPI = {
        hasError = false,
        requestsToObject = {}
      }

function rbAPI.getDefaultDataStore()
  return {
    selectedFoodId = nil,
    ingredientStore = {},
    methodFilters = {},
    sortedMethodFilters = {},
    methodFilterNames = {},
    methodFriendlyNames = {}
  };
end

function rbAPI.getDefaultItem(itemId)
  return { id = itemId, name = itemId, icon = "", recipes = {}, methods = {} }
end

function rbAPI.getRecipeBookEntityId()
  local foundRecipeBookIds = world.objectQuery(object.position(), 5000, { name = "recipebookMFM" })
  if(#foundRecipeBookIds == 0) then
    sb.logInfo("No recipe book found nearby")
    return nil
  end
  return foundRecipeBookIds[1]
end

function rbAPI.getRecipesForFilter(id, name, filterName)
  return rbAPI.queryRecipeBook("getRecipesForFilter", id, {}, filterName)
end

function rbAPI.queryRecipeBook(requestName, requestId, defaultResponse, data)
  local recipeBookId = rbAPI.getRecipeBookEntityId()
  if(recipeBookId == nil) then
    return defaultReturnData
  end
  return rbAPI.requestData(recipeBookId, requestName, requestId, defaultResponse, data)
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

function RecipeBookMFMAPI.init()
  message.setHandler("getDataStore", rbAPI.getDataStore);
  message.setHandler("setDataStore", rbAPI.setDataStore);
  message.setHandler("updateSelectedFilters", rbAPI.updateSelectedFilters);
  message.setHandler("storeIngredient", rbAPI.storeIngredient);
  message.setHandler("updateSelectedId", rbAPI.updateSelectedId);
  message.setHandler("getRecipesForFilter", rbAPI.getRecipesForFilter);
end

function rbAPI.requestData(entityId, requestName, requestId, defaultResponse, data)
  if(entityId == nil) then
    sb.logError("[RBMFMQAPI] No EntityId found")
    rbAPI.hasError = true
    return defaultResponse
  end
  local requestIdentifier = requestName .. requestId
  local request = rbAPI.requestsToObject[requestIdentifier]
  if(request == nil) then
    if(data ~= nil) then
      rbAPI.requestsToObject[requestIdentifier] = world.sendEntityMessage(entityId, requestName, data)
    else
      rbAPI.requestsToObject[requestIdentifier] = world.sendEntityMessage(entityId, requestName)
    end
    request = rbAPI.requestsToObject[requestIdentifier]
  end
  if(not request:finished()) then
    logDebug("Request not finished: " .. requestIdentifier)
    return nil
  end
  if(not request:succeeded()) then
    local errorMsg = request:error()
    if(errorMsg ~= nil) then
      sb.logError(errorMsg .. " the message was '" .. requestIdentifier .. "'")
      rbAPI.hasError = true
    end
    logDebug("Request failed: " .. requestIdentifier)
    rbAPI.requestsToObject[requestIdentifier] = nil
    return defaultResponse
  end
  local result = request:result()
  if(not result) then
    return defaultResponse
  end
  logDebug("Finished request: " .. requestIdentifier)
  rbAPI.requestsToObject[requestIdentifier] = nil
  return result
end

function logDebug(msg)
  if(not enableDebug) then
    return
  end
  if(DebugUtilsCN) then
    DebugUtilsCN.logDebug(msg)
  else
    sb.logInfo("[RBGUI] " .. msg)
  end
end