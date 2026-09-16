--- `:checkhealth dotfiles` — what this config expects from the machine.
---
--- Neovim's own health checks cover Neovim. This covers the parts that live
--- outside it: the language servers and tools that have to be installed by
--- hand, and what installs them.

local tools = require("util.tools")

local M = {}

function M.check()
  vim.health.start("dotfiles: external tools")

  local rows = tools.report()

  if #rows == 0 then
    vim.health.ok("Nothing is expected from outside the editor.")
    return
  end

  for _, row in ipairs(rows) do
    if row.ok then
      vim.health.ok(("%s — %s"):format(row.name, row.what))
    else
      vim.health.warn(
        ("%s is not installed — %s"):format(row.name, row.what),
        { row.install }
      )
    end
  end

  vim.health.start("dotfiles: Mason")

  -- Mason installs pip packages into a virtual environment. Without the venv
  -- module that fails on every attempt, which is why the Python servers above
  -- are installed with uv instead.
  local python = vim.fn.exepath("python3")
  if python == "" then
    vim.health.warn("python3 is not on PATH, so Mason cannot install pip packages.")
  else
    local venv_ok = vim.system({ python, "-c", "import ensurepip" }):wait().code == 0
    if venv_ok then
      vim.health.ok("python3 has ensurepip, so Mason can install pip packages.")
    else
      vim.health.warn("python3 has no ensurepip, so Mason cannot install pip packages.", {
        "Install the venv module: apt install python3.12-venv",
        "Or keep installing Python tools with uv, which is what this config expects.",
      })
    end
  end
end

return M
