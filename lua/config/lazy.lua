-- Bootstrap lazy.nvim, then load LazyVim, the extras we want, and our own
-- plugin specs on top.
--
-- This config was a fork of kickstart.nvim, which meant carrying a thousand
-- lines of other people's plugin setup and hand-merging upstream changes.
-- LazyVim owns that layer now, so what is left in lua/plugins is only what
-- actually differs from the default.

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    error("Error cloning lazy.nvim:\n" .. out)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },

    -- Language support that used to be configured by hand.
    { import = "lazyvim.plugins.extras.lang.python" },
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.markdown" },

    -- Debugging, which kickstart had enabled through kickstart/plugins/debug.lua.
    { import = "lazyvim.plugins.extras.dap.core" },

    -- Per-project settings read from .neoconf.json and .vscode/settings.json,
    -- so a project tuned for VS Code needs no second copy of its settings.
    { import = "lazyvim.plugins.extras.util.project" },

    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    -- Plugins are pinned through lazy-lock.json rather than by version range,
    -- so that a fresh clone on another machine gets what this one runs.
    version = false,
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  -- Off, because the plugins here are pinned by lazy-lock.json and updating
  -- them is a deliberate act. Enabled, it runs `git fetch` for every plugin
  -- shortly after startup: 53 git processes, each one reaching github.com.
  -- That is invisible here and is what a slow start on another machine is
  -- made of. `:Lazy check` asks the same question when the answer is wanted.
  checker = { enabled = false },
  change_detection = { notify = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
