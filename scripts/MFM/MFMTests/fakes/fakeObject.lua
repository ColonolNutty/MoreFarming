require '/scripts/MFM/MFMTests/fakes/fakeEntity.lua';
require '/scripts/MFM/MFMTests/fakes/fakeWorld.lua';
require '/scripts/MFM/MFMTests/fakes/fakeAnimator.lua';
require '/scripts/MFM/MFMTests/fakes/fakeMessage.lua';
require '/scripts/MFM/MFMTests/fakes/fakeConfig.lua';
require '/scripts/MFM/MFMTests/fakes/fakeStorage.lua';
require '/scripts/MFM/MFMTests/fakes/fakeSb.lua';

if(object == nil) then
  object = {};
end

object.id = entity.id;