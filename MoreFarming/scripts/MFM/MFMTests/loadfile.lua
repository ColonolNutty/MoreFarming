local function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end
local filePath = ...;
local pathsToTry = {};
table.insert(pathsToTry, '.');
table.insert(pathsToTry, '..');
table.insert(pathsToTry, '../..');
table.insert(pathsToTry, '../../..');
table.insert(pathsToTry, '../../../..');
table.insert(pathsToTry, '../../../../..');
table.insert(pathsToTry, '../../../../../..');
local loadedFile;
for idx,path in ipairs(pathsToTry) do
  loadedFile = loadfile(path .. filePath);
  if(loadedFile ~= nil and loadedFile ~= false) then
    break;
  end
end
if(loadedFile ~= nil and loadedFile ~= false) then
return loadedFile();
end
return nil;