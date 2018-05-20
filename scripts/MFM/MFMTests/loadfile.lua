local function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end
local filePath = ...;
local loadedFile = loadfile('../../..' .. filePath)
if(loadedFile ~= nil and loadedFile ~= false) then
  return loadedFile()
else
  loadedFile = loadfile('.' .. filePath)
  if(loadedFile ~= nil and loadedFile ~= false) then
    return loadedFile()
  end
end