require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"
require "/scripts/recipebookMFMQueryAPI.lua"
require "/scripts/MFM/recipeStoreAPI.lua"
require "/scripts/MFM/ingredientStoreAPI.lua"

if(RecipeCrafterMFMApi == nil) then
  RecipeCrafterMFMApi = {
    debugMsgPrefix = "[RCAPI]",
    containerContentsChanged = false,
    isCrafting = false
  };
end
local rcUtils = {};
local onRecipeCraftedCallbacks = {};
local additionalOnDropItems = {};
local additionalOnDropTreasurePoolNames = {};
local logger = nil;
local next = next;


function RecipeCrafterMFMApi.init(virtual)
  logger = DebugUtilsCN.init(RecipeCrafterMFMApi.debugMsgPrefix);
  logger.enableDebug();
  RecipeStoreCNAPI.init(virtual);
  IngredientStoreCNAPI.init(virtual);
  RecipeBookMFMQueryAPI.init(virtual);

  table.insert(onRecipeCraftedCallbacks, RecipeCrafterMFMApi.dropAdditionalItems);
  table.insert(onRecipeCraftedCallbacks, RecipeCrafterMFMApi.dropAdditionalPoolItems);
  
  if(virtual) then
    RecipeCrafterMFMApi.rcUtils = rcUtils;
  end
  
  logger.setDebugState(false);
  storage.slotCount = config.getParameter("slotCount", 16);
  storage.outputSlot = config.getParameter("outputSlot", 15);
  if storage.outputSlot < 0 then
    storage.outputSlot = 0;
  end
  storage.byproductSlot = config.getParameter("byproductSlot", 16);
  storage.nonZeroOutputSlot = storage.outputSlot + 1;
  storage.nonZeroByproductSlot = storage.byproductSlot + 1;
  storage.timePassed = 0;
  storage.craftSoundDelaySeconds = config.getParameter("craftSoundDelaySeconds", 10); -- In seconds
  storage.craftSoundIsPlaying = false;
  storage.isRefridgerated = config.getParameter("itemAgeMultiplier", 5) == 0;
  
  --- Changing Properties ---
  storage.ignoreContainerContentChanges = false;
  ---------------------------
  
  message.setHandler("craft", RecipeCrafterMFMApi.craftItem);
  message.setHandler("getFilterId", rcUtils.getRecipeGroup);
  message.setHandler("reloadRecipeBook", rcUtils.reloadRecipeBook);
  message.setHandler("getAutoCraftState", rcUtils.getAutoCraftState);
  message.setHandler("setAutoCraftState", rcUtils.setAutoCraftState);

  message.setHandler("getFilterData", rcUtils.getFilterDataHook);
  message.setHandler("getSelectedItem", rcUtils.getSelectedItemHook);
  message.setHandler("selectItem", rcUtils.selectItemHook);
  
  RecipeCrafterMFMApi.loadAdditionalData();
end

function RecipeCrafterMFMApi.loadAdditionalData()
  local additionalData = root.assetJson("/scripts/data/additional-rc-data.config")
  if(additionalData) then
    -- Valid Types POOL, ITEM
    for _, toDropOnRecipeCrafted in ipairs(additionalData.toDropOnRecipeCrafted) do
      local toDropType = toDropOnRecipeCrafted.type;
      if toDropType == "ITEM" then
        table.insert(additionalOnDropItems, { name = toDropOnRecipeCrafted.name, count = toDropOnRecipeCrafted.count })
      elseif toDropType == "POOL" then
        table.insert(additionalOnDropTreasurePoolNames, toDropOnRecipeCrafted.name)
      end
    end
  end
end

function rcUtils.getRecipeGroup()
  if(storage.recipeGroup == nil) then
    storage.recipeGroup = config.getParameter("recipeGroup") or "none";
  end
  return storage.recipeGroup;
end

function rcUtils.getCurrentlySelectedRecipe()
  return storage.currentlySelectedRecipe;
end

function rcUtils.setCurrentlySelectedRecipe(recipe)
  storage.currentlySelectedRecipe = recipe;
end

function rcUtils.getAutoCraftState()
  if(storage.autoCraftState == nil) then
    storage.autoCraftState = false;
  end
  return storage.autoCraftState;
end

