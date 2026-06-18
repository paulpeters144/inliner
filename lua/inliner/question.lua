local llm = require("inliner.llm")
local input = require("inliner.input")
local logger = require("inliner.logger")
local spinner = require("inliner.spinner")
local selection = require("inliner.selection")

local M = {}

local state = {
  win = nil,
  buf = nil,
  messages = {},
  config = nil,
  width = nil,
}

local SYSTEM_PROMPT =
  [[You are a concise programming assistant integrated into Neovim. Answer questions about the user's code with examples when relevant. Use markdown for code blocks.]]

local function get_win_config()
  local max_width = state.config and state.config.max_width
  local width = math.floor(vim.o.columns * 0.8)
  if max_width then
    width = math.min(width, max_width)
  end
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  return {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Inliner Question ",
    title_pos = "center",
  }
end

function M.create_window()
  local config = get_win_config()
  local width = config.width
  local height = config.height

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].modifiable = true

  state.width = width

  state.win = vim.api.nvim_open_win(state.buf, true, config)

  vim.bo[state.buf].filetype = "markdown"

  vim.api.nvim_create_autocmd("VimResized", {
    buffer = state.buf,
    callback = function()
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_set_config(state.win, get_win_config())
      end
    end,
  })

  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = state.buf, desc = "Close question" })
  vim.keymap.set("n", "<CR>", function()
    M.prompt_input()
  end, { buffer = state.buf, desc = "Ask question" })
  vim.keymap.set("n", "i", function()
    M.prompt_input()
  end, { buffer = state.buf, desc = "Ask question" })

  vim.api.nvim_set_current_win(state.win)
end

function M.send_request(text, skip_prompt)
  table.insert(state.messages, { role = "user", content = text })
  M.append("user", text)

  local ok, inliner = pcall(require, "inliner")
  if not ok then
    M.append("system", "Error: could not load inliner module. Make sure require('inliner').setup({}) was called.")
    M.prompt_input()
    return
  end

  local current_config = inliner.config
  if not current_config.llm or not current_config.llm.provider then
    M.append("system", "Error: no provider configured. Set llm.provider in setup().")
    M.prompt_input()
    return
  end

  spinner.start("Thinking...")

  llm.request_chat({
    messages = state.messages,
    provider = current_config.llm.provider,
    model = current_config.llm.model,
    baseURL = current_config.llm.base_url,
    maxOutputTokens = current_config.llm.max_output_tokens or 4096,
    timeout = current_config.llm.timeout,
  }, function(result, err)
    vim.schedule(function()
      spinner.stop()

      if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        return
      end

      if err then
        M.append("system", "Error: " .. err)
      else
        table.insert(state.messages, { role = "assistant", content = result })
        M.append("assistant", result)
      end

      if not skip_prompt then
        M.prompt_input()
      end
    end)
  end)
end

function M.open(cfg)
  local config = cfg or {}
  state.config = config
  state.messages = {
    { role = "system", content = config.system_prompt or SYSTEM_PROMPT },
  }

  local sel = selection.get_visual_selection()
  if not sel then
    sel = selection.get_line_selection()
  end
  if sel then
    local filepath = vim.api.nvim_buf_get_name(sel.bufnr)
    if filepath and filepath ~= "" then
      filepath = vim.fn.fnamemodify(filepath, ":.")
    end
    local context = "The user has the following code selected"
    if filepath and filepath ~= "" then
      context = context .. " in " .. filepath
    end
    context = context .. ":\n\n```\n" .. sel.text .. "\n```"
    table.insert(state.messages, { role = "system", content = context })
  end

  local input_config = {
    input = {
      prompt = (config.input and config.input.prompt) or "Question: ",
      icon = "󰭻",
      win = {
        title_pos = "left",
        relative = "cursor",
        row = -3,
        col = 0,
      },
    },
  }

  input.get_instruction(input_config, function(text)
    if not text or text == "" then
      state.messages = {}
      return
    end

    M.create_window()
    M.send_request(text)
  end, function() end)
end

function M.open_with_messages(cfg, msgs, initial_text)
  state.config = cfg or {}
  state.messages = msgs or {}

  M.create_window()
  M.send_request(initial_text or "", true)
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.messages = {}
  state.config = nil
end

function M.append(role, content)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = vim.split(content, "\n")

  local content_width = state.width and (state.width - 2) or 70
  local label = (role == "user" and " You ") or (role == "assistant" and " Assistant ") or " System "
  local label_width = vim.fn.strwidth(label)
  local pad_total = math.max(0, content_width - label_width)
  local pad_left = math.floor(pad_total / 2)
  local pad_right = pad_total - pad_left
  local header = string.rep("─", pad_left) .. label .. string.rep("─", pad_right)

  local append_lines = { "", header, "" }
  vim.list_extend(append_lines, lines)
  table.insert(append_lines, "")

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, -1, -1, false, append_lines)
  vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
end

function M.prompt_input()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) or not state.config then
    return
  end

  local input_config = {
    input = {
      prompt = (state.config.input and state.config.input.prompt) or "Question: ",
      icon = "󰭻",
      win = {
        title_pos = "left",
        relative = "cursor",
        row = -3,
        col = 0,
      },
    },
  }

  input.get_instruction(input_config, function(text)
    if not text or text == "" then
      return
    end

    M.send_request(text)
  end, function() end)
end

return M
