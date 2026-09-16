-- Autocommands. LazyVim provides the usual ones, such as highlighting on yank
-- and restoring the cursor position, so only what it does not cover is here.

-- Say when a filetype has no language server because nothing provides one.
-- The editor looks identical with a server and without one until a feature is
-- missing, so silence is misleading; warning on every buffer would be worse.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("lsp-availability", { clear = true }),
  callback = function(event)
    local filetype = vim.bo[event.buf].filetype

    -- Ignore the editor's own scratch buffers, which no server serves.
    if filetype == "" or vim.bo[event.buf].buftype ~= "" then
      return
    end

    -- Let the servers that are going to attach do so first.
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(event.buf) then
        return
      end
      if #vim.lsp.get_clients({ bufnr = event.buf }) == 0 then
        require("util.lsp").warn_missing(filetype)
      end
    end, 2000)
  end,
})
