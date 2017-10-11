RecipeCrafterMFMApi = {};
local rcUtils = {};
local ingredientsChanged = false;
local isExpectingOutputChange = false;
local enableDebug = false;
local enableRecipeGroupDebug = false;

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
  ingredientsChanged = true
end

function update(dt)
  if(not ingredientsChanged) then
    return
  end
  rcUtils.logDebug("Change")
  ingredientsChanged = false
  isExpectingOutputChange = true
  rcUtils.checkCraftSoundDelay(dt)
  rcUtils.consumeIngredientsIfOutputTaken()
  if not rcUtils.shouldLookForRecipe() then
    rcUtils.logDebug("No Look")
    isExpectingOutputChange = false
    return
  end
  local ingredients = rcUtils.getIngredients()
  if ingredients == nil then
    rcUtils.logDebug("No Ingredients")
    isExpectingOutputChange = false
    return
  end
  if not rcUtils.validateCurrentRecipe(storage.outputRecipe, ingredients) then
    rcUtils.logDebug("Removing Output")
    rcUtils.removeOutput()
  end
  local numberOfIngredients = 0
  for slot,item in pairs(ingredients) do
    if slot ~= storage.outputSlot + 1 then
      numberOfIngredients = numberOfIngredients + 1
    end
  end
  if numberOfIngredients > 0 then
    rcUtils.logDebug("Finding Output")
    local outputRecipe = rcUtils.findOutput(ingredients)
    if outputRecipe then
    rcUtils.logDebug("Updating Output")
      rcUtils.updateOutputSlotWith(outputRecipe)
    else
      rcUtils.removeOutput()
    end
  else
    rcUtils.removeOutput()
  end
  isExpectingOutputChange = false
end

function die()
  rcUtils.removeOutput()
end

-------------------------------------------------------------------

function containerCallback()
  if(not isExpectingOutputChange) then
    ingredientsChanged = true
    rcUtils.logDebug("Ingredients changed")
  end
end

-------------------------------------------------------------------

function rcUtils.updateOutputSlotWith(recipe)
  storage.outputRecipe = recipe
  local existingOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if not existingOutput then
    rcUtils.logRecipeDebug("Setting output item to: " .. storage.outputRecipe.output.name .. " in slot " .. storage.outputSlot)
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

function rcUtils.consumeIngredientsIfOutputTaken()
  if storage.outputRecipe == nil or not storage.outputPlacedSuccessfully then
    return
  end
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if outputSlotItem == nil then
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
  local recipeOutput = storage.outputRecipe.output
  if outputSlotItem.name == recipeOutput.name and outputSlotItem.count == recipeOutput.count then
    return
  end
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

function rcUtils.onCraft()
  if animator.hasSound("onCraft") and not storage.craftSoundIsPlaying then
    rcUtils.logDebug("Playing onCraft sounds")
    storage.timePassed = 0
    animator.playSound("onCraft")
    storage.craftSoundIsPlaying = true
  end
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