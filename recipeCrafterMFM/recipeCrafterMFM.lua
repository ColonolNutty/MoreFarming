require "/scripts/recipeCrafterAPI.lua"

function init(virtual)
  DebugUtilsCN.logDebug("Initializing MFM");
  RecipeCrafterMFMApi.init()
end

function update(dt)
  RecipeCrafterMFMApi.update(dt)
end

function die()
  RecipeCrafterMFMApi.die()
end