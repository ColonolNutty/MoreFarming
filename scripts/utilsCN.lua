UtilsCN = {}

function UtilsCN.resizeImageToIconSize(imageName, imageDirectory)
  return UtilsCN.rescale(UtilsCN.canonicalise(imageName, imageDirectory), 16, 16)
end

function UtilsCN.canonicalise(file, directory)
	if string.sub(file, 1, 1) == '/' then return file end
	return directory .. file
end

function UtilsCN.rescale(image, x, y)
	local size = root.imageSize(image)
	if size[1] <= x and size[2] <= y then return image end
	return image .. '?scalebilinear=' .. math.min(x / size[1], y / size[2])
end

function UtilsCN.sortByValueNameId(pairTable)
  return UtilsCN.sortByValue(pairTable, function(a, b)
		if a.name < b.name then return true end
		if a.name > b.name then return false end
		return a.id < b.id;
	end)
end

function UtilsCN.sortByValue(pairTable, sortFunc)
  if(pairTable == nil) then
    return true
  end
  
  local arr = {};
  for name,val in pairs(pairTable) do
    table.insert(arr, val)
  end
  table.sort(arr, sortFunc)
  return arr
end

function UtilsCN.isEmpty(pairTable)
  if(pairTable == nil) then
    return true
  end
  local empty = true;
  for one,two in pairs(pairTable) do
    if(two ~= nil) then
      empty = false
      break;
    end
  end
  return empty
end