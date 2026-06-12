local popup = require("inliner.popup")

local M = {}

function M.get_instruction(config, callback, cancel_callback)
  local icon = (config.input and config.input.icon) or "󱚣"
  local prompt = (config.input and config.input.prompt) or "AI Edit: "
  local title = prompt:gsub(":?%s*$", "")

  popup.show({
    icon = icon,
    title = title,
    prompt = prompt,
  }, function(text)
    if text and text ~= "" then
      callback(text)
    elseif cancel_callback then
      cancel_callback()
    end
  end, function()
    if cancel_callback then
      cancel_callback()
    end
  end)
end

return M
