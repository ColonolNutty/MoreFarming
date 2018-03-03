local recipeBookVisible = false
local setInitialFilter = false
local addedRequest = false

function init()
  setInitialFilter = false
  sb.logInfo("Initializing Recipe Crafter GUI");
  recipeBookVisible = false
  RBMFMGui.init(pane.containerEntityId())
end

function update(dt)
  if(RBMFMGui.isInitialized and not setInitialFilter and not addedRequest) then
    requestEnableSingleFilter()
    addedRequest = true
  end
  RBMFMGui.update(dt)
end

function craft()
  sb.logInfo("Crafting with Crafter GUI");
  world.sendEntityMessage(pane.containerEntityId(), "craft")
end

function requestEnableSingleFilter()
  local handle = function()
    local result = RequestsMFMAPI.requestData("getFilterId", 0)
    if(result ~= nil) then
      return true, result
    end
    return false, nil
  end
  local onComplete = function(result)
    local success = RBMFMGui.enableSingleFilter(result)
    if(success) then
      setInitialFilter = true
    end
    addedRequest = false
  end
  RequestsMFMAPI.addRequest(handle, onComplete)
end