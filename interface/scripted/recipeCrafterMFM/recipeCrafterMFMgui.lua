require "/scripts/debugUtilsCN.lua"
require "/scripts/MFM/entityQueryAPI.lua"
require "/interface/scripted/recipebookMFM/recipebookMFMgui.lua"

local recipeBookVisible = false
local setInitialFilter = false
local entityId = nil
local logger = nil
local byproductSlot = 17
local checkedForRecipeBook = false
local dataStore = nil;

function init()
  logger = DebugUtilsCN.init("[RCGUI]")
  entityId = pane.containerEntityId()
  EntityQueryAPI.init()
  setInitialFilter = false
  --sb.logInfo("Initializing Recipe Crafter GUI");
  recipeBookVisible = false
  RBMFMGui.init(entityId)
  hideByproductSlotIfSpacesNotAvailable()
end

function update(dt)
  RBMFMGui.update(dt)
end

function RBMFMGui.onDataStoreLoaded(dataStoreResult)
  dataStore = dataStoreResult;
  requestEnableSingleFilter();
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
      RBMFMGui.loadDataStore()
    end
  end
  EntityQueryAPI.addRequest("checkForRecipeBook" .. entityId, handle, onComplete)
end

function craft()
  logger.logDebug("Crafting with Crafter GUI");
  world.sendEntityMessage(entityId, "craft")
end

function requestEnableSingleFilter()
  local handle = function(eId)
    return function()
      local result = EntityQueryAPI.requestData(eId, "getFilterId", eId)
      if(result ~= nil) then
        return true, result
      end
      return false, nil
    end
  end
  local onComplete = function(result)
    local methodNames = {}
    table.insert(methodNames, result)
    RBMFMGui.displayItemsByMethod(methodNames)
    setInitialFilter = true
  end
  EntityQueryAPI.addRequest("requestEnableSingleFilter" .. entityId, handle(entityId), onComplete)
end

function hideByproductSlotIfSpacesNotAvailable()
  local containerSize = world.containerSize(entityId)
  if(containerSize < byproductSlot) then
    widget.setVisible("lblByproduct", false)
    widget.setVisible("pointerBottom", false)
  end
end