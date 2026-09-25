-- Keeps `. and g; on your own last edit across a format.
--
-- A formatter's edit is a change like any other, so after format-on-save the
-- last-change mark and the changelist point at whatever the formatter touched
-- last -- usually line 1 (stylua, ruff's and vtsls's LSP formatting all did
-- this). Neovim refuses to set '. directly (setpos() returns -1,
-- nvim_buf_set_mark() errors, :lockmarks does not cover it), so the position
-- is put back the only way Neovim accepts: an empty edit at the right spot,
-- joined into the format's undo block. The text does not change and no undo
-- step is added.
--
-- Where the edit went is worked out from the text, not from an extmark: an
-- extmark inside a region the formatter replaces is pushed to the end of it,
-- and a formatter that replaces the whole buffer (many LSP servers do) leaves
-- it past the last line. Instead the buffer before and after is diffed by
-- line. Outside a changed hunk the position just shifts by the lines added or
-- removed above it. Inside one, it is found again by counting the
-- non-whitespace characters before it in the old hunk and walking the same
-- count into the new one -- formatters mostly move whitespace, so this lands
-- on the same character even when a line is split in three or re-indented,
-- and drifts only by characters the formatter really removed or added.

local M = {}

---@param a string[]
---@param b string[]
---@return integer[][] hunks {start_a, count_a, start_b, count_b}
local function diff(a, b)
  return vim.diff(table.concat(a, "\n") .. "\n", table.concat(b, "\n") .. "\n", {
    result_type = "indices",
    algorithm = "histogram",
  }) --[[@as integer[][] ]]
end

--- Where item i of `a` ends up in `b`. Returns the index, or, when item i is
--- inside a changed hunk, nil plus the hunk.
---@return integer|nil, integer[]|nil
local function through(hunks, i)
  local shift = 0
  for _, h in ipairs(hunks) do
    local sa, ca, cb = h[1], h[2], h[4]
    if ca == 0 then
      -- Items inserted after a[sa].
      if sa < i then
        shift = shift + cb
      else
        break
      end
    elseif i < sa then
      break
    elseif i >= sa + ca then
      shift = shift + cb - ca
    else
      return nil, h
    end
  end
  return i + shift
end

--- The non-whitespace characters of lines[first..last], each with its place.
---@return string[] chars, integer[][] places {row, col}
local function solid(lines, first, last)
  local chars, places = {}, {}
  for row = first, last do
    local line = lines[row] or ""
    for col = 1, #line do
      local c = line:sub(col, col)
      if c:match("%S") then
        chars[#chars + 1] = c
        places[#places + 1] = { row, col - 1 }
      end
    end
  end
  return chars, places
end

--- Map a position in `old` to the same place in `new`.
---
--- Lines outside a changed hunk shift by what was added or removed above
--- them. Inside one, the non-whitespace characters of the two versions of the
--- hunk are diffed the same way, so the position follows its own character
--- through re-indenting, line splits and joins, and through characters the
--- formatter added or removed around it.
---@param old string[]
---@param new string[]
---@param row integer 1-based
---@param col integer 0-based
---@return integer row 1-based, integer col 0-based
function M.map(old, new, row, col)
  local mapped, hunk = through(diff(old, new), row)
  if mapped then
    return mapped, col
  end
  local sa, ca, sb, cb = hunk[1], hunk[2], hunk[3], hunk[4]
  if cb == 0 then
    -- The lines are gone: the line that now follows where they were.
    return math.max(1, math.min(sb + 1, #new)), 0
  end

  local a, a_at = solid(old, sa, sa + ca - 1)
  local b, b_at = solid(new, sb, sb + cb - 1)
  -- The first non-whitespace character at or after the position.
  local k = #a + 1
  for i, place in ipairs(a_at) do
    if place[1] > row or (place[1] == row and place[2] >= col) then
      k = i
      break
    end
  end
  if k > #a or #b == 0 then
    local last = sb + cb - 1
    return last, #(new[last] or "")
  end

  local j, inner = through(diff(a, b), k)
  if not j then
    -- The character itself was replaced: the start of what replaced it.
    j = inner[4] > 0 and inner[3] or inner[3] + 1
  end
  j = math.max(1, math.min(j, #b))
  return b_at[j][1], b_at[j][2]
end

---@param buf integer
---@return integer[]|nil row (1-based), col
local function last_change(buf)
  local pos = vim.api.nvim_buf_get_mark(buf, ".")
  if pos[1] == 0 then
    return nil
  end
  return pos
end

--- Run fn (a format of buf, or an edit the server makes on its own) and put
--- the last-change position back after it.
---@param buf integer
---@param fn fun()
function M.preserve(buf, fn)
  local before = last_change(buf)
  if not before then
    return fn()
  end
  local old = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ok, err = pcall(fn)

  if vim.api.nvim_buf_is_valid(buf) then
    local after = last_change(buf)
    local moved = after and (after[1] ~= before[1] or after[2] ~= before[2])
    if moved then
      local new = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local row, col = M.map(old, new, before[1], before[2])
      row = math.max(1, math.min(row, #new))
      col = math.min(col, #(new[row] or ""))
      vim.api.nvim_buf_call(buf, function()
        pcall(vim.cmd, "silent! undojoin")
        vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { "" })
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
