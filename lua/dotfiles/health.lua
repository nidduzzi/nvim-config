--- `:checkhealth dotfiles` — which language servers this checkout provides.
---
--- Nothing is installed automatically, so the interesting question is not
--- "what is configured" but "what can actually start here, and from where".

local lsp = require("util.lsp")

local M = {}

function M.check()
  vim.health.start("dotfiles: language servers for " .. lsp.root(vim.fn.getcwd()))

  -- Resolution happens when nvim-lspconfig loads, which has not necessarily
  -- happened yet: a health check run before any file is opened would otherwise
  -- report nothing and look like a broken config. Load the plugin rather than
  -- rebuilding its options by hand, because resolving a server needs the
  -- lspconfig definitions to exist, and without them every server looks
  -- missing.
  if vim.tbl_isempty(lsp.status) then
    pcall(function()
      require("lazy").load({ plugins = { "nvim-lspconfig" } })
    end)
  end

  local names = vim.tbl_keys(lsp.status)
  table.sort(names)

  if #names == 0 then
    vim.health.warn("No servers could be resolved. nvim-lspconfig may have failed to load.")
    return
  end

  for _, name in ipairs(names) do
    local info = lsp.status[name]
    local filetypes = table.concat(info.filetypes or {}, ", ")

    if info.status == "project" then
      vim.health.ok(("%s — from this project: %s"):format(name, info.cmd[1]))
    elseif info.status == "editor" then
      local exe = info.cmd and info.cmd[1] or name
      local found = vim.fn.exepath(exe)
      if found ~= "" then
        vim.health.ok(("%s — the editor's own, installed by Mason: %s"):format(name, found))
      else
        vim.health.warn(("%s — the editor's own, but Mason has not installed it yet"):format(name), {
          "It installs on the next start. :Mason shows progress.",
        })
      end
    elseif info.status == "ignored" then
      vim.health.info(("%s — provided here, but this project's .nvim.lua ignores it"):format(name))
    elseif info.status == "PATH" then
      vim.health.ok(("%s — from PATH: %s"):format(name, vim.fn.exepath(info.cmd[1])))
    else
      vim.health.info(("%s — not provided here, so it will not start (%s)"):format(name, filetypes ~= "" and filetypes or "no filetypes declared"))
    end
  end

  vim.health.start("dotfiles: keys that were overwritten")

  local overwrites = require("config.keyguard").overwrites
  if #overwrites == 0 then
    vim.health.ok("Nothing has overwritten a mapping since startup.")
  else
    for _, entry in ipairs(overwrites) do
      local line = ("%s (%s) was %q, now %q — %s"):format(entry.lhs, entry.mode, entry.before, entry.after, entry.who)

      -- Three kinds, and only the last is a problem. A plugin refining its own
      -- key is ordinary; this config taking a key is a decision already made;
      -- a plugin taking a key this config owns is how a feature disappears.
      if entry.mine then
        vim.health.info(line .. "  (on purpose, by this config)")
      elseif require("config.keyguard").watched[entry.mode .. entry.lhs] then
        vim.health.warn(line .. "  (a key this config uses)")
      else
        vim.health.info(line)
      end
    end
  end

  vim.health.start("dotfiles: installing servers")
  vim.health.info(table.concat({
    "Servers are never installed automatically, and how you install one is not",
    "this configuration's concern. Put the executable either inside the project,",
    "where only this project will use it, or anywhere on PATH.",
    "",
    "Project directories that are searched first:",
    "  " .. table.concat(lsp.bin_dirs(lsp.root(vim.fn.getcwd())), "  "),
  }, "\n"))
end

return M
