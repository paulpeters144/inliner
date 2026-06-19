local logger = require("inliner.logger")

local M = {}

function M.get_visual_selection(range)
  local start_line, end_line
  local bufnr = vim.api.nvim_get_current_buf()

  if range then
    start_line = range.start
    end_line = range["end"]
  else
    local mode = vim.fn.mode()
    if mode:match("^[vV\22]") then
      vim.cmd('normal! \27') -- Esc to write marks
    end
    
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    start_line = start_pos[2]
    end_line = end_pos[2]
  end

  if start_line == 0 or end_line == 0 then
    return nil, "No active visual selection"
  end

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  if #lines == 0 then
    logger.warn("selection", "Empty selection")
    return nil, "Empty selection"
  end

  local last_line_len = string.len(lines[#lines] or "")

  local result = {
    text = table.concat(lines, "\n"),
    start_line = start_line,
    end_line = end_line,
    start_col = 1,
    end_col = last_line_len + 1,
    bufnr = bufnr,
  }

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
