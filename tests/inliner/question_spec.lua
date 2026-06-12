local question = require("inliner.question")

describe("question", function()
  local original_notify
  local original_keymap_set
  local original_nvim_create_buf
  local original_nvim_open_win
  local original_nvim_buf_set_option
  local original_nvim_buf_set_lines
  local original_nvim_buf_line_count
  local original_nvim_win_set_cursor
  local original_nvim_set_current_win
  local original_nvim_buf_is_valid
  local original_nvim_win_is_valid
  local original_nvim_win_close

  local notify_calls = {}
  local keymap_calls = {}

  before_each(function()
    notify_calls = {}
    keymap_calls = {}

    original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end

    original_keymap_set = vim.keymap.set
    vim.keymap.set = function(mode, lhs, rhs, opts)
      table.insert(keymap_calls, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
    end

    original_nvim_create_buf = vim.api.nvim_create_buf
    vim.api.nvim_create_buf = function(listed, scratch)
      return 42
    end

    original_nvim_buf_set_option = vim.api.nvim_buf_set_option
    vim.api.nvim_buf_set_option = function() end

    original_nvim_open_win = vim.api.nvim_open_win
    vim.api.nvim_open_win = function(buf, enter, config)
      return 100
    end

    original_nvim_set_current_win = vim.api.nvim_set_current_win
    vim.api.nvim_set_current_win = function() end

    original_nvim_buf_set_lines = vim.api.nvim_buf_set_lines
    vim.api.nvim_buf_set_lines = function() end

    original_nvim_buf_line_count = vim.api.nvim_buf_line_count
    vim.api.nvim_buf_line_count = function()
      return 1
    end

    original_nvim_win_set_cursor = vim.api.nvim_win_set_cursor
    vim.api.nvim_win_set_cursor = function() end

    original_nvim_buf_is_valid = vim.api.nvim_buf_is_valid
    vim.api.nvim_buf_is_valid = function()
      return true
    end

    original_nvim_win_is_valid = vim.api.nvim_win_is_valid
    vim.api.nvim_win_is_valid = function()
      return true
    end

    original_nvim_win_close = vim.api.nvim_win_close
    vim.api.nvim_win_close = function() end

    -- Reset module state between tests
    package.loaded["inliner.question"] = nil
    package.loaded["inliner.input"] = nil
    package.loaded["inliner.llm"] = nil
    question = require("inliner.question")
  end)

  after_each(function()
    vim.notify = original_notify
    vim.keymap.set = original_keymap_set
    vim.api.nvim_create_buf = original_nvim_create_buf
    vim.api.nvim_buf_set_option = original_nvim_buf_set_option
    vim.api.nvim_open_win = original_nvim_open_win
    vim.api.nvim_set_current_win = original_nvim_set_current_win
    vim.api.nvim_buf_set_lines = original_nvim_buf_set_lines
    vim.api.nvim_buf_line_count = original_nvim_buf_line_count
    vim.api.nvim_win_set_cursor = original_nvim_win_set_cursor
    vim.api.nvim_buf_is_valid = original_nvim_buf_is_valid
    vim.api.nvim_win_is_valid = original_nvim_win_is_valid
    vim.api.nvim_win_close = original_nvim_win_close
  end)

  describe("create_window", function()
    it("creates buffer with correct options", function()
      local create_buf_calls = {}
      vim.api.nvim_create_buf = function(listed, scratch)
        table.insert(create_buf_calls, { listed = listed, scratch = scratch })
        return 42
      end

      local set_option_calls = {}
      vim.api.nvim_buf_set_option = function(buf, opt, val)
        table.insert(set_option_calls, { buf = buf, opt = opt, val = val })
      end

      local open_win_calls = {}
      vim.api.nvim_open_win = function(buf, enter, config)
        table.insert(open_win_calls, { buf = buf, enter = enter, config = config })
        return 100
      end

      question.create_window()

      assert.equals(1, #create_buf_calls)
      assert.is_false(create_buf_calls[1].listed)
      assert.is_true(create_buf_calls[1].scratch)
    end)

    it("creates floating window with correct dimensions", function()
      local open_win_calls = {}
      vim.api.nvim_open_win = function(buf, enter, config)
        table.insert(open_win_calls, { buf = buf, enter = enter, config = config })
        return 100
      end

      question.create_window()

      assert.equals(1, #open_win_calls)
      assert.equals("editor", open_win_calls[1].config.relative)
      assert.equals("rounded", open_win_calls[1].config.border)
      assert.is_true(open_win_calls[1].config.title:find("Inliner Question") ~= nil)
    end)

    it("sets keymaps for close and input", function()
      question.create_window()

      local found_q = false
      local found_cr = false
      local found_i = false
      for _, call in ipairs(keymap_calls) do
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
      assert.is_true(found_q, "q keymap not set")
      assert.is_true(found_cr, "<CR> keymap not set")
      assert.is_true(found_i, "i keymap not set")
    end)
  end)

  describe("close", function()
    it("closes window and resets state", function()
      local close_calls = {}
      vim.api.nvim_win_close = function(win, force)
        table.insert(close_calls, { win = win, force = force })
      end

      question.create_window()
      question.close()

      assert.equals(1, #close_calls)
    end)

    it("handles already-closed window", function()
      vim.api.nvim_win_is_valid = function()
        return false
      end

      question.create_window()
      question.close()

      -- Should not error
    end)
  end)

  describe("append", function()
    it("handles nil/invalid buffer", function()
      vim.api.nvim_buf_is_valid = function()
        return false
      end

      question.append("user", "some text")
      -- Should not error
    end)

    it("sets modifiable before writing", function()
      local modifiable_calls = {}
      vim.api.nvim_buf_set_option = function(buf, opt, val)
        if opt == "modifiable" then
          table.insert(modifiable_calls, { buf = buf, val = val })
        end
      end

      question.create_window()
      question.append("user", "test content")

      assert.is_true(#modifiable_calls > 0)
    end)

    it("scrolls cursor to end", function()
      local cursor_calls = {}
      vim.api.nvim_win_set_cursor = function(win, pos)
        table.insert(cursor_calls, { win = win, pos = pos })
      end

      question.create_window()
      question.append("user", "test content")

      assert.is_true(#cursor_calls > 0)
    end)

    it("formats user messages with You header", function()
      local lines_calls = {}
      vim.api.nvim_buf_set_lines = function(buf, start, finish, strict, lines)
        table.insert(lines_calls, { buf = buf, lines = lines })
      end

      question.create_window()
      question.append("user", "hello")

      assert.is_true(#lines_calls > 0)
      local has_you = false
      for _, lc in ipairs(lines_calls) do
        for _, line in ipairs(lc.lines) do
          if line:find(" You ") then
            has_you = true
          end
        end
      end
      assert.is_true(has_you)
    end)

    it("formats assistant messages with Assistant header", function()
      local lines_calls = {}
      vim.api.nvim_buf_set_lines = function(buf, start, finish, strict, lines)
        table.insert(lines_calls, { buf = buf, lines = lines })
      end

      question.create_window()
      question.append("assistant", "response")

      local has_assistant = false
      for _, lc in ipairs(lines_calls) do
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

      assert.equals(1, #request_chat_calls)
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
      local original_append = question.append
      question.append = function(role, content)
        table.insert(append_calls, { role = role, content = content })
      end

      question.create_window()
      question.send_request("test")

      vim.wait(50)

      question.append = original_append

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

      vim.api.nvim_buf_is_valid = function()
        return false
      end

      question.create_window()
      question.send_request("test")

      vim.wait(50)
      -- Should not error
    end)
  end)

  describe("prompt_input", function()
    it("returns early when buffer is invalid", function()
      vim.api.nvim_buf_is_valid = function()
        return false
      end

      question.prompt_input()
      -- Should not error
    end)
  end)
end)
