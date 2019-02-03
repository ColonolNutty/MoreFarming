if(animator == nil) then
  animator = {};
end

local soundsPlaying = {};

animator.setAnimationState = function(stateName, state)
  if(animator.states == nil) then
    animator.states = {};
  end
  animator.states[stateName] = state;
end

animator.getAnimationState = function(stateName)
  if(animator.states == nil) then
    return nil;
  end
  return animator.states[stateName];
end

animator.setSound = function(soundName, value)
  animator[soundName] = value;
end

animator.hasSound = function(soundName)
  return animator[soundName] ~= nil;
end

animator.playSound = function(soundName)
  soundsPlaying[soundName] = true;
end

animator.stopAllSounds = function(soundName)
  soundsPlaying[soundName] = false;
end