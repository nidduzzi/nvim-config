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
-- Asked when you first open a file from a project, not when the editor
-- starts.
--
-- Two reasons. A startup event is the wrong hook: LazyVim loads this file on
-- VeryLazy, so a VimEnter or User VeryLazy handler registered here waits for
-- something that has already happened and never runs --- which is exactly
-- what the first version did, silently. And the question is about this
-- project's code, so the moment you open some of it is the moment it means
-- something; opening the editor and closing it again asks nothing.
vim.api.nvim_create_autocmd({ "BufReadPost", "DirChanged" }, {
  group = vim.api.nvim_create_augroup("dotfiles_trust_prompt", { clear = true }),
  callback = function(event)
    -- BufReadPost reports the file, and the project is the directory holding
    -- it. DirChanged reports the directory itself, and taking its parent asks
    -- about the wrong place --- which asked about nothing at all, because the
    -- parent of a project is rarely a project.
    local from = nil
    if event.file ~= "" then
      from = event.event == "DirChanged" and event.file or vim.fs.dirname(event.file)
    end
    require("util.trust_menu").ask_if_untrusted(from)
  end,
})

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
