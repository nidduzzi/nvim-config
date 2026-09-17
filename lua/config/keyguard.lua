--- Notice when a mapping is overwritten, and say who did it.
---
--- Neovim has one mechanism for this and it is rarely used: `unique = true`
--- makes `vim.keymap.set` fail with E227 when the key is already mapped. It
--- guards the moment *you* bind, which is the wrong half of the problem — a
--- plugin that loads later overwrites you silently, and nothing anywhere
--- reports it. That is how <leader>cA ended up losing to LazyVim's Source
--- Action without a word.
---
--- So the setters are wrapped. Every overwrite is recorded with both sides and
--- the file that caused it, which turns "that key stopped working" into a line
--- naming the plugin. Keys this config cares about can be watched, and those
--- say so as they are taken rather than waiting to be asked.
---
--- This has to be loaded before lazy.nvim, or the plugins that load first are
--- the ones it cannot see.

local M = {}

---@class keyguard.Overwrite
---@field mode string
---@field lhs string
---@field before string
---@field after string
---@field who string
---@field mine boolean  this config made the change, rather than a plugin
---@field buffer boolean

---@type keyguard.Overwrite[]
M.overwrites = {}

--- Keys worth interrupting for: this config's own, where being overwritten
--- means a feature quietly stopped existing.
---@type table<string, boolean>
M.watched = {}

--- Describe a mapping the way a person would recognise it.
---@param map table|nil
---@return string
local function summarise(map)
  if not map or vim.tbl_isempty(map) then
    return ""
  end
  if map.desc and map.desc ~= "" then
    return map.desc
  end
  if map.rhs and map.rhs ~= "" then
    return map.rhs
  end
  return map.callback and "<callback>" or ""
end

--- This config's own directory, with symlinks resolved: the trial runs from a
--- worktree reached through a link, so comparing the unresolved paths says the
--- config is a stranger to itself.
local config_root = vim.uv.fs_realpath(vim.fn.stdpath("config")) or vim.fn.stdpath("config")

--- Where the call came from, skipping this file and the wrapper itself.
---@return string label
---@return boolean mine  true when this config made the call
local function caller()
  for level = 3, 8 do
    local info = debug.getinfo(level, "Sl")
    if not info then
      break
    end

    local source = (info.source or ""):gsub("^@", "")
    if source ~= "" and not source:find("keyguard", 1, true) and not source:find("^%[") then
      -- A plugin's own path is the useful part: .../lazy/which-key.nvim/...
      local plugin = source:match("/lazy/([^/]+)/")
      if plugin then
        return ("%s (%s:%d)"):format(plugin, vim.fn.fnamemodify(source, ":t"), info.currentline or 0), false
      end

      local real = vim.uv.fs_realpath(source) or source
      local mine = real:sub(1, #config_root) == config_root
      return ("%s:%d"):format(vim.fn.fnamemodify(source, ":~:."), info.currentline or 0), mine
    end
  end
  return "unknown", false
end

--- True while the Lua helper is running, so the API call it makes underneath
--- is not counted as a second overwrite of the same key.
local inside_helper = false

--- Record one overwrite, and speak up when it takes a watched key.
---@param mode string
---@param lhs string
---@param before table|nil
---@param buffer boolean
local function record(mode, lhs, before, buffer)
  local previous = summarise(before)
  if previous == "" then
    return
  end

  -- The caller has to be read here, while the stack that made the call still
  -- exists. Reading it inside the scheduled part below answers "unknown"
  -- every time, which is what the first version of this did.
  local who, mine = caller()

  -- What the key became is only knowable after the set has happened.
  vim.schedule(function()
    local now = vim.fn.maparg(lhs, mode, false, true)
    local after = summarise(now)

    -- Replacing a mapping with the identical one is not an overwrite.
    if after == previous or after == "" then
      return
    end

    local entry = {
      mode = mode,
      -- The lhs arrives as it was written, "<leader>sg". keytrans is for
      -- termcodes read back out of nvim_get_keymap; running it on this escapes
      -- the angle bracket to "<lt>leader>sg", which then matches nothing in
      -- the watch list and turns the warning off silently.
      lhs = lhs,
      before = previous,
      after = after,
      who = who,
      mine = mine,
      buffer = buffer,
    }
    table.insert(M.overwrites, entry)

    -- A key this config takes on purpose is not the fault being watched for.
    -- The watch list names the keys this config owns, so its own deliberate
    -- overwrite of <leader>? matched every startup and cried wolf. Only a
    -- third party taking one of these keys is news.
    if M.watched[mode .. entry.lhs] and not mine then
      vim.notify(
        ("%s was %s\nnow %s\ntaken by %s"):format(entry.lhs, entry.before, entry.after, entry.who),
        vim.log.levels.WARN,
        { title = "A key this config uses was overwritten" }
      )
    end
  end)
end

--- Start watching. Call before lazy.nvim loads anything.
function M.setup()
  local set = vim.keymap.set

  ---@diagnostic disable-next-line: duplicate-set-field
  vim.keymap.set = function(mode, lhs, rhs, opts)
    local modes = type(mode) == "table" and mode or { mode }
    local buffer = type(opts) == "table" and opts.buffer ~= nil

    for _, one in ipairs(modes) do
      -- maparg answers for the current buffer, which is what the key will do.
      local before = vim.fn.maparg(lhs, one, false, true)
      if before and not vim.tbl_isempty(before) then
        record(one, lhs, before, buffer)
      end
    end

    inside_helper = true
    local ok, result = pcall(set, mode, lhs, rhs, opts)
    inside_helper = false

    if not ok then
      error(result, 0)
    end
    return result
  end

  -- Plugins that skip the Lua helper and call the API directly.
  for _, name in ipairs({ "nvim_set_keymap", "nvim_buf_set_keymap" }) do
    local original = vim.api[name]
    local is_buffer = name == "nvim_buf_set_keymap"

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api[name] = function(...)
      -- vim.keymap.set calls this underneath; counting both would report every
      -- overwrite twice.
      if not inside_helper then
        local args = { ... }
        local mode = is_buffer and args[2] or args[1]
        local lhs = is_buffer and args[3] or args[2]

        local before = vim.fn.maparg(lhs, mode, false, true)
        if before and not vim.tbl_isempty(before) then
          record(mode, lhs, before, is_buffer)
        end
      end

      return original(...)
    end
  end
end

--- Watch a key, so being overwritten is reported as it happens.
---@param mode string
---@param lhs string
function M.watch(mode, lhs)
  M.watched[mode .. lhs] = true
end

--- Bind a key that must not already be taken.
---
--- This is Neovim's own `unique`, which errors rather than overwriting. Use it
--- for a key that would be wrong to share, and handle the refusal: the error
--- says what to rename, which is better than two features fighting.
---@param mode string|string[]
---@param lhs string
---@param rhs string|function
---@param opts? table
---@return boolean bound
function M.set_unique(mode, lhs, rhs, opts)
  opts = vim.tbl_extend("force", opts or {}, { unique = true })
  local ok, err = pcall(vim.keymap.set, mode, lhs, rhs, opts)

  if not ok then
    vim.notify(
      ("%s is already taken, so it was left alone.\n\n%s"):format(lhs, err),
      vim.log.levels.WARN,
      { title = "Key not bound" }
    )
  end

  return ok
end

return M
