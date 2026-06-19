if vim.g.loaded_inliner then
  return
end
vim.g.loaded_inliner = true

vim.api.nvim_create_user_command("InlinerEdit", function()
  require("inliner").edit()
end, { range = true })

vim.api.nvim_create_user_command("InlinerQuestion", function(args)
  require("inliner").question(args.range ~= 0 and { start = args.line1, ["end"] = args.line2 } or nil)
end, { range = true })

vim.api.nvim_create_user_command("InlinerExplain", function()
  require("inliner").explain()
end, { range = true })
