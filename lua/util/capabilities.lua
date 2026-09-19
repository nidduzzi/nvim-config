--- Fuzzy-search what you can do here, and do it.
---
--- Two things answer "what can I do in this buffer". which-key lists the keys
--- bound in it; the configuration adds features whose keys you have to know
--- before which-key can show them to you. Same question asked twice, so this
--- is one picker over both rather than two of them competing for a key.
---
--- `<Tab>` switches scope the way tabs would: everything, the configuration's
--- own features, the keymaps, or the editor's own Ex commands. which-key keeps
--- its job — its popup, which groups keys by prefix, is one of the entries, and
--- `<leader>sk` still lists every keymap in the editor.
---
--- The commands scope exists because `:tabclose` is not guessable. Vim's
--- commands are a vocabulary you either know or do not, `:help` answers only
--- when you already have the word, and tab completion after `:` needs the
--- first letters. Fuzzy matching over the whole list turns "close" into a
--- short list containing the one you meant.

local M = {}

---@alias capability { name: string, desc: string, key?: string, kind: string, writes?: boolean, run: fun() }

--- What a plugin's undescribed keys actually do.
---
--- The only hand-written part, and deliberately the smallest one: a line per
--- plugin, added when `check-keymaps.sh` reports a new name under "single keys
--- a plugin took over". Everything else about the list is derived.
---@type table<string, string>
M.behaviour = {
  ["flash.nvim"] = "Jump to a label. f and t work as always, then every further match is labelled; Esc cancels",
  ["Matchit"] = "Jump between matching keywords, not just brackets: if/end, opening and closing tags",
}

--- The scopes `<Tab>` cycles through, in order.
M.scopes = { "everything", "features", "keymaps", "commands" }

