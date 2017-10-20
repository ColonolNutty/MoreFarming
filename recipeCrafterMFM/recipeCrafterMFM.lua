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
  storage.outputRecipe = nil
  storage.outputPlacedSuccessfully = false
  storage.craftSoundDelaySeconds = config.getParameter("craftSoundDelaySeconds", 10) -- In seconds
  storage.craftSoundIsPlaying = false
  storage.recipeGroup = config.getParameter("recipeGroup")
  storage.noRecipeBookGroup = storage.recipeGroup .. "NoRecipeBook"
  message.setHandler("makeMeal", RecipeCrafterMFMApi.makeMeal)
  message.setHandler("enableDebug", RecipeCrafterMFMApi.enableDebug)
  enableDebug = false
end

function update(dt)
  rcUtils.checkCraftSoundDelay(dt)
end

function die()
end

-------------------------------------------------------------------

function RecipeCrafterMFMApi.enableDebug(id, name, newValue)
  enableDebug = newValue or false
  if(enableDebug) then
    sb.logInfo("Toggled Debug On")
  else
    sb.logInfo("Toggled Debug Off")
  end
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
  if (animator.hasSound("onCraft") and storage.craftSoundIsPlaying) then
    animator.stopAllSounds("onCraft")
    storage.craftSoundIsPlaying = false
  end
end

function RecipeCrafterMFMApi.makeMeal()
  if (isCrafting) then
    return
  end
  isCrafting = true
  rcUtils.logDebug("Make Meal Called")
  if not rcUtils.shouldLookForRecipe() then
    rcUtils.logDebug("No Look")
    return
  end
  local ingredients = rcUtils.getIngredients()
  if ingredients == nil then
    rcUtils.logDebug("No Ingredients")
    return
  end
  local numberOfIngredients = 0
  for slot,item in pairs(ingredients) do
    if slot ~= storage.outputSlot + 1 then
      numberOfIngredients = numberOfIngredients + 1
    end
  end
  if numberOfIngredients == 0 then
    return
  end
  storage.outputRecipe = nil
  storage.outputPlacedSuccessfully = false
  rcUtils.logDebug("Finding Output")
  rcUtils.onCraft()
  local outputRecipe = rcUtils.findOutput(ingredients)
  if outputRecipe then
    rcUtils.updateOutputSlotWith(outputRecipe)
    rcUtils.consumeIngredients()
    rcUtils.logDebug("Updating Output")
  end
  rcUtils.stopCraftSound()
  isCrafting = false
end

-------------------------------------------------------------------

function rcUtils.updateOutputSlotWith(recipe)
  storage.outputRecipe = recipe
  local existingOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if not existingOutput or (existingOutput and existingOutput.name == recipe.output.name) then
    local existingAmount = 0
    if(existingOutput) then
      existingAmount = existingOutput.count
    end
    local expectedNewAmount = recipe.output.count + existingAmount
    local outputItem = {name = recipe.output.name, count = expectedNewAmount}
    world.containerTakeAt(entity.id(), storage.outputSlot)
    rcUtils.logDebug("New output count: " .. outputItem.count)
    rcUtils.logRecipeDebug("Setting output item to: " .. outputItem.name .. " in slot " .. storage.outputSlot)
    local leftoverOutput = world.containerItemApply(entity.id(), outputItem, storage.outputSlot)
    if(leftoverOutput) then
      local toSpawn = {name = leftoverOutput.name, count = 1}
      world.spawnItem(leftoverOutput, object.position(), leftoverOutput.count)
    end
    local newOutput = world.containerItemAt(entity.id(), storage.outputSlot)
    if newOutput == nil then
      storage.outputPlacedSuccessfully = false
    elseif newOutput.name == outputItem.name and newOutput.count == outputItem.count then
      storage.outputPlacedSuccessfully = true
    else
      storage.outputPlacedSuccessfully = false
    end
    if not storage.outputPlacedSuccessfully then
      if newOutput ~= nil then
        rcUtils.logRecipeDebug("Output not successfully placed, item found instead: " .. newOutput.name)
      else
        rcUtils.logRecipeDebug("Output not successfully placed, and no item found at slot " .. storage.outputSlot)
      end
    end
  else
    rcUtils.logRecipeDebug("Could not place output because of existing item with name: " .. existingOutput.name .. " in slot " .. storage.outputSlot)
  end
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
    end
  end
  return recipeFound
