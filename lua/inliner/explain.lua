local question = require("inliner.question")
local selection = require("inliner.selection")

local M = {}

local EXPLAIN_PROMPT = [[You are a concise programming assistant. Explain the following code clearly, covering what it does, its inputs/outputs, and any notable patterns or techniques used. Use markdown for code examples.]]

function M.explain()
  local sel = selection.get_visual_selection()
  if not sel then
    sel = selection.get_line_selection()
  end
  if not sel or not sel.text or sel.text == "" then
    vim.notify("[inliner] No code selected or on current line", vim.log.levels.WARN)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(sel.bufnr)
  if filepath and filepath ~= "" then
    filepath = vim.fn.fnamemodify(filepath, ":.")
  end

  local context = "Explain the following code"
  if filepath and filepath ~= "" then
    context = context .. " from " .. filepath
  end
  context = context .. ":\n\n```\n" .. sel.text .. "\n```"

  local messages = {
    { role = "system", content = EXPLAIN_PROMPT },
    { role = "system", content = context },
  }

  question.open_with_messages({ input = { prompt = "Ask about the explanation: " } }, messages, "Explain this code")
end

return M