function rcUtils.setAutoCraftState(id, name, newAutoCraftState)
  if (storage.autoCraftState ~= newAutoCraftState) then
    if (newAutoCraftState) then
      storage.currentlySelectedRecipe = nil;
    else
      rcUtils.consumeIngredients()
      storage.currentlySelectedRecipe = nil;
    end
  end
  storage.autoCraftState = newAutoCraftState or false;
end

function rcUtils.ingredientsMatchRecipe(recipe, ingredients)
  if(recipe == nil or recipe.input == nil or ingredients == nil or recipe.output == nil or recipe.output.name == nil) then
    logger.logDebug("Ingredients no match");
    return false;
  end
  logger.logDebug("Checking recipe: " .. recipe.output.name);
  local recipeMatches = true;
  local inputMatches = false;
  for slot, ingredient in pairs(ingredients) do
    inputMatches = false;
    for inputName, inputInfo in pairs(recipe.input) do
      logger.logDebug("Matching input: " .. inputName);
      if(ingredient.name == inputName) then
        if(ingredient.count >= inputInfo.count) then
          logger.logDebug("Ingredient matched!")
          inputMatches = true;
          break;
        else
          logger.logDebug("Count didnt match: (" .. ingredient.count .. ", " .. inputInfo.count .. ")");
        end
      else
        logger.logDebug("Names didnt match: (" .. ingredient.name .. ", " .. inputName .. ")");
      end
    end
    if(not inputMatches) then
      recipeMatches = false;
      break;
    end
  end
  return recipeMatches;
end

function rcUtils.getSelectedItemHook()
  if(storage.selectedItem == nil) then
    return nil;
  end
  return storage.selectedItem;
end

function rcUtils.selectItemHook(id, name, itemId)
  if(itemId == nil) then
    logger.logDebug("itemId was nil!");
  else
    logger.logDebug("Selecting item with id: " .. itemId);
  end
  return rcUtils.selectItem(itemId);
end

function rcUtils.selectItem(itemId)
  if(itemId == nil) then
    storage.selectedItem = nil;
    return;
  else
    storage.selectedItem = {
      id = itemId,
      data = IngredientStoreCNAPI.loadIngredient(itemId)
    };
  end
  return storage.selectedItem;
end

function rcUtils.getFilterDataHook()
  local recipeGroup = rcUtils.getRecipeGroup();
  local filters = {};
  filters[recipeGroup] = { id = recipeGroup, name = recipeGroup, isSelected = true };
  RecipeBookMFMQueryAPI.initializeRecipeBook(recipeGroup, RecipeStoreCNAPI.initializeRecipeStore);
  return filters;
end



function RecipeCrafterMFMApi.dropAdditionalItems(recipeCrafted)
  for _,additionalItem in ipairs(additionalOnDropItems) do
    world.spawnItem(additionalItem, world.xwrap(object.position()))
  end
end

function RecipeCrafterMFMApi.dropAdditionalPoolItems(recipeCrafted)
  for _,poolName in ipairs(additionalOnDropTreasurePoolNames) do
    world.spawnTreasure(world.xwrap(object.position()), poolName, 0)
  end
end

function RecipeCrafterMFMApi.update(dt)
  if(rcUtils.shouldStopCraftSound(dt)) then
    rcUtils.stopCraftSound();
  end
  RecipeBookMFMQueryAPI.update(dt);
  
  ---- Autocraft ----
  if(not RecipeCrafterMFMApi.containerContentsChanged or not rcUtils.getAutoCraftState()) then
    return;
  end
  if(storage.currentlySelectedRecipe ~= nil and rcUtils.isOutputSlotModified()) then
    rcUtils.consumeIngredients()
    storage.currentlySelectedRecipe = nil;
  elseif(storage.currentlySelectedRecipe ~= nil and rcUtils.shouldRemoveOutput()) then
    rcUtils.removeOutput()
    storage.currentlySelectedRecipe = nil;
  elseif(rcUtils.getAutoCraftState()) then
    RecipeCrafterMFMApi.craftItem()
  end
end

function RecipeCrafterMFMApi.die()
  if(rcUtils.getAutoCraftState()) then
    rcUtils.removeOutput();
  end
  RecipeCrafterMFMApi.releaseIngredients();
  rcUtils.releaseOutput();
end

