vim.g.autoformat = false
vim.g.snacks_animate = false

vim.opt.number = true
vim.opt.relativenumber = false

if vim.env.SSH_CONNECTION or vim.env.SSH_TTY then
  vim.g.clipboard = "osc52"
end
