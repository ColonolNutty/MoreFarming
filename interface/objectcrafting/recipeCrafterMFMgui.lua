local debugStateUpdated = false;
local debugStateRequest = nil;

function craft()
  world.sendEntityMessage(pane.containerEntityId(), "craft")
end

function update()
  updateDebugState()
end

function toggleDebug()
  local toEnable = widget.getChecked("toggleDebug")
  world.sendEntityMessage(pane.containerEntityId(), "setDebugState", toEnable)
  if(toEnable) then
    sb.logInfo("[RCGUI] Debug is enabled")
  else
    sb.logInfo("[RCGUI] Debug is disabled")
  end
end

function updateDebugState()
  if(debugStateUpdated) then
    return
  end
  if(debugStateRequest == nil) then
    debugStateRequest = world.sendEntityMessage(pane.containerEntityId(), "getDebugState")
  end
  if(not debugStateRequest:finished()) then
    return
  end
  if(not debugStateRequest:succeeded()) then
    local errorMsg = debugStateRequest:error()
    if(errorMsg ~= nil) then
      sb.logError(errorMsg)
    end
    toggleDebug()
    debugStateUpdated = true
    return
  end
  local debugStateRequestResult = debugStateRequest:result()
  if(not debugStateRequestResult) then
    debugStateUpdated = true
    return
  end
  local debugState = debugStateRequestResult.debugState
  if(debugState) then
    sb.logInfo("[RCGUI] Debug is enabled")
  else
    sb.logInfo("[RCGUI] Debug is disabled")
  end
  widget.setChecked("enableDebug", debugState)
  debugStateUpdated = true
  debugStateRequest = nil
end