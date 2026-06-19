_G.test = function()
  print("mode: " .. vim.fn.mode())
  print("< : " .. vim.inspect(vim.fn.getpos("'<")))
  print("> : " .. vim.inspect(vim.fn.getpos("'>")))
end
