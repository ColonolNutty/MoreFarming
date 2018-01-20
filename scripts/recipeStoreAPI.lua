require "/scripts/debugUtilsCN.lua"

RecipeStoreMFMApi = {
  debugMsgPrefix = "[RSAPI]"
};
local rsUtils = {};

function RecipeStoreMFMApi.init(msgPrefix)
  if(msgPrefix ~= nil) then
    RecipeStoreMFMApi.debugMsgPrefix = msgPrefix
  end
  DebugUtilsCN.init(RecipeStoreMFMApi.debugMsgPrefix)
  DebugUtilsCN.logDebug("Initializing API");
end

function RecipeStoreMFMApi.update(dt)
end

function RecipeStoreMFMApi.die()
end

-----------------------------------------------------------------
