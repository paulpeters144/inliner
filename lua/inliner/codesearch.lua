local logger = require("inliner.logger")

local M = {}

local project_root = nil

local SEARCH_KEYWORDS = {
  "find%s+([%w_%.]+)",
  "search%s+for%s+([%w_%.]+)",
  "look%s+up%s+([%w_%.]+)",
  "where%s+is%s+([%w_%.]+)",
  "callers%s+of%s+([%w_%.]+)",
  "usages%s+of%s+([%w_%.]+)",
  "references%s+to%s+([%w_%.]+)",
  "define",
}

local function detect_project_root()
  if project_root then
    return project_root
  end

  local ok = pcall(function()
    local git_result = vim.fn.systemlist("git rev-parse --show-toplevel")
    if git_result and #git_result > 0 and git_result[1] ~= "" then
      project_root = vim.fn.fnamemodify(git_result[1], ":p")
    end
  end)

  if not ok or not project_root then
    project_root = vim.fn.getcwd()
  end

  logger.debug("codesearch", "Detected project root: " .. project_root)
  return project_root
end

function M.ensure_rg()
  if vim.fn.executable("rg") == 1 then
    return true
  end
  return false, "ripgrep (rg) is not installed. Install it from https://github.com/BurntSushi/ripgrep"
end

function M.search_project(pattern, opts)
  opts = opts or {}
  local max_results = opts.max_results or 15
  local max_total_results = opts.max_total_results or 50
  local context_lines = opts.context_lines or 3
  local file_glob = opts.file_glob

  local ok, err = M.ensure_rg()
  if not ok then
    return nil, err
  end

  if not pattern or pattern == "" then
    return nil, "Empty search pattern"
  end

  local root = detect_project_root()
  local args = {
    "rg",
    "--json",
    "-C",
    tostring(context_lines),
    "--max-count",
    tostring(max_results),
  }

  if file_glob then
    table.insert(args, "-g")
    table.insert(args, file_glob)
  end

  table.insert(args, "--")
  table.insert(args, pattern)
  table.insert(args, root)

  logger.debug("codesearch", "Running: rg -C " .. context_lines .. " --max-count " .. max_results .. " " .. pattern)

  local output = vim.fn.systemlist(args)
  local exit_code = vim.v.shell_error

  if exit_code == 2 then
    return nil, "rg exited with error. Check that ripgrep is installed correctly."
  end

  if exit_code == 1 or #output == 0 then
    return {}
  end

  local results = {}
  local current_result = nil

  for _, line in ipairs(output) do
    local ok, data = pcall(vim.json.decode, line)
    if ok and data then
      if data.type == "match" then
        if current_result then
          table.insert(results, current_result)
        end
        local path = data.data.path and data.data.path.text or ""
        current_result = {
          file = vim.fn.fnamemodify(path, ":."),
          line_number = data.data.line_number,
          content = data.data.lines and data.data.lines.text or "",
          context = {},
        }
        if current_result.content then
          current_result.content = vim.trim(current_result.content:gsub("\n$", ""))
        end
      elseif data.type == "context" then
        if current_result then
          local ctx = data.data.lines and data.data.lines.text or ""
          ctx = vim.trim(ctx:gsub("\n$", ""))
          if ctx ~= "" then
            table.insert(current_result.context, ctx)
          end
        end
      end
    end
  end

  if current_result then
    table.insert(results, current_result)
  end

  if #results > max_total_results then
    logger.debug("codesearch", "Truncating " .. #results .. " results to " .. max_total_results)
    results = { table.unpack(results, 1, max_total_results) }
  end

  logger.debug("codesearch", "Found " .. #results .. " results for: " .. pattern)
  return results, nil
end

function M.format_results(results, query)
  if not results or #results == 0 then
    return ""
  end

  local parts = {}
  table.insert(parts, '--- Codebase search results for "' .. query .. '" ---')

  local max_per_file = 5
  local previous_file = nil
  local count_in_file = 0

  for _, r in ipairs(results) do
    local skip = false
    if r.file ~= previous_file then
      previous_file = r.file
      count_in_file = 0
    end

    count_in_file = count_in_file + 1
    if count_in_file > max_per_file then
      if count_in_file == max_per_file + 1 then
        local remaining = #results - count_in_file + 1
        table.insert(parts, "  ... (" .. remaining .. " more results in " .. r.file .. ")")
      end
      skip = true
    end

    if not skip then
      if r.file and not parts[#parts] or parts[#parts] ~= (r.file .. ":") then
        table.insert(parts, "")
        table.insert(parts, r.file .. ":")
      end

      for _, ctx_line in ipairs(r.context or {}) do
        table.insert(parts, "  " .. ctx_line)
      end

      table.insert(parts, "  > " .. r.line_number .. ": " .. r.content)
    end
  end

  table.insert(parts, "--- End search results ---")
  return table.concat(parts, "\n")
end

function M.extract_keywords(code_text, question_text)
  local keywords = {}
  local seen = {}

  local function add_keyword(kw)
    kw = vim.trim(kw)
    if #kw < 2 then
      return
    end
    if seen[kw] then
      return
    end
    seen[kw] = true
    table.insert(keywords, kw)
  end

  if code_text and #code_text > 0 then
    for line in code_text:gmatch("[^\n]+") do
      -- function definitions: local function NAME(  or  function NAME(  or M.NAME = function(
      local func_def = line:match("^%s*local%s+function%s+([%w_]+)%s*%(")
      if func_def then
        add_keyword(func_def)
      end

      func_def = line:match("^%s*function%s+([%w_]+)%s*%(")
      if func_def then
        add_keyword(func_def)
      end

      local m_func_def = line:match("^%s*M%.([%w_]+)%s*=%s*function%s*%(")
      if m_func_def then
        add_keyword(m_func_def)
      end

      local var_func = line:match("^%s*local%s+([%w_]+)%s*=%s*function%s*%(")
      if var_func then
        add_keyword(var_func)
      end

      -- require calls
      local req = line:match("require%(%s*[\"']([%w_%.%-/]+)[\"']%s*%)")
      if req then
        local short = req:match("([%w_]+)$")
        if short then
          add_keyword(short)
        end
      end

      -- called functions: NAME(
      for func_call in line:gmatch("([%w_]+)%s*%(") do
        local skip = {
          ["if"] = true,
          ["for"] = true,
          ["while"] = true,
          ["function"] = true,
          ["when"] = true,
          ["ifnot"] = true,
        }
        if not skip[func_call] then
          add_keyword(func_call)
        end
      end

      -- module-style calls: M.NAME(
      local m_call = line:match("M%.([%w_]+)%s*%(")
      if m_call then
        add_keyword(m_call)
      end
    end
  end

  if question_text and #question_text > 0 then
    -- Extract symbols from the question itself
    for _, sym in ipairs({ question_text:match("`([%w_%.]+)`") }) do
      add_keyword(sym)
    end

    for _, sym in ipairs({ question_text:match("[\"']([%w_%.]+)[\"']") }) do
      add_keyword(sym)
    end

    local caps = { question_text:match("([A-Z][%w_]*)") }
    for _, sym in ipairs(caps) do
      add_keyword(sym)
    end
  end

  return keywords
end

function M.extract_search_query(question)
  for _, pat in ipairs(SEARCH_KEYWORDS) do
    local m = { question:lower():match(pat:lower()) }
    if m and #m > 0 and m[1] and #m[1] > 0 then
      return m[1]
    end
  end

  -- Try to find backticked symbols
  local sym = question:match("`([%w_%.]+)`")
  if sym then
    return sym
  end

  return nil
end

return M
