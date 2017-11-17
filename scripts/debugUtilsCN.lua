DebugUtilsCN = {
  debugMsgPrefix = "[DBGCN]"
};
local debugUtils = {};
local debugLoggingEnabled = false;
local debugMsgPrefix = "[DBGCN]"

function DebugUtilsCN.init(messagePrefix)
  if(messagePrefix ~= nil) then
    DebugUtilsCN.debugMsgPrefix = messagePrefix
  end
  if(not storage) then
    sb.logInfo(DebugUtilsCN.debugMsgPrefix .. " No 'storage' variable found within this script, disabling debug logging")
    debugLoggingEnabled = false;
    return
  end
  debugLoggingEnabled = true
  if(storage.enableDebug == nil) then
    storage.enableDebug = false
  end
  message.setHandler("getDebugState", debugUtils.getDebugState)
  message.setHandler("setDebugState", debugUtils.setDebugState)
end

function debugUtils.getDebugState(id, name)
  return {
    debugState = debugLoggingEnabled and storage.enableDebug
  }
end

function debugUtils.setDebugState(id, name, newValue)
  if(not debugLoggingEnabled) then
    return
  end
  storage.enableDebug = newValue or false
  if(storage.enableDebug) then
    sb.logInfo(DebugUtilsCN.debugMsgPrefix .. " Toggled Debug On")
  else
    sb.logInfo(DebugUtilsCN.debugMsgPrefix .. " Toggled Debug Off")
  end
end

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

function DebugUtilsCN.logDebug(msg, indentAmt)
  if(debugLoggingEnabled and storage.enableDebug) then
    sb.logInfo(DebugUtilsCN.debugMsgPrefix .. " " .. debugUtils.getIndentString(indentAmt) .. msg)
  end
end