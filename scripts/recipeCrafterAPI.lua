require "/scripts/debugUtilsCN.lua"
require "/scripts/utilsCN.lua"
require "/scripts/recipebookMFMQueryAPI.lua"

RecipeCrafterMFMApi = {
  debugMsgPrefix = "[RCAPI]",
  loadedRecipes = false,
  reloadingRecipeBook = false,
  reloadedRecipeBook = false
};
local rcUtils = {};
local logger = nil;
local isCrafting = false;
local next = next;

function RecipeCrafterMFMApi.init()
  logger = DebugUtilsCN.init(RecipeCrafterMFMApi.debugMsgPrefix)
  RecipeBookMFMQueryAPI.init();
  local outputConfigPath = config.getParameter("outputConfig")
  if outputConfigPath == nil then
    storage.possibleOutputs = {}
  else
    storage.possibleOutputs = root.assetJson(outputConfigPath).possibleOutput
  end
  storage.slotCount = config.getParameter("slotCount", 16)
  storage.outputSlot = config.getParameter("outputSlot", 15)
  storage.byproductSlot = config.getParameter("byproductSlot", 16)
  storage.nonZeroOutputSlot = storage.outputSlot + 1;
  storage.nonZeroByproductSlot = storage.byproductSlot + 1;
  if storage.outputSlot < 0 then
    storage.outputSlot = 0
  end
  storage.timePassed = 0
  storage.craftSoundDelaySeconds = config.getParameter("craftSoundDelaySeconds", 10) -- In seconds
  storage.craftSoundIsPlaying = false
  storage.recipeGroup = config.getParameter("recipeGroup")
  storage.isRefridgerated = config.getParameter("itemAgeMultiplier", 5) == 0
  
  if(storage.enableRecipeGroupDebug == nil) then
    storage.enableRecipeGroupDebug = false
  end
  
  --- Changing Properties ---
  if(storage.previousRecipe == nil) then
    storage.previousRecipe = nil
  end
  
  if(storage.currentIngredients == nil) then
    storage.currentIngredients = nil;
  end
  
  storage.ignoreContainerContentChanges = false;
  ---------------------------
  
  ----- Configuration -----
  storage.consumeIngredientsOnCraft = true;
  storage.noHold = false;
  storage.playSoundBeforeOutputPlaced = true;
  storage.appendNewOutputToCurrentOutput = true;
  -------------------------
  message.setHandler("craft", RecipeCrafterMFMApi.craftItem)
  message.setHandler("getFilterId", rcUtils.getFilterId);
  message.setHandler("reloadRecipeBook", rcUtils.reloadRecipeBook);
end

function rcUtils.getFilterId()
  return storage.recipeGroup
end

function RecipeCrafterMFMApi.update(dt)
  rcUtils.checkCraftSoundDelay(dt)
  rcUtils.loadRecipeBookRecipes()
  RecipeBookMFMQueryAPI.update(dt)
end

function RecipeCrafterMFMApi.die()
  isCrafting = false
  RecipeCrafterMFMApi.releaseIngredients()
end

function rcUtils.reloadRecipeBook()
  if(not RecipeCrafterMFMApi.reloadingRecipeBook) then
    RecipeCrafterMFMApi.loadedRecipes = false
    rcUtils.loadRecipeBookRecipes()
  end
  return RecipeCrafterMFMApi.reloadedRecipeBook;
end

