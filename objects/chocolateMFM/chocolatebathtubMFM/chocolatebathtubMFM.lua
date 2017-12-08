function init(args)
  if storage.active == nil then
    storage.active = false;
  end
  
  setActive(storage.active)
  object.setInteractive(true)
end

function onInteraction(args)
  setActive(not storage.active)
end

function setActive(flag)
  if(not flag) then
    animator.setAnimationState("switchState", "off")
  else
    animator.setAnimationState("switchState", "on")
  end
  storage.active = flag;
end