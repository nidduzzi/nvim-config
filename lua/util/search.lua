local M = {}

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

---@return { docs?: string[], presets?: table[] }
local function project_config()
  local config = vim.g.search_filters
  return type(config) == "table" and config or {}
end

---@return string[]
function M.docs_globs()
  return project_config().docs or M.default_docs
end

---@param globs string[]
---@param exclude boolean
---@return string[]
local function glob_args(globs, exclude)
  local args = {}
  for _, glob in ipairs(globs) do
    table.insert(args, "--glob=" .. (exclude and "!" or "") .. glob)
  end
  return args
end

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

---@type { name: string, key: string, desc: string, flag: string, label: string, on: string, off: string }[]
M.toggles = {
  {
    name = "ignore_case",
    key = "<a-c>",
    desc = "Ignore case",
    flag = "--ignore-case",
    label = "any case",
    on = "Ignoring case.",
    off = "Case matters again (smart-case).",
  },
}

---@param picker table
---@return string
local function title_for(picker)
  local parts = { picker.opts.search_preset or M.presets()[1].name }
  local args = picker.opts.args or {}
  for _, toggle in ipairs(M.toggles) do
    if vim.tbl_contains(args, toggle.flag) then
      table.insert(parts, toggle.label)
    end
  end
  return "Grep (" .. table.concat(parts, ", ") .. ")"
end

---@param picker table
---@param preset table
local function apply(picker, preset)
  local toggle_flags_kept = {}
  for _, toggle in ipairs(M.toggles) do
    if vim.tbl_contains(picker.opts.args or {}, toggle.flag) then
      table.insert(toggle_flags_kept, toggle.flag)
    end
  end

  picker.opts.args = vim.list_extend(vim.deepcopy(preset.args), toggle_flags_kept)
  picker.opts.search_preset = preset.name
  picker.title = title_for(picker)
  picker:find({ refresh = true })
end

---@param picker table
---@param open_prompt fun(on_prompt_closed: fun())
local function keep_open(picker, open_prompt)
  local auto_close_before = picker.opts.auto_close
  picker.opts.auto_close = false
  open_prompt(function()
    picker.opts.auto_close = auto_close_before
    if not picker.closed then
      picker:focus()
    end
  end)
end

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

---@param picker table
function M.choose(picker)
  local presets = M.presets()
  local labels = {}
  for _, preset in ipairs(presets) do
    table.insert(labels, ("%-12s %s"):format(preset.name, preset.desc))
  end

  keep_open(picker, function(on_prompt_closed)
    vim.ui.select(labels, { prompt = "Search filter" }, function(_, index)
      if index then
        apply(picker, presets[index])
      end
      on_prompt_closed()
    end)
  end)
end

