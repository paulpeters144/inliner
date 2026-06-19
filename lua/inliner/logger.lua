local M = {}

M.enabled = false
M.log_file = nil
M.max_content_size = 5000

local levels = {
  DEBUG = "DEBUG",
  INFO = "INFO",
  WARN = "WARN",
  ERROR = "ERROR",
}

function M.init(config)
  M.enabled = config.debug or false
  M.log_file = config.log_file or (vim.fn.stdpath("state") .. "/inliner.log")
  M.max_content_size = config.debug_max_log_size or 5000

  local log_dir = vim.fn.fnamemodify(M.log_file, ":h")
  local dir_success = vim.fn.mkdir(log_dir, "p", "0700")
  if dir_success == 0 then
    vim.notify("Failed to create log directory: " .. log_dir, vim.log.levels.ERROR)
    M.log_file = nil
    M.enabled = false
    return
  end

  if not M.enabled then
    return
  end

  local file_success, err = pcall(function()
    local file = io.open(M.log_file, "a")
    if not file then
      error("Could not open log file: " .. M.log_file)
    end
    local date_prefix = string.format("[%s]", os.date("%Y-%m-%d %H:%M:%S"))
    local debug_msg = "[INFO] [lua:logger] Debug logging initialized"
    local write_msg = string.format("%s %s\n", date_prefix, debug_msg)
    file:write(write_msg)
    file:close()
  end)

  if not file_success then
    local prefix_msg = "[inliner] Failed to initialize log file: "
    local notify_msg = prefix_msg .. M.log_file .. ": " .. tostring(err)
    vim.notify(notify_msg, vim.log.levels.ERROR)
    M.enabled = false
    return
  end

  if vim.fn.has("unix") == 1 then
    vim.fn.setfperm(M.log_file, "rw-------")
  end

  vim.notify(
    "[inliner] Debug logging enabled. Log file: " .. M.log_file .. " (contains full code content)",
    vim.log.levels.WARN
  )
end

local function format_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

local function truncate_content(content)
  if M.max_content_size == 0 or #content <= M.max_content_size then
    return content
  end

  local truncated = string.sub(content, 1, M.max_content_size)
  local remaining = #content - M.max_content_size
  return truncated .. "\n... (truncated, " .. remaining .. " more chars)"
end

local util = require("inliner.util")

local function write_log(level, source, message, content)
  if not M.log_file then
    return
  end

  local file = io.open(M.log_file, "a")
  if not file then
    return
  end

  local timestamp = format_timestamp()
  local msg = util.serialize_message(message)
  local ts_part = string.format("[%s]", timestamp)
  local level_part = string.format("[%s]", level)
  local source_part = string.format("[lua:%s]", source)
  local log_line = ts_part .. " " .. level_part .. " " .. source_part .. " " .. msg

  file:write(log_line .. "\n")

  if content then
    if type(content) ~= "string" then
      content = vim.inspect(content)
    end
    local safe_content = truncate_content(content)
    for line in safe_content:gmatch("[^\n]+") do
      file:write("  " .. line .. "\n")
    end
  end

  file:close()
end

function M.debug(source, message, content)
  if not M.enabled then
    return
  end
  write_log(levels.DEBUG, source, message, content)
end

function M.info(source, message, content)
  if not M.enabled then
    return
  end
  write_log(levels.INFO, source, message, content)
end

function M.warn(source, message, content)
  write_log(levels.WARN, source, message, content)
end

function M.error(source, message, content)
  write_log(levels.ERROR, source, message, content)
end

return M
