require "/scripts/debugUtilsCN.lua"

RecipeCrafterMFMApi = {};
local rcUtils = {};
local isCrafting = false;
local debugMsgPrefix = "[RCAPI]"

function RecipeCrafterMFMApi.init(msgPrefix)
  if(not msgPrefix) then
    debugMsgPrefix = msgPrefix
  end
  DebugUtilsCN.init(debugMsgPrefix)
  local outputConfigPath = config.getParameter("outputConfig")
  if outputConfigPath == nil then
    storage.possibleOutputs = {}
  else
    storage.possibleOutputs = root.assetJson(outputConfigPath).possibleOutput
  end
  storage.slotCount = config.getParameter("slotCount", 16)
  storage.outputSlot = config.getParameter("outputSlot", 15)
  DebugUtilsCN.logDebug("Setting output slot to: " .. storage.outputSlot)
  if storage.outputSlot < 0 then
    storage.outputSlot = 0
  end
  storage.timePassed = 0
  storage.previousRecipe = nil
  storage.heldIngredients = {}
  storage.craftSoundDelaySeconds = config.getParameter("craftSoundDelaySeconds", 10) -- In seconds
  storage.craftSoundIsPlaying = false
  storage.recipeGroup = config.getParameter("recipeGroup")
  storage.noRecipeBookGroup = storage.recipeGroup .. "NoRecipeBook"
  storage.isRefridgerated = config.getParameter("itemAgeMultiplier", 5) == 0
  
  ----- Configuration -----
  storage.consumeIngredientsOnCraft = true;
  storage.noHold = false;
  storage.playSoundBeforeOutputPlaced = true;
  storage.appendToOutput = true;
  
  if(storage.outputSlotModified == nil) then
    storage.outputSlotModified = false;
  end
  
  if(storage.currentIngredients == nil) then
    storage.currentIngredients = nil;
  end
  -------------------------
  
  storage.ignoreContainerContentChanges = false;
  if(storage.enableRecipeGroupDebug == nil) then
    storage.enableRecipeGroupDebug = false
  end
  message.setHandler("craft", rcUtils.craftHandler)
end

function RecipeCrafterMFMApi.update(dt)
  rcUtils.checkCraftSoundDelay(dt)
end

function RecipeCrafterMFMApi.die()
  isCrafting = false
  RecipeCrafterMFMApi.releaseIngredients()
end

--------------------------Callbacks---------------------------------------

--onIngredientChange() when the container contents change, this is invoked
function RecipeCrafterMFMApi.onIngredientsChanged()

end

--onNoRecipeFound() when startCrafting is called, this method is invoked when no recipe is found using the current ingredients
function RecipeCrafterMFMApi.onNoRecipeFound()

end

--isOutputSlotAvailableCallback(ItemInOutputSlot<ItemDescriptor>) when startCrafting is called, this method is the final determination to decide if a new recipe should be located
--  Recipe - { output: { name (string), count (double) }, input: [{ name (string), count (double) }], groups: [string] }
--  outputSlotItem - { name (string), count (double) }
function RecipeCrafterMFMApi.isOutputSlotAvailable()
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if outputSlotItem == nil then
    DebugUtilsCN.logDebug("No output item, so look for recipe")
    return true;
  end
  if(storage.previousRecipe == nil) then
    DebugUtilsCN.logDebug("No previous recipe, so look for recipe")
    return true;
  end
  return storage.previousRecipe.output.name == outputSlotItem.name
end

function containerCallback()
  if(storage.ignoreContainerContentChanges) then
    storage.ignoreContainerContentChanges = false
    return
  end
  DebugUtilsCN.logDebug("Container contents changed")
  RecipeCrafterMFMApi.onIngredientsChanged()
end

-----------------------------------------------------------------

function RecipeCrafterMFMApi.holdIngredients(recipe)
  RecipeCrafterMFMApi.releaseIngredients()
  storage.heldIngredients = {}
  DebugUtilsCN.logDebug("Holding ingredients")
  local containerId = entity.id()
  for _,input in ipairs(recipe.input) do
    DebugUtilsCN.logDebug("Holding ingredient with name: " .. input.name .. " and count: " .. input.count)
    if(world.containerConsume(containerId, input)) then
      table.insert(storage.heldIngredients, input)
    end
  end
