require "/scripts/recipeCrafterAPI.lua"

function init(virtual)
  RecipeCrafterMFMApi.init("/_MFMversioning.config");
end

function update(dt)
  RecipeCrafterMFMApi.update(dt)
end

function die()
  RecipeCrafterMFMApi.die()
end