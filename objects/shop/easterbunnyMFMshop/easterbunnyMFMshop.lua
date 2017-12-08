require "/scripts/debugUtilsCN.lua"

function init()
  DebugUtilsCN.init();
  -- DebugUtilsCN.enableDebug();
  storage.easterBunnyDetectionRadius = 200.0;
  storage.currentPosition = object.toAbsolutePosition({0, 0});
  storage.queryPosition = {storage.currentPosition[1], storage.currentPosition[2] + 2};
  storage.easterBunnyType = config.getParameter("easterBunnyType", "easterbunnyMFM");
  storage.easterBunnySpecies = config.getParameter("easterBunnySpecies", "human");
end

function update(dt)
  storage.easterBunnyId = findEasterBunny()
  spawnEasterBunnyIfNotExists();
end

function findEasterBunny()
  if(storage.easterBunnyId ~= nil and world.entityExists(storage.easterBunnyId)) then
    return storage.easterBunnyId;
  end
  storage.easterBunnyId = nil;
  DebugUtilsCN.logDebug("Easter bunny not detected, searching");
  local nearbyNpcIds = world.npcQuery(storage.currentPosition, 50, { notAnObject = true });
  if(nearbyNpcIds == nil) then
    return nil;
  end
  local foundId = nil;
  for _, entityId in pairs(nearbyNpcIds) do
    if(world.npcType(entityId) == storage.easterBunnyType) then
      DebugUtilsCN.logDebug("Easter Bunny Found");
      foundId = entityId;
      break
    end
  end
  return foundId;
end

function spawnEasterBunnyIfNotExists()
  if(storage.easterBunnyId ~= nil and world.entityExists(storage.easterBunnyId)) then
    return;
  end
  DebugUtilsCN.logDebug("Easter bunny does not exist, spawning");
  storage.easterBunnyId = nil;
  local spawnLocation = {storage.currentPosition[1], storage.currentPosition[2] + 2}
  storage.easterBunnyId = world.spawnNpc(spawnLocation, storage.easterBunnySpecies, storage.easterBunnyType, 1);
  world.sendEntityMessage(storage.easterBunnyId, "setInteractive", false)
end

function die()
  if(storage.easterBunnyId == nil) then
    DebugUtilsCN.logDebug("No easter bunny id");
    return
  end
  DebugUtilsCN.logDebug("Breaking easter bunny");
  world.spawnProjectile("npcdeathprojectileMFM", world.entityPosition(storage.easterBunnyId), world.players()[1]); 
  if(world.entityExists(storage.easterBunnyId)) then
    DebugUtilsCN.logDebug("Failed to murder easter bunny");
  end
end