end

function RecipeCrafterMFMApi.releaseIngredients()
  if(storage.heldIngredients == nil) then
    return false
  end
  DebugUtilsCN.logDebug("Releasing ingredients")
  local containerId = entity.id()
  for _,input in ipairs(storage.heldIngredients) do
    DebugUtilsCN.logDebug("Releasing ingredient with name: " .. input.name .. " and count: " .. input.count)
    local toExpel = world.containerAddItems(containerId, input)
    RecipeCrafterMFMApi.expelItems(toExpel)
  end
  storage.heldIngredients = nil
end

function RecipeCrafterMFMApi.consumeIngredients()
  if(storage.heldIngredients == nil) then
    return false
  end
  DebugUtilsCN.logDebug("Consuming ingredients")
  storage.heldIngredients = nil
end

function rcUtils.craftHandler()
  RecipeCrafterMFMApi.startCrafting()
end

function RecipeCrafterMFMApi.startCrafting()
  DebugUtilsCN.logDebug("startCrafting Called")
  if(isCrafting) then
    DebugUtilsCN.logDebug("Already crafting, ignoring request")
    return
  end
  isCrafting = true;
  
  DebugUtilsCN.logDebug("Starting to Craft")
  
  storage.currentIngredients = RecipeCrafterMFMApi.getIngredients();
  
  if not rcUtils.hasIngredients() then
    DebugUtilsCN.logDebug("No ingredients found, aborting recipe search")
    isCrafting = false;
    RecipeCrafterMFMApi.onNoRecipeFound()
    return;
  end
  
  local canCraft = rcUtils.canCraft();
  if(not canCraft) then
    DebugUtilsCN.logDebug("Aborting startCrafting call")
    isCrafting = false;
    return;
  end
  
  storage.previousRecipe = nil
  if(storage.playSoundBeforeOutputPlaced) then
    RecipeCrafterMFMApi.onCraft()
  end
  DebugUtilsCN.logDebug("Locating suitable recipe")
  local outputRecipe = rcUtils.findOutput(storage.currentIngredients)
  if outputRecipe then
    DebugUtilsCN.logDebug("Found recipe, updating output")
    rcUtils.craftWithRecipe(outputRecipe)
  else
    DebugUtilsCN.logDebug("Failed to locate valid recipe")
    RecipeCrafterMFMApi.onNoRecipeFound()
  end
  RecipeCrafterMFMApi.releaseIngredients()
  isCrafting = false
end

function rcUtils.canCraft()
  return RecipeCrafterMFMApi.isOutputSlotAvailable()
end

