local cookingMFMApi = {};

function cookingMFMApi.updateOutputSlotWith(recipe)
  storage.outputRecipe = recipe
  local existingOutput = world.containerItemAt(entity.id(), storage.outputSlot)
  if not existingOutput then
    world.containerPutItemsAt(entity.id(), storage.outputRecipe.output, storage.outputSlot)
  end
end

function cookingMFMApi.recipeCanBeCrafted(recipe)
  if storage.recipeGroup == nil then
    return true
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

function cookingMFMApi.findRecipe(recipesForItem, ingredients)
  local recipeFound = nil
  for _,recipe in ipairs(recipesForItem) do
    if cookingMFMApi.recipeCanBeCrafted(recipe) and cookingMFMApi.checkIngredientsMatchRecipe(recipe, ingredients) then
      recipeFound = recipe
      break;
    end
  end
  return recipeFound
end

function cookingMFMApi.findOutput(ingredients)
  local outputRecipe = nil
  for _,itemName in ipairs(storage.possibleOutputs) do
    local recipesForItem = root.recipesForItem(itemName)
    if recipesForItem ~= nil and #recipesForItem > 0 then
      outputRecipe = cookingMFMApi.findRecipe(recipesForItem, ingredients)
      if outputRecipe then
        break;
      end
    end
  end
  return outputRecipe
end

function cookingMFMApi.checkIngredientsMatchRecipe(recipe, ingredients)
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
  storage.outputSlot = config.getParameter("outputSlot", 1) - 1
  if storage.outputSlot < 0 then
    storage.outputSlot = 0
  end
  storage.outputRecipe = nil
  storage.recipeGroup = config.getParameter("recipeGroup")
end

function update(dt)
  cookingMFMApi.consumeIngredientsIfOutputTaken()
  if not cookingMFMApi.shouldLookForRecipe() then
    return
  end
  local ingredients = cookingMFMApi.getIngredients()
  if ingredients == nil then
    return
  end
  if not cookingMFMApi.validateCurrentRecipe(storage.outputRecipe, ingredients) then
    cookingMFMApi.removeOutput()
  end
  local numberOfIngredients = 0
  for slot,item in pairs(ingredients) do
    if slot ~= 1 then
      numberOfIngredients = numberOfIngredients + 1
    end
  end
  if numberOfIngredients > 0 then
    local outputRecipe = cookingMFMApi.findOutput(ingredients)
    if outputRecipe then
      cookingMFMApi.updateOutputSlotWith(outputRecipe)
    else
      cookingMFMApi.removeOutput()
    end
  else
    cookingMFMApi.removeOutput()
  end
end

function cookingMFMApi.consumeIngredientsIfOutputTaken()
  if storage.outputRecipe == nil then
    return
  end
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if outputSlotItem == nil then
    for _,input in ipairs(storage.outputRecipe.input) do
      world.containerConsume(entity.id(), input)
    end
    storage.outputRecipe = nil
    return
  end
  local recipeOutput = storage.outputRecipe.output
  if outputSlotItem.name == recipeOutput.name and outputSlotItem.count == recipeOutput.count then
    return
  end
end

function cookingMFMApi.getIngredients()
  return world.containerItems(entity.id())
end

function cookingMFMApi.removeOutput()
  -- Find existing output
  local outputSlotItem = world.containerItemAt(entity.id(), storage.outputSlot)
  if not outputSlotItem then
    storage.outputRecipe = nil
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
end

function cookingMFMApi.validateCurrentRecipe(recipe, ingredients)
  if recipe == nil or ingredients == nil then
    return false
  end
  return cookingMFMApi.checkIngredientsMatchRecipe(recipe, ingredients)
end

function cookingMFMApi.shouldLookForRecipe()
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

function die()
  cookingMFMApi.removeOutput()
end