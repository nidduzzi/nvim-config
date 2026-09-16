-- Keymaps. LazyVim already provides window navigation with <C-h/j/k/l>,
-- buffer and search keys, so only what it does not cover is here.

local map = vim.keymap.set

-- Clear the search highlight without typing a command.
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Diagnostics for this buffer, in the location list.
map("n", "<leader>xq", vim.diagnostic.setloclist, { desc = "Diagnostics to location list" })
