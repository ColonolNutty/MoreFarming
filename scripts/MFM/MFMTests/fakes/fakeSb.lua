if(sb == nil) then
  sb = {};
end

sb.logInfo = function(msg)
  if(sb.messages == nil) then
    sb.messages = {};
  end
  table.insert(sb.messages, msg);
end

sb.getMessages = function()
  return sb.messages;
end

sb.clearMessages = function()
  sb.messages = {};
end