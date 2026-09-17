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

--- Rank a definition above the places that merely mention it.
---
--- Grepping a symbol in a real project buries the declaration: a name is
--- written once and used fifty times, so the uses win on weight of numbers. In
--- label-studio, `Project` matched 400 lines, 98 of them inside tests.
---
--- The first version of this carried a list of patterns — `^%s*def%s+`,
--- `^%s*class%s+`, twenty of them, plus eleven more for test paths. That is the
--- same hand-written approach that, applied to keymaps earlier, silently missed
--- two of the six keys it was meant to cover. A list like that is wrong for
--- every language nobody thought of, and nobody maintains it.
---
--- Treesitter already knows. Every grammar ships a `locals.scm` written by the
--- people who wrote the grammar, and it captures `@local.definition.*` on
--- exactly the nodes that declare something. Asking it costs 1.1ms per file,
--- measured over label-studio, and the answer is cached.
---
--- Languages whose grammar ships no locals query — rust and go, here — get no
--- opinion rather than a guess. Silence is the honest answer.

--- Definition lines per file, keyed by path and modification time so an edited
--- file is re-read and an untouched one is not.
---@type table<string, { mtime: integer, lines: table<integer, boolean> }>
local definition_cache = {}

--- How long one ranking pass may spend parsing, in milliseconds. A grep over a
--- large repository can touch hundreds of files; beyond this budget the rest
--- are ranked without an opinion rather than freezing the picker.
M.parse_budget_ms = 120

local spent_ms = 0

--- Reset the parsing budget. Called when a picker starts a new search.
function M.begin_pass()
  spent_ms = 0
end

--- Forget what treesitter said about every file.
function M.forget_definitions()
  definition_cache = {}
end

--- The lines of a file on which something is declared, according to that
--- language's own locals query.
---@param path string
---@return table<integer, boolean>|nil nil when the language cannot say
local function definition_lines(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end

  local cached = definition_cache[path]
  if cached and cached.mtime == stat.mtime.sec then
    return cached.lines
  end

  if spent_ms >= M.parse_budget_ms then
    return nil
  end
  local started = vim.uv.hrtime()

  local filetype = vim.filetype.match({ filename = path })
  local lang = filetype and vim.treesitter.language.get_lang(filetype)
  if not lang then
    return nil
  end

  local ok_query, query = pcall(vim.treesitter.query.get, lang, "locals")
  if not ok_query or not query then
    -- The grammar ships no locals query. Nothing to say about this language.
    return nil
  end

  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local source = fd:read("*a")
  fd:close()

  local ok_parser, parser = pcall(vim.treesitter.get_string_parser, source, lang)
  if not ok_parser or not parser then
    return nil
  end

  local ok_tree, trees = pcall(parser.parse, parser)
  if not ok_tree or not trees or not trees[1] then
    return nil
  end

  local lines = {}
  for id, node in query:iter_captures(trees[1]:root(), source) do
    if query.captures[id]:match("^local%.definition") then
      local row = node:range()
      lines[row + 1] = true
    end
  end

  spent_ms = spent_ms + (vim.uv.hrtime() - started) / 1e6
  definition_cache[path] = { mtime = stat.mtime.sec, lines = lines }
  return lines
end

--- Promote a hit that lands on a declaration.
---
--- score_mul scales rather than filters, so a call site still surfaces when it
--- is the only thing that matches, and a definition inside a test file is
--- ranked on being a definition, which is what it is.
---@param item table
---@return table
function M.rank_item(item)
  local path = item.file
  local lnum = item.pos and item.pos[1] or item.lnum
  if not path or not lnum then
    return item
  end

  -- Assign rather than multiply, and only once. A transform may be run more
  -- than once on the same item, and `score_mul = score_mul * 2.5` compounds
  -- every time it is: a second pass turned 2.5 into 6.2, and nothing bounds
  -- that.
  if item.ranked_definition == nil then
    local lines = definition_lines(path)
    item.ranked_definition = (lines and lines[lnum]) and true or false
  end

  if item.ranked_definition then
    item.score_mul = 2.5
  end

  return item
end

--- Search without regard to case, and back again.
---
--- ripgrep is given --smart-case, so a lowercase query already ignores case
--- and any capital makes it exact. That is the right default and the wrong one
--- exactly when you typed a capital and meant a name: searching `Project` will
--- not find `project`. This forces the insensitive read without retyping.
---@param picker table
function M.toggle_case(picker)
  local args = vim.deepcopy(picker.opts.args or {})
  local insensitive = false

  for index, arg in ipairs(args) do
    if arg == "--ignore-case" then
      table.remove(args, index)
      insensitive = true
      break
    end
  end

  if not insensitive then
    table.insert(args, "--ignore-case")
  end

  picker.opts.args = args
  picker.title = ("Grep (%s%s)"):format(
    picker.opts.search_preset or "code",
    insensitive and "" or ", any case"
  )
  picker:find({ refresh = true })

  vim.notify(
    insensitive and "Case matters again (smart-case)." or "Ignoring case.",
    vim.log.levels.INFO,
    { title = "Search" }
  )
end

--- Say what can be pressed in here, since a picker's own keys reach neither
--- which-key nor the capability list.
---@param picker table
function M.show_keys(picker)
  local lines = {
    "# Inside this picker",
    "",
    "  a-s    next search scope (code, everything, documentation)",
    "  a-S    choose a scope from the list",
    "  a-e    only these file extensions",
    "  a-G    only this path glob",
    "  a-r    regex, or a plain string",
    "  a-c    ignore case (smart-case is the default: a capital means exact)",
    "  a-h    include hidden files",
    "  a-i    include ignored files",
    "  c-g    live search, or filter what is already found",
    "  c-t    send these results to Trouble, grouped by file",
    "  c-f    scroll the preview",
    "",
    "Ranking: a hit on a declaration ranks higher, per treesitter.",
    "The title shows the scope in force.",
  }

  local _ = picker
  require("util.agent.panel").show("Picker keys", table.concat(lines, "\n"))
end

--- Options to open a grep picker with a preset already applied.
---@param name string
---@return table
function M.opts(name)
  local preset = M.preset(name) or M.presets()[1]
  M.begin_pass()
  return {
    args = preset.args,
    search_preset = preset.name,
    title = "Grep (" .. preset.name .. ")",
    transform = M.rank_item,
  }
end

return M
