local selection = require("inliner.selection")

local function mock(t, k, v)
  t[k] = v
end

describe("selection", function()
  before_each(function()
    vim.cmd("enew!")
  end)

  describe("get_visual_selection", function()
    it("should return error when not in visual mode", function()
      local result, err = selection.get_visual_selection()
      assert.is_nil(result)
      assert.are.equal("No active visual selection", err)
    end)

    it("should capture single line selection", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
      vim.cmd("normal! gg0vee")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert(result)
      assert.are.equal("hello world", result.text)
      assert.are.equal(1, result.start_line)
      assert.are.equal(1, result.end_line)
    end)

    it("should capture multi-line selection", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1", "line 2", "line 3" })
      vim.cmd("normal! ggVjj")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert(result)
      assert.are.equal("line 1\nline 2\nline 3", result.text)
      assert.are.equal(1, result.start_line)
      assert.are.equal(3, result.end_line)
    end)

    it("should capture partial line character selection", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world foo bar" })
      vim.cmd("normal! gg6lv3l")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert(result)
      assert.are.equal("worl", result.text)
      assert.are.equal(1, result.start_line)
      assert.are.equal(1, result.end_line)
    end)

    it("should capture character selection across multiple lines", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first line", "second line", "third line" })
      vim.cmd("normal! gg$vjj0")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert(result)
      assert.is_true(#result.text > 0)
      assert.are.equal(1, result.start_line)
      assert.are.equal(3, result.end_line)
    end)

    it("should return correct column positions", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
      vim.cmd("normal! gg0v4l")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert(result)
      assert.are.equal(1, result.start_col)
      assert.is_true(result.end_col > result.start_col)
    end)

    it("should handle empty buffer", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {})

      local result, err = selection.get_visual_selection()
      assert.is_nil(result)
      assert.are.equal("No active visual selection", err)
    end)

    it("should handle single empty line", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
      vim.cmd("normal! ggv$")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert(result)
      assert.are.equal("", result.text)
    end)

    it("should handle visual line mode selection", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1", "line 2" })
      vim.cmd("normal! ggVj")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert(result)
      assert.are.equal("line 1\nline 2", result.text)
      assert.are.equal(1, result.start_line)
      assert.are.equal(2, result.end_line)
    end)

    it("should handle selection with special characters", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello\ttab" })
      vim.cmd("normal! ggV")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert(result)
      assert.is_true(result.text:find("\t") ~= nil)
    end)

    it("should handle selection at end of buffer", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1", "line 2", "line 3" })
      vim.cmd("normal! GV")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert(result)
      assert.are.equal("line 3", result.text)
      assert.are.equal(3, result.start_line)
      assert.are.equal(3, result.end_line)
    end)

    it("should prefer the visual mark buffer over the current buffer", function()
      local current_bufnr = vim.api.nvim_get_current_buf()
      local other_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(other_bufnr, 0, -1, false, { "from mark buffer" })

      local original_getpos = vim.fn.getpos
      mock(vim.fn, "getpos", function(mark)
        if mark == "'<" then
          return { other_bufnr, 1, 1, 0 }
        end
        if mark == "'>" then
          return { other_bufnr, 1, 16, 0 }
        end
        return original_getpos(mark)
      end)

      local ok, result = pcall(selection.get_visual_selection)

      mock(vim.fn, "getpos", original_getpos)
      vim.api.nvim_buf_delete(other_bufnr, { force = true })

      assert.is_true(ok)
      assert.are.equal(current_bufnr, vim.api.nvim_get_current_buf())
      assert(result)
      assert.are.equal(other_bufnr, result.bufnr)
      assert.are.equal("from mark buffer", result.text)
    end)
  end)
end)
