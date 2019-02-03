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

local testParameters = {
    recipeGroup = "bananaMFM",
    slotCount = 24,
    outputSlot = 299,
    byproductSlot = 18,
    craftSoundDelaySeconds = 5,
    itemAgeMultiplier = 1.2
  };
local rcUtils;

test.start_up = function()
  RecipeCrafterMFMApi.init(true);
  rcUtils = RecipeCrafterMFMApi.rcUtils;
end

test.shouldLoadSettingsFromConfig = function()
  config.setParameters(testParameters);
  RecipeCrafterMFMApi.init(true);
  test.equal(storage.recipeGroup, testParameters.recipeGroup);
  test.equal(storage.slotCount, testParameters.slotCount);
  test.equal(storage.outputSlot, testParameters.outputSlot);
  test.equal(storage.byproductSlot, testParameters.byproductSlot);
  test.equal(storage.craftSoundDelaySeconds, testParameters.craftSoundDelaySeconds);
  test.is_false(storage.isRefridgerated);
end