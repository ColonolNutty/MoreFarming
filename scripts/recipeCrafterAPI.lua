require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"
require "/scripts/recipebookMFMQueryAPI.lua"
require "/scripts/MFM/recipeLocatorAPI.lua"

if(RecipeCrafterMFMApi == nil) then
  RecipeCrafterMFMApi = {
    debugMsgPrefix = "[RCAPI]",
    containerContentsChanged = false,
    isCrafting = false
  };
end
local rcUtils = {};
local logger = nil;
local next = next;

function RecipeCrafterMFMApi.init()
  logger = DebugUtilsCN.init(RecipeCrafterMFMApi.debugMsgPrefix);
  RecipeBookMFMQueryAPI.init();
  RecipeLocatorAPI.init();
  
  storage.recipeGroup = config.getParameter("recipeGroup");
  storage.slotCount = config.getParameter("slotCount", 16);
  storage.outputSlot = config.getParameter("outputSlot", 15);
  storage.byproductSlot = config.getParameter("byproductSlot", 16);
  storage.nonZeroOutputSlot = storage.outputSlot + 1;
  storage.nonZeroByproductSlot = storage.byproductSlot + 1;
  if storage.outputSlot < 0 then
    storage.outputSlot = 0;
  end
  storage.timePassed = 0;
  storage.craftSoundDelaySeconds = config.getParameter("craftSoundDelaySeconds", 10); -- In seconds
  storage.craftSoundIsPlaying = false;
  storage.isRefridgerated = config.getParameter("itemAgeMultiplier", 5) == 0;
  
  --- Changing Properties ---
  if(storage.currentlySelectedRecipe == nil) then
    storage.currentlySelectedRecipe = nil;
  end
  
  if(storage.currentIngredients == nil) then
    storage.currentIngredients = nil;
  end
  
  storage.ignoreContainerContentChanges = false;
  ---------------------------
  
  ------ Configuration ------
  storage.consumeIngredientsOnCraft = true;
  storage.holdIngredientsOnCraft = true;
  storage.playSoundBeforeOutputPlaced = true;
  storage.appendNewOutputToCurrentOutput = true;
  ---------------------------

  message.setHandler("craft", RecipeCrafterMFMApi.craftItem);
  message.setHandler("getFilterId", rcUtils.getFilterId);
  message.setHandler("reloadRecipeBook", rcUtils.reloadRecipeBook);
end

function rcUtils.getFilterId()
  if(not storage.recipeGroup) then
    return "none"
  end
  return storage.recipeGroup
end

function RecipeCrafterMFMApi.update(dt)
  if(rcUtils.shouldStopCraftSound(dt)) then
    rcUtils.stopCraftSound();
  end
  RecipeLocatorAPI.update();
  RecipeBookMFMQueryAPI.update(dt);
end

function RecipeCrafterMFMApi.die()
  RecipeCrafterMFMApi.releaseIngredients()
end

--------------------------Callbacks---------------------------------------

function RecipeCrafterMFMApi.onCraftStart()
  
end

--onRecipeFound() when craftItem is called, this method is invoked when a recipe is found using the current ingredients
function RecipeCrafterMFMApi.onRecipeFound()

end

--onNoIngredientsFound() when craftItem is called, this method is invoked when no ingredients are found in the container
function RecipeCrafterMFMApi.onNoIngredientsFound()

end

--onNoRecipeFound() when craftItem is called, this method is invoked when no recipe is found using the current ingredients
function RecipeCrafterMFMApi.onNoRecipeFound()

end

--isOutputSlotAvailable() when craftItem is called, this method is determines if the output slot is available for placing a new output
-- Returns true if a new output can be placed
-- Returns false if a new output can not be placed (Slot is full, or slot is not the same item)
function RecipeCrafterMFMApi.isOutputSlotAvailable()
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if outputSlotItem == nil then
    logger.logDebug("Output slot is empty")
    return true;
  end
  
  if(storage.currentlySelectedRecipe == nil) then
    logger.logDebug("Nothing crafted yet, but there is an output item")
    return false;
  end

  local previousOutput = storage.currentlySelectedRecipe.output;
  
  if(previousOutput == nil) then
    storage.currentlySelectedRecipe = nil;
    return false;
  end
  
  if(previousOutput.name ~= outputSlotItem.name) then
    logger.logDebug("Current output does not match previous recipe")
    return false;
  end
  
  -- Check current ingredients to verify the previous recipe still has the required ingredients
  local hasRequiredIngredients = RecipeLocatorAPI.hasIngredientsForRecipe(storage.currentlySelectedRecipe, storage.currentIngredients);
  if(not hasRequiredIngredients) then
    logger.logDebug("Current output matched previous recipe, but the current ingredients weren't right")
    return false;
  end
  
  return true;
