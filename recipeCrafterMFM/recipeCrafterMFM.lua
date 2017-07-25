local recipeCrafterMFMApi = {};
local enableDebug = false;
local enableRecipeGroupDebug = false;

function recipeCrafterMFMApi.updateOutputSlotWith(recipe)
  storage.outputRecipe = recipe
  local existingOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if not existingOutput then
    if enableRecipeGroupDebug then
      sb.logInfo("Setting output item to: " .. storage.outputRecipe.output.name .. " in slot " .. storage.outputSlot)
    end
    world.containerPutItemsAt(entity.id(), storage.outputRecipe.output, storage.outputSlot)
    local newOutput = world.containerItemAt(entity.id(), storage.outputSlot)
    if newOutput == nil then
      storage.outputPlacedSuccessfully = false
    elseif newOutput.name == storage.outputRecipe.output.name then
      storage.outputPlacedSuccessfully = true
    else
      storage.outputPlacedSuccessfully = false
    end
    if not storage.outputPlacedSuccessfully then
      if enableRecipeGroupDebug then
        if newOutput ~= nil then
          sb.logInfo("Output not successfully placed, item found instead: " .. newOutput.name)
        else
          sb.logInfo("Output not successfully placed, and no item found at slot " .. storage.outputSlot)
        end
      end
    end
  else    
    if enableRecipeGroupDebug then
      sb.logInfo("Could not place output because of existing item with name: " .. existingOutput.name .. " in slot " .. storage.outputSlot)
    end
  end
end

function recipeCrafterMFMApi.recipeCanBeCrafted(recipe)
  if storage.recipeGroup == nil then
    if enableRecipeGroupDebug then
      sb.logInfo("No Recipe Group specified")
    end
    return false
  end
  if enableRecipeGroupDebug then
    sb.logInfo("Recipe group specified: " .. storage.recipeGroup)
  end
  local canBeCrafted = false
  for _,group in ipairs(recipe.groups) do
    if group == storage.recipeGroup then
      canBeCrafted = true
      break
    end
  end
  return canBeCrafted
end

function recipeCrafterMFMApi.findRecipe(recipesForItem, ingredients)
  local recipeFound = nil
  for _,recipe in ipairs(recipesForItem) do
    if recipeCrafterMFMApi.recipeCanBeCrafted(recipe) and recipeCrafterMFMApi.checkIngredientsMatchRecipe(recipe, ingredients) then
      recipeFound = recipe
      break;
    end
  end
  return recipeFound
end

function recipeCrafterMFMApi.findOutput(ingredients)
  local outputRecipe = nil
  for _,itemName in ipairs(storage.possibleOutputs) do
    local recipesForItem = root.recipesForItem(itemName)
    if recipesForItem ~= nil and #recipesForItem > 0 then
      outputRecipe = recipeCrafterMFMApi.findRecipe(recipesForItem, ingredients)
      if outputRecipe then
        if enableRecipeGroupDebug then
          sb.logInfo("Found recipe with output name: " .. outputRecipe.output.name)
        end
        break;
      end
    end
  end
  return outputRecipe
end

function recipeCrafterMFMApi.checkIngredientsMatchRecipe(recipe, ingredients)
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

function init(virtual)
  local outputConfigPath = config.getParameter("outputConfig")
  if outputConfigPath == nil then
    storage.possibleOutputs = {}
  else
    storage.possibleOutputs = root.assetJson(outputConfigPath).possibleOutput
  end
  storage.slotCount = config.getParameter("slotCount", 16)
  storage.outputSlot = config.getParameter("outputSlot", 15)
  if enableDebug then
    sb.logInfo("Setting output slot to: " .. storage.outputSlot)
  end
  if storage.outputSlot < 0 then
    storage.outputSlot = 0
  end
  storage.timePassed = 0
  storage.outputRecipe = nil
  storage.outputPlacedSuccessfully = false
  storage.craftSoundDelaySeconds = config.getParameter("craftSoundDelaySeconds", 10) -- In seconds
  storage.craftSoundIsPlaying = false
  storage.recipeGroup = config.getParameter("recipeGroup")
end

function recipeCrafterMFMApi.checkCraftSoundDelay(dt)
  if not storage.craftSoundIsPlaying then
    return
  end
  storage.timePassed = storage.timePassed + dt
  if enableDebug then
    sb.logInfo("Craft sound playing, time passed: " .. storage.timePassed)
  end
  if storage.timePassed <= 0 then
    return
  end
  if storage.timePassed >= storage.craftSoundDelaySeconds then
    if enableDebug then
      sb.logInfo("Stopping all onCraft sounds")
    end
    storage.timePassed = 0
    storage.craftSoundIsPlaying = false
    animator.stopAllSounds("onCraft")
  end
end

function update(dt)
  recipeCrafterMFMApi.checkCraftSoundDelay(dt)
  recipeCrafterMFMApi.consumeIngredientsIfOutputTaken()
  if not recipeCrafterMFMApi.shouldLookForRecipe() then
    return
  end
  local ingredients = recipeCrafterMFMApi.getIngredients()
  if ingredients == nil then
    return
  end
  if not recipeCrafterMFMApi.validateCurrentRecipe(storage.outputRecipe, ingredients) then
    recipeCrafterMFMApi.removeOutput()
  end
  local numberOfIngredients = 0
  for slot,item in pairs(ingredients) do
    if slot ~= storage.outputSlot + 1 then
      numberOfIngredients = numberOfIngredients + 1
    end
  end
  if numberOfIngredients > 0 then
    local outputRecipe = recipeCrafterMFMApi.findOutput(ingredients)
    if outputRecipe then
      recipeCrafterMFMApi.updateOutputSlotWith(outputRecipe)
    else
      recipeCrafterMFMApi.removeOutput()
    end
  else
    recipeCrafterMFMApi.removeOutput()
  end
end

function recipeCrafterMFMApi.consumeIngredientsIfOutputTaken()
  if storage.outputRecipe == nil or not storage.outputPlacedSuccessfully then
    return
  end
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if outputSlotItem == nil then
    if enableRecipeGroupDebug then
      sb.logInfo("Consuming ingredients for recipe with output: " .. storage.outputRecipe.output.name)
    end
    for _,input in ipairs(storage.outputRecipe.input) do
      if enableDebug then
        sb.logInfo("Consuming ingredient with name: " .. input.name)
      end
      world.containerConsume(entity.id(), input)
    end
    recipeCrafterMFMApi.onCraft()
    storage.outputRecipe = nil
    storage.outputPlacedSuccessfully = false
    return
  end
  local recipeOutput = storage.outputRecipe.output
  if outputSlotItem.name == recipeOutput.name and outputSlotItem.count == recipeOutput.count then
    return
  end
end

function recipeCrafterMFMApi.getIngredients()
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

function recipeCrafterMFMApi.removeOutput()
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

function recipeCrafterMFMApi.validateCurrentRecipe(recipe, ingredients)
  if recipe == nil or ingredients == nil then
    return false
  end
  return recipeCrafterMFMApi.checkIngredientsMatchRecipe(recipe, ingredients)
end

function recipeCrafterMFMApi.shouldLookForRecipe()
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

function recipeCrafterMFMApi.onCraft()
  if animator.hasSound("onCraft") and not storage.craftSoundIsPlaying then
    if enableDebug then
      sb.logInfo("Playing onCraft sounds")
    end
    storage.timePassed = 0
    animator.playSound("onCraft")
    storage.craftSoundIsPlaying = true
  end
end

function die()
  recipeCrafterMFMApi.removeOutput()
end