function rcUtils.isOutputSlotModified()
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  
  local currentlySelectedRecipe = storage.currentlySelectedRecipe;
  -- If no previous recipe exists, then we haven't crafted yet
  -- If we haven't crafted and there is an output slot item, then it is modified
  -- If we haven't crafted and there is no output slot item, then it is not modified
  if(currentlySelectedRecipe == nil or currentlySelectedRecipe.output == nil) then
    return outputSlotItem ~= nil;
  end
  
  -- Output slot is empty, so it must be modified
  if(outputSlotItem == nil) then
    logger.logDebug("Expected item in output slot, but no item was found.");
    return true;
  end
  
  local previousOutput = currentlySelectedRecipe.output;
  
  if(outputSlotItem.name ~= previousOutput.name) then
    logger.logDebug("Item name in the output slot differs; Expected name: " .. previousOutput.name .. " Actual name: " .. outputSlotItem.name);
    return true;
  end
  
  if(outputSlotItem.count ~= previousOutput.count) then
    logger.logDebug("Item count in the output slot differs; Expected count: " .. previousOutput.count .. " Actual count: " .. outputSlotItem.count);
    return true;
  end
  
  logger.logDebug("Output slot has not been modified.");
  return false;
end

function rcUtils.consumeIngredients()
  local currentlySelectedRecipe = rcUtils.getCurrentlySelectedRecipe();
  if(currentlySelectedRecipe == nil) then
    return;
  end
  RecipeCrafterMFMApi.playCraftSound()
  RecipeCrafterMFMApi.holdIngredients(currentlySelectedRecipe)
  RecipeCrafterMFMApi.consumeIngredients()
  RecipeCrafterMFMApi.recipeCrafted(currentlySelectedRecipe)
end

function rcUtils.shouldRemoveOutput()
  if(storage.currentlySelectedRecipe == nil) then
    return false;
  end
  local currentIngredients = RecipeCrafterMFMApi.getIngredients();
  return not rcUtils.ingredientsMatchRecipe(storage.currentlySelectedRecipe, currentIngredients);
end

function rcUtils.removeOutput()
  world.containerTakeAt(entity.id(), storage.outputSlot);
  storage.currentlySelectedRecipe = nil
end

function rcUtils.releaseOutput()
  if(not rcUtils.isOutputSlotModified()) then
    logger.logDebug("Output slot not modified, not releasing output")
    -- If not modified, then the output slot must be something the script put in, so remove it.
    rcUtils.removeOutput()
    return true;
  end
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
  if (rcUtils.getAutoCraftState()) then
    RecipeCrafterMFMApi.onNoRecipeFoundAutoCraft()
  else
    RecipeCrafterMFMApi.onNoRecipeFoundBase()
  end
end

function RecipeCrafterMFMApi.onNoRecipeFoundAutoCraft()
  rcUtils.removeOutput();
  storage.currentlySelectedRecipe = nil;
end

function RecipeCrafterMFMApi.onNoRecipeFoundBase()

end

--isOutputSlotAvailable() when craftItem is called, this method is determines if the output slot is available for placing a new output
-- Returns true if a new output can be placed
-- Returns false if a new output can not be placed (Slot is full, or slot is not the same item)
function RecipeCrafterMFMApi.isOutputSlotAvailable()
  if(rcUtils.getAutoCraftState()) then
    return RecipeCrafterMFMApi.isOutputSlotAvailableAutoCraft()
  else
    return RecipeCrafterMFMApi.isOutputSlotAvailableBase()
  end
end

function RecipeCrafterMFMApi.isOutputSlotAvailableAutoCraft()
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  -- Output slot is empty
  if(outputSlotItem == nil) then
    logger.logDebug("No output item detected in output slot, it is available")
    return true;
  end
  
  local currentlySelectedRecipe = storage.currentlySelectedRecipe;
  
  -- If there is no currentlySelectedRecipe, but there is an output item
  -- If the output slot item has been modified
  if(currentlySelectedRecipe == nil) then
    logger.logDebug("No previous recipe, but an output item exists")
    return false;
  end
  
  -- When the ingredients change
  
  local currentIngredients = RecipeCrafterMFMApi.getIngredients();
  -- Check current ingredients to verify the previous recipe still has the required ingredients
  local hasRequiredIngredients = rcUtils.ingredientsMatchRecipe(currentlySelectedRecipe, currentIngredients);
  if(not hasRequiredIngredients) then
    logger.logDebug("Required ingredients missing for current recipe.")
    return true;
  end
  
  return not rcUtils.isOutputSlotModified();
