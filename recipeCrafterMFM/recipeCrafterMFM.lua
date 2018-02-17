require "/scripts/recipeCrafterAPI.lua"

function init(virtual)
  DebugUtilsCN.logDebug("Initializing MFM");
  RecipeCrafterMFMApi.init(nil, "/_MFMversioning.config")
end

function update(dt)
  RecipeCrafterMFMApi.update(dt)
end

function die()
  RecipeCrafterMFMApi.die()
end