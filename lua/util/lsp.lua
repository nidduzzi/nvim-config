--- Attach the language servers a project provides, and nothing else.
---
--- Installing every server the config knows about produces servers that
--- disagree with each other: two type checkers reporting different things
--- about the same untouched file, or the same linter running twice because one
--- server embeds it and another provides it natively.
---
--- So nothing is installed automatically, and a server starts only when the
--- project can already provide it, which means one of:
---
---   * an executable inside the project's own environment, which is preferred,
---     because it is the version the project pins and it matches the project's
---     dependencies
---   * an executable on PATH
---
--- How either of them got there is not the editor's business. A server
--- installed with apt, uv, npm, mise, Mason or built by hand all look the same
--- from here, and all work. The editor's job is to use what it finds and to
--- say what it could not find, not to have an opinion about package managers.
---
--- A project therefore selects its own servers by what it installs, and the
--- same config behaves differently in each checkout without being edited.
--- Servers that nothing provides are disabled quietly and listed by
--- `:checkhealth dotfiles`.

local M = {}

--- Directories inside a project that hold executables, for the ecosystems this
--- is likely to meet. Anything ending in a glob is expanded.
---
--- This list is about where tools live, not about which languages are
--- supported: a server for any language is found as long as its executable
--- ends up in one of these.
M.bin_dirs = {
  ".venv/bin", -- Python virtualenv
  "venv/bin",
  ".direnv/*/bin", -- direnv layouts
  "node_modules/.bin", -- npm, pnpm, yarn
  ".yarn/bin",
  "vendor/bin", -- Composer
  ".bundle/bin", -- Bundler
  "bin", -- project-local scripts, Mix and Gradle wrappers
  ".tools/bin",
  "result/bin", -- Nix build output
}

--- Files that mean "the directory containing me is a project root".
M.root_markers = {
  ".git",
  ".hg",
  "pyproject.toml",
  "setup.cfg",
  "package.json",
  "deno.json",
  "Cargo.toml",
  "go.mod",
  "composer.json",
  "Gemfile",
  "mix.exs",
  "build.gradle",
  "pom.xml",
  "flake.nix",
  ".venv",
}

--- The project root for a starting directory.
---@param start string
---@return string
function M.root(start)
  local found = vim.fs.find(M.root_markers, { path = start, upward = true })[1]
  return found and vim.fs.dirname(found) or start
end

--- Look for an executable inside the project, before falling back to PATH.
---@param name string
---@param start? string directory to search from. Default: the current one.
---@return string|nil path an absolute path, or nil when the project has none
function M.project_bin(name, start)
  local root = M.root(start or vim.fn.getcwd())

  for _, dir in ipairs(M.bin_dirs) do
    for _, candidate in ipairs(vim.fn.glob(root .. "/" .. dir .. "/" .. name, false, true)) do
      if vim.fn.executable(candidate) == 1 then
        return candidate
      end
    end
  end
end

--- Where a server's command would come from, if anywhere.
---@param name string server name, as lspconfig knows it
---@return { cmd: string[], source: "project"|"PATH" }|nil
function M.resolve(name)
  local ok, config = pcall(function()
    return vim.lsp.config[name]
  end)

  local cmd = ok and config and config.cmd

  -- A server that builds its own command, rather than naming an executable,
  -- knows better than this does. Leave it alone.
  if type(cmd) ~= "table" or type(cmd[1]) ~= "string" then
    return nil
  end

  local resolved = vim.deepcopy(cmd)

  local in_project = M.project_bin(cmd[1])
  if in_project then
    resolved[1] = in_project
    return { cmd = resolved, source = "project" }
  end

  if vim.fn.executable(cmd[1]) == 1 then
    return { cmd = resolved, source = "PATH" }
  end
end

--- Servers the editor installs for itself, whatever the project is.
---
--- This configuration is written in Lua, so editing it is not a project
--- concern: it has to work in any checkout, including one that has nothing to
--- do with Lua. These are therefore installed by Mason and always enabled, and
--- they are the only things that are.
---
--- Everything else is the project's business. Keep this list short; every name
--- added is a server that will attach somewhere it was not asked for.
M.baseline = { "lua_ls" }

--- What happened to each server the config asked for. Read by the health check
--- and by the warning, so both describe the same decisions.
---@type table<string, { status: "project"|"PATH"|"editor"|"missing", cmd?: string[], filetypes?: string[] }>
M.status = {}

--- Disable every server the project cannot provide, and point the rest at the
--- project's own executable when there is one.
---@param servers table<string, table|boolean>
function M.keep_available(servers)
  M.status = {}

  for name, config in pairs(servers) do
    local settings = type(config) == "table" and config or {}

    -- "*" is not a server. LazyVim uses it to hold the settings applied to
    -- every server, so disabling it would disable the lot.
    if name == "*" or settings.enabled == false then
      goto continue
    end

    local found = M.resolve(name)
    local declared = vim.lsp.config[name] or {}
    local is_baseline = vim.tbl_contains(M.baseline, name)

    if is_baseline then
      -- Enabled whether or not the executable is there yet: on a new machine
      -- Mason is still installing it while this runs, and the server attaches
      -- on the next buffer. A project copy is still preferred if there is one.
      if found and found.source == "project" then
        settings.cmd = found.cmd
      end
      settings.mason = false
      servers[name] = settings
      M.status[name] = {
        status = found and found.source == "project" and "project" or "editor",
        cmd = found and found.cmd or declared.cmd,
        filetypes = declared.filetypes,
      }
    elseif not found then
      settings.enabled = false
      servers[name] = settings
      M.status[name] = { status = "missing", filetypes = declared.filetypes }
    else
      if found.source == "project" then
        settings.cmd = found.cmd
      end

      -- Tell LazyVim not to route this server through mason-lspconfig.
      -- LazyVim only calls vim.lsp.enable() itself for servers mason does not
      -- manage; for the rest it waits for mason-lspconfig to enable them, and
      -- that is turned off here, so the server would never start at all. We
      -- have already decided where the executable comes from, so mason has
      -- nothing left to contribute.
      settings.mason = false

      servers[name] = settings
      M.status[name] = {
        status = found.source,
        cmd = found.cmd,
        filetypes = declared.filetypes,
      }
    end

    ::continue::
  end
end

--- Filetypes already warned about, so opening ten files of one kind produces
--- one message rather than ten.
local warned = {}

--- Say which servers this filetype could have used but nothing provides.
---
--- Silence would be wrong, because the editor looks the same with a server as
--- without one until a feature is missing. Repeating it on every buffer would
--- be worse.
---@param filetype string
function M.warn_missing(filetype)
  if warned[filetype] or filetype == "" then
    return
  end
  warned[filetype] = true

  local missing = {}
  for name, info in pairs(M.status) do
    if info.status == "missing" and vim.tbl_contains(info.filetypes or {}, filetype) then
      table.insert(missing, name)
    end
  end

  if #missing == 0 then
    return
  end

  table.sort(missing)

  vim.notify(
    ("No language server for %s.\n\nConfigured but not provided by this project or PATH:\n  %s\n\nInstall one in the project, or on PATH, and restart.\n:checkhealth dotfiles lists them.")
      :format(filetype, table.concat(missing, ", ")),
    vim.log.levels.WARN,
    { title = "Language servers" }
  )
end

return M