function rcUtils.loadRecipeBookRecipes()
  if(RecipeCrafterMFMApi.loadedRecipes or RecipeCrafterMFMApi.reloadingRecipeBook) then
    return
  end
  RecipeCrafterMFMApi.reloadingRecipeBook = true;
  RecipeCrafterMFMApi.reloadedRecipeBook = false;
  local handle = function()
    local result = RecipeBookMFMQueryAPI.getRecipesForFilter(storage.recipeGroup, nil, storage.recipeGroup)
    if(result ~= nil) then
      return true, result;
    end
    return false, nil;
  end
  
  local onComplete = function(result)
    if(next(result) == nil) then
      storage.recipeBookRecipes = nil
      logger.logDebug("Recipe Book Not Found")
    else
      storage.recipeBookRecipes = result;
      logger.logDebug("Loaded Recipe Book Recipes")
    end
    RecipeCrafterMFMApi.loadedRecipes = true
    RecipeCrafterMFMApi.reloadingRecipeBook = false
    RecipeCrafterMFMApi.reloadedRecipeBook = true;
  end
  EntityQueryAPI.addRequest("loadRecipeBookRecipes", handle, onComplete)
end

--------------------------Callbacks---------------------------------------

function RecipeCrafterMFMApi.onCraftStart()
  
end

function RecipeCrafterMFMApi.onContainerContentsChanged()

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
  
  if(storage.previousRecipe == nil) then
    logger.logDebug("Nothing crafted yet, but there is an output item")
    return false;
  end

  local previousOutput = storage.previousRecipe.output;
  
  if(previousOutput == nil) then
    storage.previousRecipe = nil;
    return false;
  end
  
  if(previousOutput.name ~= outputSlotItem.name) then
    logger.logDebug("Current output does not match previous recipe")
    return false;
  end
  
  -- Check current ingredients to verify the previous recipe still has the required ingredients
  local hasRequiredIngredients = RecipeCrafterMFMApi.hasIngredientsForRecipe(storage.previousRecipe, storage.currentIngredients);
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
  logger.logDebug("Container contents changed")
  RecipeCrafterMFMApi.onContainerContentsChanged()
end

-----------------------------------------------------------------

-- Main Craft Process --
function RecipeCrafterMFMApi.craftItem()
  logger.logDebug("craftItem Called")
  if(isCrafting) then
    logger.logDebug("Already crafting, ignoring request")
    return
  end
  isCrafting = true;
  
  logger.logDebug("Craft Process Started");
  
  storage.currentIngredients = RecipeCrafterMFMApi.getIngredients();
  
  if not rcUtils.hasIngredients() then
    logger.logDebug("No ingredients found, aborting craft process")
    isCrafting = false;
    RecipeCrafterMFMApi.onNoIngredientsFound()
    return;
  end
  
  logger.logDebug("Checking output slot for availability");
  
  local outputSlotAvailable = RecipeCrafterMFMApi.isOutputSlotAvailable();
  if(not outputSlotAvailable) then
    logger.logDebug("Cannot craft item, output is not available, aborting craft process")
    isCrafting = false;
    return;
  end
  
  logger.logDebug("Output slot is available");
  
  RecipeCrafterMFMApi.onCraftStart();
  if(storage.playSoundBeforeOutputPlaced) then
    RecipeCrafterMFMApi.playCraftSound()
  end
  logger.logDebug("Locating suitable recipe")
  local outputRecipe = rcUtils.findOutput(storage.currentIngredients)
  if outputRecipe then
    logger.logDebug("Found recipe, updating output")
    RecipeCrafterMFMApi.onRecipeFound()
    rcUtils.craftWithRecipe(outputRecipe)
  else
    logger.logDebug("Failed to locate valid recipe")
    RecipeCrafterMFMApi.onNoRecipeFound()
  end
  RecipeCrafterMFMApi.releaseIngredients()
  isCrafting = false
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
    RecipeCrafterMFMApi.expelItems(toExpel)
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

