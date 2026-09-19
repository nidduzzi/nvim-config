--- What you typed here last time.
---
--- Several prompts in this configuration ask for free text — a question, a
--- path glob, a set of extensions — and then forget it. You retype the same
--- glob every time you come back to a project, which is the sort of friction
--- that is invisible until someone names it.
---
--- So each kind of prompt keeps a short list per project, most recent first,
--- and offers it as a picker you can filter or ignore. Typing something new is
--- still one keystroke away; the list is a shortcut, never a gate.
---
--- Kept per project because a glob that makes sense in one repository rarely
--- makes sense in another, and a list mixing them is worse than no list.

local M = {}

--- How many entries a kind keeps. Long enough to hold a working set, short
--- enough that the picker is still a glance rather than a search.
M.limit = 30

---@param kind string
---@param root string
---@return string
local function store(kind, root)
  local dir = vim.fs.joinpath(vim.fn.stdpath("state") --[[@as string]], "recall", kind)
  vim.fn.mkdir(dir, "p")
  return vim.fs.joinpath(dir, vim.fn.sha256(root):sub(1, 16))
end

--- The project this belongs to, matching how the agent decides the same thing.
---@return string
local function root()
  local ok, agent = pcall(require, "util.agent")
  if ok then
    return agent.root()
  end
  return assert(vim.uv.cwd())
end

--- Everything remembered for this kind, most recent first.
---@param kind string
---@return string[]
function M.list(kind)
  local fd = io.open(store(kind, root()), "r")
  if not fd then
    return {}
  end

  local out = {}
  for line in fd:lines() do
    if vim.trim(line) ~= "" then
      table.insert(out, line)
    end
  end
  fd:close()
  return out
end

--- Remember an entry, moving it to the front if it is already there.
---@param kind string
---@param value string
function M.add(kind, value)
  value = vim.trim(value or "")
  if value == "" then
    return
  end
  -- A multi-line question would break the one-per-line file, and is not the
  -- sort of thing worth offering back anyway.
  value = value:gsub("%s+", " ")

  local kept = { value }
  for _, existing in ipairs(M.list(kind)) do
    if existing ~= value and #kept < M.limit then
      table.insert(kept, existing)
    end
  end

  local fd = io.open(store(kind, root()), "w")
  if fd then
    fd:write(table.concat(kept, "\n") .. "\n")
    fd:close()
  end
end

--- Ask for text, offering what was typed here before.
---
--- With nothing remembered, and with no picker available, this is an ordinary
--- prompt — the recall is an addition, never a dependency.
---@param opts { kind: string, prompt: string, suggestions?: string[] }
---@param on_done fun(value: string)
function M.input(opts, on_done)
  local function accept(value)
    if not value or vim.trim(value) == "" then
      return
    end
    M.add(opts.kind, value)
    on_done(value)
  end

  local items = {}
  local seen = {}
  for _, source in ipairs({ M.list(opts.kind), opts.suggestions or {} }) do
    for _, value in ipairs(source) do
      if not seen[value] then
        seen[value] = true
        table.insert(items, value)
      end
    end
  end

  if #items == 0 or not pcall(require, "snacks") then
    vim.ui.input({ prompt = opts.prompt }, accept)
    return
  end

  local entries = {}
  for i, value in ipairs(items) do
    table.insert(entries, { idx = i, text = value, value = value })
  end

  Snacks.picker.pick({
    title = opts.prompt,
    items = entries,
    layout = { preset = "select" },
    format = function(item)
      return { { item.value, "SnacksPickerLabel" } }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        accept(item.value)
      end
    end,
    -- Nothing matched means you are typing something new, which is the common
    -- case the first few times. Take the query itself rather than making the
    -- prompt a dead end.
    actions = {
      use_query = function(picker)
        local query = picker:filter().pattern
        picker:close()
        accept(query)
      end,
    },
    win = {
      input = {
        keys = {
          ["<c-y>"] = { "use_query", mode = { "i", "n" }, desc = "Use exactly what I typed" },
        },
      },
    },
  })
end

--- Directories whose contents are not this project's code.
---
--- Walking them is slow and the answers are wrong: the extensions inside
--- node_modules describe somebody else's project, and offering them as filters
--- for this one is worse than offering nothing.
---@type table<string, boolean>
local vendored = {
  [".git"] = true,
  [".hg"] = true,
  [".svn"] = true,
  [".venv"] = true,
  ["venv"] = true,
  ["node_modules"] = true,
  ["__pycache__"] = true,
  ["target"] = true,
  ["dist"] = true,
  ["build"] = true,
  [".mypy_cache"] = true,
  [".pytest_cache"] = true,
  [".ruff_cache"] = true,
  [".next"] = true,
  [".tox"] = true,
}

---@param path string
---@return boolean
local function is_vendored(path)
  for part in path:gmatch("[^/]+") do
    if vendored[part] then
      return true
    end
  end
  return false
end

--- Answers already worked out, per project. The walk is bounded but not free:
--- measured at 45ms over label-studio's 5626 files, on the main loop, every
--- time the extension filter is opened. Once per project is plenty — the set
--- of languages in a repository does not change while you are looking at it.
---@type table<string, string[]>
local extension_cache = {}

--- Forget the cached walks, for when a project really has changed shape.
function M.rescan()
  extension_cache = {}
end

--- The file extensions this project actually contains, most common first, so
--- the extension filter can offer them rather than ask you to remember.
---@param limit? integer
---@return string[]
function M.extensions(limit)
  local where = root()
  if extension_cache[where] then
    return vim.list_slice(extension_cache[where], 1, limit or 15)
  end

  local counts = {}

  -- git already knows what the project contains, and asking it is one process
  -- rather than a walk of the working tree. Walking label-studio took 218ms of
  -- blocking time; on a filesystem slower than this one it is seconds.
  local found = vim.fn.systemlist({ "git", "-C", where, "ls-files" })
  if vim.v.shell_error ~= 0 then
    found = vim.fs.find(function(name, path)
      return name:match("%.[%w]+$") ~= nil and not is_vendored(path)
    end, { path = where, type = "file", limit = 4000 })
  else
    found = vim.tbl_filter(function(file)
      return not is_vendored(file)
    end, found)
  end

  for _, file in ipairs(found) do
    local ext = file:match("%.([%w]+)$")
    if ext then
      counts[ext] = (counts[ext] or 0) + 1
    end
  end

  local exts = vim.tbl_keys(counts)
  table.sort(exts, function(a, b)
    if counts[a] ~= counts[b] then
      return counts[a] > counts[b]
    end
    return a < b
  end)

  extension_cache[where] = exts
  return vim.list_slice(exts, 1, limit or 15)
end

--- The top-level directories of this project, as globs, so the path filter has
--- somewhere to start.
---@return string[]
function M.top_level_globs()
  local out = {}
  for name, kind in vim.fs.dir(root()) do
    if kind == "directory" and not name:match("^%.") and not vendored[name] then
      table.insert(out, name .. "/**")
    end
  end
  table.sort(out)
  return out
end

return M
