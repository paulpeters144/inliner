local M = {}

local state = {}

local function wrap_text(text, max_width)
  local lines = {}
  for line in text:gmatch("[^\r\n]+") do
    while #line > max_width do
      local sub = line:sub(1, max_width + 1)
      local space_pos = sub:match("^.*()%s")
      if space_pos then
        lines[#lines + 1] = sub:sub(1, space_pos - 1)
        line = line:sub(space_pos + 1):match("^%s*(.*)$")
      else
        lines[#lines + 1] = line:sub(1, max_width)
        line = line:sub(max_width + 1)
      end
    end
    if #line > 0 then
      lines[#lines + 1] = line
    end
  end
  return lines
end

function M.show(opts, callback, cancel_callback)
  M.close()

  state.callback = callback
  state.cancel_callback = cancel_callback

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

  local prompt = opts.prompt or "Instruction:"
  local width = opts.width or 55
  local inner_width = width - 4
  local prompt_lines = wrap_text(prompt, inner_width)
  local wrapped = {}
  for _, pl in ipairs(prompt_lines) do
    wrapped[#wrapped + 1] = "  " .. pl
  end
  local lines = {
    "",
    unpack(wrapped),
    "",
    "> ",
    "",
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local prompt_line_count = #prompt_lines
  local input_line_idx = prompt_line_count + 3
  local height = prompt_line_count + 4
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local title = " " .. (opts.icon or "") .. "  " .. (opts.title or "") .. " "

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "left",
  })

  vim.api.nvim_win_set_option(win, "winhl", "Normal:NormalFloat,FloatBorder:FloatBorder")
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "linebreak", true)

  vim.api.nvim_buf_set_option(buf, "textwidth", 0)
  vim.api.nvim_buf_set_option(buf, "wrapmargin", 0)

  vim.api.nvim_win_set_cursor(win, { input_line_idx, 3 })
  vim.cmd("startinsert!")

  local function submit()
    local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input_line = content[input_line_idx] or ""
    local text = input_line:match("^>%s?(.*)$") or input_line
    local cb = state.callback
    local cc = state.cancel_callback
    M.close()
    if text and text ~= "" then
      if cb then
        cb(text)
      end
    else
      if cc then
        cc()
      end
    end
  end

  local function cancel()
    local cc = state.cancel_callback
    M.close()
    if cc then
      cc()
    end
  end

  vim.keymap.set("i", "<CR>", submit, { buffer = buf, nowait = true })
  vim.keymap.set("i", "<C-c>", cancel, { buffer = buf, nowait = true })
  vim.keymap.set("n", "q", cancel, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<CR>", submit, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<C-c>", cancel, { buffer = buf, nowait = true })
  vim.keymap.set("i", "<Esc>", function()
    vim.cmd("stopinsert")
  end, { buffer = buf, nowait = true })

  vim.api.nvim_create_autocmd("WinClosed", {
    buffer = buf,
    once = true,
    callback = function()
      pcall(vim.cmd, "stopinsert")
      state.win = nil
      state.buf = nil
    end,
  })

  state.buf = buf
  state.win = win
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.callback = nil
  state.cancel_callback = nil
  pcall(vim.cmd, "stopinsert")
end

return M