end


function RecipeCrafterMFMApi.isOutputSlotAvailableBase()
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
  
  local currentIngredients = RecipeCrafterMFMApi.getIngredients();
  -- Check current ingredients to verify the previous recipe still has the required ingredients
  local hasRequiredIngredients = rcUtils.ingredientsMatchRecipe(storage.currentlySelectedRecipe, currentIngredients);
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
    return;
  end
  RecipeCrafterMFMApi.isCrafting = true;
  
  --logger.logDebug("Craft Process Started");
  
  local ingredients = RecipeCrafterMFMApi.getIngredients();
  
  if(not rcUtils.hasIngredients(ingredients)) then
    --logger.logDebug("No ingredients found, aborting craft process")
    RecipeCrafterMFMApi.isCrafting = false;
    RecipeCrafterMFMApi.onNoIngredientsFound();
    RecipeCrafterMFMApi.containerContentsChanged = false;
    return;
  end
  
  logger.logDebug("Checking output slot for availability");
  
  local outputSlotAvailable = RecipeCrafterMFMApi.isOutputSlotAvailable();
  if(not outputSlotAvailable) then
    logger.logDebug("Cannot craft item, output is not available, aborting craft process");
    RecipeCrafterMFMApi.isCrafting = false;
    RecipeCrafterMFMApi.containerContentsChanged = false;
    return;
  end
  
  logger.logDebug("Output slot is available");
  
  RecipeCrafterMFMApi.onCraftStart();
  if(not rcUtils.getAutoCraftState()) then
    RecipeCrafterMFMApi.playCraftSound();
  end
  local recipes = RecipeStoreCNAPI.getRecipesContainingIngredientCounts(rcUtils.getRecipeGroup(), ingredients);
  local outputRecipe = nil;
  for outputName, recipeInfos in pairs(recipes) do
    outputRecipe = recipeInfos[1];
    break;
  end
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
  for inputName, inputInfo in pairs(recipe.input) do
    local ingredient = { name = inputName, count = inputInfo.count };
    if(world.containerConsume(containerId, ingredient)) then
      logger.logDebug("Holding ingredient with name: " .. inputName .. " and count: " .. inputInfo.count)
      table.insert(storage.heldIngredients, ingredient)
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
  if(not rcUtils.getAutoCraftState() and existingOutput) then
    expectedNewAmount = expectedNewAmount + existingOutput.count
  end
  return {name = recipe.output.name, count = expectedNewAmount}
end

function RecipeCrafterMFMApi.registerOnRecipeCrafted(uniqueIdentifier, onRecipeCraftedCallback)
  if uniqueIdentifier ~= nil and onRecipeCraftedCallback ~= nil and onRecipeCraftedCallbacks[uniqueIdentifier] == nil then
      onRecipeCraftedCallbacks[uniqueIdentifier] = onRecipeCraftedCallback;
  end
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
  
  if(not rcUtils.getAutoCraftState()) then
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
    if(not rcUtils.getAutoCraftState()) then
      RecipeCrafterMFMApi.consumeIngredients()
      RecipeCrafterMFMApi.recipeCrafted(storage.currentlySelectedRecipe)
    end
    storage.currentlySelectedRecipe = recipe
    storage.outputPlacedSuccessfully = true
    return
  end
  
  logger.logDebug("Output not successfully placed, item found instead: " .. newOutput.name)
end

function rcUtils.hasIngredients(ingredients)
  if(ingredients == nil) then
    return false;
  end
  local numberOfIngredients = 0
  for slot,item in pairs(ingredients) do
    if slot ~= storage.nonZeroOutputSlot and slot ~= storage.nonZeroByproductSlot then
      numberOfIngredients = numberOfIngredients + 1
    end
  end
  return numberOfIngredients > 0
end

function RecipeCrafterMFMApi.recipeCrafted(recipeCrafted)
  for identifier, onRecipeCraftedCallback in pairs(onRecipeCraftedCallbacks) do
    logger.logDebug("Recipe Crafted, Calling callback with name: " .. identifier)
    onRecipeCraftedCallback(recipeCrafted)
  end
end

return RecipeCrafterMFMApi;