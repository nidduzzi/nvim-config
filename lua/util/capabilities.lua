--- Fuzzy-search what this editor can do, and run it.
---
--- Pickers search files and text. Nothing searches the editor itself, so a
--- feature you use once a month is a feature you have to remember the key for,
--- or go looking through which-key one prefix at a time.
---
--- This lists what the configuration adds on top of a stock editor, each entry
--- carrying the key that runs it, and runs whichever one is chosen. The last
--- entries open the exhaustive lists: every picker, every command, every
--- keymap, for when the thing being looked for is not one of ours.

local M = {}

--- The capabilities this configuration adds, in the order they are most
--- likely to be wanted.
---
--- Keeping this by hand is deliberate: a generated list would be every keymap
--- in the editor, which is the haystack this exists to avoid.
---@return { name: string, desc: string, key?: string, run: fun() }[]
function M.items()
  local search = require("util.search")

  local items = {
    {
      name = "Grep, without documentation",
      desc = "Search file contents, skipping the project's prose",
      key = "<leader>sg",
      run = function()
        Snacks.picker.grep(search.opts("code"))
      end,
    },
    {
      name = "Grep, everything",
      desc = "Search file contents with no filter at all",
      key = "<leader>sG",
      run = function()
        Snacks.picker.grep(search.opts("all"))
      end,
    },
    {
      name = "Grep, documentation only",
      desc = "Search the prose and nothing else",
      key = "<leader>sO",
      run = function()
        Snacks.picker.grep(search.opts("docs"))
      end,
    },
    {
      name = "Search filters",
      desc = "Inside a grep: a-d cycles, a-p chooses, a-e by extension, a-G by path glob",
      run = function()
        Snacks.picker.grep(search.opts("code"))
      end,
    },
    {
      name = "File tree",
      desc = "Browse files as a tree; i filters it, and it stays a tree",
      key = "<leader>e",
      run = function()
        Snacks.picker.explorer()
      end,
    },
    {
      name = "Results as a tree",
      desc = "Inside a picker: c-t groups the results by file in Trouble",
      run = function()
        vim.notify("Open a picker, then press <c-t>.", vim.log.levels.INFO, { title = "Capabilities" })
      end,
    },
    {
      name = "Diff the working tree",
      desc = "Side-by-side diff; the same key closes it",
      key = "<leader>gd",
      run = function()
        require("util.diff").toggle("DiffviewOpen")
      end,
    },
    {
      name = "Resolve merge conflicts",
      desc = "Three-way view of a merge in progress; the same key closes it",
      key = "<leader>gm",
      run = function()
        require("util.diff").toggle_merge()
      end,
    },
    {
      name = "History of this file",
      desc = "Every commit that touched the current file",
      key = "<leader>gf",
      run = function()
        require("util.diff").toggle("DiffviewFileHistory %")
      end,
    },
    {
      name = "Yank history",
      desc = "Everything yanked this session, not just the last thing",
      key = "<leader>sy",
      run = function()
        Snacks.picker.yanky()
      end,
    },
    {
      name = "Restore a session",
      desc = "Reopen the files this directory was left with",
      key = "<leader>P",
      run = function()
        require("persistence").load()
      end,
    },
    {
      name = "Language servers here",
      desc = "What this project provides, and what it does not",
      run = function()
        vim.cmd("checkhealth dotfiles")
      end,
    },
    {
      name = "Project settings",
      desc = "Edit this project's .nvim.lua, which tunes the config per repository",
      run = function()
        local root = require("util.lsp").root(vim.fn.getcwd())
        vim.cmd.edit(root .. "/.nvim.lua")
      end,
    },
    {
      name = "Plugins",
      desc = "What is installed, and what it costs at startup",
      key = "<leader>l",
      run = function()
        vim.cmd("Lazy")
      end,
    },
    {
      name = "Install a tool",
      desc = "Mason, which installs nothing on its own here",
      key = "<leader>cm",
      run = function()
        vim.cmd("Mason")
      end,
    },
  }

  -- The exhaustive lists, last, for when the thing wanted is not one of ours.
  vim.list_extend(items, {
    {
      name = "All pickers…",
      desc = "Every picker this editor has",
      run = function()
        Snacks.picker.pickers()
      end,
    },
    {
      name = "All commands…",
      desc = "Every : command",
      key = "<leader>sC",
      run = function()
        Snacks.picker.commands()
      end,
    },
    {
      name = "All keymaps…",
      desc = "Every key bound in this buffer",
      key = "<leader>sk",
      run = function()
        Snacks.picker.keymaps()
      end,
    },
    {
      name = "All help…",
      desc = "Neovim's own documentation",
      key = "<leader>sh",
      run = function()
        Snacks.picker.help()
      end,
    },
  })

  return items
end

--- Open the picker.
function M.open()
  local items = {}

  for index, capability in ipairs(M.items()) do
    table.insert(items, {
      idx = index,
      score = 0,
      -- What the fuzzy matcher sees: the name, what it does, and its key, so
      -- searching for "conflict", "merge" or "gm" all find the same entry.
      text = table.concat({ capability.name, capability.desc, capability.key or "" }, " "),
      capability = capability,
    })
  end

  Snacks.picker.pick({
    source = "capabilities",
    items = items,
    title = "What this editor can do",
    layout = { preset = "select", layout = { width = 0.7, height = 0.7 } },
    format = function(item)
      local capability = item.capability
      -- Pad to a width the longest name fits in, and keep a real gap after it:
      -- a name that fills its column otherwise runs straight into the key.
      return {
        { ("%-28s"):format(capability.name), "SnacksPickerLabel" },
        { "  ", "SnacksPickerComment" },
        { ("%-12s"):format(capability.key or ""), "SnacksPickerSpecial" },
        { "  ", "SnacksPickerComment" },
        { capability.desc, "SnacksPickerComment" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item and item.capability then
        vim.schedule(item.capability.run)
      end
    end,
  })
end

return M
