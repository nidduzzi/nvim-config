--- One key that closes whatever is open.
---
--- Before this, closing depended on what had opened: `q` in Trouble and Lazy,
--- `<Esc>` in a picker's list but not its input, `<c-c>` in some places, the
--- key that opened it in others, `:q` for a help or checkhealth buffer. Every
--- one of them is defensible on its own and the set is not learnable, and
--- getting it wrong is not harmless — `q` in a search box types a q, and
--- `<Esc>` in one leaves insert mode without closing anything.
---
--- So `<c-c>` means "back to normal, and close whatever is open" — everywhere.
---
--- It is the right key because Vim already half-does it: `<c-c>` leaves insert,
--- visual and operator-pending, and aborts the command line and the search
--- prompt. Two gaps were left, and both are fixed here.
---
--- In normal mode with something open — Trouble, help, quickfix, Lazy, a hover
--- float — it did nothing at all. Now it dismisses.
---
--- In insert mode, Vim's `<c-c>` deliberately skips InsertLeave. That is not a
--- nicety: autopairs, format-on-leave and abbreviations all hang off that
--- event, so `<c-c>` quietly behaved differently from `<Esc>`. It is mapped to
--- `<Esc>` so the two are the same key with two names.
---
--- Terminal mode is the one deliberate exception. There `<c-c>` must reach the
--- program as an interrupt — a terminal you cannot interrupt is worse than an
--- inconsistent close key — so `<a-q>` covers that case and is also bound
--- everywhere else as an alias.
---
--- Lazy was a second exception and no longer is. It binds `<c-c>` in its own
--- window to abort a running install, which is a real thing to want and not a
--- key worth stealing. Its keys live in a plain table, so abort moves to
--- `<c-x>` instead and `<c-c>` means the same thing there as everywhere else.
--- Lazy renders its own `?` help from that table, so the help shows the new
--- key without being told.
---
--- The old keys all still work. This is an addition for anyone who has not
--- memorised them, not a replacement for anyone who has.

local M = {}

--- Buffers that are a view of something rather than a file, and whose window
--- should close rather than be navigated away from.
---@type table<string, boolean>
M.overlay_filetypes = {
  ["checkhealth"] = true,
  ["help"] = true,
  ["lazy"] = true,
  ["man"] = true,
  ["mason"] = true,
  ["noice"] = true,
  ["qf"] = true,
  ["snacks_notif_history"] = true,
  ["trouble"] = true,
}

---@return integer[] floating windows, most recently opened first
local function floats()
  local found = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local config = vim.api.nvim_win_get_config(win)
    if config.relative and config.relative ~= "" then
      table.insert(found, win)
    end
  end

  -- Later windows are the ones opened later, and the topmost is the one
  -- someone means when they say "close this".
  table.sort(found, function(a, b)
    return a > b
  end)
  return found
end

