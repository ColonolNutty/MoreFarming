DebugUtilsCN = {};
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

function settings.setDebugState(val, prefix)
  if(storage) then
    storage.debugState = val or false
  else
    settings.debugState = val or false
  end
  if(settings.getDebugState()) then
    sb.logInfo(prefix .. " Debug Toggled On")
  else
    sb.logInfo(prefix .. " Debug Toggled Off")
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
  settings.initialize()
  if(message) then
    message.setHandler("getDebugState", debugUtils.getDebugState)
    message.setHandler("setDebugState", debugUtils.setDebugState)
  end
  return debugUtils.createNewLogger(messagePrefix)
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
  settings.setDebugState(newValue, "Global")
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

function debugUtils.createNewLogger(messagePrefix)
  --sb.logInfo("Initializing Logger with prefix " .. messagePrefix)
  local logger = {
    messagePrefix = messagePrefix
  }
  logger.setDebugState = function(val)
    settings.setDebugState(val, logger.messagePrefix)
  end
  logger.getDebugState = settings.getDebugState
  logger.logInfo = function(msg, indentAmt)
    sb.logInfo(logger.messagePrefix .. " " .. debugUtils.getIndentString(indentAmt) .. msg)
  end
  logger.logDebug = function(msg, indentAmt)
    if(not settings.getDebugState()) then
      return;
    end
    sb.logInfo(logger.messagePrefix .. " " .. debugUtils.getIndentString(indentAmt) .. msg)
  end
  logger.logError = function(msg, indentAmt)
    sb.logError(logger.messagePrefix .. " " .. debugUtils.getIndentString(indentAmt) .. msg)
  end
  logger.enableDebug = function()
    logger.setDebugState(true)
  end
  
  return logger
end