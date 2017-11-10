require "/scripts/debugUtilsCN.lua"

RecipeCrafterMFMApi = {};
local rcUtils = {};
local isCrafting = false;
local debugMsgPrefix = "[RCAPI]"

function RecipeCrafterMFMApi.init()
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
  if(not storage.previousRecipeName) then
    storage.previousRecipeName = nil
  end
  storage.previousRecipeName = nil
  storage.heldIngredients = {}
  storage.craftSoundDelaySeconds = config.getParameter("craftSoundDelaySeconds", 10) -- In seconds
  storage.craftSoundIsPlaying = false
  storage.recipeGroup = config.getParameter("recipeGroup")
  storage.noRecipeBookGroup = storage.recipeGroup .. "NoRecipeBook"
  storage.isRefridgerated = config.getParameter("itemAgeMultiplier", 5) == 0
  if(storage.enableRecipeGroupDebug == nil) then
    storage.enableRecipeGroupDebug = false
  end
  message.setHandler("craft", RecipeCrafterMFMApi.startCrafting)
end

function RecipeCrafterMFMApi.update(dt)
  rcUtils.checkCraftSoundDelay(dt)
end

function RecipeCrafterMFMApi.die()
  isCrafting = false
  rcUtils.releaseIngredients()
end

function RecipeCrafterMFMApi.startCrafting()
  DebugUtilsCN.logDebug("startCrafting Called")
  if(isCrafting) then
    DebugUtilsCN.logDebug("Already crafting, ignoring request")
    return
  end
  DebugUtilsCN.logDebug("Starting to Craft")
  isCrafting = true
  if not rcUtils.shouldLookForRecipe() then
    DebugUtilsCN.logDebug("No Look")
    isCrafting = false
    return
  end
  local ingredients = rcUtils.getIngredients()
  if ingredients == nil or rcUtils.hasNoIngredients(ingredients) then
    DebugUtilsCN.logDebug("No Ingredients")
    isCrafting = false
    return
  end
  storage.previousRecipeName = nil
  DebugUtilsCN.logDebug("Finding Output")
  rcUtils.onCraft()
  local outputRecipe = rcUtils.findOutput(ingredients)
  if outputRecipe then
    DebugUtilsCN.logDebug("Updating Output")
    rcUtils.craftWithRecipe(outputRecipe)
  else
    DebugUtilsCN.logDebug("No output found")
  end
  rcUtils.releaseIngredients()
  isCrafting = false
end

function rcUtils.craftWithRecipe(recipe)
  local outputName = recipe.output.name
  storage.previousRecipeName = outputName
  rcUtils.holdIngredients(recipe)
  local existingOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if existingOutput and (existingOutput.name ~= outputName) then
    DebugUtilsCN.logDebug("Could not place output '" .. outputName .. "' because of existing item found with name: '" .. existingOutput.name .. "' in slot " .. storage.outputSlot)
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
    DebugUtilsCN.logDebug("Output not successfully placed, item found instead: " .. newOutput.name)
  else
    DebugUtilsCN.logDebug("Output not successfully placed, and no item found at slot " .. storage.outputSlot)
  end
  
  rcUtils.releaseIngredients()
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
    if rcUtils.recipeCanBeCrafted(recipe) and rcUtils.checkIngredientsMatchRecipe(recipe, ingredients) then
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

function rcUtils.checkIngredientsMatchRecipe(recipe, ingredients)
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

function rcUtils.holdIngredients(outputRecipe)
  rcUtils.releaseIngredients()
  storage.heldIngredients = {}
  DebugUtilsCN.logDebug("Holding ingredients")
  local containerId = entity.id()
  for _,input in ipairs(outputRecipe.input) do
    DebugUtilsCN.logDebug("Holding ingredient with name: " .. input.name .. " and count: " .. input.count)
    if(world.containerConsume(containerId, input)) then
      table.insert(storage.heldIngredients, input)
    end
  end
end

function rcUtils.releaseIngredients()
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

function rcUtils.consumeIngredients()
  if(storage.heldIngredients == nil) then
    return false
  end
  DebugUtilsCN.logDebug("Consuming ingredients")
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
    DebugUtilsCN.logDebug("Playing onCraft sounds")
    storage.timePassed = 0
    animator.playSound("onCraft")
    storage.craftSoundIsPlaying = true
  end
end

function rcUtils.stopCraftSound()
  DebugUtilsCN.logDebug("Stopping onCraft Sound")
  if (animator.hasSound("onCraft") and storage.craftSoundIsPlaying) then
    animator.stopAllSounds("onCraft")
    storage.craftSoundIsPlaying = false
  end
end