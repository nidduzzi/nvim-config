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

--- What a key does globally, ignoring any buffer-local mapping over it.
---
--- `vim.fn.maparg` is buffer-aware and answers with the buffer-local mapping
--- when one exists, which makes it the wrong witness twice. It cannot tell a
--- shadow from a replacement, and while a shadow is in place it reports the
--- same answer before and after a global set — so a plugin replacing a global
--- key while you sit in a diff view looked like no change at all.
---@param mode string
---@param lhs string
---@return string
local function global_map(mode, lhs)
  local wanted = vim.fn.keytrans(vim.api.nvim_replace_termcodes(lhs, true, true, true))
  for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
    if vim.fn.keytrans(vim.api.nvim_replace_termcodes(map.lhs, true, true, true)) == wanted then
      return summarise(map)
    end
  end
  return ""
end

--- Whether the global mapping for this key is still what it was.
---@param mode string
---@param lhs string
---@param previous string
---@return boolean
local function still_global(mode, lhs, previous)
  return global_map(mode, lhs) == previous
end

--- Record one overwrite, and speak up when it takes a watched key.
---@param mode string
---@param lhs string
---@param before table|nil
---@param buffer boolean
---@param mode string
---@param lhs string
---@param before table|string|nil
---@param buffer integer|nil the buffer a buffer-local set applied to
local function record(mode, lhs, before, buffer)
  local previous = type(before) == "string" and before or summarise(before)
  if previous == "" then
    return
  end

  -- The caller has to be read here, while the stack that made the call still
  -- exists. Reading it inside the scheduled part below answers "unknown"
  -- every time, which is what the first version of this did.
  local who, mine = caller()

  -- What the key became is only knowable after the set has happened. A global
  -- set is judged against the global table, for the reason in global_map.
  vim.schedule(function()
    -- Read a buffer-local mapping in the buffer it was set for. This runs on
    -- the next tick, by which time the current buffer may be something else
    -- entirely — and then maparg answers about the wrong buffer, finds the
    -- global mapping unchanged, and concludes nothing happened.
    local after
    if buffer then
      if not vim.api.nvim_buf_is_valid(buffer) then
        return
      end
      vim.api.nvim_buf_call(buffer, function()
        after = summarise(vim.fn.maparg(lhs, mode, false, true))
      end)
    else
      after = global_map(mode, lhs)
    end

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

    -- A buffer-local mapping shadows the global one inside that buffer and
    -- leaves it intact everywhere else. That is not the loss this watches for,
    -- and reporting it as one was wrong twice over: `maparg` answers with the
    -- buffer-local mapping when there is one, so the "now" it read was the
    -- shadow while the global key it claimed had been taken was still bound.
    --
    -- Diffview is the honest case. It binds <leader>gd, <leader>gm and
    -- <leader>e inside its own two windows, from file.lua and panel.lua, so
    -- opening a diff produced six warnings about three keys that all still
    -- worked the moment you left the diff.
    --
    -- So a shadow is only news when the global mapping is gone as well. The
    -- global table is asked directly, because `maparg` cannot be.
    if entry.buffer and still_global(mode, lhs, previous) then
      entry.shadow = true
      return
    end

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

    -- Which buffer, not merely whether. `buffer = true` and `buffer = 0` both
    -- mean the current one, and it has to be resolved now rather than on the
    -- next tick.
    local buffer = nil
    if type(opts) == "table" and opts.buffer ~= nil and opts.buffer ~= false then
      buffer = (opts.buffer == true or opts.buffer == 0) and vim.api.nvim_get_current_buf() or opts.buffer
    end

    for _, one in ipairs(modes) do
      -- A buffer-local set is judged by what the key does in this buffer,
      -- which is what maparg answers. A global set is judged by the global
      -- table, which is the only thing a global set can actually replace.
      if buffer then
        local before
        vim.api.nvim_buf_call(buffer, function()
          before = vim.fn.maparg(lhs, one, false, true)
        end)
        if before and not vim.tbl_isempty(before) then
          record(one, lhs, before, buffer)
        end
      else
        local before = global_map(one, lhs)
        if before ~= "" then
          record(one, lhs, before, false)
        end
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
        -- nvim_buf_set_keymap takes the buffer first, and 0 means this one.
        local buffer = nil
        if is_buffer then
          buffer = args[1] == 0 and vim.api.nvim_get_current_buf() or args[1]
        end

        local before
        if buffer then
          if vim.api.nvim_buf_is_valid(buffer) then
            vim.api.nvim_buf_call(buffer, function()
              before = vim.fn.maparg(lhs, mode, false, true)
            end)
          end
        else
          before = vim.fn.maparg(lhs, mode, false, true)
        end

        if before and not vim.tbl_isempty(before) then
          record(mode, lhs, before, buffer)
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
