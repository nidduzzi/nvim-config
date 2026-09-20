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

    -- Let the servers that are going to attach do so first, and read buftype
    -- again when they have: a plugin sets its filetype before it sets
    -- buftype, so the check above sees "" for a panel that is about to
    -- become a nofile buffer. Opening a merge conflict warned that nothing
    -- serves DiffviewFiles.
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(event.buf) or vim.bo[event.buf].buftype ~= "" then
        return
      end
      if #vim.lsp.get_clients({ bufnr = event.buf }) == 0 then
        require("util.lsp").warn_missing(filetype)
      end
    end, 2000)
  end,
})

-- Ask about a project nobody has answered for, once, when one is opened.
--
-- Trust decides whether the project's own programs run, which since git was
-- gated includes the gutter signs and every diff. Without the question, the
-- first sign of an untrusted project is a feature quietly missing.
-- Asked directly rather than from a startup event: LazyVim loads this file on
-- VeryLazy, so a VimEnter or User VeryLazy handler registered here is
-- registered after the event it waits for has already fired, and never runs.
-- Opening an untrusted repository asked nothing at all until this was found.
vim.api.nvim_create_autocmd("DirChanged", {
  group = vim.api.nvim_create_augroup("dotfiles_trust_prompt", { clear = true }),
  callback = function()
    require("util.trust_menu").ask_if_untrusted()
  end,
})

require("util.trust_menu").ask_if_untrusted()

vim.api.nvim_create_user_command("DotfilesTrustProject", function()
  local lsp = require("util.lsp")
  local trust = require("util.trust")
  local root = lsp.root(vim.fn.getcwd())

  trust.allow(root)
  -- git asks once per project and remembers the answer, so it has to be told
  -- the answer changed. Reloading the buffer is what makes gitsigns attach
  -- without restarting the editor.
  require("util.git").forget()
  require("util.trust_menu").forget()
  vim.cmd("silent! edit")

  vim.notify(
    ("%s is trusted to run its own programs.\n\n:DotfilesRevokeProject undoes it."):format(vim.fn.fnamemodify(root, ":~")),
    vim.log.levels.INFO,
    { title = "Trusted project" }
  )
end, { desc = "Let this project run its own programs, including git" })

vim.api.nvim_create_user_command("DotfilesRevokeProject", function()
  local lsp = require("util.lsp")
  local trust = require("util.trust")
  local root = lsp.root(vim.fn.getcwd())

  trust.revoke(root)
  require("util.git").forget()
  require("util.trust_menu").forget()
  vim.notify(("%s is no longer trusted."):format(vim.fn.fnamemodify(root, ":~")), vim.log.levels.INFO, { title = "Trusted project" })
end, { desc = "Stop letting this project run the programs it ships" })