function RecipeCrafterMFMApi.hasIngredientsForRecipe(recipe, ingredients)
  if(ingredients == nil or recipe == nil or recipe.output == nil) then
    return false;
  end
  logger.logDebug("Verifying ingredients are available for recipe: " .. recipe.output.name)
  -- Check the recipe inputs to verify ingredients match with all inputs
  local indent = 1
  local recipeIngredients = {}
  local allIngredientsAreRecipeIngredients = true
  for i,input in ipairs(recipe.input) do
    local inputName = input.name;
    logger.logDebug("Attempting to locate ingredient in container: " .. inputName, indent)
    local matchFound = false
    for slot,ingred in pairs(ingredients) do
      local ingredName = ingred.name
      logger.logDebug("Verifying container ingredient name '" .. ingredName .. "' in slot " .. slot .. " matches with recipe ingredient name '" .. inputName .. "'", indent + 1)
      if ingredName ~= recipe.output.name then
        if ingredName == inputName then
          logger.logDebug("Name matches, verifying count: " .. ingredName, indent + 2)
          if(input.count <= ingred.count) then
            matchFound = true
            logger.logDebug("Ingredient located: " .. ingredName, indent + 3)
            table.insert(recipeIngredients, ingredName)
            break
          else
            logger.logDebug("Insufficient ingredient count for: '" .. ingredName .. "' expected count: " .. input.count .. " actual count: " .. ingred.count, indent + 3)
          end
        else
          logger.logDebug("Name " .. inputName .. " did not match name " .. ingredName, indent + 2)
        end
      end
    end
    if not matchFound then
      logger.logDebug("Failed to locate ingredient '" .. inputName .. "' in the amount of " .. input.count, indent)
      allIngredientsAreRecipeIngredients = false
      break;
    end
  end
  if(not allIngredientsAreRecipeIngredients) then
    logger.logDebug("Failed to locate some or all required ingredients for recipe: " .. recipe.output.name, indent)
    return false;
  end
  -- All ingredients that exist should be used, even the ones not being used by the recipe
  for slot,ingred in pairs(ingredients) do
    local ingredName = ingred.name
    if ingredName ~= recipe.output.name then
      local matches = false
      for _,recipeIngredient in ipairs(recipeIngredients) do
        logger.logDebug("Verifying ingredient '" .. ingredName .. "' is used in recipe " .. recipe.output.name, indent)
        if ingredName == recipeIngredient then
          matches = true
          logger.logDebug("Success: Ingredient '" .. recipeIngredient .. "' is being used in the recipe", indent + 1)
          break
        end
      end
      if not matches then
        logger.logDebug("Failure: Extra ingredient '" .. ingredName .. "' found. It is not being used in recipe '" .. recipe.output.name .. "'", indent + 2)
        allIngredientsAreRecipeIngredients = false
        break;
      end
    end
  end
  return allIngredientsAreRecipeIngredients
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

function RecipeCrafterMFMApi.expelItems(toExpel)
  if(toExpel == nil or toExpel.count == 0) then
    return 0
  end
  local toSpawn = {name = toExpel.name, count = 1}
  logger.logDebug("Spawning toExpel with name: " .. toExpel.name .. " and count: " .. toExpel.count)
  local itemDropped = world.spawnItem(toExpel, object.position(), toExpel.count)
  if(itemDropped == nil) then
    return 0
  end
  return toExpel.count
end

-- Returns leftover output
function RecipeCrafterMFMApi.setOutputItem(outputItem)
    logger.logDebug("Attempting to replace output")
    if(outputItem == nil) then
      return
    end
    logger.logDebug("Placing output name: " .. outputItem.name .. " count: " .. outputItem.count .. " in slot " .. storage.outputSlot)
    world.containerTakeAt(entity.id(), storage.outputSlot)
    
    local toExpel = world.containerPutItemsAt(entity.id(), outputItem, storage.outputSlot)
    local newOutput = world.containerItemAt(entity.id(), storage.outputSlot)
    local totalAmount = 0
    if(toExpel) then
      if(toExpel.name == outputItem.name and toExpel.count == outputItem.count) then
        totalAmount = toExpel.count - newOutput.count
      end
    else
      totalAmount = outputItem.count - newOutput.count
    end
    return { name = outputItem.name, count = totalAmount }
  ---end
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

