--- Check for external tools this config expects, and say what is missing.
---
--- Some language servers are not installed by Mason here. Mason installs pip
--- packages into a virtual environment, which needs the python3-venv module,
--- and on a machine without it every Python file produces an install failure
--- that cannot be fixed from inside the editor. Those servers are provided by
--- uv instead, which is how this machine manages Python tools anyway.
---
--- The editor's job is therefore not to install anything, but to say clearly
--- what is missing and what would provide it, once, rather than failing
--- repeatedly and silently doing nothing.

local M = {}

--- Tools that are expected to come from outside the editor.
---@type table<string, { filetypes: string[], install: string, what: string }>
M.external = {
  pylsp = {
    filetypes = { "python" },
    what = "Python language server with ruff integration",
    -- Square brackets are eaten when the notification is rendered, so use
    -- the --with form rather than an extras specifier.
    install = "uv tool install python-lsp-server --with python-lsp-ruff",
  },
  pyrefly = {
    filetypes = { "python" },
    what = "Python type checker",
    install = "uv tool install pyrefly",
  },
}

--- Remember what has already been reported, so opening ten Python files does
--- not produce ten identical warnings.
local reported = {}

---@param name string
---@return boolean
function M.available(name)
  return vim.fn.executable(name) == 1
end

--- Warn about the tools missing for a filetype, once per session.
---@param filetype string
function M.check_filetype(filetype)
  local missing = {}

  for name, spec in pairs(M.external) do
    if not reported[name] and vim.tbl_contains(spec.filetypes, filetype) and not M.available(name) then
      reported[name] = true
      table.insert(missing, ("  %s — %s\n    %s"):format(name, spec.what, spec.install))
    end
  end

  if #missing == 0 then
    return
  end

  vim.notify(
    "Not installed, so these features are unavailable:\n\n"
      .. table.concat(missing, "\n\n")
      .. "\n\nRun :checkhealth dotfiles for the full list.",
    vim.log.levels.WARN,
    { title = "External tools" }
  )
end

--- Everything expected, with whether it is present. Used by the health check.
---@return { name: string, ok: boolean, what: string, install: string }[]
function M.report()
  local rows = {}

  for name, spec in pairs(M.external) do
    table.insert(rows, {
      name = name,
      ok = M.available(name),
      what = spec.what,
      install = spec.install,
    })
  end

  table.sort(rows, function(a, b)
    return a.name < b.name
  end)

  return rows
end

return M