---@param picker table
function M.by_extension(picker)
  local recall = require("util.recall")
  keep_open(picker, function(on_prompt_closed)
    recall.input({
      kind = "extensions",
      prompt = "Extensions (comma separated)",
      suggestions = recall.extensions(),
      on_close = on_prompt_closed,
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
  end)
end

---@param picker table
function M.by_glob(picker)
  local recall = require("util.recall")
  keep_open(picker, function(on_prompt_closed)
    recall.input({
      kind = "glob",
      prompt = "Path glob (! excludes)",
      suggestions = recall.top_level_globs(),
      on_close = on_prompt_closed,
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
  end)
end

---@param picker table
---@param name string
function M.toggle(picker, name)
  local toggle
  for _, candidate in ipairs(M.toggles) do
    if candidate.name == name then
      toggle = candidate
      break
    end
  end
  assert(toggle, "no such search toggle: " .. name)

  local args = vim.deepcopy(picker.opts.args or {})
  local was_on = false

  for index, arg in ipairs(args) do
    if arg == toggle.flag then
      table.remove(args, index)
      was_on = true
      break
    end
  end

  if not was_on then
    table.insert(args, toggle.flag)
  end

  picker.opts.args = args
  picker.title = title_for(picker)
  picker:find({ refresh = true })

  vim.notify(was_on and toggle.off or toggle.on, vim.log.levels.INFO, { title = "Search" })
end

M.DEFINITION_SCORE_MUL = 2.5
M.DRAIN_BUDGET_MS = 120
M.DRAIN_DELAY_MS = 60

---@alias search.DeclaredNames table<string, boolean>
---@alias search.DefinitionLines table<integer, search.DeclaredNames>

---@type table<string, { mtime: integer, lines: search.DefinitionLines }>
local definitions_by_path = {}

---@param path string
---@return integer|nil
local function modified_seconds(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.mtime.sec
end

---@param path string
---@param mtime integer
---@return search.DefinitionLines|nil
function M.cached_definitions(path, mtime)
  local cached = definitions_by_path[path]
  return cached and cached.mtime == mtime and cached.lines or nil
end

---@param path string
---@return search.DefinitionLines
local function parse_definition_lines(path)
  local filetype = vim.filetype.match({ filename = path })
  local lang = filetype and vim.treesitter.language.get_lang(filetype)
  if not lang then
    return {}
  end

  local has_locals_query, locals_query = pcall(vim.treesitter.query.get, lang, "locals")
  if not has_locals_query or not locals_query then
    return {}
  end

  local file = io.open(path, "r")
  if not file then
    return {}
  end
  local source = file:read("*a")
  file:close()

  local has_parser, parser = pcall(vim.treesitter.get_string_parser, source, lang)
  if not has_parser or not parser then
    return {}
  end

  local parsed, trees = pcall(parser.parse, parser)
  if not parsed or not trees or not trees[1] then
    return {}
  end

  local lines = {}
  for capture_id, node in locals_query:iter_captures(trees[1]:root(), source) do
    if locals_query.captures[capture_id]:match("^local%.definition") then
      local row = node:range()
      local declared_name = vim.treesitter.get_node_text(node, source)
      lines[row + 1] = lines[row + 1] or {}
      lines[row + 1][declared_name] = true
    end
  end
  return lines
end

---@param path string
---@param mtime integer
---@return search.DefinitionLines
function M.parse_definitions(path, mtime)
  local lines = parse_definition_lines(path)
  definitions_by_path[path] = { mtime = mtime, lines = lines }
  return lines
end

function M.forget_definitions()
  definitions_by_path = {}
end

---@param declared_names search.DeclaredNames|nil
---@param searched string
---@return boolean
local function declares_searched_name(declared_names, searched)
  if not declared_names then
    return false
  end
  if searched == "" then
    return true
  end
  for declared_name in pairs(declared_names) do
    if declared_name:find(searched, 1, true) then
      return true
    end
  end
  return false
end

---@param item table
---@return string|nil path, integer|nil line
local function item_location(item)
  return item.file, item.pos and item.pos[1] or item.lnum
end

---@param item table
---@param lines search.DefinitionLines
---@param searched string
---@return number|nil
local function definition_score_mul(item, lines, searched)
  local _, line = item_location(item)
  return declares_searched_name(lines[line], searched) and M.DEFINITION_SCORE_MUL or nil
end

---@class search.Ranking
---@field budget_ms number
---@field delay_ms number
---@field search string|nil
---@field pending table<string, boolean>
---@field unranked table<string, boolean>
---@field draining boolean
local Ranking = {}
Ranking.__index = Ranking
M.Ranking = Ranking

---@param opts? { budget_ms?: number, delay_ms?: number }
---@return search.Ranking
function Ranking.new(opts)
  opts = opts or {}
  return setmetatable({
    budget_ms = opts.budget_ms or M.DRAIN_BUDGET_MS,
    delay_ms = opts.delay_ms or M.DRAIN_DELAY_MS,
    search = nil,
    pending = {},
    unranked = {},
    draining = false,
  }, Ranking)
end

---@param item table
---@param ctx { picker?: table, filter?: { search?: string } }
---@return table
function Ranking:rank(item, ctx)
  local searched = ctx.filter and ctx.filter.search or ""
  if searched ~= self.search then
    self.search = searched
    self.unranked = {}
  end

  local path, line = item_location(item)
  if not path or not line or self.unranked[path] then
    return item
  end

  local mtime = modified_seconds(path)
  if not mtime then
    return item
  end

  local lines = M.cached_definitions(path, mtime)
  if not lines then
    self.pending[path] = true
    self:schedule_drain(ctx.picker)
    return item
  end

  item.score_mul = definition_score_mul(item, lines, searched)
  return item
end

---@param picker table|nil
function Ranking:schedule_drain(picker)
  if self.draining or not picker then
    return
  end
  self.draining = true
  vim.defer_fn(function()
    self:drain(picker)
  end, self.delay_ms)
end

---@return table<string, boolean> parsed_paths
function Ranking:parse_pending_within_budget()
  local paths = vim.tbl_keys(self.pending)
  self.pending = {}

  local parsed_paths = {}
  local spent_ms = 0
  for _, path in ipairs(paths) do
    local mtime = modified_seconds(path)
    if mtime and spent_ms < self.budget_ms then
      local started = vim.uv.hrtime()
      M.parse_definitions(path, mtime)
      spent_ms = spent_ms + (vim.uv.hrtime() - started) / 1e6
      parsed_paths[path] = true
    elseif mtime then
      self.unranked[path] = true
    end
  end
  return parsed_paths
end

---@param picker table
---@param parsed_paths table<string, boolean>
---@return boolean changed
function Ranking:rescore(picker, parsed_paths)
  local searched = picker:filter().search or ""
  local changed = false
  for _, item in ipairs(picker.finder.items) do
    local path = item_location(item)
    local mtime = parsed_paths[path] and modified_seconds(path)
    local lines = mtime and M.cached_definitions(path, mtime)
    if lines then
      local score_mul = definition_score_mul(item, lines, searched)
      if score_mul ~= item.score_mul then
        item.score_mul = score_mul
        changed = true
      end
    end
  end
  return changed
end

---@param picker table
function Ranking:drain(picker)
  local parsed_paths = self:parse_pending_within_budget()
  self.draining = false
  if picker.closed then
    return
  end

  if self:rescore(picker, parsed_paths) then
    picker.list:set_target()
    picker.matcher.tick = picker.matcher.tick + 1
    picker.matcher:run(picker)
  end

  if next(self.pending) then
    self:schedule_drain(picker)
  end
end

---@param name? string
---@return table
function M.opts(name)
  local preset = M.preset(name or require("util.settings").get("search_preset")) or M.presets()[1]
  local ranking = Ranking.new()
  return {
    args = preset.args,
    search_preset = preset.name,
    title = "Grep (" .. preset.name .. ")",
    matcher = { sort_empty = true },
    sort = { fields = { "score:desc", "file", "idx" } },
    transform = function(item, ctx)
      return ranking:rank(item, ctx)
    end,
  }
end

return M
