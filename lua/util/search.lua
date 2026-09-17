--- Search filters for the picker.
---
--- The problem this solves: in an openspec repository most text lives in
--- `openspec/` and `docs/`, so grepping for a symbol buries the two lines of
--- code you wanted under a dozen paragraphs of prose. Excluding prose outright
--- is wrong too, because sometimes the prose is exactly what you are looking
--- for.
---
--- So the filter is a mode you switch while the picker is open, not a decision
--- you make before it. Each preset is a set of ripgrep globs. The active preset
--- shows in the picker title, and `<a-d>` cycles to the next one and re-runs
--- the search against the results already on screen.
---
--- A project can define its own idea of what counts as documentation in its
--- `.nvim.lua`:
---
---     vim.g.search_filters = {
---       docs = { "adr/**", "*.rst" },
---     }
---
--- and can add presets of its own:
---
---     vim.g.search_filters = {
---       presets = {
---         { name = "api only", globs = { "src/api/**" } },
---       },
---     }

local M = {}

--- Globs treated as documentation when no project overrides them.
---
--- Markdown alone is not enough. Checked against real repositories: in Flask,
--- searching for "blueprint" hits 45 files, 17 of them in docs/ and written in
--- reStructuredText, with a changelog in CHANGES.rst at the root. Excluding
--- only docs/ and markdown leaves 28; adding the prose formats leaves 27 and
--- no code.
M.default_docs = {
  "openspec/**",
  "docs/**",
  "*.md",
  "*.mdx",
  "*.rst",
  "*.txt",
  "*.adoc",
  "CHANGELOG*",
  "CHANGES*",
}

--- Read the project's overrides, if its `.nvim.lua` set any.
---@return { docs?: string[], presets?: table[] }
local function project_config()
  local config = vim.g.search_filters
  return type(config) == "table" and config or {}
end

---@return string[]
function M.docs_globs()
  return project_config().docs or M.default_docs
end

--- Turn a list of globs into ripgrep arguments.
---@param globs string[]
---@param exclude boolean true to exclude the globs, false to keep only them
---@return string[]
local function glob_args(globs, exclude)
  local args = {}
  for _, glob in ipairs(globs) do
    table.insert(args, "--glob=" .. (exclude and "!" or "") .. glob)
  end
  return args
end

--- The presets `<a-d>` cycles through, in order.
---
--- `code` comes first because it is the common case: you are reading code and
--- the prose is noise.
---@return table[]
function M.presets()
  local docs = M.docs_globs()

  local builtin = {
    { name = "code", desc = "everything except documentation", args = glob_args(docs, true) },
    { name = "all", desc = "no filter at all", args = {} },
    { name = "docs", desc = "documentation only", args = glob_args(docs, false) },
  }

  for _, extra in ipairs(project_config().presets or {}) do
    table.insert(builtin, {
      name = extra.name,
      desc = extra.desc or "from this project's .nvim.lua",
      args = glob_args(extra.globs or {}, extra.exclude or false),
    })
  end

  return builtin
end

---@param name string
---@return table|nil
function M.preset(name)
  for _, preset in ipairs(M.presets()) do
    if preset.name == name then
      return preset
    end
  end
end

--- Apply a preset to an open picker and search again.
---@param picker table
---@param preset table
local function apply(picker, preset)
  picker.opts.args = preset.args
  picker.opts.search_preset = preset.name
  picker.title = "Grep (" .. preset.name .. ")"
  picker:find({ refresh = true })
end

--- Move to the next preset. Bound to `<a-d>` inside the picker.
---@param picker table
function M.cycle(picker)
  local presets = M.presets()
  local current = picker.opts.search_preset or presets[1].name

  local index = 1
  for i, preset in ipairs(presets) do
    if preset.name == current then
      index = i
      break
    end
  end

  local next_preset = presets[(index % #presets) + 1]
  apply(picker, next_preset)
  vim.notify(next_preset.name .. ": " .. next_preset.desc, vim.log.levels.INFO, { title = "Search filter" })
end

--- Pick a preset from a list instead of cycling. Bound to `<a-p>`.
---@param picker table
function M.choose(picker)
  local presets = M.presets()
  local labels = {}
  for _, preset in ipairs(presets) do
    table.insert(labels, ("%-12s %s"):format(preset.name, preset.desc))
  end

  vim.ui.select(labels, { prompt = "Search filter" }, function(_, index)
    if index then
      apply(picker, presets[index])
    end
  end)
end

--- Limit the search to one or more file extensions. Bound to `<a-e>`.
---@param picker table
function M.by_extension(picker)
  -- Offer the extensions this project actually contains. Recalling that a
  -- repository is .ts and not .js is not work worth doing from memory.
  local recall = require("util.recall")
  recall.input({
    kind = "extensions",
    prompt = "Extensions (comma separated)",
    suggestions = recall.extensions(),
  }, function(input)
    if not input or input == "" then
      return
    end

    local globs = {}
    for ext in input:gmatch("[^,%s]+") do
      table.insert(globs, "*." .. ext:gsub("^%.", ""))
    end

    apply(picker, {
      name = "ext:" .. input,
      desc = "only " .. input,
      args = glob_args(globs, false),
    })
  end)
end

--- Limit the search to an arbitrary path glob. Bound to `<a-G>`.
---@param picker table
function M.by_glob(picker)
  local recall = require("util.recall")
  recall.input({
    kind = "glob",
    prompt = "Path glob (! excludes)",
    suggestions = recall.top_level_globs(),
  }, function(input)
    if not input or input == "" then
      return
    end

    local exclude = input:sub(1, 1) == "!"
    local glob = exclude and input:sub(2) or input

    apply(picker, {
      name = (exclude and "not " or "") .. glob,
      desc = "path glob",
      args = glob_args({ glob }, exclude),
    })
  end)
end

--- Options to open a grep picker with a preset already applied.
---@param name string
---@return table
function M.opts(name)
  local preset = M.preset(name) or M.presets()[1]
  return {
    args = preset.args,
    search_preset = preset.name,
    title = "Grep (" .. preset.name .. ")",
  }
end

return M
