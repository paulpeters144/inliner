_G.test = function()
  local mode = vim.fn.mode()
  if mode:match("^[vV\22]") then
    vim.cmd('normal! \27') -- Esc
  end
  print("mode: " .. vim.fn.mode())
  print("< : " .. vim.inspect(vim.fn.getpos("'<")))
  print("> : " .. vim.inspect(vim.fn.getpos("'>")))
end