function RecipeCrafterMFMApi.hasIngredientsForRecipe(recipe, ingredients)
  if(ingredients == nil or recipe == nil or recipe.output == nil) then
    return false;
  end
  DebugUtilsCN.logDebug("Verifying ingredients are available for recipe: " .. recipe.output.name)
  -- Check the recipe inputs to verify ingredients match with all inputs
  local indent = 1
  local recipeIngredients = {}
  local allIngredientsAreRecipeIngredients = true
  for i,input in ipairs(recipe.input) do
    local inputName = input.name;
    DebugUtilsCN.logDebug("Attempting to locate ingredient in container: " .. inputName, indent)
    local matchFound = false
    for slot,ingred in pairs(ingredients) do
      local ingredName = ingred.name
      DebugUtilsCN.logDebug("Verifying container ingredient name '" .. ingredName .. "' matches with recipe ingredient name '" .. inputName .. "'", indent + 1)
      if ingredName ~= recipe.output.name then
        if ingredName == inputName then
          DebugUtilsCN.logDebug("Name matches, verifying count: " .. ingredName, indent + 2)
          if(input.count <= ingred.count) then
            matchFound = true
            DebugUtilsCN.logDebug("Ingredient located: " .. ingredName, indent + 3)
            table.insert(recipeIngredients, ingredName)
            break
          else
            DebugUtilsCN.logDebug("Insufficient ingredient count for: '" .. ingredName .. "' expected count: " .. input.count .. " actual count: " .. ingred.count, indent + 3)
          end
        else
          DebugUtilsCN.logDebug("Name " .. inputName .. " did not match name " .. ingredName, indent + 2)
        end
      end
    end
    if not matchFound then
      DebugUtilsCN.logDebug("Failed to locate ingredient '" .. inputName .. "' in the amount of " .. input.count, indent)
      allIngredientsAreRecipeIngredients = false
      break;
    end
  end
  if(not allIngredientsAreRecipeIngredients) then
    DebugUtilsCN.logDebug("Failed to locate some or all required ingredients for recipe: " .. recipe.output.name, indent)
    return false;
  end
  -- All ingredients that exist should be used, even the ones not being used by the recipe
  for slot,ingred in pairs(ingredients) do
    local ingredName = ingred.name
    if ingredName ~= recipe.output.name then
      local matches = false
      for _,recipeIngredient in ipairs(recipeIngredients) do
        DebugUtilsCN.logDebug("Verifying ingredient '" .. ingredName .. "' is used in recipe " .. recipe.output.name, indent)
        if ingredName == recipeIngredient then
          matches = true
          DebugUtilsCN.logDebug("Success: Ingredient '" .. recipeIngredient .. "' is being used in the recipe", indent + 1)
          break
        end
      end
      if not matches then
        DebugUtilsCN.logDebug("Failure: Extra ingredient '" .. ingredName .. "' found. It is not being used in recipe '" .. recipe.output.name .. "'", indent + 2)
        allIngredientsAreRecipeIngredients = false
        break;
      end
    end
  end
  return allIngredientsAreRecipeIngredients
end

function RecipeCrafterMFMApi.getIngredients()
  local ingredientNames = {}
  local uniqueIngredients = {}
  local ingredients = world.containerItems(entity.id())
  for slot,item in pairs(ingredients) do
    local isNotOutputItem = storage.previousRecipe == nil or (storage.previousRecipe and storage.previousRecipe.output.name ~= item.name);
    if (ingredientNames[item.name] == nil and isNotOutputItem and slot ~= storage.outputSlot) then
      item.count = world.containerAvailable(entity.id(), item.name)
      ingredientNames[item.name] = true
      uniqueIngredients[slot] = item
    end
  end
  return uniqueIngredients
end

function RecipeCrafterMFMApi.onCraft()
  if animator.hasSound("onCraft") and not storage.craftSoundIsPlaying then
    DebugUtilsCN.logDebug("Playing onCraft sounds")
    storage.timePassed = 0
    animator.playSound("onCraft")
    storage.craftSoundIsPlaying = true
  end
end

function RecipeCrafterMFMApi.getOutputItem(recipe)
  local outputCount = recipe.output.count
  local outputName = recipe.output.name
  local existingAmount = 0
  local existingOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if(existingOutput) then
    existingAmount = existingOutput.count
    if existingOutput.name ~= outputName or (not storage.appendToOutput and existingOutput.count > 0 and existingOutput.count < recipe.output.count) then
      DebugUtilsCN.logDebug("Could not place output '" .. outputName .. "' because of existing item '" .. existingOutput.name .. "' in slot: " .. storage.outputSlot)
      return nil
    end
  end
  
  local expectedNewAmount = recipe.output.count
  if(storage.appendToOutput) then
    expectedNewAmount = expectedNewAmount + existingAmount
  end
  return {name = outputName, count = expectedNewAmount}
end

------------------------------------------------------------------

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
    DebugUtilsCN.logDebug("Output not successfully placed, and no item found at slot " .. storage.outputSlot)
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
  
  DebugUtilsCN.logDebug("Output not successfully placed, item found instead: " .. newOutput.name)
end

