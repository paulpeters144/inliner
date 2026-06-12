if vim.g.loaded_inliner then
  return
end
vim.g.loaded_inliner = true

vim.api.nvim_create_user_command("InlinerEdit", function()
  require("inliner").edit()
end, { range = true })

vim.api.nvim_create_user_command("InlinerQuestion", function()
  require("inliner").question()
end, {})

vim.api.nvim_create_user_command("InlinerExplain", function()
  require("inliner").explain()
end, { range = true })
