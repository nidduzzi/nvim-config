--- Where answers appear: a scratch window you read and close.
---
--- Deliberately not a chat sidebar. A sidebar is a place a conversation lives,
--- and a conversation that lives somewhere becomes the thing you work in. This
--- opens, answers, and goes away as soon as you carry on --- the first cursor
--- move, insert or buffer change closes it --- leaving you in the buffer you
--- were typing in. `<a-q>` closes it sooner, and the footer says so.
---
--- Nothing focuses it, which is the point: an answer you have to leave is an
--- answer that interrupted you. The `q` and `<Esc>` maps below are for the
--- case where you did focus it yourself.
---
--- Nothing here is ever written to a file, and the buffer is not modifiable, so
--- the only way an answer becomes code is if you type it.

local M = {}

---@type integer|nil
local win = nil

--- Close whatever is open.
function M.close()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil

  -- The autocommands that were waiting to close it have nothing left to
  -- close. Each is `once`, so the one that fired is gone, but the others are
  -- still armed and would call this again on the next keystroke.
  pcall(vim.api.nvim_clear_autocmds, { group = "agent-panel-close" })
end

--- Show text, as markdown, in a float sized to what it holds.
---@param title string
---@param text string
---@param opts? { footer?: string }
function M.show(title, text, opts)
  opts = opts or {}
  M.close()

  local lines = vim.split(vim.trim(text), "\n", { plain = true })

  local editor_width = vim.o.columns
  local width = math.min(math.max(48, math.floor(editor_width * 0.6)), 100)

  -- Wrap by hand to work out the height, since a float has to be sized before
  -- it knows how its contents fold.
  local height = 0
  for _, line in ipairs(lines) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / (width - 2)))
  end
  height = math.min(height, math.floor(vim.o.lines * 0.8))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- Opened without taking focus. Taking it broke the hint ladder outright:
  -- pressing <leader>ah again was evaluated in the panel buffer, where the
  -- position is not the code's position, so the ladder reset and rung two was
  -- rung one again. Reading an answer should not move the cursor out of the
  -- work either.
  win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = math.max(height, 1),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "left",
    -- The footer always carries the close key, whatever else it says. An
    -- overlay that does not tell you how to leave it is the thing this
    -- configuration keeps getting wrong.
    footer = (" %s "):format(opts.footer and (opts.footer .. "  ·  a-q closes") or "a-q closes"),
    footer_pos = "right",
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].conceallevel = 2

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, M.close, { buffer = buf, nowait = true, desc = "Close this answer" })
  end

  -- Nothing has focus in the panel, so nothing can press q in it. Close on the
  -- next move instead, which is what someone does when they have read it.
  --
  -- Armed a moment later, not now: opening a window fires CursorMoved itself,
  -- and a once-only autocmd would spend itself on that and close the panel
  -- before it had been read.
  local group = vim.api.nvim_create_augroup("agent-panel-close", { clear = true })
  vim.defer_fn(function()
    if not (win and vim.api.nvim_win_is_valid(win)) then
      return
    end
    vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufLeave" }, {
      group = group,
      once = true,
      callback = M.close,
    })
  end, 200)
end

return M
