require "/scripts/recipeCrafterAPI.lua"

function init(virtual)
  RecipeCrafterMFMApi.init();
end

function update(dt)
  RecipeCrafterMFMApi.update(dt)
end

function die()
  RecipeCrafterMFMApi.die()
end