--- How the list is ordered, which is really which question is being asked.
---
---   by action — "what runs the thing I want", the list reads as verbs
---   by key    — "what does this key do", the list reads as a keyboard
---
--- `<a-o>` switches. Fuzzy matching covers both either way; the order decides
--- what the list looks like when you have not typed anything yet.
M.orders = { "by action", "by key" }

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
      -- Getting into a popup is the half nobody documents. Both of these open
      -- unfocused and focus on a second press, which is Neovim's own
      -- behaviour and is written down nowhere anyone looks.
      name = "Read a hover popup, and scroll it",
      desc = "K opens it. K again moves the cursor inside, so you can scroll and select. c-c leaves",
      key = "K  K",
      kind = "feature",
      run = function()
        vim.lsp.buf.hover()
      end,
    },
    {
      name = "Read the diagnostic under the cursor",
      desc = "Same twice-to-enter: <leader>cd opens it, again moves inside, c-c leaves",
      key = "<leader>cd  <leader>cd",
      kind = "feature",
      run = function()
        vim.diagnostic.open_float()
      end,
    },
    {
      name = "Close whatever is open",
      desc = "c-c returns to normal from every popup, picker, list and split. In a terminal it interrupts the program instead, and a-q closes that",
      key = "<c-c>",
      kind = "feature",
      run = function()
        require("util.dismiss").dismiss()
      end,
    },
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
      desc = "Or press a-s inside a grep to cycle to it",
      key = "<leader>sg a-s",
      kind = "feature",
      run = function()
        Snacks.picker.grep(search.opts("all"))
      end,
    },
    {
      name = "Grep, documentation only",
      desc = "Or press a-s twice inside a grep to cycle to it",
      key = "<leader>sg a-s a-s",
      kind = "feature",
      run = function()
        Snacks.picker.grep(search.opts("docs"))
      end,
    },
    {
      name = "Search filters",
      desc = "Inside a grep: a-s cycles, a-S chooses, a-e by extension, a-G by path glob",
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
      name = "Switch worktree",
      desc = "Another checkout of this repository, on another branch",
      key = "<leader>gw",
      kind = "feature",
      run = function()
        require("util.worktree").pick()
      end,
    },
    {
      name = "Worktree for a branch",
      desc = "Check a branch out beside the repository, without disturbing this one",
      key = "<leader>gW",
      kind = "feature",
      run = function()
        require("util.worktree").pick_branch()
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

--- Say in plain words what a mapping does.
---
--- A mapping's own description is written for a person, so prefer it. What is
--- left is machinery: a Lua callback prints as `<Lua function 42>` and a right
--- hand side prints as keystrokes, neither of which answers "what does this
--- key do". Commands can be read back into a sentence.
---
--- A callback with no description used to be dropped, which is how flash.nvim
--- taking f, F, t, T, `;` and `,` left the editor unable to say what `t` did.
--- Now the callback is asked where it came from: debug.getinfo gives its
--- source file and `/lazy/<plugin>/` gives the owner. Measured over every
--- mapping in a loaded editor, that is 586 with a description, 43 readable
--- from their right-hand side and 24 attributed this way — and nothing left
--- over. Naming the plugin is not a description, but it is the difference
--- between a key you can look up and a key that does not exist as far as this
--- editor is concerned.
---@param map table a keymap from nvim_get_keymap or nvim_buf_get_keymap
---@return string
local function plain_description(map)
  local description = map.desc or ""

  -- which-key registers a trigger mapping for every prefix so it can pop up;
  -- those are plumbing, and listing them buries the real keys.
  if description:find("which%-key%-trigger") then
    return ""
  end

  if description ~= "" then
    return description
  end

  local rhs = map.rhs or ""

  -- <cmd>DiffviewClose<cr> reads back as "run :DiffviewClose".
  local command = rhs:match("^[<:]?[Cc][Mm][Dd]?>?:?(.-)<[Cc][Rr]>$") or rhs:match("^:(.-)<[Cc][Rr]>$")
  if command and command ~= "" then
    return "run :" .. vim.trim(command)
  end

  -- <Plug>(MatchitNormalForward) names its own plugin, which is the answer to
  -- "what is % now". These are a third of what used to be dropped.
  local plug = rhs:match("^<Plug>%((%a+)")
  if plug then
    -- The name runs the plugin and the action together —
    -- <Plug>(MatchitNormalForward) — so match on the longest prefix that has
    -- an entry rather than on the whole thing, which never matches.
    for name, behaviour in pairs(M.behaviour) do
      if plug:sub(1, #name) == name then
        return ("%s — %s"):format(behaviour, name)
      end
    end
    return ("no description given — %s"):format(plug)
  end

  -- Anything else with a right-hand side is keystrokes, and keystrokes are
  -- readable: `>gv` is "indent, then reselect". Showing them beats dropping
  -- the key, which is what happened to < and > in visual mode.
  if rhs ~= "" then
    return "sends " .. rhs
  end

  -- Ask the callback where it came from. One line per plugin rather than one
  -- per key: a plugin that takes six keys in four modes is 24 mappings and a
  -- single entry here.
  if map.callback then
    local ok, info = pcall(debug.getinfo, map.callback, "S")
    if ok and info then
      local source = (info.source or ""):gsub("^@", "")
      local plugin = source:match("/lazy/([^/]+)/")
      if plugin then
        return ("%s — %s"):format(M.behaviour[plugin] or "no description given", plugin)
      end

      -- This configuration's own callbacks. Anything reaching here is a
      -- mapping we wrote and forgot to describe, which is worth seeing.
      local ours = source:match("/lua/(.-)%.lua$")
      if ours then
        return ("no description given — %s"):format((ours:gsub("/", ".")))
      end
    end
  end

  return ""
end

--- Write a key the way the documentation writes it.
---
--- keytrans escapes a literal `<` to `<lt>`, so `<Tab>` comes back as
--- `<lt>Tab>` and `<leader><Tab>]` renders as `<Space><lt>Tab>]`. Searching
--- the list for "Tab" then matches the description and not the key, which is
--- how the tab mappings looked missing even once they were being collected.
---@param lhs string
---@return string
local function pretty_key(lhs)
  local key = vim.fn.keytrans(lhs or "")
  key = key:gsub("<lt>", "<")
  -- The leader is a space in this configuration, and `<Space>gd` reads as two
  -- keys rather than as the mapping people actually think of.
  key = key:gsub("^<Space>", "<leader>")
  return key
end

--- The keys bound here: what `<leader>?` showed before.
---
--- Both scopes, and buffer-local first. Only collecting buffer-local mappings
--- was wrong in a way that was invisible from the inside: every tab mapping —
--- `<leader><Tab>]`, `<leader><Tab>d` and the rest — is global, so searching
--- this list for "tab" found nothing at all and the feature looked unbound.
---@return capability[]
function M.keymaps()
  local items = {}
  local seen = {}

  local function collect(maps, mode, where)
    for _, map in ipairs(maps) do
      local lhs = pretty_key(map.lhs)
      local description = plain_description(map)

      -- <Plug>(...) as a left-hand side is a target for other mappings, not a
      -- key anyone types. Listing them is noise, and they are the only thing
      -- deliberately left out.
      if lhs:match("^<Plug>") then
        description = ""
      end

      if description ~= "" and not seen[mode .. lhs] then
        seen[mode .. lhs] = true
        table.insert(items, {
          name = description,
          desc = where .. ", " .. mode .. " mode",
          key = lhs,
          kind = "keymap",
          run = function()
            vim.api.nvim_feedkeys(vim.keycode(map.lhs), mode, false)
          end,
        })
      end
    end
  end

  for _, mode in ipairs({ "n", "x", "i" }) do
    -- Buffer-local first, so a mapping this buffer overrides is described by
    -- what it actually does here.
    collect(vim.api.nvim_buf_get_keymap(0, mode), mode, "this buffer")
    collect(vim.api.nvim_get_keymap(mode), mode, "everywhere")
  end

  table.sort(items, function(a, b)
    return a.key < b.key
  end)

  return items
end

--- The key that runs each command, where one does.
---
--- This is the point of listing commands at all. Someone learning this editor
--- reaches for the command they can describe — "close" finds `:tabclose` —
--- and a list that stops there teaches them to keep using the long way. Of the
--- 641 commands here, 22 have a key, and none of them said so.
---
--- Read from the mappings rather than written down: a key whose right-hand
--- side is `<cmd>BufferLineCloseLeft<cr>` says what it runs, so the index
--- builds itself and stays right when a plugin changes its bindings.
---@return table<string, string>
local function keys_by_command()
  local index = {}

  for _, mode in ipairs({ "n", "x" }) do
    local maps = vim.api.nvim_get_keymap(mode)
    vim.list_extend(maps, vim.api.nvim_buf_get_keymap(0, mode))

    for _, map in ipairs(maps) do
      local rhs = map.rhs or ""
      local command = rhs:match("^[<:]?[Cc][Mm][Dd]?>?:?(.-)<[Cc][Rr]>$") or rhs:match("^:(.-)<[Cc][Rr]>$")
      if command then
        local name = vim.trim(command):match("^(%a[%w_]*)")
        if name and not index[name] then
          index[name] = pretty_key(map.lhs)
        end
      end
    end
  end

  return index
end

--- The editor's own Ex commands, so `:tabclose` is findable by typing "close".
---
--- Built-in commands carry no description anywhere Neovim will tell us about,
--- so the name is all there is for them; commands defined by plugins and by
--- this configuration do have one, and it is used. Choosing one opens the
--- command line with it rather than running it, because plenty of them take
--- arguments and running `:tabonly` by accident is a bad first impression.
---@return capability[]
function M.commands()
  local items = {}
  local seen = {}
  local keys = keys_by_command()

  for name, command in pairs(vim.api.nvim_get_commands({})) do
    seen[name] = true
    table.insert(items, {
      name = ":" .. name,
      desc = (type(command) == "table" and command.definition) and tostring(command.definition):sub(1, 120) or "editor command",
      key = keys[name],
      kind = "command",
      run = function()
        vim.api.nvim_feedkeys(":" .. name .. " ", "n", false)
      end,
    })
  end

  -- getcompletion answers with the built-ins too, which nvim_get_commands does
  -- not: :tabclose lives here and not above.
  for _, name in ipairs(vim.fn.getcompletion("", "command")) do
    if not seen[name] and name:match("^%a") then
      table.insert(items, {
        name = ":" .. name,
        desc = "built-in command",
        key = keys[name],
        kind = "command",
        run = function()
          vim.api.nvim_feedkeys(":" .. name .. " ", "n", false)
        end,
      })
    end
  end

  table.sort(items, function(a, b)
    return a.name < b.name
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
  if scope == "commands" then
    return M.commands()
  end

  local all = M.features()
  vim.list_extend(all, M.keymaps())
  vim.list_extend(all, M.commands())

  -- One entry per key. A feature and the mapping that runs it are the same
  -- thing described twice, and the copies are not interchangeable: the feature
  -- knows what it does and whether it writes, and the keymap only knows which
  -- key to press. Choosing "Yank history" hit the keymap copy, fed <leader>sy,
  -- and reached the paste the feature's own guard exists to prevent.
  local best = {}
  local order = {}
  local rank = { feature = 3, keymap = 2, command = 1 }

  for _, item in ipairs(all) do
    local id = (item.key and item.key ~= "" and item.key ~= "-") and ("key:" .. item.key) or ("name:" .. item.name)
    local held = best[id]

    if not held then
      best[id] = item
      table.insert(order, id)
    elseif (rank[item.kind] or 0) > (rank[held.kind] or 0) then
      best[id] = item
    end
  end

  local deduped = {}
  for _, id in ipairs(order) do
    table.insert(deduped, best[id])
  end
  return deduped
end

--- Open the picker.
---@param scope? string one of M.scopes. Default: everything.
---@param order? string one of M.orders. Default: by action.
function M.open(scope, order)
  scope = scope or M.scopes[1]
  order = order or M.orders[1]

  local capabilities = M.items(scope)

  if order == "by key" then
    table.sort(capabilities, function(a, b)
      -- Mappings without a key sink to the bottom: they answer the other
      -- question, and there is no key to read them by.
      local ak, bk = a.key or "~~~", b.key or "~~~"
      if ak == bk then
        return a.name < b.name
      end
      return ak < bk
    end)
  end

  local items = {}
  for index, capability in ipairs(capabilities) do
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
    title = table.concat(tabs, "") .. "  <Tab> scope   <a-o> " .. order,
    layout = { preset = "select", layout = { width = 0.8, height = 0.8 } },
    format = function(item)
      local capability = item.capability
      local mark = { capability.kind == "feature" and "● " or "○ ", "SnacksPickerSpecial" }
      -- A blank key column reads as "you missed something" rather than "there
      -- is no key for this", and the difference matters to someone learning
      -- their way around. Six features are reachable only from here.
      local key = capability.key and capability.key ~= ""
          and { ("%-18s"):format(capability.key), "SnacksPickerSpecial" }
        or { ("%-18s"):format("from here"), "SnacksPickerDimmed" }
      local name = { ("%-30s"):format(capability.name:sub(1, 30)), "SnacksPickerLabel" }
      local gap = { "  ", "SnacksPickerComment" }
      local desc = { capability.desc, "SnacksPickerComment" }

      -- Reading by key means scanning the key column, so it leads.
      if order == "by key" then
        return { mark, key, gap, name, gap, desc }
      end
      return { mark, name, gap, key, gap, desc }
    end,
    win = {
      input = {
        keys = {
          ["<Tab>"] = { "capability_scope", mode = { "i", "n" }, desc = "Switch scope" },
          ["<a-o>"] = { "capability_order", mode = { "i", "n" }, desc = "Order by action or by key" },
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
          M.open(M.scopes[(index % #M.scopes) + 1], order)
        end)
      end,
      capability_order = function(picker)
        picker:close()
        vim.schedule(function()
          M.open(scope, order == M.orders[1] and M.orders[2] or M.orders[1])
        end)
      end,
    },
    confirm = function(picker, item)
      picker:close()
      if not (item and item.capability) then
        return
      end

      -- Some features end by writing into the current buffer, and the start
      -- screen cannot be written into. Reaching this list from the dashboard
      -- is a normal way in — it is on `?` there — so this is a normal thing to
      -- hit, and the editor's own answer is `E21: Cannot make changes,
      -- 'modifiable' is off`, which tells someone who asked for their yank
      -- history nothing about what to do next.
      --
      -- Catching the error is not possible from here: the feature only opens a
      -- picker, and the write happens later inside that picker's own confirm.
      -- Three attempts at catching it failed for that reason, and a fourth at
      -- wrapping vim.notify failed because noice renders Vim's errors from the
      -- msg_show UI event and never touches the Lua notify path. So the write
      -- is refused before it is attempted, which is the only place the answer
      -- is still useful.
      if item.capability.writes and not vim.bo.modifiable then
        vim.notify(
          ("%s finishes by writing into the current buffer, and this one cannot be written to.\n\nOpen a file first — <leader>ff — then try again."):format(
            item.capability.name
          ),
          vim.log.levels.WARN,
          { title = "Nothing to write into" }
        )
        return
      end

      -- The teaching moment. Someone who found this by describing it has just
      -- shown they do not know the key, and this is the one instant where the
      -- key means something concrete: it is the thing that just happened.
      -- Reading it in a list beforehand is how a key is forgotten.
      local key = item.capability.key
      if key and key ~= "" then
        vim.notify(("%s does this."):format(key), vim.log.levels.INFO, {
          title = item.capability.name,
        })
      end

      vim.schedule(item.capability.run)
    end,
  })
end

return M
