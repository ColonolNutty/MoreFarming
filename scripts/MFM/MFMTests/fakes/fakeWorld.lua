if(world == nil) then
  world = {};
end

local containers = { };

world.containerItemAt = function(objectId, slot)
  local container = containers[objectId];
  if(container == nil) then
    return nil;
  end
  return container[slot];
end

world.containerTakeAt = function(objectId, slot)
  local container = containers[object];
  if(container) then
    container[slot] = nil;
  end
end

world.containerPutItem = function(objectId, slot, item)
  local container = containers[objectId];
  if(not container) then
    container = {};
    containers[objectId] = container;
  end
  container[slot] = item;
end