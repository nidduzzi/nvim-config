--- Browse the pinned files in a snacks picker.
---
--- Harpoon ships a telescope extension and a list window of its own. This
--- config has no telescope, and the list window is a separate set of keys to
--- remember, so the pinned files are shown in the same picker as everything
--- else: same movement keys, same preview, same fuzzy filter.
---
--- What the picker adds over harpoon's own window is what a picker is for:
--- the slot number stays visible, so the list can be read as "what is on
--- <leader>2", and the preview shows the file before you commit to it.

local M = {}

--- The list for this directory. Harpoon keys lists by directory, so a second
--- worktree of the same repository has a list of its own.
---@return table
local function list()
  return require("harpoon"):list()
end

--- Pick a pinned file.
function M.pick()
  local ok, _ = pcall(require, "harpoon")
  if not ok then
    vim.notify("Harpoon is not installed.", vim.log.levels.WARN, { title = "Pinned files" })
    return
  end

  local items = {}
  for slot, entry in ipairs(list().items) do
    if entry and entry.value then
      table.insert(items, {
        idx = slot,
        score = 0,
        text = entry.value,
        file = entry.value,
        slot = slot,
        pos = entry.context and { entry.context.row or 1, entry.context.col or 0 } or nil,
      })
    end
  end

  if #items == 0 then
    vim.notify(
      "Nothing pinned here yet.\n<leader>ha pins the current file.\nEach worktree keeps its own list.",
      vim.log.levels.INFO,
      { title = "Pinned files" }
    )
    return
  end

  Snacks.picker.pick({
    source = "harpoon",
    items = items,
    title = ("Pinned files   %s"):format(vim.fn.fnamemodify(vim.uv.cwd() or "", ":~")),
    format = function(item)
      return {
        { ("<leader>%d  "):format(item.slot), "SnacksPickerSpecial" },
        { vim.fn.fnamemodify(item.file, ":."), "SnacksPickerFile" },
      }
    end,
    win = {
      input = {
        keys = {
          ["<c-x>"] = { "harpoon_remove", mode = { "i", "n" }, desc = "Unpin" },
        },
      },
    },
    actions = {
      harpoon_remove = function(picker, item)
        if not item then
          return
        end
        list():remove_at(item.slot)
        picker:close()
        vim.notify(
          ("Unpinned %s"):format(vim.fn.fnamemodify(item.file, ":.")),
          vim.log.levels.INFO,
          { title = "Pinned files" }
        )
        vim.schedule(M.pick)
      end,
    },
    confirm = function(picker, item)
      picker:close()
      if item then
        list():select(item.slot)
      end
    end,
  })
end

return M
