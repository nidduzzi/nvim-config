--- Settings, in tiers, the way the shell and tmux config already work.
---
--- Four places a setting can come from, each overriding the one before:
---
---   1. built in        the defaults below, shared by every machine
---   2. this machine    <config>/local.lua, never committed
---   3. this project    .nvim.lua, through vim.g, committed with the project
---   4. right now       set() from a key or a command, until you quit
---
--- That order is the useful one. A machine has a model it can reach; a project
--- has a language and a documentation layout; and sometimes you want something
--- different for ten minutes without editing a file to get it.
---
--- Before this, the answer varied by feature. Search filters read vim.g and
--- were project-settable; the LSP ignore list read vim.g; the agent's backend
--- was a Lua field, so choosing one lasted until you quit and there was no way
--- to say "this project uses the local model" at all.
---
--- Read with `get`, never by reaching for vim.g directly, so every setting
--- gains all four tiers at once and `:checkhealth dotfiles` can say where each
--- value actually came from.

local M = {}

--- The shared defaults. Everything settable lives here, with the name it takes
--- in a project's .nvim.lua as `vim.g.<name>`.
---@type table<string, any>
M.defaults = {
  -- Which coding agent answers. See util/agent/backends.lua.
  agent_backend = "claude",
  -- nil means "whatever that backend prefers" — "sonnet" means nothing to
  -- Hermes, so naming a model globally is wrong. It is absent from this table
  -- rather than false, so M.names below is what makes it visible.
  -- Use a backend whose inability to write has not been demonstrated here.
  agent_allow_unproven = false,
  -- Milliseconds before a request is abandoned. A local model needs far more
  -- than a hosted one.
  agent_timeout = 90000,

  -- Which grep filter a search starts on: code, all, or docs.
  search_preset = "code",

  -- Language servers this project should not start even if they are present.
  lsp_ignore = {},
}

--- Every settable name, including the ones whose default is nil and so cannot
--- appear in the table above. A setting you cannot see listed is a setting you
--- do not know you can set.
---@type string[]
M.names = {
  "agent_backend",
  "agent_model",
  "agent_allow_unproven",
  "agent_timeout",
  "search_preset",
  "lsp_ignore",
}

--- Set for this session only. Nothing is written to disk.
---@type table<string, any>
local session = {}

--- Where a machine-local file would be. Deliberately beside init.lua rather
--- than hidden in a state directory: a setting you cannot find is a setting
--- you will set twice.
---@return string
function M.local_file()
  return vim.fs.joinpath(vim.fn.stdpath("config") --[[@as string]], "local.lua")
end

---@type table<string, any>|nil
local from_file

--- Read the machine-local file once. A file that does not exist is the normal
--- case, not an error.
---@return table<string, any>
local function machine()
  if from_file then
    return from_file
  end

  from_file = {}
  local path = M.local_file()
  if vim.uv.fs_stat(path) then
    local ok, loaded = pcall(dofile, path)
    if ok and type(loaded) == "table" then
      from_file = loaded
    elseif not ok then
      vim.schedule(function()
        vim.notify(
          ("%s could not be read:\n%s"):format(path, tostring(loaded)),
          vim.log.levels.ERROR,
          { title = "Settings" }
        )
      end)
    end
  end

  return from_file
end

--- Forget the machine-local file, so editing it takes effect without a restart.
function M.reload()
  from_file = nil
end

--- What a setting is, and where it came from.
---@param name string
---@return any value
---@return string source
function M.resolve(name)
  if session[name] ~= nil then
    return session[name], "set for this session"
  end

  local project = vim.g[name]
  if project ~= nil then
    return project, "this project's .nvim.lua"
  end

  local file = machine()[name]
  if file ~= nil then
    return file, vim.fn.fnamemodify(M.local_file(), ":~")
  end

  return M.defaults[name], "built in"
end

--- What a setting is.
---@param name string
---@return any
function M.get(name)
  local value = M.resolve(name)
  return value
end

--- Set for this session, until you quit.
---@param name string
---@param value any
function M.set(name, value)
  session[name] = value
end

--- Put it back to whatever the lower tiers say.
---@param name string
function M.clear(name)
  session[name] = nil
end

--- Every setting, its value, and which tier it came from. Used by
--- `:checkhealth dotfiles` and by the capability list.
---@return { name: string, value: any, source: string }[]
function M.all()
  local names = vim.list_slice(M.names)
  table.sort(names)

  local rows = {}
  for _, name in ipairs(names) do
    local value, source = M.resolve(name)
    if value == nil then
      -- No tier set it, so there is no value to show and "built in" would be
      -- a claim about a default that does not exist.
      value, source = "(unset)", "the backend decides"
    end
    table.insert(rows, { name = name, value = value, source = source })
  end
  return rows
end

--- Show them, with where each one came from.
function M.show()
  local lines = { "Settings, and where each value came from:", "" }

  -- Column widths from the values actually present. A fixed 28-wide value
  -- column pushed "set for this session" past the panel's edge and wrapped
  -- the tier onto its own line, which is the one thing this panel exists to
  -- say clearly.
  local rows = M.all()
  local widest_name, widest_value = 0, 0
  for _, row in ipairs(rows) do
    local value = row.value
    if type(value) == "table" then
      value = vim.inspect(value):gsub("%s+", " ")
    end
    row.shown = tostring(value)
    widest_name = math.max(widest_name, #row.name)
    widest_value = math.max(widest_value, #row.shown)
  end

  for _, row in ipairs(rows) do
    table.insert(lines, ("%-" .. widest_name .. "s  %-" .. widest_value .. "s  %s"):format(row.name, row.shown, row.source))
  end
  table.insert(lines, "")
  table.insert(lines, ("Machine-local file: %s"):format(vim.fn.fnamemodify(M.local_file(), ":~")))
  table.insert(lines, "A project overrides it through vim.g.<name> in its .nvim.lua.")

  require("util.agent.panel").show("Settings", table.concat(lines, "\n"))
end

return M
