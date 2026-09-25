-- Keeps `. and g; on your own last edit across a format.
--
-- A formatter's edit is a change like any other, so after format-on-save the
-- last-change mark and the changelist point at whatever the formatter touched
-- last -- usually line 1 (stylua, ruff's and vtsls's LSP formatting all did
-- this). Neovim refuses to set '. directly (setpos() returns -1,
-- nvim_buf_set_mark() errors, :lockmarks does not cover it), so the position
-- is put back the only way Neovim accepts: an empty edit at the old spot,
-- joined into the format's undo block. The text does not change and no undo
-- step is added.
--
-- The old spot is held in an extmark, so a formatter that adds or removes
-- lines above it (sorted imports, a blank line) moves it along.

local M = {}

local ns = vim.api.nvim_create_namespace("format_marks")

---@param buf integer
---@return integer[]|nil row (0-based), col
local function last_change(buf)
  local pos = vim.api.nvim_buf_get_mark(buf, ".")
  if pos[1] == 0 then
    return nil
  end
  return { pos[1] - 1, pos[2] }
end

--- Run fn (a format of buf) and put the last-change position back after it.
---@param buf integer
---@param fn fun()
function M.preserve(buf, fn)
  local before = last_change(buf)
  if not before then
    return fn()
  end
  local id = vim.api.nvim_buf_set_extmark(buf, ns, before[1], before[2], {})
  local ok, err = pcall(fn)

  if vim.api.nvim_buf_is_valid(buf) then
    local mark = vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, {})
    pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
    local after = last_change(buf)
    local moved = after and (after[1] ~= before[1] or after[2] ~= before[2])
    if moved and mark[1] then
      local row, col = mark[1], mark[2]
      -- A formatter that replaces the whole buffer collapses the extmark to
      -- the top; the old row is a better guess than line 1 then.
      if row == 0 and before[1] > 0 then
        row = math.min(before[1], vim.api.nvim_buf_line_count(buf) - 1)
        col = before[2]
      end
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, true)[1] or ""
      col = math.min(col, #line)
      vim.api.nvim_buf_call(buf, function()
        pcall(vim.cmd, "silent! undojoin")
        vim.api.nvim_buf_set_text(buf, row, col, row, col, { "" })
      end)
    end
  end

  if not ok then
    error(err, 0)
  end
end

--- Wrap LazyVim's format entry point: format-on-save, <leader>cf and
--- :LazyFormat all go through it, whichever formatter or LSP does the work.
function M.install()
  local format = require("lazyvim.util.format")
  if format._marks_preserved then
    return
  end
  local original = format.format
  format.format = function(opts)
    local buf = (opts and opts.buf) or vim.api.nvim_get_current_buf()
    if buf == 0 then
      buf = vim.api.nvim_get_current_buf()
    end
    return M.preserve(buf, function()
      original(opts)
    end)
  end
  format._marks_preserved = true
end

return M
