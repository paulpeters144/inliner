local selection = require("inliner.selection")

vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "line 1",
  "line 2",
  "line 3",
  "line 4",
  "line 5"
})

-- Test 1: Upward visual selection
vim.cmd("normal! 4Gv2G")
local sel = selection.get_visual_selection()

print("Text selected upwards:")
print(sel.text)
print("Start line: " .. sel.start_line)
print("End line: " .. sel.end_line)
