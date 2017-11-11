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
  storage.consumeIngredientsOnCraft = true
  storage.noHold = false
  storage.playOnCraftBeforeOutputPlaced = true
  storage.appendToOutput = true
  storage.expectOutputChange = false
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

--shouldLookForRecipeCallback(Recipe, ItemDescriptor) when startCrafting is called, this method is the final determination to decide if a new recipe should be located
--  Recipe - { output: { name (string), count (double) }, input: [{ name (string), count (double) }], groups: [string] }
--  outputSlotItem - { name (string), count (double) }
function RecipeCrafterMFMApi.shouldLookForRecipeCallback(previousOutput, outputSlotItem)
  return  previousOutput.name == outputSlotItem.name
end

function containerCallback()
  if(not storage.expectOutputChange) then
    DebugUtilsCN.logDebug("Ingredients changed")
    RecipeCrafterMFMApi.onIngredientsChanged()
  else
    storage.expectOutputChange = false
  end
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
    local leftovers = world.containerAddItems(containerId, input)
    rcUtils.spawnLeftovers(leftovers)
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

function RecipeCrafterMFMApi.startCrafting(containerIngredients)
  DebugUtilsCN.logDebug("startCrafting Called")
  if(isCrafting) then
    DebugUtilsCN.logDebug("Already crafting, ignoring request")
    return
  end
  DebugUtilsCN.logDebug("Starting to Craft")
  isCrafting = true
  if not rcUtils.shouldLookForRecipe() then
    DebugUtilsCN.logDebug("Recipe already found, aborting recipe search")
    isCrafting = false
    return
  end
  local ingredients
  if(containerIngredients) then
    ingredients = containerIngredients
  else
    ingredients = RecipeCrafterMFMApi.getIngredients()
  end
  if ingredients == nil or rcUtils.hasNoIngredients(ingredients) then
    DebugUtilsCN.logDebug("No ingredients found, aborting recipe search")
    isCrafting = false
    RecipeCrafterMFMApi.onNoRecipeFound()
    return
  end
  storage.previousRecipe = nil
  if(storage.playOnCraftBeforeOutputPlaced) then
    RecipeCrafterMFMApi.onCraft()
  end
  DebugUtilsCN.logDebug("Locating suitable recipe")
  local outputRecipe = rcUtils.findOutput(ingredients)
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

function RecipeCrafterMFMApi.checkIngredientsMatchRecipe(recipe, ingredients)
  DebugUtilsCN.logDebug("Checking Recipe Ingredients For Recipe: " .. recipe.output.name)
  -- Check the recipe inputs to verify ingredients match with all inputs
  local indent = 1
  local ingredientsUsed = {}
  local matchesAllInput = true
  for i,input in ipairs(recipe.input) do
    local inputName = input.name;
    DebugUtilsCN.logDebug("Attempting to locate ingredient: " .. inputName, indent)
    local matchFound = false
    for slot,ingred in pairs(ingredients) do
      DebugUtilsCN.logDebug("Checking for name match: " .. ingred.name, indent + 1)
      if ingred.name ~= recipe.output.name then
        if input.name == ingred.name then
          DebugUtilsCN.logDebug("Name matches, verifying count: " .. inputName, indent + 2)
          if(input.count <= ingred.count) then
            matchFound = true
            DebugUtilsCN.logDebug("Ingredient located: " .. inputName, indent + 3)
            table.insert(ingredientsUsed, ingred.name)
            break
          else
            DebugUtilsCN.logDebug("Insufficient ingredient count: " .. inputName .. " expected: " .. input.count .. " actual: " .. ingred.count, indent + 3)
          end
        else
          DebugUtilsCN.logDebug("Name " .. inputName .. " did not match name " .. ingred.name, indent + 2)
        end
      end
    end
    if not matchFound then
      DebugUtilsCN.logDebug("Failed to locate ingredient: " .. inputName, indent)
      matchesAllInput = false
      break;
    end
  end
  if(not matchesAllInput) then
    DebugUtilsCN.logDebug("Failed to locate all ingredients for recipe: " .. recipe.output.name, indent)
    return false;
  end
  -- All ingredients that exist should be used
  for slot,ingred in pairs(ingredients) do
    if ingred.name ~= recipe.output.name then
      local matches = false
      for _,ingreds in ipairs(ingredientsUsed) do
        DebugUtilsCN.logDebug("Checking ingredient name " .. ingreds .. " matches name: " .. ingred.name, indent)
        if ingred.name == ingreds then
          matches = true
          DebugUtilsCN.logDebug("Ingredient name matches: " .. ingreds, indent + 1)
          break
        end
      end
      if not matches then
        DebugUtilsCN.logDebug("No match found for " .. ingred.name, indent + 2)
        matchesAllInput = false
        break;
      end
    end
  end
  return matchesAllInput
end

function RecipeCrafterMFMApi.getIngredients()
  local ingredientNames = {}
  local uniqueIngredients = {}
  local ingredients = world.containerItems(entity.id())
  for slot,item in pairs(ingredients) do
    if ingredientNames[item.name] == nil then
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

------------------------------------------------------------------

