RecipeCrafterMFMApi = {};
local rcUtils = {};
local enableRecipeGroupDebug = false;
local isCrafting = false
local enableDebug = false

function init(virtual)
  local outputConfigPath = config.getParameter("outputConfig")
  if outputConfigPath == nil then
    storage.possibleOutputs = {}
  else
    storage.possibleOutputs = root.assetJson(outputConfigPath).possibleOutput
  end
  storage.slotCount = config.getParameter("slotCount", 16)
  storage.outputSlot = config.getParameter("outputSlot", 15)
  rcUtils.logDebug("Setting output slot to: " .. storage.outputSlot)
  if storage.outputSlot < 0 then
    storage.outputSlot = 0
  end
  storage.timePassed = 0
  storage.previousRecipeName = nil
  storage.heldIngredients = {}
  storage.craftSoundDelaySeconds = config.getParameter("craftSoundDelaySeconds", 10) -- In seconds
  storage.craftSoundIsPlaying = false
  enableDebug = false
  enableRecipeGroupDebug = false
  storage.recipeGroup = config.getParameter("recipeGroup")
  storage.noRecipeBookGroup = storage.recipeGroup .. "NoRecipeBook"
  storage.isRefridgerated = config.getParameter("itemAgeMultiplier", 5) == 0
  message.setHandler("makeMeal", RecipeCrafterMFMApi.makeMeal)
  message.setHandler("setEnableDebug", RecipeCrafterMFMApi.setEnableDebug)
end

function update(dt)
  rcUtils.checkCraftSoundDelay(dt)
end

function die()
  rcUtils.releaseIngredients()
end

-------------------------------------------------------------------

function RecipeCrafterMFMApi.setEnableDebug(id, name, newValue)
  enableDebug = newValue or false
  enableRecipeGroupDebug = newValue or false
  if(enableDebug) then
    sb.logInfo("Toggled Debug On")
  else
    sb.logInfo("Toggled Debug Off")
  end
end

function RecipeCrafterMFMApi.makeMeal()
  rcUtils.logDebug("Make Meal Called")
  if(isCrafting) then
    return
  end
  isCrafting = true
  rcUtils.startCrafting()
  isCrafting = false
end

-------------------------------------------------------------------

function rcUtils.startCrafting()
  if not rcUtils.shouldLookForRecipe() then
    rcUtils.logDebug("No Look")
    return
  end
  local ingredients = rcUtils.getIngredients()
  if ingredients == nil or rcUtils.hasNoIngredients(ingredients) then
    rcUtils.logDebug("No Ingredients")
    return
  end
  storage.previousRecipeName = nil
  rcUtils.logDebug("Finding Output")
  rcUtils.onCraft()
  local outputRecipe = rcUtils.findOutput(ingredients)
  if outputRecipe then
    rcUtils.logDebug("Updating Output")
    rcUtils.craftWithRecipe(outputRecipe)
  else
    rcUtils.logDebug("No output found")
  end
  rcUtils.releaseIngredients()
end

function rcUtils.craftWithRecipe(recipe)
  local outputName = recipe.output.name
  storage.previousRecipeName = outputName
  rcUtils.holdIngredients(recipe)
  local existingOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if existingOutput and (existingOutput.name ~= outputName) then
    rcUtils.logRecipeDebug("Could not place output '" .. outputName .. "' because of existing item found with name: '" .. existingOutput.name .. "' in slot " .. storage.outputSlot)
    return
  end
  
  local existingAmount = 0
  if(existingOutput) then
    existingAmount = existingOutput.count
  end
  local expectedNewAmount = recipe.output.count + existingAmount
  local outputItem = {name = outputName, count = expectedNewAmount}
  
  local leftoverOutput = rcUtils.setOutputItem(recipe, outputItem)
  local totalOutputCount = rcUtils.spawnLeftovers(leftoverOutput);
  
  local newOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if(newOutput ~= nil) then
    totalOutputCount = totalOutputCount + newOutput.count
  end
  if newOutput ~= nil and newOutput.name == outputItem.name and totalOutputCount == outputItem.count then
    rcUtils.consumeIngredients()
    return
  end
  
  if newOutput ~= nil then
    rcUtils.logDebug("Output not successfully placed, item found instead: " .. newOutput.name)
  else
    rcUtils.logDebug("Output not successfully placed, and no item found at slot " .. storage.outputSlot)
  end
  
  rcUtils.releaseIngredients()
end

-- Returns leftover output
function rcUtils.setOutputItem(recipe, outputItem)
  ---if(storage.isRefridgerated) then
  ---  rcUtils.logDebug("Attempting to stack output")
   
  ---  return world.containerItemApply(entity.id(), recipe.output, storage.outputSlot)
  ---else
    rcUtils.logDebug("Attempting to replace output")
    if(outputItem == nil) then
      return
    end
    rcUtils.logDebug("Placing output name: " .. outputItem.name .. " count: " .. outputItem.count .. " in slot " .. storage.outputSlot)
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
  rcUtils.logDebug("Spawning leftovers with name: " .. leftovers.name .. " and count: " .. leftovers.count)
  local itemDropped = world.spawnItem(leftovers, object.position(), leftovers.count)
  if(itemDropped == nil) then
    return 0
  end
  return leftovers.count
end

