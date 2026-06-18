local question = require("inliner.question")
local selection = require("inliner.selection")
local codesearch = require("inliner.codesearch")

local M = {}

local EXPLAIN_PROMPT =
  [[You are a concise programming assistant. Explain the following code clearly, covering what it does, its inputs/outputs, and any notable patterns or techniques used. Use markdown for code examples.]]

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

  local ok, inliner = pcall(require, "inliner")
  local codesearch_config = {}
  if ok and inliner then
    codesearch_config = (inliner.config or {}).codesearch or {}
  end
  if codesearch_config.enabled ~= false then
    local max_keywords = codesearch_config.max_keywords or 5
    local keywords = codesearch.extract_keywords(sel.text, "")
    if #keywords > max_keywords then
      keywords = { table.unpack(keywords, 1, max_keywords) }
    end
    for _, kw in ipairs(keywords) do
      local results, err = codesearch.search_project(kw, {
        max_results = codesearch_config.max_results or 15,
        max_total_results = codesearch_config.max_total_results or 50,
        context_lines = codesearch_config.context_lines or 3,
      })
      if results and #results > 0 then
        local formatted = codesearch.format_results(results, kw)
        table.insert(messages, { role = "system", content = formatted })
      end
    end
  end

  question.open_with_messages({ input = { prompt = "Ask about the explanation: " } }, messages, "Explain this code")
end

return M
