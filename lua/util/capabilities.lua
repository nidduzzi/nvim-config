--- Fuzzy-search what you can do here, and do it.
---
--- Two things answer "what can I do in this buffer". which-key lists the keys
--- bound in it; the configuration adds features whose keys you have to know
--- before which-key can show them to you. Same question asked twice, so this
--- is one picker over both rather than two of them competing for a key.
---
--- `<Tab>` switches scope the way tabs would: everything, the configuration's
--- own features, or this buffer's keymaps. which-key keeps its job — its
--- popup, which groups keys by prefix, is one of the entries, and `<leader>sk`
--- still lists every keymap in the editor.

local M = {}

---@alias capability { name: string, desc: string, key?: string, kind: string, run: fun() }

--- The scopes `<Tab>` cycles through, in order.
M.scopes = { "everything", "features", "keymaps" }

--- What this configuration adds on top of a stock editor.
---
--- Kept by hand on purpose: generating it would produce every keymap in the
--- editor, which is the haystack this exists to avoid. The keymaps scope
--- already covers that ground.
---@return capability[]
function M.features()
  local search = require("util.search")

  return {
    {
      name = "Grep, without documentation",
      desc = "Search file contents, skipping the project's prose",
      key = "<leader>sg",
      kind = "feature",
      run = function()
        Snacks.picker.grep(search.opts("code"))
      end,
    },
    {
      name = "Grep, everything",
      desc = "Or press a-d inside a grep to cycle to it",
      key = "<leader>sg a-d",
      kind = "feature",
      run = function()
        Snacks.picker.grep(search.opts("all"))
      end,
    },
    {
      name = "Grep, documentation only",
      desc = "Or press a-d twice inside a grep to cycle to it",
      key = "<leader>sg a-d a-d",
      kind = "feature",
      run = function()
        Snacks.picker.grep(search.opts("docs"))
      end,
    },
    {
      name = "Search filters",
      desc = "Inside a grep: a-d cycles, a-p chooses, a-e by extension, a-G by path glob",
      kind = "feature",
      run = function()
        Snacks.picker.grep(search.opts("code"))
      end,
    },
    {
      name = "File tree",
      desc = "Browse files as a tree; i filters it, and it stays a tree",
      key = "<leader>e",
      kind = "feature",
      run = function()
        Snacks.picker.explorer()
      end,
    },
    {
      name = "Results as a tree",
      desc = "Inside a picker: c-t groups the results by file in Trouble",
      kind = "feature",
      run = function()
        vim.notify("Open a picker, then press <c-t>.", vim.log.levels.INFO, { title = "Capabilities" })
      end,
    },
    {
      name = "Diff the working tree",
      desc = "Side-by-side diff; the same key closes it",
      key = "<leader>gd",
      kind = "feature",
      run = function()
        require("util.diff").toggle("DiffviewOpen")
      end,
    },
    {
      name = "Resolve merge conflicts",
      desc = "Three-way view of a merge in progress; the same key closes it",
      key = "<leader>gm",
      kind = "feature",
      run = function()
        require("util.diff").toggle_merge()
      end,
    },
    {
      name = "History of this file",
      desc = "Every commit that touched the current file",
      key = "<leader>gf",
      kind = "feature",
      run = function()
        require("util.diff").toggle("DiffviewFileHistory %")
      end,
    },
    {
      name = "Yank history",
      desc = "Everything yanked this session, not just the last thing",
      key = "<leader>sy",
      kind = "feature",
      run = function()
        Snacks.picker.yanky()
      end,
    },
    {
      name = "Restore a session",
      desc = "Reopen the files this directory was left with",
      key = "<leader>P",
      kind = "feature",
      run = function()
        require("persistence").load()
      end,
    },
    {
      name = "Language servers here",
      desc = "What this project provides, and what it does not",
      kind = "feature",
      run = function()
        vim.cmd("checkhealth dotfiles")
      end,
    },
    {
      name = "Project settings",
      desc = "Edit this project's .nvim.lua, which tunes the config per repository",
      kind = "feature",
      run = function()
        local root = require("util.lsp").root(vim.fn.getcwd())
        vim.cmd.edit(root .. "/.nvim.lua")
      end,
    },
    {
      name = "Plugins",
      desc = "What is installed, and what it costs at startup",
      key = "<leader>l",
      kind = "feature",
      run = function()
        vim.cmd("Lazy")
      end,
    },
    {
      name = "Install a tool",
      desc = "Mason, which installs nothing on its own here",
      key = "<leader>cm",
      kind = "feature",
      run = function()
        vim.cmd("Mason")
      end,
    },
    {
      -- which-key keeps its job. Its popup groups keys by prefix, which is the
      -- better view when learning a prefix rather than looking for one thing.
      name = "Key hints for this buffer",
      desc = "which-key's popup, grouped by prefix",
      kind = "feature",
      run = function()
        require("which-key").show({ global = false })
      end,
    },
    {
      name = "All pickers…",
      desc = "Every picker this editor has",
      kind = "feature",
      run = function()
        Snacks.picker.pickers()
      end,
    },
    {
      name = "All commands…",
      desc = "Every : command",
      key = "<leader>sC",
      kind = "feature",
      run = function()
        Snacks.picker.commands()
      end,
    },
    {
      name = "All keymaps…",
      desc = "Every key bound in the editor, not only this buffer",
      key = "<leader>sk",
      kind = "feature",
      run = function()
        Snacks.picker.keymaps()
      end,
    },
    {
      name = "All help…",
      desc = "Neovim's own documentation",
      key = "<leader>sh",
      kind = "feature",
      run = function()
        Snacks.picker.help()
      end,
    },
  }
