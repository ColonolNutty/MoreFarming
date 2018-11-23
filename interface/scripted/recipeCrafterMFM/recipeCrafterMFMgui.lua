require "/scripts/debugUtilsCN.lua"
require "/scripts/MFM/entityQueryAPI.lua"
require "/interface/scripted/recipebookMFM/recipebookMFMgui.lua"

if(not RecipeCrafterMFMGui) then
  RecipeCrafterMFMGui = {};
end

local autoCraftStateUpdated = false;
local entityId = nil;
local logger = nil;
local byproductSlot = 17;
local settings = {
  autoCraftState = false
};

TOGGLE_AUTOCRAFT_NAME = "toggleAutoCraft";

function init()
  RecipeCrafterMFMGui.init()
end

function RecipeCrafterMFMGui.init()
  logger = DebugUtilsCN.init("[RCGUI]");
  entityId = pane.containerEntityId();
  EntityQueryAPI.init();
  --sb.logInfo("Initializing Recipe Crafter GUI");
  autoCraftStateUpdated = false;
  RBMFMGui.init(entityId);
  hideByproductSlotIfSpacesNotAvailable();
end

function update(dt)
  RecipeCrafterMFMGui.update(dt)
end

function RecipeCrafterMFMGui.update(dt)
  if(not EntityQueryAPI.update(dt)) then
    return
  end
  updateAutoCraftState()
  RBMFMGui.update(dt)
end

function craft()
  logger.logDebug("Crafting with Crafter GUI");
  world.sendEntityMessage(entityId, "craft")
end

function hideByproductSlotIfSpacesNotAvailable()
  local containerSize = world.containerSize(entityId)
  if(containerSize < byproductSlot) then
    widget.setVisible("lblByproduct", false)
    widget.setVisible("pointerBottom", false)
  end
end

---------------------------------------------------------------------

function getAutoCraftState()
  if(storage) then
    return storage.autoCraftState
  else
    return settings.autoCraftState
  end
end

function setAutoCraftState(val)
  if(storage) then
    storage.autoCraftState = toEnable
  else
    settings.autoCraftState = toEnable
  end
  hideCraftButtonIfAutoCraftEnabled()
end

function toggleAutoCraft()
  if(entityId == nil) then
    return
  end
  local toEnable = widget.getChecked(TOGGLE_AUTOCRAFT_NAME)
  setAutoCraftState(toEnable)
  hideCraftButtonIfAutoCraftEnabled()
  world.sendEntityMessage(entityId, "setAutoCraftState", toEnable)
end

function hideCraftButtonIfAutoCraftEnabled()
  if(getAutoCraftState()) then
    widget.setVisible("craft", false)
  else
    widget.setVisible("craft", true)
  end
end

function updateAutoCraftState()
  if(autoCraftStateUpdated) then
    return;
  end
  local handle = function()
    return EntityQueryAPI.requestData(entityId, "getAutoCraftState", 0, nil);
  end
  
  local onCompleted = function(autoCraftState)
    if(autoCraftState == nil) then
      autoCraftState = false;
    end
    setAutoCraftState(autoCraftState);
    hideCraftButtonIfAutoCraftEnabled();
    widget.setChecked(TOGGLE_AUTOCRAFT_NAME, autoCraftState);
    autoCraftStateUpdated = true;
  end
  
  EntityQueryAPI.addRequest("RGMFMGui.updateAutoCraftState", handle, onCompleted);
end