--- The window showing something that is not a file, most recent first.
---@return integer|nil
function M.overlay_window()
  local here = vim.api.nvim_get_current_win()
  if M.overlay_filetypes[vim.bo.filetype] or vim.bo.buftype == "quickfix" then
    return here
  end

  local found = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if M.overlay_filetypes[vim.bo[buf].filetype] or vim.bo[buf].buftype == "quickfix" then
      found[#found + 1] = win
    end
  end

  table.sort(found, function(a, b)
    return a > b
  end)
  return found[1]
end

---@return boolean
local function in_diffview()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype:match("^Diffview") then
      return true
    end
  end
  return false
end

--- Close the most intrusive thing that is open, and nothing else.
---
--- Ordered so that the answer is never surprising: the thing covering the
--- screen goes first, and the quietest thing — a leftover search highlight —
--- goes last. Each step returns true when it did something, so one press does
--- one thing.
---@return boolean did_something
function M.dismiss()
  -- A picker sits above everything and owns the keyboard.
  local ok, pickers = pcall(function()
    return Snacks.picker.get()
  end)
  if ok and type(pickers) == "table" and #pickers > 0 then
    for _, picker in ipairs(pickers) do
      pcall(function()
        picker:close()
      end)
    end
    return true
  end

  -- The float you are in, before any other. Closing "the topmost" float is
  -- wrong the moment the cursor is inside one that is not topmost — pressing
  -- the key inside a focused hover closed a different window and left the
  -- hover exactly where it was.
  local here = vim.api.nvim_get_current_win()
  local config = vim.api.nvim_win_get_config(here)
  if config.relative and config.relative ~= "" then
    pcall(vim.api.nvim_win_close, here, true)
    return true
  end

  -- Otherwise the topmost float: hover, signature help, this configuration's
  -- own answer panel, Lazy, a notification history.
  local floating = floats()
  if #floating > 0 then
    pcall(vim.api.nvim_win_close, floating[1], true)
    return true
  end

  -- A diff view owns its whole tab, and closing one of its windows is not
  -- closing it: the tab stays, with the panel and the files it was showing.
  -- Diffview has a command for this, and it is the only thing that puts the
  -- editor back where it was.
  if in_diffview() then
    pcall(vim.cmd.DiffviewClose)
    return true
  end

  -- Then a split showing something that is not a file, whether or not the
  -- cursor is in it. Trouble and the quickfix list open without taking focus,
  -- and reading only the current buffer's filetype meant the key did nothing
  -- while a list sat in plain sight.
  local overlay = M.overlay_window()
  if overlay then
    -- Not the last window: closing that quits the editor, which is a large
    -- answer to a small key.
    if #vim.api.nvim_tabpage_list_wins(0) > 1 then
      pcall(vim.api.nvim_win_close, overlay, false)
      return true
    end
    pcall(vim.cmd.bdelete)
    return true
  end

  -- Then whatever is still on screen but not in a window of its own.
  local hidden = pcall(function()
    Snacks.notifier.hide()
  end)
  if hidden and vim.v.hlsearch == 0 then
    return true
  end

  if vim.v.hlsearch == 1 then
    vim.cmd.nohlsearch()
    return true
  end

  return false
end

--- Move a plugin's own `<c-c>` out of the way, where it has one and the key
--- can be moved without patching the plugin.
local function free_ctrl_c()
  -- lazy.nvim keeps its view's keys in a mutable table read at bind time, so
  -- this is a setting rather than a patch.
  local ok, view = pcall(require, "lazy.view.config")
  if ok and type(view) == "table" and type(view.keys) == "table" then
    if view.keys.abort == "<C-c>" then
      view.keys.abort = "<C-x>"
    end
  end
end

--- Bind it everywhere something can be open.
function M.setup()
  free_ctrl_c()

  -- Normal mode: Vim's <c-c> does nothing here, which is the gap.
  vim.keymap.set("n", "<c-c>", function()
    M.dismiss()
  end, { desc = "Back to normal, closing whatever is open" })

  -- Insert, visual, select: behave exactly as <Esc>, which fires InsertLeave
  -- and friends. Vim's own <c-c> skips them.
  vim.keymap.set({ "i", "v", "x", "s" }, "<c-c>", "<Esc>", {
    desc = "Back to normal, closing whatever is open",
  })

  -- The command line and the search prompt already abort on <c-c>. Mapping
  -- them would replace working behaviour with the same behaviour.

  -- Terminal mode keeps <c-c> for the program. <a-q> is the way out of a
  -- terminal, and is an alias for dismiss everywhere else so there is one key
  -- that is never ambiguous.
  vim.keymap.set({ "n", "i", "v", "t" }, "<a-q>", function()
    if vim.bo.buftype == "terminal" then
      vim.cmd("stopinsert")
      return
    end
    M.dismiss()
  end, { desc = "Close whatever is open (works in a terminal too)" })
end

return M