end

function rcUtils.findOutput(ingredients)
  local outputRecipe = nil
  for _,itemName in ipairs(storage.possibleOutputs) do
    local recipesForItem = root.recipesForItem(itemName)
    if recipesForItem ~= nil and #recipesForItem > 0 then
      outputRecipe = rcUtils.findRecipe(recipesForItem, ingredients)
      if outputRecipe then
        rcUtils.logRecipeDebug("Found recipe with output name: " .. outputRecipe.output.name)
        break;
      end
    end
  end
  return outputRecipe
end

function rcUtils.checkIngredientsMatchRecipe(recipe, ingredients)
  -- Check the recipe inputs to verify ingredients match with all inputs
  local ingredientsUsed = {}
  local matchesAllInput = true
  for i,input in ipairs(recipe.input) do
    local matchFound = false
    for slot,ingred in pairs(ingredients) do
      if ingred.name ~= recipe.output.name then
        if input.name == ingred.name and input.count <= ingred.count then
          matchFound = true
          table.insert(ingredientsUsed, ingred.name)
          break
        end
      end
    end
    if not matchFound then
      matchesAllInput = false
      break;
    end
  end
  -- All ingredients that exist should be used
  for slot,ingred in pairs(ingredients) do
    if ingred.name ~= recipe.output.name then
      local matches = false
      for _,ingreds in ipairs(ingredientsUsed) do
        if ingred.name == ingreds then
          matches = true
          break
        end
      end
      if not matches then
        matchesAllInput = false
        break;
      end
    end
  end
  return matchesAllInput
end

function rcUtils.checkCraftSoundDelay(dt)
  if not storage.craftSoundIsPlaying then
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

function rcUtils.consumeIngredients()
  if storage.outputRecipe == nil or not storage.outputPlacedSuccessfully then
    return
  end
  rcUtils.logRecipeDebug("Consuming ingredients for recipe with output: " .. storage.outputRecipe.output.name)
  for _,input in ipairs(storage.outputRecipe.input) do
    rcUtils.logDebug("Consuming ingredient with name: " .. input.name)
    world.containerConsume(entity.id(), input)
  end
  rcUtils.onCraft()
  storage.outputRecipe = nil
  storage.outputPlacedSuccessfully = false
  return
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

function rcUtils.removeOutput()
  -- Find existing output
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if not outputSlotItem then
    storage.outputRecipe = nil
    storage.outputPlacedSuccessfully = false
    return
  end
  
  if storage.outputRecipe then
    local outputItem = storage.outputRecipe.output
    -- If the item in the output is the same as the one we placed
    -- then we remove the amount we placed and spit the rest out of the machine
    if outputSlotItem.name == outputItem.name then
      world.containerConsumeAt(entity.id(), storage.outputSlot, outputItem.count)
    end
  end
  -- If output still exists, we ignore it and prevent adding new output
  storage.outputRecipe = nil
  storage.outputPlacedSuccessfully = false
end

function rcUtils.validateCurrentRecipe(recipe, ingredients)
  if recipe == nil or ingredients == nil then
    return false
  end
  return rcUtils.checkIngredientsMatchRecipe(recipe, ingredients)
end

function rcUtils.shouldLookForRecipe()
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if outputSlotItem == nil then
    return true
  end
  if storage.outputRecipe == nil then
    return true
  end
  local outputRecipeOutput = storage.outputRecipe.output
  if outputRecipeOutput.name == outputSlotItem.name and outputRecipeOutput.count == outputSlotItem.count then
    return true
  end
  return false
end


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