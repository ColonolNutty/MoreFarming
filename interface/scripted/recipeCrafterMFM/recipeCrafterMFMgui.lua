require "/scripts/debugUtilsCN.lua"
require "/scripts/MFM/entityQueryAPI.lua"

local recipeBookVisible = false
local setInitialFilter = false
local entityId = nil
local logger = nil
local byproductSlot = 17
local checkedForRecipeBook = false

function init()
  logger = DebugUtilsCN.init("[RCGUI]")
  entityId = pane.containerEntityId()
  setInitialFilter = false
  --sb.logInfo("Initializing Recipe Crafter GUI");
  recipeBookVisible = false
  RBMFMGui.init(entityId)
  EntityQueryAPI.init()
  hideByproductSlotIfSpacesNotAvailable()
end

function update(dt)
  if(RBMFMGui.isInitialized and not setInitialFilter) then
    requestEnableSingleFilter()
  end
  RBMFMGui.update(dt)
  EntityQueryAPI.update(dt)
end

function checkForRecipeBook()
  if(checkedForRecipeBook) then
    return;
  end
  checkedForRecipeBook = true
  local handle = function()
    local result = EntityQueryAPI.requestData(entityId, "reloadRecipeBook", entityId)
    if(result ~= nil) then
      return true, result
    end
    return false, nil
  end
  local onComplete = function(result)
    if(result) then
      RBMFMGui.reloadDataStore()
    end
  end
  EntityQueryAPI.addRequest("checkForRecipeBook" .. entityId, handle, onComplete)
end

function craft()
  logger.logDebug("Crafting with Crafter GUI");
  world.sendEntityMessage(entityId, "craft")
end

function requestEnableSingleFilter()
  local handle = function()
    local result = EntityQueryAPI.requestData(entityId, "getFilterId", entityId)
    if(result ~= nil) then
      return true, result
    end
    return false, nil
  end
  local onComplete = function(result)
    RBMFMGui.filterByMethod(result)
    setInitialFilter = true
  end
  EntityQueryAPI.addRequest("requestEnableSingleFilter" .. entityId, handle, onComplete)
end

function hideByproductSlotIfSpacesNotAvailable()
  local containerSize = world.containerSize(entityId)
  if(containerSize < byproductSlot) then
    widget.setVisible("lblByproduct", false)
    widget.setVisible("pointerBottom", false)
  end
end