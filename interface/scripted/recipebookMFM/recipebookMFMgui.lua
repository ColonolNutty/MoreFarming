local recipeListNeedsUpdate = true
local requests = {}
local enableDebug = true

ingredientStore = nil
selectedFilters = nil
recipeFilters = nil
recipeFilterStore = nil

RECIPE_LIST_NAME = "recipeList.itemList"
RECIPE_LIST_EMPTY = "recipeList.empty"
INGREDIENTS_LIST_NAME = "ingredientList.ingredientItemList"
INGREDIENTS_LIST_EMPTY = "ingredientList.ingredientRecipeList.empty"

function init()
end

function update()
  if(ingredientStore == nil or recipeFilterStore == nil or recipeFilters == nil or selectedFilters == nil) then
    local ingredientStoreResult = updateStore("getIngredientStore", {})
    if(ingredientStoreResult ~= nil) then
      ingredientStore = ingredientStoreResult
    end
    local filterStoreResult = updateStore("getRecipeFilterStore", {})
    if(filterStoreResult ~= nil) then
      recipeFilterStore = filterStoreResult
    end
    local recipeFiltersResult = updateStore("getRecipeFilters", {})
    if(recipeFiltersResult ~= nil) then
      recipeFilters = recipeFiltersResult
    end
    local selectedFiltersResult = updateStore("getSelectedFilters", {})
    if(selectedFiltersResult ~= nil) then
      selectedFilters = selectedFiltersResult
      updateSelectedFilters()
    end
    recipeListNeedsUpdate = true
    return
  end
  if(recipeListNeedsUpdate) then
    updateRecipeList()
    recipeListNeedsUpdate = false
  end
  world.sendEntityMessage(pane.sourceEntity(), "setSelectedFilters", selectedFilters)
end

function updateSelectedFilters()
  for name,isSelected in pairs(selectedFilters) do
    widget.setChecked(name .. "chkbox", isSelected)
  end
end

function updateRecipeList()
  widget.clearListItems(RECIPE_LIST_NAME)
  widget.setVisible(RECIPE_LIST_EMPTY, false)
  
  local hasRecipes = false
  local includedRecipes = {}
  logInfo("Updating recipe list")
  for filterName, isSelected in pairs(selectedFilters) do
    logInfo("Using filter: " .. filterName)
    if(isSelected and recipeFilterStore[filterName] ~= nil) then
      logInfo("Is selected and found")
      for recipeName, recipeItem in pairs(recipeFilterStore[filterName]) do
        logInfo("Looking at recipe: " .. recipeName)
        if(includedRecipes[recipeName] == nil) then
          local item = ingredientStore[recipeName]
          if(item ~= nil) then
            logInfo("Loading recipe with name: " .. recipeName)
            includedRecipes[recipeName] = true
            local path = string.format("%s.%s", RECIPE_LIST_NAME, widget.addListItem(RECIPE_LIST_NAME))
            widget.setText(path .. ".itemName", item.name .. " " .. formatMethods(item.methods))
            widget.setImage(path .. ".itemIcon", item.icon)
            widget.setData(path, { id = item.id, recipes = item.recipes})
            widget.setVisible(path .. ".itemName", true)
            widget.setVisible(path .. ".itemIcon", true)
            hasRecipes = true
          end
        else
          logInfo("Skipping dupe ingred: " .. recipeName)
            hasRecipes = true
        end
      end
    end
  end
  
  widget.setVisible(RECIPE_LIST_EMPTY, not hasRecipes)
end

function formatMethods(methods)
  if(methods == nil) then
    return ""
  end
  local formatted = ""
  for idx, method in ipairs(methods) do
    formatted = formatted .. "(" .. method .. ")"
  end
  return formatted
end

function updateIngredientList()
  widget.clearListItems(INGREDIENTS_LIST_NAME)
  widget.setVisible(INGREDIENTS_LIST_EMPTY, false)
  
  local hasIngredients = false
  
  widget.setVisible(INGREDIENTS_LIST_EMPTY, not hasIngredients)
end

function toggleFilter(id, data)
  local newValue = widget.getChecked(id)
  if(newValue) then
    logInfo("New value is true")
  end
  selectedFilters[data.filterName] = newValue
  updateRecipeList()
end

function filterByName(val)
  logInfo("Filtering")
end

function btnFilterHaveMaterials(val, valTwo)
  logInfo("Filter has Mats")
end

function updateStore(requestName, defaultValue)
  local updatedName = requestName .. "Updated"
  if(requests[updatedName] ~= nil and not requests[updatedName]) then
    return nil
  end
  local request = requests[requestName]
  if(request == nil) then
    requests[requestName] = world.sendEntityMessage(pane.sourceEntity(), requestName)
    request = requests[requestName]
  end
  if(not request:finished()) then
    return nil
  end
  if(not request:succeeded()) then
    local errorMsg = request:error()
    if(errorMsg ~= nil) then
      sb.logError(errorMsg)
    end
    requests[updatedName] = true
    return defaultValue
  end
  local result = request:result()
  if(not result) then
    requests[updatedName] = true
    return defaultValue
  end
  logInfo("Loaded store: " .. requestName)
  requests[updatedName] = true
  requests[requestName] = nil
  return result
end

function logInfo(msg)
  if(enableDebug) then
    sb.logInfo(msg)
  end
end

function uninit()
end