-- Autocommands. LazyVim provides the usual ones, such as highlighting on yank
-- and restoring the cursor position, so only what it does not cover is here.

-- Report tools that have to be installed outside the editor, the first time a
-- file that needs them is opened. Warning once beats failing on every file.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("external-tool-check", { clear = true }),
  pattern = { "python" },
  callback = function(event)
    require("util.tools").check_filetype(vim.bo[event.buf].filetype)
  end,
})
