--- The yank ring, in the picker this configuration uses everywhere else.
---
--- `Snacks.picker.yanky()` does not exist. It never did — snacks has 69 picker
--- sources and yanky is not one of them — so `<leader>sy` raised
--- "attempt to call field 'yanky' (a nil value)" from the moment it was
--- written.
---
--- Nothing caught it. The capability list held two entries for this feature,
--- one describing it and one feeding the key, and the one that ran was always
--- the key. The error surfaced the day the list stopped holding duplicates.
---
--- yanky keeps its own ring and will hand it over: `history.all()` returns the
--- entries newest first, each with its register contents and type. That is
--- everything a picker needs, and it is the same shape as the harpoon list
--- this configuration already renders.

local M = {}

--- One line of a yank, as a list entry: whitespace collapsed so a multi-line
--- yank is still one row, and long yanks cut rather than wrapped.
---@param text string
---@return string
local function summarise(text)
  local line = (text or ""):gsub("%s+", " ")
  return vim.trim(line)
end

--- Show the yank ring, and put the chosen entry in the unnamed register so the
--- next `p` uses it.
---
--- Deliberately not pasting on choose. A picker that edits the buffer the
--- moment you press enter is the thing that fails on an unwritable one, and
--- loading the register leaves the paste where it belongs — in your hands,
--- with p or P, at the position you meant.
function M.history()
  local ok, history = pcall(require, "yanky.history")
  if not ok then
    vim.notify(
      "yanky is not loaded, so there is no yank ring to show.",
      vim.log.levels.WARN,
      { title = "Yank history" }
    )
    return
  end

  local entries = history.all()
  if not entries or #entries == 0 then
    vim.notify("Nothing yanked yet this session.", vim.log.levels.INFO, { title = "Yank history" })
    return
  end

  local items = {}
  for index, entry in ipairs(entries) do
    local text = summarise(entry.regcontents)
    table.insert(items, {
      idx = index,
      score = 0,
      text = text,
      preview = { text = entry.regcontents or "", ft = vim.bo.filetype },
      entry = entry,
    })
  end

  Snacks.picker.pick({
    source = "yank_history",
    items = items,
    -- snacks reads item.preview only in this mode; without it the preview pane
    -- says "Item has no `file`", which is true and unhelpful — a yank is text,
    -- not a file.
    preview = "preview",
    title = "Yank history — enter loads it, then p pastes",
    format = function(item)
      local kind = item.entry.regtype == "V" and "line" or (item.entry.regtype == "v" and "char" or "block")
      return {
        { ("%-5s "):format(kind), "SnacksPickerComment" },
        { item.text, "SnacksPickerLabel" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end

      vim.fn.setreg('"', item.entry.regcontents, item.entry.regtype)
      vim.notify("Loaded. Press p to paste it.", vim.log.levels.INFO, { title = "Yank history" })
    end,
  })
end

return M
