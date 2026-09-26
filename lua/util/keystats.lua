-- Counts how often each of your mappings is used, so the ones you press most
-- can be moved to shorter keys. `:KeyStats` shows the report.
--
-- What it stores, and only this: the mode, the mapping's left-hand side (say
-- `<Space>gw`), its description and a count, in stdpath("state")/keystats.json.
-- A key sequence is stored only when it is exactly the lhs of a mapping that
-- exists; anything else -- text you type, search patterns, commands, keys
-- that are not a mapping -- is dropped without being kept anywhere. Insert,
-- replace, command-line and terminal keys are not looked at at all. Nothing
-- is sent anywhere and nothing is run. `vim.g.keystats = false` turns it off.
--
-- It starts on UIEnter, so a headless editor (the specs, the harness's
-- headless runs) records nothing.

local M = {}

local FILE = "keystats.json"
local FLUSH_MS = 60 * 1000
local CACHE_MS = 5000

-- nvim_get_mode() -> the keymap mode whose mappings apply to typed keys, or
-- nil where keys are text or a command line and must not be looked at.
---@param mode string
---@return string|nil
local function map_mode(mode)
  local c = mode:sub(1, 1)
  if mode:sub(1, 2) == "no" then
    return "o"
  elseif mode == "n" then
    return "n"
  elseif c == "v" or c == "V" or c == "\22" then
    return "x"
  elseif c == "s" or c == "S" or c == "\19" then
    return "s"
  end
  return nil
end

