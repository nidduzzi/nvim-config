--- `:checkhealth dotfiles` — which language servers this checkout provides.
---
--- Nothing is installed automatically, so the interesting question is not
--- "what is configured" but "what can actually start here, and from where".

local lsp = require("util.lsp")

local M = {}

function M.check()
  vim.health.start("dotfiles: language servers for " .. lsp.root(vim.fn.getcwd()))

  local names = vim.tbl_keys(lsp.status)
  table.sort(names)

  if #names == 0 then
    vim.health.info("No servers have been resolved yet. Open a file first.")
    return
  end

  for _, name in ipairs(names) do
    local info = lsp.status[name]
    local filetypes = table.concat(info.filetypes or {}, ", ")

    if info.status == "project" then
      vim.health.ok(("%s — from this project: %s"):format(name, info.cmd[1]))
    elseif info.status == "PATH" then
      vim.health.ok(("%s — from PATH: %s"):format(name, vim.fn.exepath(info.cmd[1])))
    else
      vim.health.info(
        ("%s — not provided here, so it will not start (%s)"):format(
          name,
          filetypes ~= "" and filetypes or "no filetypes declared"
        )
      )
    end
  end

  vim.health.start("dotfiles: installing servers")
  vim.health.info(table.concat({
    "Servers are never installed automatically.",
    "Install one into the project, so only this project uses it:",
    "  Python:     uv pip install <server>      (into .venv)",
    "  Node:       npm install -D <server>      (into node_modules/.bin)",
    "Or install it for the whole machine, with uv, mise or a package manager.",
    "Or use :Mason by hand, which installs into Neovim's own data directory.",
  }, "\n"))
end

return M
