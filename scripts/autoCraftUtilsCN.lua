ACUtilsCN = {};
local autocraftUtils = {};

------------------------ Settings ------------------------

local settings = {
  autocraftState = nil
}

function settings.initialize()
  if(settings.autocraftState == nil) then
    settings.autocraftState = false
  end
end

function settings.setAutoCraftState(val)
  if(storage) then
    storage.autocraftState = val or false
  else
    settings.autocraftState = val or false
  end
end

function settings.getAutoCraftState()
  if(storage) then
    return storage.autocraftState
  else
    return settings.autocraftState
  end
end

----------------------------------------------------------

function ACUtilsCN.init()
  settings.initialize()
  if(message) then
    message.setHandler("getAutoCraftState", autocraftUtils.getAutoCraftState)
    message.setHandler("setAutoCraftState", autocraftUtils.setAutoCraftState)
  end
end

------------------------ Handlers ------------------------

--- Meant to be called from a GUI script query ---
function autocraftUtils.getAutoCraftState()
  return {
    autocraftState = settings.getAutoCraftState()
  }
end

--- Meant to be called from a GUI script query ---
function autocraftUtils.setAutoCraftState(id, name, newValue)
  settings.setAutoCraftState(newValue)
end

----------------------------------------------------------