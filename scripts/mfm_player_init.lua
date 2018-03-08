local origInit = init;

function init()
  origInit();
  sb.logInfo("----- MFM FU player init -----");
  local metadata = root.assetJson("/_MFMFUversioning.config")
  if(metadata) then
    sb.logInfo("Running with " .. metadata.friendlyName .. " " .. metadata.version)
  end
end