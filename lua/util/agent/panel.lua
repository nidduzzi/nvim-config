--- Where answers appear: a scratch window you read and close.
---
--- Deliberately not a chat sidebar. A sidebar is a place a conversation lives,
--- and a conversation that lives somewhere becomes the thing you work in. This
--- opens, answers, and goes away on q, leaving the buffer you were typing in.
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
  height = math.min(height, math.floor(vim.o.lines * 0.6))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = math.max(height, 1),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "left",
    footer = opts.footer and (" " .. opts.footer .. " ") or nil,
    footer_pos = opts.footer and "right" or nil,
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].conceallevel = 2

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, M.close, { buffer = buf, nowait = true, desc = "Close this answer" })
  end
end

return M
