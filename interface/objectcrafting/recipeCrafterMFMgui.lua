function makeMeal()
  world.sendEntityMessage(pane.containerEntityId(), "makeMeal")
end

function enableDebug()
  local toEnable = widget.getChecked("enableDebug")
  if(toEnable) then
    sb.logInfo("Enabled")
  else
    sb.logInfo("Disabled")
  end
  world.sendEntityMessage(pane.containerEntityId(), "setEnableDebug", toEnable)
end