end

--- The keys bound in this buffer: what `<leader>?` showed before.
---@return capability[]
function M.keymaps()
  local items = {}
  local seen = {}

  for _, mode in ipairs({ "n", "x", "i" }) do
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
      local lhs = vim.fn.keytrans(map.lhs or "")
      local description = map.desc or map.rhs or ""

      -- which-key registers a trigger mapping for every prefix so it can pop
      -- up; those are plumbing, and listing them buries the real keys.
      if description:find("which%-key%-trigger") then
        description = ""
      end

      -- A key with no description is noise in a list meant to be read.
      if description ~= "" and not seen[mode .. lhs] then
        seen[mode .. lhs] = true
        table.insert(items, {
          name = description,
          desc = "buffer mapping, " .. mode .. " mode",
          key = lhs,
          kind = "keymap",
          run = function()
            vim.api.nvim_feedkeys(vim.keycode(lhs), mode, false)
          end,
        })
      end
    end
  end

  table.sort(items, function(a, b)
    return a.key < b.key
  end)

  return items
end

---@param scope string
---@return capability[]
function M.items(scope)
  if scope == "features" then
    return M.features()
  end
  if scope == "keymaps" then
    return M.keymaps()
  end

  local all = M.features()
  vim.list_extend(all, M.keymaps())
  return all
end

--- Open the picker.
---@param scope? string one of M.scopes. Default: everything.
function M.open(scope)
  scope = scope or M.scopes[1]

  local items = {}
  for index, capability in ipairs(M.items(scope)) do
    table.insert(items, {
      idx = index,
      score = 0,
      -- What the fuzzy matcher sees: name, description and key alike, so
      -- "conflict", "merge" and "gm" all find the same entry.
      text = table.concat({ capability.name, capability.desc, capability.key or "" }, " "),
      capability = capability,
    })
  end

  -- The scopes read as a row of tabs, with the active one bracketed.
  local tabs = {}
  for _, name in ipairs(M.scopes) do
    table.insert(tabs, name == scope and ("[" .. name .. "]") or (" " .. name .. " "))
  end

  Snacks.picker.pick({
    source = "capabilities",
    items = items,
    title = table.concat(tabs, "") .. "  <Tab> switches",
    layout = { preset = "select", layout = { width = 0.8, height = 0.8 } },
    format = function(item)
      local capability = item.capability
      return {
        { capability.kind == "feature" and "● " or "○ ", "SnacksPickerSpecial" },
        { ("%-30s"):format(capability.name:sub(1, 30)), "SnacksPickerLabel" },
        { "  ", "SnacksPickerComment" },
        { ("%-16s"):format(capability.key or ""), "SnacksPickerSpecial" },
        { "  ", "SnacksPickerComment" },
        { capability.desc, "SnacksPickerComment" },
      }
    end,
    win = {
      input = {
        keys = {
          ["<Tab>"] = { "capability_scope", mode = { "i", "n" }, desc = "Switch scope" },
        },
      },
    },
    actions = {
      capability_scope = function(picker)
        local index = 1
        for i, name in ipairs(M.scopes) do
          if name == scope then
            index = i
            break
          end
        end
        picker:close()
        vim.schedule(function()
          M.open(M.scopes[(index % #M.scopes) + 1])
        end)
      end,
    },
    confirm = function(picker, item)
      picker:close()
      if item and item.capability then
        vim.schedule(item.capability.run)
      end
    end,
  })
end

return M
