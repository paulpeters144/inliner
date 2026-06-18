local question = require("inliner.question")

local function mock(t, k, v)
  t[k] = v
end

local mock_notify_calls = {}
local mock_keymap_calls = {}
local mock_create_buf_calls = {}
local mock_set_option_calls = {}
local mock_open_win_calls = {}
local mock_buf_set_lines_calls = {}
local mock_buf_line_count_return = 1
local mock_win_set_cursor_calls = {}
local mock_buf_is_valid_return = true
local mock_win_is_valid_return = true
local mock_win_close_calls = {}
local mock_create_autocmd_calls = {}

describe("question", function()
  local original_notify
  local original_keymap_set
  local original_nvim_create_buf
  local original_nvim_create_autocmd
  local original_nvim_set_option_value
  local original_nvim_buf_set_option
  local original_nvim_open_win
  local original_nvim_set_current_win
  local original_nvim_buf_set_lines
  local original_nvim_buf_line_count
  local original_nvim_win_set_cursor
  local original_nvim_buf_is_valid
  local original_nvim_win_is_valid
  local original_nvim_win_close

  before_each(function()
    mock_notify_calls = {}
    mock_keymap_calls = {}
    mock_create_buf_calls = {}
    mock_set_option_calls = {}
    mock_open_win_calls = {}
    mock_buf_set_lines_calls = {}
    mock_win_set_cursor_calls = {}
    mock_win_close_calls = {}
    mock_create_autocmd_calls = {}
    mock_buf_line_count_return = 1
    mock_buf_is_valid_return = true
    mock_win_is_valid_return = true

    original_notify = vim.notify
    original_keymap_set = vim.keymap.set
    original_nvim_create_buf = vim.api.nvim_create_buf
    original_nvim_create_autocmd = vim.api.nvim_create_autocmd
    original_nvim_set_option_value = rawget(vim.api, "nvim_set_option_value")
    original_nvim_buf_set_option = rawget(vim.api, "nvim_buf_set_option")
    original_nvim_open_win = vim.api.nvim_open_win
    original_nvim_set_current_win = vim.api.nvim_set_current_win
    original_nvim_buf_set_lines = vim.api.nvim_buf_set_lines
    original_nvim_buf_line_count = vim.api.nvim_buf_line_count
    original_nvim_win_set_cursor = vim.api.nvim_win_set_cursor
    original_nvim_buf_is_valid = vim.api.nvim_buf_is_valid
    original_nvim_win_is_valid = vim.api.nvim_win_is_valid
    original_nvim_win_close = vim.api.nvim_win_close

    mock(vim, "notify", function(msg, level)
      table.insert(mock_notify_calls, { msg = msg, level = level })
    end)
    mock(vim.keymap, "set", function(mode, lhs, rhs, opts)
      table.insert(mock_keymap_calls, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
    end)
    mock(vim.api, "nvim_create_buf", function(listed, scratch)
      table.insert(mock_create_buf_calls, { listed = listed, scratch = scratch })
      return 42
    end)
    mock(vim.api, "nvim_set_option_value", function(name, val, opts)
      if opts and opts.buf then
        table.insert(mock_set_option_calls, { buf = opts.buf, opt = name, val = val })
      end
    end)
    mock(vim.api, "nvim_buf_set_option", function(buf, opt, val)
      table.insert(mock_set_option_calls, { buf = buf, opt = opt, val = val })
    end)
    mock(vim.api, "nvim_open_win", function(buf, enter, config)
      table.insert(mock_open_win_calls, { buf = buf, enter = enter, config = config })
      return 100
    end)
    mock(vim.api, "nvim_set_current_win", function() end)
    mock(vim.api, "nvim_buf_set_lines", function(buf, start, finish, strict, lines)
      table.insert(mock_buf_set_lines_calls, { buf = buf, lines = lines })
    end)
    mock(vim.api, "nvim_buf_line_count", function()
      return mock_buf_line_count_return
    end)
    mock(vim.api, "nvim_win_set_cursor", function(win, pos)
      table.insert(mock_win_set_cursor_calls, { win = win, pos = pos })
    end)
    mock(vim.api, "nvim_buf_is_valid", function()
      return mock_buf_is_valid_return
    end)
    mock(vim.api, "nvim_win_is_valid", function()
      return mock_win_is_valid_return
    end)
    mock(vim.api, "nvim_create_autocmd", function(event, opts)
      table.insert(mock_create_autocmd_calls, { event = event, opts = opts })
    end)
    mock(vim.api, "nvim_win_close", function(win, force)
      table.insert(mock_win_close_calls, { win = win, force = force })
    end)

    package.loaded["inliner.question"] = nil
    package.loaded["inliner.input"] = nil
    package.loaded["inliner.llm"] = nil
    question = require("inliner.question")
  end)

  after_each(function()
    mock(vim, "notify", original_notify)
    mock(vim.keymap, "set", original_keymap_set)
    mock(vim.api, "nvim_create_buf", original_nvim_create_buf)
    mock(vim.api, "nvim_create_autocmd", original_nvim_create_autocmd)
    mock(vim.api, "nvim_set_option_value", original_nvim_set_option_value)
    mock(vim.api, "nvim_buf_set_option", original_nvim_buf_set_option)
    mock(vim.api, "nvim_open_win", original_nvim_open_win)
    mock(vim.api, "nvim_set_current_win", original_nvim_set_current_win)
    mock(vim.api, "nvim_buf_set_lines", original_nvim_buf_set_lines)
    mock(vim.api, "nvim_buf_line_count", original_nvim_buf_line_count)
    mock(vim.api, "nvim_win_set_cursor", original_nvim_win_set_cursor)
    mock(vim.api, "nvim_buf_is_valid", original_nvim_buf_is_valid)
    mock(vim.api, "nvim_win_is_valid", original_nvim_win_is_valid)
    mock(vim.api, "nvim_win_close", original_nvim_win_close)
  end)

  describe("create_window", function()
    it("creates buffer with correct options", function()
      question.create_window()

      assert.are.equal(1, #mock_create_buf_calls)
      assert.is_false(mock_create_buf_calls[1].listed)
      assert.is_true(mock_create_buf_calls[1].scratch)
    end)

    it("creates floating window with correct dimensions", function()
      question.create_window()

      assert.are.equal(1, #mock_open_win_calls)
      assert.are.equal("editor", mock_open_win_calls[1].config.relative)
      assert.are.equal("rounded", mock_open_win_calls[1].config.border)
      assert.is_true(mock_open_win_calls[1].config.title:find("Inliner Question") ~= nil)
    end)

    it("sets keymaps for close and input", function()
      question.create_window()

      local found_q = false
      local found_cr = false
      local found_i = false
      for _, call in ipairs(mock_keymap_calls) do
        if call.lhs == "q" then
          found_q = true
        end
        if call.lhs == "<CR>" then
          found_cr = true
        end
        if call.lhs == "i" then
          found_i = true
        end
      end
      assert(found_q, "q keymap not set")
      assert(found_cr, "<CR> keymap not set")
      assert(found_i, "i keymap not set")
    end)
  end)

  describe("close", function()
    it("closes window and resets state", function()
      question.create_window()
      question.close()

      assert.are.equal(1, #mock_win_close_calls)
    end)

    it("handles already-closed window", function()
      mock_win_is_valid_return = false

      question.create_window()
      question.close()
    end)
  end)

  describe("append", function()
    it("handles nil/invalid buffer", function()
      mock_buf_is_valid_return = false

      question.append("user", "some text")
    end)

    it("sets modifiable before writing", function()
      question.create_window()
      question.append("user", "test content")

      local found_modifiable = false
      for _, call in ipairs(mock_set_option_calls) do
        if call.opt == "modifiable" then
          found_modifiable = true
          break
        end
      end
      assert.is_true(found_modifiable)
    end)

    it("scrolls cursor to end", function()
      question.create_window()
      question.append("user", "test content")

      assert.is_true(#mock_win_set_cursor_calls > 0)
    end)

    it("formats user messages with You header", function()
      question.create_window()
      question.append("user", "hello")

      assert.is_true(#mock_buf_set_lines_calls > 0)
      local has_you = false
      for _, lc in ipairs(mock_buf_set_lines_calls) do
        for _, line in ipairs(lc.lines) do
          if line:find(" You ") then
            has_you = true
          end
        end
      end
      assert.is_true(has_you)
    end)

    it("formats assistant messages with Assistant header", function()
      question.create_window()
      question.append("assistant", "response")

      local has_assistant = false
      for _, lc in ipairs(mock_buf_set_lines_calls) do
        for _, line in ipairs(lc.lines) do
          if line:find(" Assistant ") then
            has_assistant = true
          end
        end
      end
      assert.is_true(has_assistant)
    end)
  end)

  describe("send_request", function()
    it("inserts user message into state", function()
      local request_chat_calls = {}
      local mock_llm = {
        request_chat = function(params, callback)
          table.insert(request_chat_calls, params)
          vim.schedule(function()
            callback("assistant response", nil)
          end)
        end,
      }
      package.loaded["inliner.llm"] = mock_llm
      package.loaded["inliner.question"] = nil
      question = require("inliner.question")

      package.loaded["inliner"] = {
        config = {
          llm = {
            provider = "openai",
            model = "gpt-4",
            base_url = nil,
            max_output_tokens = 4096,
            timeout = 30000,
          },
        },
      }

      question.create_window()
      question.send_request("test question")

      vim.wait(50)

      assert.are.equal(1, #request_chat_calls)
    end)

    it("handles error from llm", function()
      local mock_llm = {
        request_chat = function(params, callback)
          vim.schedule(function()
            callback(nil, "API error")
          end)
        end,
      }
      package.loaded["inliner.llm"] = mock_llm
      package.loaded["inliner.question"] = nil
      question = require("inliner.question")

      package.loaded["inliner"] = {
        config = {
          llm = {
            provider = "openai",
            model = "gpt-4",
            base_url = nil,
            max_output_tokens = 4096,
            timeout = 30000,
          },
        },
      }

      local append_calls = {}
      mock(question, "append", function(role, content)
        table.insert(append_calls, { role = role, content = content })
      end)

      question.create_window()
      question.send_request("test")

      vim.wait(50)

      local found_error = false
      for _, call in ipairs(append_calls) do
        if call.role == "system" and call.content:find("Error") then
          found_error = true
          break
        end
      end
      assert.is_true(found_error)
    end)

    it("handles buf being destroyed mid-request", function()
      local mock_llm = {
        request_chat = function(params, callback)
          vim.schedule(function()
            callback("response", nil)
          end)
        end,
      }
      package.loaded["inliner.llm"] = mock_llm
      package.loaded["inliner.question"] = nil
      question = require("inliner.question")

      package.loaded["inliner"] = {
        config = {
          llm = {
            provider = "openai",
            model = "gpt-4",
          },
        },
      }

      mock_buf_is_valid_return = false

      question.create_window()
      question.send_request("test")

      vim.wait(50)
    end)
  end)

  describe("prompt_input", function()
    it("returns early when buffer is invalid", function()
      mock_buf_is_valid_return = false

      question.prompt_input()
    end)
  end)
end)
