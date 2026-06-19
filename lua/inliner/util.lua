local M = {}

local function pretty_print_json(json_str)
  local result = {}
  local indent = 0
  local in_string = false
  local escape = false

  for i = 1, #json_str do
    local char = json_str:sub(i, i)

    if in_string then
      if escape then
        escape = false
      elseif char == "\\" then
        escape = true
      elseif char == '"' then
        in_string = false
      end
      table.insert(result, char)
    else
      if char == '"' then
        in_string = true
        table.insert(result, char)
      elseif char == "{" or char == "[" then
        indent = indent + 1
        local next = json_str:sub(i + 1, i + 1)
        if next ~= "}" and next ~= "]" then
          table.insert(result, char .. "\n" .. string.rep("  ", indent))
        else
          table.insert(result, char)
        end
      elseif char == "}" or char == "]" then
        indent = indent - 1
        table.insert(result, "\n" .. string.rep("  ", indent) .. char)
      elseif char == "," then
        local next = json_str:sub(i + 1, i + 1)
        if next ~= "}" and next ~= "]" then
          table.insert(result, ",\n" .. string.rep("  ", indent))
        else
          table.insert(result, ",")
        end
      elseif char == ":" then
        table.insert(result, ": ")
      elseif char == " " then
      else
        table.insert(result, char)
      end
    end
  end

  return table.concat(result)
end

function M.build_file_context(opts)
  if not opts or (#opts.before_lines == 0 and #opts.after_lines == 0) then
    return nil
  end

  local parts = {}
  parts[#parts + 1] = ("<file_context total_lines=\"%d\">"):format(opts.total_lines)

  for i, line in ipairs(opts.before_lines) do
    parts[#parts + 1] = ("Line %d: %s"):format(opts.before_start + i - 1, line)
  end

  parts[#parts + 1] = "<selection>"
  for i, line in ipairs(opts.sel_lines) do
    parts[#parts + 1] = ("Line %d: %s"):format(opts.sel_start + i - 1, line)
  end
  parts[#parts + 1] = "</selection>"

  for i, line in ipairs(opts.after_lines) do
    parts[#parts + 1] = ("Line %d: %s"):format(opts.after_start + i - 1, line)
  end

  parts[#parts + 1] = "</file_context>"
  return table.concat(parts, "\n")
end

function M.serialize_message(msg)
  if type(msg) == "table" then
    local ok, json = pcall(vim.fn.json_encode, msg)
    if ok then
      return pretty_print_json(json)
    end
  end
  return tostring(msg)
end

return M
