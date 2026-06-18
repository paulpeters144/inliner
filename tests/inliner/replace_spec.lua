local replace = require("inliner.replace")

describe("replace", function()
  before_each(function()
    vim.cmd("enew!")
    vim.bo[0].swapfile = false
    vim.wait(10)
  end)

  describe("replace_selection", function()
    it("should replace single line selection", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })

      local selection = {
        text = "hello world",
        bufnr = 0,
        start_line = 1,
        end_line = 1,
        start_col = 1,
        end_col = 11,
      }

      replace.replace_selection(selection, "goodbye world")

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(1, #lines)
      assert.are.equal("goodbye world", lines[1])
    end)

    it("should replace multi-line selection with single line", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1", "line 2", "line 3" })

      local selection = {
        text = "line 1\nline 2\nline 3",
        bufnr = 0,
        start_line = 1,
        end_line = 3,
        start_col = 1,
        end_col = 6,
      }

      replace.replace_selection(selection, "single line")

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(1, #lines)
      assert.are.equal("single line", lines[1])
    end)

    it("should replace single line with multi-line", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "single line" })

      local selection = {
        text = "single line",
        bufnr = 0,
        start_line = 1,
        end_line = 1,
        start_col = 1,
        end_col = 11,
      }

      replace.replace_selection(selection, "line 1\nline 2\nline 3")

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(3, #lines)
      assert.are.equal("line 1", lines[1])
      assert.are.equal("line 2", lines[2])
      assert.are.equal("line 3", lines[3])
    end)

    it("should replace multi-line with multi-line", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "old 1", "old 2", "old 3" })

      local selection = {
        text = "old 1\nold 2\nold 3",
        bufnr = 0,
        start_line = 1,
        end_line = 3,
        start_col = 1,
        end_col = 5,
      }

      replace.replace_selection(selection, "new 1\nnew 2")

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(2, #lines)
      assert.are.equal("new 1", lines[1])
      assert.are.equal("new 2", lines[2])
    end)

    it("should handle empty replacement text", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1", "line 2" })

      local selection = {
        text = "line 1\nline 2",
        bufnr = 0,
        start_line = 1,
        end_line = 2,
        start_col = 1,
        end_col = 6,
      }

      replace.replace_selection(selection, "")

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(1, #lines)
      assert.are.equal("", lines[1])
    end)

    it("should replace middle lines preserving surrounding content", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "keep 1", "replace me", "keep 2" })

      local selection = {
        text = "replace me",
        bufnr = 0,
        start_line = 2,
        end_line = 2,
        start_col = 1,
        end_col = 10,
      }

      replace.replace_selection(selection, "replaced")

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(3, #lines)
      assert.are.equal("keep 1", lines[1])
      assert.are.equal("replaced", lines[2])
      assert.are.equal("keep 2", lines[3])
    end)

    it("should handle replacement with trailing newline", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "original" })

      local selection = {
        text = "original",
        bufnr = 0,
        start_line = 1,
        end_line = 1,
        start_col = 1,
        end_col = 8,
      }

      replace.replace_selection(selection, "new text\n")

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(2, #lines)
      assert.are.equal("new text", lines[1])
      assert.are.equal("", lines[2])
    end)

    it("should default to the current buffer when bufnr is missing", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "replace me" })

      local selection = {
        text = "replace me",
        start_line = 1,
        end_line = 1,
        start_col = 1,
        end_col = 10,
      }

      replace.replace_selection(selection, "replaced")

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert.are.equal(1, #lines)
      assert.are.equal("replaced", lines[1])
    end)
  end)
end)
