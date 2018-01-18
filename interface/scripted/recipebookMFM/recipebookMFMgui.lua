local recipeStoreUpdated = false;
local recipeStoreRequest = nil;
local recipeFiltersUpdated = false;
local recipeFiltersRequest = nil;
local selectedFiltersUpdated = false;
local selectedFiltersRequest = nil;

recipeStore = {}
selectedFilters = {}
recipeFilters = {}

function init()
  recipeStoreUpdated = false
  recipeFiltersUpdated = false
  selectedFiltersUpdated = false
end

function update()
  updateRecipeStore()
  updateRecipeFilters()
  updateSelectedFilters()
end

function toggleFilter(valOne, valTwo, valThree)
  sb.logInfo("Did it")
end

function filterByName(val)
  sb.logInfo("Filtering")
end

function btnFilterHaveMaterials(val, valTwo)
  sb.logInfo("Filter has Mats")
end

function updateRecipeStore()
  if(recipeStoreUpdated) then
    return
  end
  if(recipeStoreRequest == nil) then
    recipeStoreRequest = world.sendEntityMessage(pane.sourceEntity(), "getRecipeStore")
  end
  if(not recipeStoreRequest:finished()) then
    return
  end
  if(not recipeStoreRequest:succeeded()) then
    local errorMsg = recipeStoreRequest:error()
    if(errorMsg ~= nil) then
      sb.logError(errorMsg)
    end
    recipeStoreUpdated = true
    return
  end
  local recipeStoreRequestResult = recipeStoreRequest:result()
  if(not recipeStoreRequestResult) then
    recipeStoreUpdated = true
    return
  end
  sb.logInfo("Loaded recipe store")
  recipeStore = recipeStoreRequestResult
  recipeStoreUpdated = true
  recipeStoreRequest = nil
end

function updateRecipeFilters()
  if(recipeFiltersUpdated) then
    return
  end
  if(recipeFiltersRequest == nil) then
    recipeFiltersRequest = world.sendEntityMessage(pane.sourceEntity(), "getRecipeFilters")
  end
  if(not recipeFiltersRequest:finished()) then
    return
  end
  if(not recipeFiltersRequest:succeeded()) then
    local errorMsg = recipeFiltersRequest:error()
    if(errorMsg ~= nil) then
      sb.logError(errorMsg)
    end
    recipeFiltersUpdated = true
    return
  end
  local recipeFiltersRequestResult = recipeFiltersRequest:result()
  if(not recipeFiltersRequestResult) then
    recipeFiltersUpdated = true
    return
  end
  sb.logInfo("Loaded recipe filters")
  recipeFilters = recipeFiltersRequestResult
  recipeFiltersUpdated = true
  recipeFiltersRequest = nil
end

function updateSelectedFilters()
  if(selectedFiltersUpdated) then
    return
  end
  if(selectedFiltersRequest == nil) then
    selectedFiltersRequest = world.sendEntityMessage(pane.sourceEntity(), "getSelectedFilters")
  end
  if(not selectedFiltersRequest:finished()) then
    return
  end
  if(not selectedFiltersRequest:succeeded()) then
    local errorMsg = selectedFiltersRequest:error()
    if(errorMsg ~= nil) then
      sb.logError(errorMsg)
    end
    selectedFiltersUpdated = true
    return
  end
  local selectedFiltersRequestResult = selectedFiltersRequest:result()
  if(not selectedFiltersRequestResult) then
    selectedFiltersUpdated = true
    return
  end
  sb.logInfo("Loaded selected filters")
  selectedFilters = selectedFiltersRequestResult
  selectedFiltersUpdated = true
  selectedFiltersRequest = nil
end