-- Returns leftover output
function RecipeCrafterMFMApi.setOutputItem(outputItem)
    DebugUtilsCN.logDebug("Attempting to replace output")
    if(outputItem == nil) then
      return
    end
    DebugUtilsCN.logDebug("Placing output name: " .. outputItem.name .. " count: " .. outputItem.count .. " in slot " .. storage.outputSlot)
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

function RecipeCrafterMFMApi.expelItems(toExpel)
  if(toExpel == nil or toExpel.count == 0) then
    return 0
  end
  local toSpawn = {name = toExpel.name, count = 1}
  DebugUtilsCN.logDebug("Spawning toExpel with name: " .. toExpel.name .. " and count: " .. toExpel.count)
  local itemDropped = world.spawnItem(toExpel, object.position(), toExpel.count)
  if(itemDropped == nil) then
    return 0
  end
  return toExpel.count
end

function rcUtils.recipeCanBeCrafted(recipe)
  if storage.recipeGroup == nil then
    DebugUtilsCN.logDebug("No Recipe Group specified")
    return false
  end
  DebugUtilsCN.logDebug("Recipe group specified: " .. storage.recipeGroup)
  local canBeCrafted = false
  for _,group in ipairs(recipe.groups) do
    if group == storage.recipeGroup or group == storage.noRecipeBookGroup then
      canBeCrafted = true
      break
    end
  end
  return canBeCrafted
end

function rcUtils.findRecipe(recipesForItem, ingredients)
  local recipeFound = nil
  for _,recipe in ipairs(recipesForItem) do
    if rcUtils.recipeCanBeCrafted(recipe) and RecipeCrafterMFMApi.hasIngredientsForRecipe(recipe, ingredients) then
      recipeFound = recipe
      break;
    else
      DebugUtilsCN.logDebug("Recipe cannot be crafted: " .. recipe.output.name)
    end
  end
  return recipeFound
end

function rcUtils.findOutput(ingredients)

  -- A shortcircuit to searching the entire recipe list, just to the find the same recipe
  if(storage.previousRecipe ~= nil) then
    local previousRecipeMatches = RecipeCrafterMFMApi.hasIngredientsForRecipe(storage.previousRecipe, ingredients);
    if(previousRecipeMatches) then
      DebugUtilsCN.logDebug("Previous recipe matches current ingredients, using it")
      return storage.previousRecipe;
    end
  end

  local foundOutput = nil
  for _,itemName in ipairs(storage.possibleOutputs) do
    local recipesForItem = root.recipesForItem(itemName)
    if recipesForItem ~= nil and #recipesForItem > 0 then
      foundOutput = rcUtils.findRecipe(recipesForItem, ingredients)
      if foundOutput then
        DebugUtilsCN.logDebug("Found recipe with output name: " .. foundOutput.output.name)
        break;
      end
    end
  end
  return foundOutput
end

function rcUtils.checkCraftSoundDelay(dt)
  if not storage.craftSoundIsPlaying or isCrafting then
    return
  end
  storage.timePassed = storage.timePassed + dt
  DebugUtilsCN.logDebug("Craft sound playing, time passed: " .. storage.timePassed)
  if storage.timePassed <= 0 then
    return
  end
  if storage.timePassed >= storage.craftSoundDelaySeconds then
    DebugUtilsCN.logDebug("Stopping all onCraft sounds")
    storage.timePassed = 0
    storage.craftSoundIsPlaying = false
    animator.stopAllSounds("onCraft")
  end
end

function rcUtils.hasIngredients()
  if(storage.currentIngredients == nil) then
    return false;
  end
  local numberOfIngredients = 0
  for slot,item in pairs(storage.currentIngredients) do
    if slot ~= storage.outputSlot + 1 then
      numberOfIngredients = numberOfIngredients + 1
    end
  end
  return numberOfIngredients > 0
end

function rcUtils.stopCraftSound()
  DebugUtilsCN.logDebug("Stopping onCraft Sound")
  if (animator.hasSound("onCraft") and storage.craftSoundIsPlaying) then
    animator.stopAllSounds("onCraft")
    storage.craftSoundIsPlaying = false
  end
end