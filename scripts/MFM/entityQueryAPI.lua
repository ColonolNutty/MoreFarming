require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"
if(EntityQueryAPI == nil) then
  EntityQueryAPI = {
    hasError = false,
    isInitialized = false,
    requestsToObject = {},
    requests = {},
    requestIds = {}
  }
end
local logger = nil
local eqApi = {};

local entityRequests = {}

function EntityQueryAPI.init()
  logger = DebugUtilsCN.init("[EQAPI]")
  if(EntityQueryAPI.isInitialized) then
    return;
  end
  EntityQueryAPI.hasError = false;
  EntityQueryAPI.isInitialized = true;
end

function EntityQueryAPI.update(dt)
  if(EntityQueryAPI.hasError) then
    return false
  end
  if(not EntityQueryAPI.isInitialized) then
    sb.logError("EntityQueryAPI was not Initialized")
    EntityQueryAPI.hasError = true
    return false
  end
  eqApi.updateRequests()
  return true
end

function EntityQueryAPI.uninit()

end

function eqApi.updateRequests()
  if(#EntityQueryAPI.requests == 0) then
    return
  end
  
  logger.logDebug("Requests found, handling")
  local currentRequests = EntityQueryAPI.requests
  EntityQueryAPI.requests = {}
  local activeRequests = {}
  for i = 1, #currentRequests do
    local request = currentRequests[i]
    if(request ~= nil and request.active) then
      logger.logDebug("Handling request: " .. request.id)
      local isDone, result = request.handle();
      if(isDone) then
        logger.logDebug("Finished Handling request: " .. request.id)
        request.active = false;
        request.onCompleted(result);
      else
        table.insert(activeRequests, request)
      end
    end
  end
  for i = 1, #activeRequests do
    table.insert(EntityQueryAPI.requests, activeRequests[i])
  end
  logger.logDebug("Done with requests")
end

function EntityQueryAPI.addRequest(requestId, handle, onCompleted)
  if(EntityQueryAPI.requestIds[requestId] == false) then
    return
  end
  if(onCompleted == nil) then
    onCompleted = function(result) end
  end
  local newOnCompleted = function(reqId, oldOnCompleted)
    return function(result)
      EntityQueryAPI.requestIds[reqId] = nil
      oldOnCompleted(result)
    end
  end
  logger.logDebug("Adding new request: " .. requestId)
  EntityQueryAPI.requestIds[requestId] = false
  table.insert(EntityQueryAPI.requests, {
    active = true,
    id = requestId,
    handle = handle,
    onCompleted = newOnCompleted(requestId, onCompleted)
  });
end

function EntityQueryAPI.requestData(entityId, requestName, requestId, defaultResponse, data)
  if(not EntityQueryAPI.isInitialized) then
    sb.logError("EntityQueryAPI not initialized before use")
    return
  end
  if(entityId == nil) then
    sb.logError("No EntityId found")
    EntityQueryAPI.hasError = true
    return defaultResponse
  end
  local requestIdentifier = requestName .. "_" .. requestId
  local request = EntityQueryAPI.requestsToObject[requestIdentifier]
  if(request == nil) then
    if(data ~= nil) then
      EntityQueryAPI.requestsToObject[requestIdentifier] = world.sendEntityMessage(entityId, requestName, data)
    else
      EntityQueryAPI.requestsToObject[requestIdentifier] = world.sendEntityMessage(entityId, requestName)
    end
    request = EntityQueryAPI.requestsToObject[requestIdentifier]
  end
  if(not request:finished()) then
    logger.logDebug("Request not finished: " .. requestIdentifier)
    return nil
  end
  if(not request:succeeded()) then
    local errorMsg = request:error()
    if(errorMsg ~= nil) then
      logger.logError("Error occurred during request with identifier '" .. requestIdentifier .. "', Message: '" .. errorMsg .. "'")
      EntityQueryAPI.hasError = true
    end
    logger.logDebug("Request failed: " .. requestIdentifier)
    EntityQueryAPI.requestsToObject[requestIdentifier] = nil
    return defaultResponse
  end
  local result = request:result()
  if(not result) then
    return defaultResponse
  end
  logger.logDebug("Finished request: " .. requestIdentifier)
  EntityQueryAPI.requestsToObject[requestIdentifier] = nil
  return result
end