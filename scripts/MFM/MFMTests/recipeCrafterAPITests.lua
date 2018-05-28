package.path = package.path .. ';./loadfile.lua;./scripts/MFM/MFMTests/loadfile.lua';
local test = require '/scripts/MFM/MFMTests/lib/u-test.lua';
require '/scripts/MFM/MFMTests/fakes/fakeObject.lua';
local RecipeCrafterMFMApi = require '/scripts/recipeCrafterAPI.lua';

if(not test) then
  return;
end

if(storage == nil) then
  storage = {};
end

local rcUtils;

test.start_up = function()
  config.setParameter("recipeGroup", "bakingMFM")
  RecipeCrafterMFMApi.init(true);
  rcUtils = RecipeCrafterMFMApi.rcUtils;
end

test.shouldLoadSettingsFromConfig = function()
  local parameters = {
    recipeGroup = "bananaMFM",
    slotCount = 24,
    outputSlot = 299,
    byproductSlot = 18,
    craftSoundDelaySeconds = 5,
    itemAgeMultiplier = 1.2
  };
  config.setParameters(parameters);
  RecipeCrafterMFMApi.init(true);
  test.equal(storage.recipeGroup, parameters["recipeGroup"]);
  test.equal(storage.slotCount, parameters["slotCount"]);
  test.equal(storage.outputSlot, parameters["outputSlot"]);
  test.equal(storage.byproductSlot, parameters["byproductSlot"]);
  test.equal(storage.craftSoundDelaySeconds, parameters["craftSoundDelaySeconds"]);
  test.is_false(storage.isRefridgerated);
end