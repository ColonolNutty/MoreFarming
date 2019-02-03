require "/scripts/debugUtilsCN.lua"
require "/scripts/MFM/entityQueryAPI.lua"

local debugStateUpdated = false;
local entityId = nil
local logger = nil

TOGGLE_DEBUG_NAME = "toggleDebug"

function craft()
  logger.logDebug("Crafting with old crafting GUI");
  world.sendEntityMessage(entityId, "craft")
end

function init()
  logger = DebugUtilsCN.init("[OldRCGUI]")
  EntityQueryAPI.init()
  entityId = pane.containerEntityId()
  debugStateUpdated = false;
end

function update(dt)
  if(not EntityQueryAPI.update(dt)) then
    return
  end
  updateDebugState()
end

function toggleDebug()
  if(entityId == nil) then
    logger.logError("Failed to toggle debug, entityId is nil")
    return
  end
  local toEnable = widget.getChecked(TOGGLE_DEBUG_NAME)
  logger.setDebugState(toEnable)
  world.sendEntityMessage(entityId, "setDebugState", toEnable)
end

function updateDebugState()
  if(debugStateUpdated) then
    return
  end
  local handle = function()
    local result = EntityQueryAPI.requestData(entityId, "getDebugState", 0, nil)
    if(result ~= nil) then
      return true, result
    end
    return false, nil
  end
  
  local onCompleted = function(debugState)
    logger.setDebugState(debugState)
    widget.setChecked(TOGGLE_DEBUG_NAME, debugState)
    debugStateUpdated = true
  end
  
  EntityQueryAPI.addRequest("updateDebugState", handle, onCompleted)
end