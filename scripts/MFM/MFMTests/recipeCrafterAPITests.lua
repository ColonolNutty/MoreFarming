package.path = package.path .. ';./loadfile.lua;./scripts/MFM/MFMTests/loadfile.lua';
local test = require '/scripts/MFM/MFMTests/u-test.lua';
local RecipeCrafterMFMApi = require '/scripts/recipeCrafterAPI.lua';

if(not test) then
  return;
end

test.thing = function()
  test.equal(RecipeCrafterMFMApi.debugMsgPrefix, 3)
end

test.otherthing = function()
  test.almost_equal(1 + 1, 42, 24)
end