function rcUtils.checkCraftSoundDelay(dt)
  if not storage.craftSoundIsPlaying or isCrafting then
    return
  end
  storage.timePassed = storage.timePassed + dt
  logger.logDebug("Craft sound playing, time passed: " .. storage.timePassed)
  if storage.timePassed <= 0 then
    return
  end
  if storage.timePassed >= storage.craftSoundDelaySeconds then
    logger.logDebug("Stopping all onCraft sounds")
    storage.timePassed = 0
    storage.craftSoundIsPlaying = false
    if(animator.hasSound("onCraft")) then
      animator.stopAllSounds("onCraft")
    end
  end
end

function rcUtils.stopCraftSound()
  logger.logDebug("Stopping onCraft Sound")
  if (storage.craftSoundIsPlaying and animator.hasSound("onCraft")) then
    animator.stopAllSounds("onCraft")
    storage.craftSoundIsPlaying = false
  end
end

function rcUtils.craftWithRecipe(recipe)
  local outputName = recipe.output.name
  
  storage.previousRecipe = nil
  storage.outputPlacedSuccessfully = false
  
  if(not storage.noHold) then
    RecipeCrafterMFMApi.holdIngredients(recipe)
  end
  
  local outputItem = RecipeCrafterMFMApi.getOutputItem(recipe)
  
  if(outputItem == nil) then
    return
  end
  
  local leftoverOutput = RecipeCrafterMFMApi.setOutputItem(outputItem)
  local totalOutputCount = RecipeCrafterMFMApi.expelItems(leftoverOutput);
  
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
    storage.previousRecipe = recipe
    storage.outputPlacedSuccessfully = true
    return
  end
  
  logger.logDebug("Output not successfully placed, item found instead: " .. newOutput.name)
end

function rcUtils.recipeCanBeCrafted(recipe)
  if storage.recipeGroup == nil then
    logger.logDebug("No Recipe Group specified")
    return false
  end
  logger.logDebug("Recipe group specified: " .. storage.recipeGroup)
  local canBeCrafted = false
  for _,group in ipairs(recipe.groups) do
    if group == storage.recipeGroup then
      canBeCrafted = true
      break
    end
  end
  return canBeCrafted
end

function rcUtils.findRecipe(recipesForItem, ingredients)
  local recipeFound = nil
  for _,recipe in ipairs(recipesForItem) do
    if (rcUtils.recipeCanBeCrafted(recipe) and RecipeCrafterMFMApi.hasIngredientsForRecipe(recipe, ingredients)) then
      recipeFound = recipe
      break;
    else
      logger.logDebug("Recipe cannot be crafted: " .. recipe.output.name)
    end
  end
  return recipeFound
end

function rcUtils.findOutput(ingredients)

  -- A shortcircuit to searching the entire recipe list, just to the find the same recipe
  if(storage.previousRecipe ~= nil) then
    local previousRecipeMatches = RecipeCrafterMFMApi.hasIngredientsForRecipe(storage.previousRecipe, ingredients);
    if(previousRecipeMatches) then
      logger.logDebug("Previous recipe matches current ingredients, using it")
      return storage.previousRecipe;
    end
  end

  local foundOutput = nil
  
  if(storage.recipeBookRecipes ~= nil) then
    logger.logDebug("Using Recipe Book Recipes")
    for itemName,item in pairs(storage.recipeBookRecipes) do
      local recipesForItem = item.recipes
      if recipesForItem ~= nil and #recipesForItem > 0 then
        foundOutput = rcUtils.findRecipe(recipesForItem, ingredients)
        if foundOutput then
          logger.logDebug("Found recipe with output name: " .. foundOutput.output.name)
          break;
        end
      end
    end
  else
    for _,itemName in ipairs(storage.possibleOutputs) do
        local recipesForItem = root.recipesForItem(itemName)
        if recipesForItem ~= nil and #recipesForItem > 0 then
          foundOutput = rcUtils.findRecipe(recipesForItem, ingredients)
          if foundOutput then
            logger.logDebug("Found recipe with output name: " .. foundOutput.output.name)
            break;
          end
        end
      end
    end
  return foundOutput
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