--- Split a keytrans()-normalized string into keys: `<C-N>`, `<Space>`, `g`.
---@param s string
---@return string[]
function M.tokens(s)
  local out, i = {}, 1
  while i <= #s do
    local special = s:match("^<[^<>]+>", i)
    if special then
      out[#out + 1] = special
      i = i + #special
    else
      local len = vim.str_utf_end(s, i) + 1
      out[#out + 1] = s:sub(i, i + len - 1)
      i = i + len
    end
  end
  return out
end

---@param lhs string as nvim_get_keymap reports it
---@return string
local function normalize(lhs)
  return vim.fn.keytrans(vim.api.nvim_replace_termcodes(lhs, true, true, true))
end

---@class keystats.Maps
---@field lhs table<string, string> normalized lhs -> desc ("" when none)
---@field prefix table<string, true> every proper prefix of every lhs

---@param maps table[] from nvim_get_keymap / nvim_buf_get_keymap
---@param into? keystats.Maps
---@return keystats.Maps
function M.index(maps, into)
  into = into or { lhs = {}, prefix = {} }
  for _, map in ipairs(maps) do
    local raw = map.lhs or ""
    -- <Plug> and script-local maps cannot be typed, and which-key's trigger
    -- maps only stand in for the real mapping it replays afterwards.
    if raw ~= "" and not raw:find("<Plug>", 1, true) and not raw:find("<SNR>", 1, true) and not (map.desc or ""):find("^which%-key%-trigger") then
      local lhs = normalize(raw)
      into.lhs[lhs] = map.desc or into.lhs[lhs] or ""
      local seq = ""
      local toks = M.tokens(lhs)
      for i = 1, #toks - 1 do
        seq = seq .. toks[i]
        into.prefix[seq] = true
      end
    end
  end
  return into
end

--- The sequence matcher, separate from on_key so it can be tested with a
--- made-up set of mappings.
---
--- `lookup(mode)` returns the keystats.Maps for that mode. `feed` takes one
--- typed key and returns the mappings it completed, as { mode, lhs }.
---@param lookup fun(mode: string): keystats.Maps
function M.matcher(lookup)
  local self = { pending = "", mode = nil }

  local function done(out)
    if self.pending ~= "" and self.mode then
      local maps = lookup(self.mode)
      if maps.lhs[self.pending] then
        out[#out + 1] = { self.mode, self.pending, maps.lhs[self.pending] }
      end
    end
    self.pending, self.mode = "", nil
  end

  --- Count what is pending if it is a whole mapping (the timeout ran out, or
  --- the mode changed).
  function self.flush()
    local out = {}
    done(out)
    return out
  end

  ---@param mode string keymap mode
  ---@param key string one keytrans()-normalized key
  function self.feed(mode, key)
    local out = {}
    if self.mode and self.mode ~= mode then
      done(out)
    end

    local function start(k)
      local maps = lookup(mode)
      if maps.prefix[k] then
        self.pending, self.mode = k, mode
      elseif maps.lhs[k] then
        out[#out + 1] = { mode, k, maps.lhs[k] }
      end
    end

    if self.pending == "" then
      start(key)
      return out
    end

    local seq = self.pending .. key
    local maps = lookup(mode)
    if maps.prefix[seq] then
      self.pending = seq
    elseif maps.lhs[seq] then
      out[#out + 1] = { mode, seq, maps.lhs[seq] }
      self.pending, self.mode = "", nil
    elseif maps.lhs[self.pending] then
      -- Not an extension of a whole mapping: that mapping was the one used,
      -- and this key starts over on its own.
      done(out)
      start(key)
    else
      -- Not an extension of something that was only ever a prefix: Vim runs
      -- these keys as its own commands (g then g is gg), so neither counts.
      self.pending, self.mode = "", nil
    end
    return out
  end

  --- Forget what is pending without counting it.
  function self.drop()
    self.pending, self.mode = "", nil
  end

  function self.waiting()
    return self.pending ~= ""
  end

  return self
end

-- Counting ---------------------------------------------------------------------

---@type table<string, table<string, { count: integer, desc: string }>>
local delta = {}
local dirty = false

---@param hits table[]
function M.record(hits)
  for _, hit in ipairs(hits) do
    local mode, lhs, desc = hit[1], hit[2], hit[3]
    delta[mode] = delta[mode] or {}
    local entry = delta[mode][lhs] or { count = 0, desc = desc or "" }
    entry.count = entry.count + 1
    if desc and desc ~= "" then
      entry.desc = desc
    end
    delta[mode][lhs] = entry
    dirty = true
  end
end

---@return string
function M.path()
  return vim.fs.joinpath(vim.fn.stdpath("state"), FILE)
end

---@param path string
---@return table
local function read(path)
  local f = io.open(path, "r")
  if not f then
    return { version = 1, since = os.date("%Y-%m-%d"), counts = {} }
  end
  local text = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" or type(data.counts) ~= "table" then
    -- Kept, not deleted, in case it is worth reading by hand.
    vim.uv.fs_rename(path, ("%s.corrupt-%d"):format(path, os.time()))
    return { version = 1, since = os.date("%Y-%m-%d"), counts = {} }
  end
  return data
end

--- Add this editor's counts to the file. Read, add, write to a temporary file
--- and rename it over: two editors writing add up rather than one replacing
--- the other's counts, except in the moment between one's read and rename.
---@param path? string
function M.flush(path)
  if not dirty then
    return
  end
  path = path or M.path()
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local data = read(path)
  for mode, maps in pairs(delta) do
    data.counts[mode] = data.counts[mode] or {}
    for lhs, entry in pairs(maps) do
      local have = data.counts[mode][lhs] or { count = 0, desc = "" }
      have.count = (tonumber(have.count) or 0) + entry.count
      if entry.desc ~= "" then
        have.desc = entry.desc
      end
      data.counts[mode][lhs] = have
    end
  end
  local tmp = ("%s.%d.tmp"):format(path, vim.fn.getpid())
  local f = assert(io.open(tmp, "w"))
  f:write(vim.json.encode(data))
  f:close()
  -- vim.uv, not os.rename: on Windows os.rename refuses to replace an
  -- existing file ("File exists"), so every flush after the first failed.
  -- libuv renames over the target on every platform.
  local ok, err = vim.uv.fs_rename(tmp, path)
  if not ok then
    os.remove(tmp)
    error(err)
  end
  delta, dirty = {}, false
end

---@param path? string
---@return table
function M.load(path)
  return read(path or M.path())
end

--- For the specs: forget what has not been written.
function M._reset_delta()
  delta, dirty = {}, false
end

-- Wiring -----------------------------------------------------------------------

local cache = { global = {}, buf = {} }

---@param mode string
---@return keystats.Maps
local function lookup(mode)
  local now = vim.uv.now()
  local g = cache.global[mode]
  if not g or now - g.at > CACHE_MS then
    g = { at = now, maps = M.index(vim.api.nvim_get_keymap(mode)) }
    cache.global[mode] = g
  end
  local buf = vim.api.nvim_get_current_buf()
  cache.buf[buf] = cache.buf[buf] or {}
  local b = cache.buf[buf][mode]
  if not b or now - b.at > CACHE_MS or b.global ~= g then
    local merged = { lhs = setmetatable({}, { __index = g.maps.lhs }), prefix = setmetatable({}, { __index = g.maps.prefix }) }
    b = { at = now, global = g, maps = M.index(vim.api.nvim_buf_get_keymap(buf, mode), merged) }
    cache.buf[buf][mode] = b
  end
  return b.maps
end

local started = false

function M.start()
  if started or vim.g.keystats == false or #vim.api.nvim_list_uis() == 0 then
    return
  end
  started = true

  local matcher = M.matcher(lookup)
  local timer = assert(vim.uv.new_timer())
  local ns = vim.api.nvim_create_namespace("keystats")

  local function on_key(typed)
    local mode = map_mode(vim.api.nvim_get_mode().mode)
    if not mode then
      matcher.flush()
      return
    end
    for _, key in ipairs(M.tokens(vim.fn.keytrans(typed))) do
      M.record(matcher.feed(mode, key))
    end
    timer:stop()
    if matcher.waiting() then
      -- After timeoutlen Vim stops waiting: a whole mapping runs, a prefix
      -- is given up on.
      timer:start(
        vim.o.timeoutlen + 50,
        0,
        vim.schedule_wrap(function()
          M.record(matcher.flush())
        end)
      )
    end
  end

  vim.on_key(function(_, typed)
    -- Keys that came from a mapping's rhs, a macro or feedkeys are not presses.
    if not typed or typed == "" or vim.fn.reg_executing() ~= "" then
      return
    end
    -- which-key reads the keys after a trigger itself, then replays the whole
    -- sequence as typed once it knows what it is. Counting both would count
    -- every leader mapping twice, so the keys it is still collecting are
    -- skipped and the replay is what gets counted.
    local wk = package.loaded["which-key.state"]
    if wk and wk.state ~= nil then
      matcher.drop()
      return
    end
    -- Counting must never get in the way of typing.
    pcall(on_key, typed)
  end, ns)

  local group = vim.api.nvim_create_augroup("dotfiles_keystats", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "LspAttach", "LspDetach" }, {
    group = group,
    callback = function(ev)
      if cache.buf[ev.buf] then
        cache.buf[ev.buf] = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      cache.buf[ev.buf] = nil
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.record(matcher.flush())
      pcall(M.flush)
    end,
  })
  local every = assert(vim.uv.new_timer())
  every:start(
    FLUSH_MS,
    FLUSH_MS,
    vim.schedule_wrap(function()
      pcall(M.flush)
    end)
  )
end

-- Report -----------------------------------------------------------------------

---@param lhs string
---@return string
local function shown(lhs)
  local leader = vim.g.mapleader and normalize(vim.g.mapleader) or nil
  if leader and leader ~= "" and vim.startswith(lhs, leader) then
    return "<leader>" .. lhs:sub(#leader + 1)
  end
  return lhs
end

--- The report's lines, from saved counts plus the current mappings.
---@param data table
---@param current table<string, keystats.Maps> mode -> maps now defined
---@return string[]
function M.report(data, current)
  local rows = {}
  for mode, maps in pairs(data.counts or {}) do
    for lhs, entry in pairs(maps) do
      local len = #M.tokens(lhs)
      rows[#rows + 1] = {
        mode = mode,
        lhs = lhs,
        desc = entry.desc or "",
        count = tonumber(entry.count) or 0,
        len = len,
        extra = (tonumber(entry.count) or 0) * (len - 1),
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.lhs < b.lhs
  end)

  local lines = {
    ("Key usage since %s  (%s)"):format(data.since or "?", vim.fn.fnamemodify(M.path(), ":~")),
    "keys = keystrokes per press; extra = presses x (keys - 1)",
    "",
    "Most used",
    ("  %-4s %-22s %5s %5s %6s  %s"):format("mode", "keys", "keys", "count", "extra", "what"),
  }
  local function row(r)
    return ("  %-4s %-22s %5d %5d %6d  %s"):format(r.mode, shown(r.lhs), r.len, r.count, r.extra, r.desc)
  end
  for i = 1, math.min(#rows, 40) do
    lines[#lines + 1] = row(rows[i])
  end
  if #rows == 0 then
    lines[#lines + 1] = "  nothing recorded yet"
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Used often but deep (3+ keys, by extra keystrokes)"
  local deep = vim.tbl_filter(function(r)
    return r.len >= 3 and r.count >= 5
  end, rows)
  table.sort(deep, function(a, b)
    return a.extra > b.extra
  end)
  for i = 1, math.min(#deep, 20) do
    lines[#lines + 1] = row(deep[i])
  end
  if #deep == 0 then
    lines[#lines + 1] = "  none yet (needs 5+ presses)"
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Mapped but never used (described mappings, by prefix)"
  local groups, names = {}, {}
  for mode, maps in pairs(current) do
    for lhs, desc in pairs(maps.lhs) do
      local used = data.counts[mode] and data.counts[mode][lhs]
      -- Neovim's own defaults describe themselves as ":help ..."; they are
      -- not yours to move.
      if desc ~= "" and not used and not desc:find("^:help ") and desc ~= "which_key_ignore" then
        local toks = M.tokens(lhs)
        local prefix = shown(table.concat(toks, "", 1, math.min(2, #toks)))
        if not groups[prefix] then
          groups[prefix] = {}
          names[#names + 1] = prefix
        end
        table.insert(groups[prefix], ("%s %s  %s"):format(mode, shown(lhs), desc))
      end
    end
  end
  table.sort(names)
  for _, prefix in ipairs(names) do
    table.sort(groups[prefix])
    lines[#lines + 1] = ("  %s (%d)"):format(prefix, #groups[prefix])
    for _, item in ipairs(groups[prefix]) do
      lines[#lines + 1] = "    " .. item
    end
  end
  return lines
end

function M.show()
  pcall(M.flush)
  local current = {}
  local buf = vim.api.nvim_get_current_buf()
  for _, mode in ipairs({ "n", "x", "o", "s" }) do
    current[mode] = M.index(vim.api.nvim_buf_get_keymap(buf, mode), M.index(vim.api.nvim_get_keymap(mode)))
  end
  local lines = M.report(M.load(), current)
  if not started then
    table.insert(lines, 1, "Recording is off (vim.g.keystats = false, or no UI).")
  end
  vim.cmd("tabnew")
  buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, "keystats://report")
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "Close the report" })
end

function M.reset()
  if vim.fn.confirm("Forget every recorded key count?", "&Forget\n&Keep", 2) ~= 1 then
    return
  end
  M._reset_delta()
  os.remove(M.path())
  vim.notify("Key counts cleared.", vim.log.levels.INFO, { title = "KeyStats" })
end

function M.setup()
  vim.api.nvim_create_user_command("KeyStats", function(opts)
    if opts.args == "reset" then
      M.reset()
    else
      M.show()
    end
  end, {
    nargs = "?",
    complete = function()
      return { "reset" }
    end,
    desc = "How often each mapping is used, and which are deep or unused",
  })
  if vim.g.keystats == false then
    return
  end
  if #vim.api.nvim_list_uis() > 0 then
    M.start()
  else
    vim.api.nvim_create_autocmd("UIEnter", { once = true, callback = M.start })
  end
end

return M
