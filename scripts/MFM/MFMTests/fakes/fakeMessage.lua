if(message == nil) then
  message = {};
end

message.setHandler = function(handlerName, func)
  message[handlerName] = func;
end

message.invokeHandler = function(handlerName, paramOne, paramTwo, paramThree)
  local handler = message[handlerName];
  if(handler) then
    return handler(paramOne, paramTwo, paramThree)
  end
  return nil;
end