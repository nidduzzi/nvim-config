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

--- Is this buffer a view of something rather than a file?
---
--- Asked of the buffer rather than of a list of names. This was a list --- of
--- checkhealth, help, lazy, man, mason, noice, qf, the notification history
--- and trouble --- and a list only covers what someone thought of: the
--- debugger UI's six panels and a terminal in a split were all invisible to
--- it, so the key that closes whatever is open did nothing in front of them.
---
--- Every one of those windows is a buffer with a buftype. A file has none.
---@param buf integer
---@return boolean
local function is_overlay(buf)
  return vim.bo[buf].buftype ~= ""
end

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
  if is_overlay(vim.api.nvim_win_get_buf(here)) then
    return here
  end

  local found = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_overlay(vim.api.nvim_win_get_buf(win)) then
      found[#found + 1] = win
    end
  end

  table.sort(found, function(a, b)
    return a > b
  end)
  return found[1]
end

--- Views made of several windows, which close as a whole or not at all.
---
--- Closing one window of a debugger UI leaves the other five, and closing one
--- window of a diff view leaves the tab, the file panel and the diff. Both
--- ship a command that puts the editor back where it was, and that is the
--- only thing that ends them.
---@type { filetype: string, close: fun() }[]
local composite_views = {
  {
    filetype = "^Diffview",
    close = function()
      vim.cmd.DiffviewClose()
    end,
  },
  {
    filetype = "^dap",
    close = function()
      require("dapui").close()
    end,
  },
}

--- How to close the composite view on screen, if one is.
---@return fun()|nil
local function composite_view()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local filetype = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    for _, view in ipairs(composite_views) do
      if filetype:match(view.filetype) then
        return view.close
      end
    end
  end
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

  -- A view made of several windows closes as a whole.
  local close_composite = composite_view()
  if close_composite then
    pcall(close_composite)
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
