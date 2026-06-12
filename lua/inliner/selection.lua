local logger = require("inliner.logger")

local M = {}

function M.get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_bufnr = start_pos[1]
  local end_bufnr = end_pos[1]
  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]
  local bufnr = start_bufnr ~= 0 and start_bufnr or vim.api.nvim_get_current_buf()

  if start_bufnr ~= 0 and end_bufnr ~= 0 and start_bufnr ~= end_bufnr then
    logger.warn("selection", "Selection marks span different buffers")
    return nil, "Selection marks span different buffers"
  end

  if start_line == 0 or end_line == 0 then
    return nil, "No active visual selection"
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  if #lines == 0 then
    logger.warn("selection", "Empty selection")
    return nil, "Empty selection"
  end

  local mode = vim.fn.visualmode()
  logger.debug("selection", string.format("Visual mode: %s, lines: %d", mode, #lines))

  if mode == "V" then
    -- Visual line mode - don't trim columns
  elseif #lines == 1 then
    -- Character mode, single line
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    -- Character mode, multiple lines
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end

  local result = {
    text = table.concat(lines, "\n"),
    start_line = start_line,
    end_line = end_line,
    start_col = start_col,
    end_col = end_col,
    bufnr = bufnr,
  }

  logger.debug(
    "selection",
    string.format("Extracted selection: %d chars, lines %d-%d", #result.text, start_line, end_line)
  )

  return result
end

function M.get_line_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]

  local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""

  return {
    text = text,
    start_line = line,
    end_line = line,
    start_col = 1,
    end_col = #text + 1,
    bufnr = bufnr,
  }
end

return M