end

function containerCallback()
  if(storage.ignoreContainerContentChanges) then
    storage.ignoreContainerContentChanges = false
    return
  end
  RecipeCrafterMFMApi.containerContentsChanged = true
end

-----------------------------------------------------------------

-- Main Craft Process --
function RecipeCrafterMFMApi.craftItem()
  --logger.logDebug("craftItem Called")
  if(RecipeCrafterMFMApi.isCrafting) then
    --logger.logDebug("Already crafting, ignoring request")
    return
  end
  RecipeCrafterMFMApi.isCrafting = true;
  
  --logger.logDebug("Craft Process Started");
  
  storage.currentIngredients = RecipeCrafterMFMApi.getIngredients();
  
  if not rcUtils.hasIngredients() then
    --logger.logDebug("No ingredients found, aborting craft process")
    RecipeCrafterMFMApi.isCrafting = false;
    RecipeCrafterMFMApi.onNoIngredientsFound()
    RecipeCrafterMFMApi.containerContentsChanged = false;
    return;
  end
  
  logger.logDebug("Checking output slot for availability");
  
  local outputSlotAvailable = RecipeCrafterMFMApi.isOutputSlotAvailable();
  if(not outputSlotAvailable) then
    logger.logDebug("Cannot craft item, output is not available, aborting craft process")
    RecipeCrafterMFMApi.isCrafting = false;
    RecipeCrafterMFMApi.containerContentsChanged = false;
    return;
  end
  
  logger.logDebug("Output slot is available");
  
  RecipeCrafterMFMApi.onCraftStart();
  if(storage.playSoundBeforeOutputPlaced) then
    RecipeCrafterMFMApi.playCraftSound()
  end
  local outputRecipe = RecipeLocatorAPI.findRecipeForIngredients(storage.currentIngredients, storage.recipeGroup)
  if (outputRecipe) then
    logger.logDebug("Found recipe, updating output");
    RecipeCrafterMFMApi.onRecipeFound();
    rcUtils.craftWithRecipe(outputRecipe);
    storage.currentlySelectedRecipe = outputRecipe;
  else
    logger.logDebug("Failed to locate valid recipe");
    RecipeCrafterMFMApi.onNoRecipeFound();
    storage.currentlySelectedRecipe = nil;
  end
  RecipeCrafterMFMApi.releaseIngredients();
  RecipeCrafterMFMApi.isCrafting = false;
  RecipeCrafterMFMApi.containerContentsChanged = false;
end

function RecipeCrafterMFMApi.holdIngredients(recipe)
  RecipeCrafterMFMApi.releaseIngredients()
  storage.heldIngredients = {}
  logger.logDebug("Holding ingredients")
  local containerId = entity.id()
  for _,input in ipairs(recipe.input) do
    if(world.containerConsume(containerId, input)) then
      logger.logDebug("Holding ingredient with name: " .. input.name .. " and count: " .. input.count)
      table.insert(storage.heldIngredients, input)
    end
  end
end

function RecipeCrafterMFMApi.releaseIngredients()
  if(storage.heldIngredients == nil) then
    return false
  end
  logger.logDebug("Releasing ingredients")
  local containerId = entity.id()
  for _,input in ipairs(storage.heldIngredients) do
    logger.logDebug("Releasing ingredient with name: " .. input.name .. " and count: " .. input.count)
    local toExpel = world.containerAddItems(containerId, input)
    RecipeCrafterMFMApi.expelItem(toExpel)
  end
  storage.heldIngredients = nil
end

function RecipeCrafterMFMApi.consumeIngredients()
  if(storage.heldIngredients == nil) then
    return false
  end
  logger.logDebug("Consuming ingredients")
  storage.heldIngredients = nil
end

function RecipeCrafterMFMApi.getIngredients()
  local ingredientNames = {};
  local uniqueIngredients = {};
  local ingredients = world.containerItems(entity.id())
  if(ingredients == nil) then
    return nil;
  end
  for slot,item in pairs(ingredients) do
    if (ingredientNames[item.name] == nil and slot ~= storage.nonZeroOutputSlot and slot ~= storage.nonZeroByproductSlot) then
      item.count = world.containerAvailable(entity.id(), item.name)
      ingredientNames[item.name] = true
      uniqueIngredients[slot] = item
    end
  end
  return uniqueIngredients;
end

