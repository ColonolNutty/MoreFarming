local recipeBookVisible = false

function init()
  recipeBookVisible = false
  RBMFMGui.init(pane.containerEntityId())
end

function craft()
  sb.logInfo("Initializing Recipe Crafter GUI");
  world.sendEntityMessage(pane.containerEntityId(), "craft")
end

function toggleRecipeBook()
  sb.logInfo("Toggling Recipe Book")
  recipeBookVisible = not recipeBookVisible
  widget.setVisible("recipeBookFrame", recipeBookVisible)
  widget.setVisible("recipeBookFrame.background", recipeBookVisible)
end