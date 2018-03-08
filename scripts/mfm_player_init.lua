local origInit = init;

function init()
  origInit();
  sb.logInfo("----- MFM player init -----");
  local metadata = root.assetJson("/_MFMversioning.config")
  if(metadata) then
    sb.logInfo("Running with " .. metadata.friendlyName .. " " .. metadata.version)
  end
end