function rcUtils.craftWithRecipe(recipe)
  local outputName = recipe.output.name
  
  storage.previousRecipe = nil
  storage.outputPlacedSuccessfully = false
  
  if(not storage.noHold) then
    RecipeCrafterMFMApi.holdIngredients(recipe)
  end
  local existingOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if existingOutput and (existingOutput.name ~= outputName) then
    DebugUtilsCN.logDebug("Could not place output '" .. outputName .. "' because of existing item found with name: '" .. existingOutput.name .. "' in slot " .. storage.outputSlot)
    return
  end
  
  local existingAmount = 0
  if(existingOutput) then
    existingAmount = existingOutput.count
  end
  local expectedNewAmount = recipe.output.count
  if(storage.appendToOutput) then
    expectedNewAmount = expectedNewAmount + existingAmount
  end
  local outputItem = {name = outputName, count = expectedNewAmount}
  
  local leftoverOutput = rcUtils.setOutputItem(recipe, outputItem)
  local totalOutputCount = rcUtils.spawnLeftovers(leftoverOutput);
  
  local newOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if(newOutput ~= nil) then
    totalOutputCount = totalOutputCount + newOutput.count
  end
  if newOutput ~= nil and newOutput.name == outputItem.name and totalOutputCount == outputItem.count then
    if(storage.consumeIngredientsOnCraft) then
      RecipeCrafterMFMApi.consumeIngredients()
    end
    storage.previousRecipe = recipe
    storage.outputPlacedSuccessfully = true
    return
  end
  
  if newOutput ~= nil then
    DebugUtilsCN.logDebug("Output not successfully placed, item found instead: " .. newOutput.name)
  else
    DebugUtilsCN.logDebug("Output not successfully placed, and no item found at slot " .. storage.outputSlot)
  end
  RecipeCrafterMFMApi.releaseIngredients()
end

-- Returns leftover output
function rcUtils.setOutputItem(recipe, outputItem)
  ---if(storage.isRefridgerated) then
  ---  DebugUtilsCN.logDebug("Attempting to stack output")
   
  ---  return world.containerItemApply(entity.id(), recipe.output, storage.outputSlot)
  ---else
    DebugUtilsCN.logDebug("Attempting to replace output")
    if(outputItem == nil) then
      return
    end
    DebugUtilsCN.logDebug("Placing output name: " .. outputItem.name .. " count: " .. outputItem.count .. " in slot " .. storage.outputSlot)
    world.containerTakeAt(entity.id(), storage.outputSlot)
    
    local leftovers = world.containerPutItemsAt(entity.id(), outputItem, storage.outputSlot)
    local newOutput = world.containerItemAt(entity.id(), storage.outputSlot)
    local totalLeftovers = 0
    if(leftovers) then
      if(leftovers.name == outputItem.name and leftovers.count == outputItem.count) then
        totalLeftovers = leftovers.count - newOutput.count
      end
    else
      totalLeftovers = outputItem.count - newOutput.count
    end
    return { name = outputItem.name, count = totalLeftovers }
  ---end
end

function rcUtils.spawnLeftovers(leftovers)
  if(leftovers == nil or leftovers.count == 0) then
    return 0
  end
  local toSpawn = {name = leftovers.name, count = 1}
  DebugUtilsCN.logDebug("Spawning leftovers with name: " .. leftovers.name .. " and count: " .. leftovers.count)
  local itemDropped = world.spawnItem(leftovers, object.position(), leftovers.count)
  if(itemDropped == nil) then
    return 0
  end
  return leftovers.count
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
    if rcUtils.recipeCanBeCrafted(recipe) and RecipeCrafterMFMApi.checkIngredientsMatchRecipe(recipe, ingredients) then
      recipeFound = recipe
      break;
    else
      DebugUtilsCN.logDebug("Recipe cannot be crafted: " .. recipe.output.name)
    end
  end
  return recipeFound
end

function rcUtils.findOutput(ingredients)
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

function rcUtils.shouldLookForRecipe()
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if outputSlotItem == nil then
    DebugUtilsCN.logDebug("No output item, so look for recipe")
    return true
  end
  if(storage.previousRecipe == nil) then
    DebugUtilsCN.logDebug("No previous recipe, so look for recipe")
    return true
  end
  local previousOutput = storage.previousRecipe.output
  if previousOutput == nil then
    DebugUtilsCN.logDebug("No output recipe, so look for recipe")
    return true
  end
  return RecipeCrafterMFMApi.shouldLookForRecipeCallback(previousOutput, outputSlotItem)
end

function rcUtils.hasNoIngredients(ingredients)
  local numberOfIngredients = 0
  for slot,item in pairs(ingredients) do
    if slot ~= storage.outputSlot + 1 then
      numberOfIngredients = numberOfIngredients + 1
    end
  end
  return numberOfIngredients == 0
end

function rcUtils.stopCraftSound()
  DebugUtilsCN.logDebug("Stopping onCraft Sound")
  if (animator.hasSound("onCraft") and storage.craftSoundIsPlaying) then
    animator.stopAllSounds("onCraft")
    storage.craftSoundIsPlaying = false
  end
end