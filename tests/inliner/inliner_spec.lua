local llm = require("inliner.llm")
local selection = require("inliner.selection")
local input = require("inliner.input")
local replace = require("inliner.replace")
local diff = require("inliner.diff")
local spinner = require("inliner.spinner")
local logger = require("inliner.logger")

local inliner

describe("inliner", function()
  local original_notify
  local original_ui_select
  local original_keymap_set
  local notify_calls = {}
  local ui_select_calls = {}

  local function reset_saved_mocks()
    original_notify = nil
    original_ui_select = nil
    original_keymap_set = nil
  end

  before_each(function()
    reset_saved_mocks()

    notify_calls = {}
    ui_select_calls = {}

    original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    original_ui_select = vim.ui.select
    vim.ui.select = function(items, opts, callback)
      table.insert(ui_select_calls, { items = items, opts = opts, callback = callback })
    end

    package.loaded["inliner"] = nil
    inliner = require("inliner")
  end)

  after_each(function()
    if original_notify then
      vim.notify = original_notify
    end
    if original_ui_select then
      vim.ui.select = original_ui_select
    end
    if original_keymap_set then
      vim.keymap.set = original_keymap_set
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
        assert.is_true(ok, "expected " .. provider .. " to be valid, got error: " .. tostring(err))
      end
    end)

    it("merges user config with defaults", function()
      inliner.setup({ debug = true })
      assert.is_true(inliner.config.debug)
      assert.equals(30000, inliner.config.llm.timeout)
    end)

    it("uses default openai provider when none specified", function()
      inliner.setup({})
      assert.equals("openai", inliner.config.llm.provider)
    end)

    it("sets provider and model from config", function()
      inliner.setup({ llm = { provider = "anthropic", model = "claude-3-5-sonnet-20241022" } })
      assert.equals("anthropic", inliner.config.llm.provider)
      assert.equals("claude-3-5-sonnet-20241022", inliner.config.llm.model)
    end)

    it("registers keybindings from config", function()
      original_keymap_set = vim.keymap.set
      local keymap_calls = {}
      vim.keymap.set = function(_, lhs, _, _)
        table.insert(keymap_calls, { lhs = lhs })
      end

      inliner.setup({})

      assert.is_true(#keymap_calls > 0)
      local found = false
      for _, call in ipairs(keymap_calls) do
        if call.lhs == "<leader>ae" then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("does not register select model keybinding", function()
      original_keymap_set = vim.keymap.set
      local keymap_calls = {}
      vim.keymap.set = function(_, lhs, _, _)
        table.insert(keymap_calls, { lhs = lhs })
      end

      inliner.setup({})

      vim.keymap.set = original_keymap_set

      local found = false
      for _, call in ipairs(keymap_calls) do
        if call.lhs == "<leader>am" then
          found = true
          break
        end
      end
      assert.is_false(found)
    end)

    it("skips keybinding registration when keys list is empty", function()
      original_keymap_set = vim.keymap.set
      local keymap_calls = {}
      vim.keymap.set = function(_, lhs, _, _)
        table.insert(keymap_calls, { lhs = lhs })
      end

      inliner.config.keys = {}
      inliner.setup({})

      vim.keymap.set = original_keymap_set
      assert.equals(0, #keymap_calls)
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
      local original_get_visual = selection.get_visual_selection
      selection.get_visual_selection = function()
        return {
          text = "hello world",
          bufnr = 0,
          start_line = 1,
          end_line = 1,
          start_col = 1,
          end_col = 12,
        }
      end

      local original_input = input.get_instruction
      input.get_instruction = function() end

      inliner.edit()

      input.get_instruction = original_input
      selection.get_visual_selection = original_get_visual

      assert.is_true(#notify_calls > 0)
      assert.is_true(notify_calls[1].msg:find("setup") ~= nil)
    end)

    it("aborts when selection buffer is invalid", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_delete(bufnr, { force = true })

      local original_get_visual = selection.get_visual_selection
      selection.get_visual_selection = function()
        return {
          text = "test",
          bufnr = bufnr,
          start_line = 1,
          end_line = 1,
          start_col = 1,
          end_col = 5,
        }
      end

      local original_logger_warn = logger.warn
      local warn_called = false
      logger.warn = function(source, msg)
        if source == "edit" and msg:find("closed") then
          warn_called = true
        end
      end

      inliner.edit()

      selection.get_visual_selection = original_get_visual
      logger.warn = original_logger_warn

      assert.is_true(warn_called)
    end)

    it("calls replace.replace_selection when diff_mode is false", function()
      inliner.setup({ diff_mode = false })

      local original_get_visual = selection.get_visual_selection
      selection.get_visual_selection = function()
        return {
          text = "hello world",
          bufnr = 0,
          start_line = 1,
          end_line = 1,
          start_col = 1,
          end_col = 12,
        }
      end

      local original_input = input.get_instruction
      input.get_instruction = function(_, cb)
        cb("replace with goodbye")
      end

      local original_request_edit = llm.request_edit
      local edit_callback_called = false
      llm.request_edit = function(_, cb)
        edit_callback_called = true
        cb("goodbye world", nil)
      end

      local original_spinner_start = spinner.start
      local original_spinner_stop = spinner.stop
      spinner.start = function() end
      spinner.stop = function() end

      local replace_called = false
      local original_replace = replace.replace_selection
      replace.replace_selection = function(_, result)
        replace_called = true
        assert.equals("goodbye world", result)
      end

      inliner.edit()

      vim.wait(100, function()
        return replace_called
      end)

      replace.replace_selection = original_replace
      spinner.start = original_spinner_start
      spinner.stop = original_spinner_stop
      llm.request_edit = original_request_edit
      input.get_instruction = original_input
      selection.get_visual_selection = original_get_visual

      assert.is_true(edit_callback_called)
      assert.is_true(replace_called)
    end)

    it("calls diff.inject_conflict_markers when diff_mode is true", function()
      inliner.setup({ diff_mode = true })

      local original_get_visual = selection.get_visual_selection
      selection.get_visual_selection = function()
        return {
          text = "hello world",
          bufnr = 0,
          start_line = 1,
          end_line = 1,
          start_col = 1,
          end_col = 12,
        }
      end

      local original_input = input.get_instruction
      input.get_instruction = function(_, cb)
        cb("modify code")
      end

      local original_request_edit = llm.request_edit
      local edit_callback_called = false
      llm.request_edit = function(_, cb)
        edit_callback_called = true
        cb("modified code", nil)
      end

      local original_spinner_start = spinner.start
      local original_spinner_stop = spinner.stop
      spinner.start = function() end
      spinner.stop = function() end

      local inject_called = false
      local original_inject = diff.inject_conflict_markers
      diff.inject_conflict_markers = function(_, result)
        inject_called = true
        assert.equals("modified code", result)
      end

      inliner.edit()

      vim.wait(100, function()
        return inject_called
      end)

      diff.inject_conflict_markers = original_inject
      spinner.start = original_spinner_start
      spinner.stop = original_spinner_stop
      llm.request_edit = original_request_edit
      input.get_instruction = original_input
      selection.get_visual_selection = original_get_visual

      assert.is_true(edit_callback_called)
      assert.is_true(inject_called)
    end)

    it("aborts when selection extmarks are lost", function()
      inliner.setup({ diff_mode = false })

      local original_get_visual = selection.get_visual_selection
      selection.get_visual_selection = function()
        return {
          text = "hello",
          bufnr = 0,
          start_line = 1,
          end_line = 1,
          start_col = 1,
          end_col = 6,
        }
      end

      local original_input = input.get_instruction
      input.get_instruction = function(_, cb)
        cb("test")
      end

      local original_request_edit = llm.request_edit
      llm.request_edit = function(_, cb)
        cb("replacement", nil)
      end

      local original_spinner_start = spinner.start
      local original_spinner_stop = spinner.stop
      spinner.start = function() end
      spinner.stop = function() end

      local original_get_extmark = vim.api.nvim_buf_get_extmark_by_id
      vim.api.nvim_buf_get_extmark_by_id = function()
        return {}
      end

      local original_del_extmark = vim.api.nvim_buf_del_extmark
      vim.api.nvim_buf_del_extmark = function() end

      local warn_called = false
      local original_logger_warn = logger.warn
      logger.warn = function(source, msg)
        if source == "edit" and msg:find("extmarks") then
          warn_called = true
        end
      end

      inliner.edit()

      vim.wait(100, function()
        return warn_called
      end)

      logger.warn = original_logger_warn
      vim.api.nvim_buf_del_extmark = original_del_extmark
      vim.api.nvim_buf_get_extmark_by_id = original_get_extmark
      spinner.start = original_spinner_start
      spinner.stop = original_spinner_stop
      llm.request_edit = original_request_edit
      input.get_instruction = original_input
      selection.get_visual_selection = original_get_visual

      assert.is_true(warn_called)
    end)
  end)

  describe("question", function()
    it("warns when setup not called", function()
      local question = require("inliner.question")
      local original_open = question.open
      question.open = function() end

      inliner.question()

      question.open = original_open

      assert.is_true(#notify_calls > 0)
      assert.is_true(notify_calls[1].msg:find("setup") ~= nil)
    end)
  end)
end)
