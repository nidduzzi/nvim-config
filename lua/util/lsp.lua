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
--- A virtualenv puts its programs in `bin`, or in `Scripts` on Windows.
--- Whichever is there is the answer, so neither name is assumed.
---@param where string
---@return string|nil
local function venv_bin(where)
  for _, name in ipairs({ "bin", "Scripts" }) do
    if vim.fn.isdirectory(vim.fs.joinpath(where, name)) == 1 then
      return name
    end
  end
end

---@type { marker: string, bin: string|fun(root: string): string|nil, why: string }[]
M.bin_evidence = {
  {
    marker = "pyvenv.cfg",
    bin = function(root)
      return venv_bin(root)
    end,
    why = "a Python virtualenv names itself",
  },
  {
    marker = ".venv/pyvenv.cfg",
    bin = function(root)
      local name = venv_bin(vim.fs.joinpath(root, ".venv"))
      return name and vim.fs.joinpath(".venv", name)
    end,
    why = "a Python virtualenv in the usual place",
  },
  {
    marker = "venv/pyvenv.cfg",
    bin = function(root)
      local name = venv_bin(vim.fs.joinpath(root, "venv"))
      return name and vim.fs.joinpath("venv", name)
    end,
    why = "a Python virtualenv in the other usual place",
  },
  { marker = "package.json", bin = "node_modules/.bin", why = "npm, pnpm and yarn all install here" },
  { marker = "composer.json", bin = "vendor/bin", why = "Composer's documented location" },
  { marker = "Gemfile", bin = ".bundle/bin", why = "Bundler's binstubs" },
  { marker = ".envrc", bin = ".direnv/*/bin", why = "direnv's layout directory" },
}

