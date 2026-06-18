local llm = require("inliner.llm")
local selection = require("inliner.selection")
local input = require("inliner.input")
local replace = require("inliner.replace")
local diff = require("inliner.diff")
local spinner = require("inliner.spinner")
local logger = require("inliner.logger")

local function mock(t, k, v)
  t[k] = v
end

local inliner

local mock_notify_calls = {}
local mock_ui_select_calls = {}
local mock_keymap_calls = {}
local mock_warn_calls = {}
local mock_selection
local mock_instruction_cb
local mock_llm_edit_cb
local mock_replace_called = false
local mock_inject_called = false
local mock_question_open_called = false

describe("inliner", function()
  local original_notify
  local original_ui_select
  local original_keymap_set

  before_each(function()
    original_notify = vim.notify
    original_ui_select = vim.ui.select
    original_keymap_set = vim.keymap.set

    mock_notify_calls = {}
    mock_ui_select_calls = {}
    mock_keymap_calls = {}
    mock_warn_calls = {}
    mock_selection = nil
    mock_instruction_cb = function(cb)
      cb("default instruction")
    end
    mock_llm_edit_cb = function(cb)
      cb("default", nil)
    end
    mock_replace_called = false
    mock_inject_called = false
    mock_question_open_called = false

    mock(vim, "notify", function(msg, level)
      table.insert(mock_notify_calls, { msg = msg, level = level })
    end)
    mock(vim.ui, "select", function(items, opts, callback)
      table.insert(mock_ui_select_calls, { items = items, opts = opts, callback = callback })
    end)
    mock(vim.keymap, "set", function(_, lhs, _, _)
      table.insert(mock_keymap_calls, { lhs = lhs })
    end)

    mock(selection, "get_visual_selection", function()
      return mock_selection
    end)
    mock(input, "get_instruction", function(_, cb)
      if mock_instruction_cb then
        mock_instruction_cb(cb)
      end
    end)
    mock(llm, "request_edit", function(_, cb)
      if mock_llm_edit_cb then
        mock_llm_edit_cb(cb)
      end
    end)
    mock(spinner, "start", function() end)
    mock(spinner, "stop", function() end)
    mock(replace, "replace_selection", function(_, _)
      mock_replace_called = true
    end)
    mock(diff, "inject_conflict_markers", function(_, _)
      mock_inject_called = true
    end)
    mock(logger, "warn", function(source, msg)
      table.insert(mock_warn_calls, { source = source, msg = msg })
    end)

    local q = require("inliner.question")
    mock(q, "open", function()
      mock_question_open_called = true
    end)

    package.loaded["inliner"] = nil
    inliner = require("inliner")
  end)

  after_each(function()
    if original_notify then
      mock(vim, "notify", original_notify)
    end
    if original_ui_select then
      mock(vim.ui, "select", original_ui_select)
    end
    if original_keymap_set then
      mock(vim.keymap, "set", original_keymap_set)
    end
  end)

  describe("setup", function()
    it("errors when llm.timeout is negative", function()
      local ok, err = pcall(inliner.setup, { llm = { timeout = -1 } })
      assert.is_false(ok)
      assert.is_true(err:find("positive") ~= nil)
    end)

    it("errors when llm.timeout is zero", function()
      local ok, err = pcall(inliner.setup, { llm = { timeout = 0 } })
      assert.is_false(ok)
      assert.is_true(err:find("positive") ~= nil)
    end)

    it("errors when llm.models is used", function()
      local ok, err = pcall(inliner.setup, { llm = { models = { { provider = "openai" } } } })
      assert.is_false(ok)
      assert.is_true(err:find("no longer supported") ~= nil)
    end)

    it("errors on invalid provider", function()
      local ok, err = pcall(inliner.setup, { llm = { provider = "invalid" } })
      assert.is_false(ok)
      assert.is_true(err:find("must be one of") ~= nil)
    end)

    it("accepts valid providers", function()
      local providers = { "openai", "anthropic", "xai", "openrouter", "cerebras", "gemini", "copilot" }
      for _, provider in ipairs(providers) do
        package.loaded["inliner"] = nil
        inliner = require("inliner")
        local ok, err = pcall(inliner.setup, { llm = { provider = provider } })
        assert(ok, "expected " .. provider .. " to be valid, got error: " .. tostring(err))
      end
    end)

    it("merges user config with defaults", function()
      inliner.setup({ debug = true })
      assert.is_true(inliner.config.debug)
      assert.are.equal(30000, inliner.config.llm.timeout)
    end)

    it("uses default openai provider when none specified", function()
      inliner.setup({})
      assert.are.equal("openai", inliner.config.llm.provider)
    end)

    it("sets provider and model from config", function()
      inliner.setup({ llm = { provider = "anthropic", model = "claude-3-5-sonnet-20241022" } })
      assert.are.equal("anthropic", inliner.config.llm.provider)
      assert.are.equal("claude-3-5-sonnet-20241022", inliner.config.llm.model)
    end)

    it("registers keybindings from config", function()
      inliner.setup({})

      assert.is_true(#mock_keymap_calls > 0)
      local found = false
      for _, call in ipairs(mock_keymap_calls) do
        if call.lhs == "<leader>ae" then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("does not register select model keybinding", function()
      inliner.setup({})

      local found = false
      for _, call in ipairs(mock_keymap_calls) do
        if call.lhs == "<leader>am" then
          found = true
          break
        end
      end
      assert.is_false(found)
    end)

    it("skips keybinding registration when keys list is empty", function()
      inliner.config.keys = {}
      inliner.setup({})

      assert.are.equal(0, #mock_keymap_calls)
    end)
  end)

  describe("edit", function()
    before_each(function()
      vim.opt.swapfile = false
      vim.cmd("enew!")
      vim.wait(20)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
    end)

    it("warns when setup not called", function()
      mock_selection = {
        text = "hello world",
        bufnr = 0,
        start_line = 1,
        end_line = 1,
        start_col = 1,
        end_col = 12,
      }
      mock_instruction_cb = nil

      inliner.edit()

      assert.is_true(#mock_notify_calls > 0)
      assert.is_true(mock_notify_calls[1].msg:find("setup") ~= nil)
    end)

    it("aborts when selection buffer is invalid", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_delete(bufnr, { force = true })

      mock_selection = {
        text = "test",
        bufnr = bufnr,
        start_line = 1,
        end_line = 1,
        start_col = 1,
        end_col = 5,
      }
      mock_instruction_cb = function(cb)
        cb("instruction")
      end

      inliner.edit()

      local found_warn = false
      for _, w in ipairs(mock_warn_calls) do
        if w.source == "edit" and w.msg:find("closed") then
          found_warn = true
          break
        end
      end
      assert.is_true(found_warn)
    end)

    it("calls replace.replace_selection when diff_mode is false", function()
      inliner.setup({ diff_mode = false })

      mock_selection = {
        text = "hello world",
        bufnr = 0,
        start_line = 1,
        end_line = 1,
        start_col = 1,
        end_col = 12,
      }
      mock_instruction_cb = function(cb)
        cb("replace with goodbye")
      end
      mock_llm_edit_cb = function(cb)
        cb("goodbye world", nil)
      end

      inliner.edit()

      vim.wait(100, function()
        return mock_replace_called
      end)

      assert.is_true(mock_replace_called)
    end)

    it("calls diff.inject_conflict_markers when diff_mode is true", function()
      inliner.setup({ diff_mode = true })

      mock_selection = {
        text = "hello world",
        bufnr = 0,
        start_line = 1,
        end_line = 1,
        start_col = 1,
        end_col = 12,
      }
      mock_instruction_cb = function(cb)
        cb("modify code")
      end
      mock_llm_edit_cb = function(cb)
        cb("modified code", nil)
      end

      inliner.edit()

      vim.wait(100, function()
        return mock_inject_called
      end)

      assert.is_true(mock_inject_called)
    end)

    it("aborts when selection extmarks are lost", function()
      inliner.setup({ diff_mode = false })

      mock_selection = {
        text = "hello",
        bufnr = 0,
        start_line = 1,
        end_line = 1,
        start_col = 1,
        end_col = 6,
      }
      mock_instruction_cb = function(cb)
        cb("test")
      end
      mock_llm_edit_cb = function(cb)
        cb("replacement", nil)
      end

      local original_get_extmark = vim.api.nvim_buf_get_extmark_by_id
      local original_del_extmark = vim.api.nvim_buf_del_extmark
      mock(vim.api, "nvim_buf_get_extmark_by_id", function()
        return {}
      end)
      mock(vim.api, "nvim_buf_del_extmark", function() end)

      inliner.edit()

      vim.wait(100, function()
        for _, w in ipairs(mock_warn_calls) do
          if w.source == "edit" and w.msg:find("extmarks") then
            return true
          end
        end
        return false
      end)

      mock(vim.api, "nvim_buf_get_extmark_by_id", original_get_extmark)
      mock(vim.api, "nvim_buf_del_extmark", original_del_extmark)

      local found_warn = false
      for _, w in ipairs(mock_warn_calls) do
        if w.source == "edit" and w.msg:find("extmarks") then
          found_warn = true
          break
        end
      end
      assert.is_true(found_warn)
    end)
  end)

  describe("question", function()
    it("warns when setup not called", function()
      inliner.question()

      assert.is_true(#mock_notify_calls > 0)
      assert.is_true(mock_notify_calls[1].msg:find("setup") ~= nil)
    end)
  end)
end)
