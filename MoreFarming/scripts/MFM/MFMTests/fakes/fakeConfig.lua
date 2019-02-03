if(config == nil) then
  config = {};
end

config.getParameter = function(paramName, defaultVal)
  local paramValue = config[paramName];
  if(paramValue == nil) then
    paramValue = defaultVal;
  end
  return paramValue;
end

-- Used for tests, this function doesn't exist for Starbound
config.setParameter = function(paramName, value)
  config[paramName] = value;
end

config.setParameters = function(parameters)
  for paramName, value in pairs(parameters) do
    config.setParameter(paramName, value);
  end
end