--- Programs called `name` in `dir`, whatever extension the platform gives
--- them. A Windows executable is python.exe, not python.
---@param root string
---@param dir string
---@param name string
---@return string[]
function M.executables_named(root, dir, name)
  local found = {}
  for _, pattern in ipairs({ name, name .. ".*" }) do
    for _, candidate in ipairs(vim.fn.glob(vim.fs.joinpath(root, dir, pattern), false, true)) do
      if vim.fn.executable(candidate) == 1 and vim.fn.isdirectory(candidate) == 0 then
        found[#found + 1] = candidate
      end
    end
  end
  return found
end

---@param root string
---@return string[]
function M.bin_dirs(root)
  local found = {}
  local seen = {}

  local activated = vim.env.VIRTUAL_ENV
  if activated and activated ~= "" and vim.startswith(activated, root) then
    local name = venv_bin(activated)
    if name then
      local directory = vim.fs.joinpath(activated, name)
      found[#found + 1] = vim.fs.relpath(root, directory) or directory
      seen[found[#found]] = true
    end
  end

  for _, evidence in ipairs(M.bin_evidence) do
    local marker = vim.fn.glob(vim.fs.joinpath(root, evidence.marker), false, true)
    local directory = evidence.bin
    if type(directory) == "function" then
      directory = directory(root)
    end
    if #marker > 0 and directory and not seen[directory] then
      seen[directory] = true
      found[#found + 1] = directory
    end
  end

  if vim.uv.fs_stat(vim.fs.joinpath(root, "result", "bin")) and not seen["result/bin"] then
    found[#found + 1] = "result/bin"
  end

  return found
end

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
---
--- Resolved, because the same directory has more than one name. On macOS
--- /var is a symlink to /private/var, so a root found from the working
--- directory and a root found from a buffer's path can be the same place
--- spelled two ways --- and every decision made by comparing them, from
--- whether a project is trusted to whether a program lies inside it, is then
--- made on the spelling.
---@param start string
---@return string
function M.root(start)
  local found = vim.fs.find(M.root_markers, { path = start, upward = true })[1]
  local root = found and vim.fs.dirname(found) or start
  return vim.uv.fs_realpath(root) or root
end

--- Look for an executable inside the project, before falling back to PATH.
---@param name string
---@param start? string directory to search from. Default: the current one.
---@return string|nil path an absolute path, or nil when the project has none
---@param root string
---@return boolean
local function may_run_project_bin(root)
  local allowed = require("util.settings").get("lsp_project_bin")
  if allowed == true then
    return true
  end
  if allowed == false then
    return false
  end
  return require("util.trust").is_trusted(root)
end

---@type table<string, boolean>
local refused = {}

---@param root string
---@param candidate string
local function say_refused(root, candidate)
  if refused[root] then
    return
  end
  refused[root] = true

  vim.schedule(function()
    vim.notify(
      ("%s ships its own %s.\n\nIt was not started: a program from a repository runs as you do, with your environment. :DotfilesTrustProject to allow this one, or set lsp_project_bin."):format(
        vim.fn.fnamemodify(root, ":~"),
        vim.fn.fnamemodify(candidate, ":t")
      ),
      vim.log.levels.WARN,
      { title = "Untrusted project" }
    )
  end)
end

function M.project_bin(name, start)
  local root = M.root(start or vim.fn.getcwd())
  local trusted = may_run_project_bin(root)

  for _, dir in ipairs(M.bin_dirs(root)) do
    for _, candidate in ipairs(M.executables_named(root, dir, name)) do
      if vim.fn.executable(candidate) == 1 then
        if not trusted then
          say_refused(root, candidate)
          return nil
        end
        return candidate
      end
    end
  end
end

--- A program from PATH, unless PATH leads back into an untrusted project.
---
--- venv-selector activates a project's virtualenv, and activating one puts
--- its bin directory on PATH. After that `exepath` answers with a program
--- from the project without anything having looked in the project, which is
--- the check this module exists to make. The same is true of direnv, of a
--- shell that was started inside the project, and of anything else that
--- arranges PATH before the editor starts.
---@param name string
---@param start? string directory to judge the project from
---@return string the path, or "" when nothing safe answers
function M.safe_exepath(name, start)
  local found = vim.fn.exepath(name)
  if found == "" then
    return ""
  end
  -- Resolved for the same reason the root is: a symlinked program inside the
  -- project is inside the project, whatever its path says. Only the decision
  -- is made on the resolved path. What comes back is the name PATH gave,
  -- because a version manager's shim is a symlink to the manager itself:
  -- resolving ~/.local/share/mise/shims/julia hands back /usr/bin/mise, and
  -- running that with Julia's arguments exits 2 before the adapter speaks.
  local resolved = vim.uv.fs_realpath(found) or found

  local root = M.root(start or vim.fn.getcwd())
  local inside = vim.fs.relpath(root, resolved)
  if inside and not inside:match("^%.%.") and not may_run_project_bin(root) then
    say_refused(root, found)
    return ""
  end

  return found
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

--- Servers this project does not want, even though it provides them.
---
--- Set from a project's `.nvim.lua`:
---
---     vim.g.lsp_ignore = { "pyright" }
---
--- Python is where this bites: a virtualenv can easily hold pylsp, pyrefly,
--- pyright, ruff and ty at once, and four of those will type-check the same
--- file and disagree about how much to say. Which one a project trusts is the
--- project's business, not this config's.
---@param name string
---@return boolean
local function ignored(name)
  local list = require("util.settings").get("lsp_ignore")
  return type(list) == "table" and vim.tbl_contains(list, name) or false
end

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

    if ignored(name) then
      settings.enabled = false
      servers[name] = settings
      M.status[name] = { status = "ignored", filetypes = (vim.lsp.config[name] or {}).filetypes }
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
--- Filetypes that no language server serves, so saying one is missing would be
--- noise rather than news.
---
--- Only real files are listed. A buffer the editor or a plugin made for
--- itself is not a file: it has a buftype, and the autocmd that calls this
--- checks for one. That covers lazy, mason, trouble, the quickfix list,
--- help, man, checkhealth and every picker panel, which is what this list
--- used to name one by one --- and it covers the ones nobody thought to name,
--- which is how opening a merge conflict came to warn that nothing serves
--- DiffviewFiles.
---@type string[]
M.unserved = {
  "gitcommit",
  "gitrebase",
  "text",
}

function M.warn_missing(filetype)
  if warned[filetype] or filetype == "" then
    return
  end
  warned[filetype] = true

  -- Filetypes nobody serves, where silence is the right answer.
  if vim.tbl_contains(M.unserved, filetype) then
    return
  end

  local missing = {}
  local configured = false
  for name, info in pairs(M.status) do
    if vim.tbl_contains(info.filetypes or {}, filetype) then
      configured = true
      if info.status == "missing" then
        table.insert(missing, name)
      end
    end
  end

  -- Nothing is configured for this language at all, which is a different
  -- problem with a different fix. Returning early here was wrong in a way that
  -- only shows up outside the languages this configuration enables: a Rust or
  -- C file opened with no server, no diagnostics and no explanation, because
  -- rust_analyzer and clangd are never configured and so were never "missing".
  if not configured then
    vim.notify(
      ("No language server for %s, and none is configured for it.\n\n:LazyExtras adds language support — look for lang.%s.\nA server already on PATH is picked up without one."):format(
        filetype,
        filetype
      ),
      vim.log.levels.WARN,
      { title = "Language servers" }
    )
    return
  end

  if #missing == 0 then
    return
  end

  table.sort(missing)

  vim.notify(
    ("No language server for %s.\n\nConfigured but not provided by this project or PATH:\n  %s\n\nInstall one in the project, or on PATH, and restart.\n:checkhealth dotfiles lists them."):format(
      filetype,
      table.concat(missing, ", ")
    ),
    vim.log.levels.WARN,
    { title = "Language servers" }
  )
end

return M