-- itemDescriptor = { name, count }
function RecipeCrafterMFMApi.expelItem(itemDescriptor)
  if(itemDescriptor == nil or itemDescriptor.count == nil or itemDescriptor.count == 0) then
    return 0
  end
  logger.logDebug("Expelling item '" .. itemDescriptor.name .. "' with count of " .. itemDescriptor.count)
  local itemDropped = world.spawnItem(itemDescriptor, object.position(), itemDescriptor.count)
  if(itemDropped == nil) then
    return 0
  end
  return itemDescriptor.count
end

-- Returns leftover output
function RecipeCrafterMFMApi.setOutputItem(outputItem)
    logger.logDebug("Attempting to place output")
    if(outputItem == nil) then
      return
    end
    logger.logDebug("Placing item '" .. outputItem.name .. "' with count " .. outputItem.count .. " in output slot " .. storage.outputSlot)
    world.containerTakeAt(entity.id(), storage.outputSlot)
    
    local toExpel = world.containerPutItemsAt(entity.id(), outputItem, storage.outputSlot)
    local placedItems = world.containerItemAt(entity.id(), storage.outputSlot)
    local totalAmount = 0
    if(toExpel) then
      if(toExpel.name == outputItem.name and toExpel.count == outputItem.count) then
        totalAmount = toExpel.count - placedItems.count
      end
    else
      totalAmount = outputItem.count - placedItems.count
    end
    return { name = outputItem.name, count = totalAmount }
end

function RecipeCrafterMFMApi.getOutputItem(recipe)
  local existingOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  
  local expectedNewAmount = recipe.output.count
  if(storage.appendNewOutputToCurrentOutput and existingOutput) then
    expectedNewAmount = expectedNewAmount + existingOutput.count
  end
  return {name = recipe.output.name, count = expectedNewAmount}
end

------------------------------------------------------------------

function RecipeCrafterMFMApi.playCraftSound()
  if animator.hasSound("onCraft") and not storage.craftSoundIsPlaying then
    logger.logDebug("Playing onCraft sounds")
    storage.timePassed = 0
    animator.playSound("onCraft")
    storage.craftSoundIsPlaying = true
  end
end

function rcUtils.shouldStopCraftSound(dt)
  if not storage.craftSoundIsPlaying or RecipeCrafterMFMApi.isCrafting then
    return false
  end
  storage.timePassed = storage.timePassed + dt
  --logger.logDebug("Craft sound playing, time passed: " .. storage.timePassed)
  if storage.timePassed <= 0 then
    return false
  end
  if storage.timePassed >= storage.craftSoundDelaySeconds then
    return true
  end
end

function rcUtils.stopCraftSound()
  logger.logDebug("Stopping all onCraft sounds")
  storage.timePassed = 0
  if(animator.hasSound("onCraft")) then
    animator.stopAllSounds("onCraft")
    storage.craftSoundIsPlaying = false
  end
end

function rcUtils.craftWithRecipe(recipe)
  local outputName = recipe.output.name
  
  storage.currentlySelectedRecipe = nil;
  storage.outputPlacedSuccessfully = false;
  
  if(storage.holdIngredientsOnCraft) then
    RecipeCrafterMFMApi.holdIngredients(recipe)
  end
  
  local outputItem = RecipeCrafterMFMApi.getOutputItem(recipe)
  
  if(outputItem == nil) then
    return
  end
  
  local leftoverOutput = RecipeCrafterMFMApi.setOutputItem(outputItem)
  local totalOutputCount = RecipeCrafterMFMApi.expelItem(leftoverOutput);
  
  local newOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if(newOutput == nil) then
    logger.logDebug("Output not successfully placed, and no item found at slot " .. storage.outputSlot)
    RecipeCrafterMFMApi.releaseIngredients()
    return
  end
  
  totalOutputCount = totalOutputCount + newOutput.count
  if newOutput.name == outputItem.name and totalOutputCount == outputItem.count then
    if(storage.consumeIngredientsOnCraft) then
      RecipeCrafterMFMApi.consumeIngredients()
    end
    storage.currentlySelectedRecipe = recipe
    storage.outputPlacedSuccessfully = true
    return
  end
  
  logger.logDebug("Output not successfully placed, item found instead: " .. newOutput.name)
end


function rcUtils.hasIngredients()
  if(storage.currentIngredients == nil) then
    return false;
  end
  local numberOfIngredients = 0
  for slot,item in pairs(storage.currentIngredients) do
    if slot ~= storage.nonZeroOutputSlot and slot ~= storage.nonZeroByproductSlot then
      numberOfIngredients = numberOfIngredients + 1
    end
  end
  return numberOfIngredients > 0
end

return RecipeCrafterMFMApi;