function rcUtils.recipeCanBeCrafted(recipe)
  if storage.recipeGroup == nil then
    rcUtils.logRecipeDebug("No Recipe Group specified")
    return false
  end
  rcUtils.logRecipeDebug("Recipe group specified: " .. storage.recipeGroup)
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
    if rcUtils.recipeCanBeCrafted(recipe) and rcUtils.checkIngredientsMatchRecipe(recipe, ingredients) then
      recipeFound = recipe
      break;
    else
      rcUtils.logRecipeDebug("Recipe cannot be crafted: " .. recipe.output.name)
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
        rcUtils.logRecipeDebug("Found recipe with output name: " .. foundOutput.output.name)
        break;
      end
    end
  end
  return foundOutput
end

function rcUtils.checkIngredientsMatchRecipe(recipe, ingredients)
  rcUtils.logRecipeDebug("Checking Recipe Ingredients For Recipe: " .. recipe.output.name)
  -- Check the recipe inputs to verify ingredients match with all inputs
  local ingredientsUsed = {}
  local matchesAllInput = true
  for i,input in ipairs(recipe.input) do
      rcUtils.logRecipeDebug("Checking Input: " .. input.name)
    local matchFound = false
    for slot,ingred in pairs(ingredients) do
      rcUtils.logRecipeDebug("Checking Ingred: " .. ingred.name)
      if ingred.name ~= recipe.output.name then
        if input.name == ingred.name and input.count <= ingred.count then
          matchFound = true
          rcUtils.logRecipeDebug("Match Found: " .. ingred.name)
          table.insert(ingredientsUsed, ingred.name)
          break
        end
      end
    end
    if not matchFound then
      rcUtils.logRecipeDebug("All Inputs Do Not Match")
      matchesAllInput = false
      break;
    end
  end
  -- All ingredients that exist should be used
  for slot,ingred in pairs(ingredients) do
    if ingred.name ~= recipe.output.name then
      local matches = false
      for _,ingreds in ipairs(ingredientsUsed) do
        rcUtils.logRecipeDebug("Checking Ingredient Matches With: " .. ingreds)
        if ingred.name == ingreds then
          matches = true
          rcUtils.logRecipeDebug("Ingredient Matches: " .. ingred.name)
          break
        end
      end
      if not matches then
        rcUtils.logRecipeDebug("Ingredient Doesn't Match: " .. ingred.name)
        matchesAllInput = false
        break;
      end
    end
  end
  return matchesAllInput
end

function rcUtils.checkCraftSoundDelay(dt)
  if not storage.craftSoundIsPlaying or isCrafting then
    return
  end
  storage.timePassed = storage.timePassed + dt
  rcUtils.logDebug("Craft sound playing, time passed: " .. storage.timePassed)
  if storage.timePassed <= 0 then
    return
  end
  if storage.timePassed >= storage.craftSoundDelaySeconds then
    rcUtils.logDebug("Stopping all onCraft sounds")
    storage.timePassed = 0
    storage.craftSoundIsPlaying = false
    animator.stopAllSounds("onCraft")
  end
end

function rcUtils.holdIngredients(outputRecipe)
  rcUtils.releaseIngredients()
  storage.heldIngredients = {}
  rcUtils.logDebug("Holding ingredients")
  local containerId = entity.id()
  for _,input in ipairs(outputRecipe.input) do
    rcUtils.logDebug("Holding ingredient with name: " .. input.name .. " and count: " .. input.count)
    if(world.containerConsume(containerId, input)) then
      table.insert(storage.heldIngredients, input)
    end
  end
end

function rcUtils.releaseIngredients()
  if(storage.heldIngredients == nil) then
    return false
  end
  rcUtils.logDebug("Releasing ingredients")
  local containerId = entity.id()
  for _,input in ipairs(storage.heldIngredients) do
    rcUtils.logDebug("Releasing ingredient with name: " .. input.name .. " and count: " .. input.count)
    local leftovers = world.containerAddItems(containerId, input)
    rcUtils.spawnLeftovers(leftovers)
  end
  storage.heldIngredients = nil
end

function rcUtils.consumeIngredients()
  if(storage.heldIngredients == nil) then
    return false
  end
  rcUtils.logDebug("Consuming ingredients")
  storage.heldIngredients = nil
end

function rcUtils.getIngredients()
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

function rcUtils.shouldLookForRecipe()
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  return outputSlotItem == nil or storage.previousRecipeName == nil or storage.previousRecipeName == outputSlotItem.name
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

function rcUtils.onCraft()
  if animator.hasSound("onCraft") and not storage.craftSoundIsPlaying then
    rcUtils.logDebug("Playing onCraft sounds")
    storage.timePassed = 0
    animator.playSound("onCraft")
    storage.craftSoundIsPlaying = true
  end
end

function rcUtils.stopCraftSound()
  rcUtils.logDebug("Stopping onCraft Sound")
  if (animator.hasSound("onCraft") and storage.craftSoundIsPlaying) then
    animator.stopAllSounds("onCraft")
    storage.craftSoundIsPlaying = false
  end
end

--------------------------------------------------------------------------------

function rcUtils.logRecipeDebug(msg)
  if(enableRecipeGroupDebug) then
    rcUtils.logDebug(msg)
  end
end

function rcUtils.logDebug(msg)
  if(enableDebug) then
    sb.logInfo(msg)
  end
end