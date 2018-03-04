DebugUtilsCN = {
  debugMsgPrefix = "[DBGCN]"
};
local debugUtils = {};

------------------------ Settings ------------------------

local settings = {
  debugState = nil
}

function settings.initialize()
  if(settings.debugState == nil) then
    settings.debugState = false
  end
end

function settings.setDebugState(val)
  if(storage) then
    storage.debugState = val or false
  else
    settings.debugState = val or false
  end
end

function settings.getDebugState()
  if(storage) then
    return storage.debugState
  else
    return settings.debugState
  end
end

----------------------------------------------------------

function DebugUtilsCN.init(messagePrefix)
  if(messagePrefix ~= nil) then
    DebugUtilsCN.debugMsgPrefix = messagePrefix
  end
  settings.initialize()
  message.setHandler("getDebugState", debugUtils.getDebugState)
  message.setHandler("setDebugState", debugUtils.setDebugState)
end

function DebugUtilsCN.enableDebug()
  settings.setDebugState(true);
end

function DebugUtilsCN.logInfo(msg, indentAmt)
  if(settings.getDebugState()) then
    sb.logInfo(DebugUtilsCN.debugMsgPrefix .. " " .. debugUtils.getIndentString(indentAmt) .. msg)
  end
end

function DebugUtilsCN.logDebug(msg, indentAmt)
  if(settings.getDebugState()) then
    sb.logInfo(DebugUtilsCN.debugMsgPrefix .. " " .. debugUtils.getIndentString(indentAmt) .. msg)
  end
end

------------------------ Handlers ------------------------

--- Meant to be called from a GUI script query ---
function debugUtils.getDebugState()
  return {
    debugState = settings.getDebugState()
  }
end

--- Meant to be called from a GUI script query ---
function debugUtils.setDebugState(id, name, newValue)
  settings.setDebugState(newValue)
  if(settings.getDebugState()) then
    sb.logInfo(DebugUtilsCN.debugMsgPrefix .. " Debug Toggled On")
  else
    sb.logInfo(DebugUtilsCN.debugMsgPrefix .. " Debug Toggled Off")
  end
end

----------------------------------------------------------

function debugUtils.getIndentString(indentAmt)
  if(not indentAmt or indentAmt < 1) then
    return ""
  end
  if(indentAmt == 1) then
    return " "
  end
  local indent = ""
  for i = 1,indentAmt do
    indent = indent .. " "
  end
  return indent
end