--- Work with git worktrees from inside the editor.
---
--- A worktree is a second checkout of the same repository: another branch, in
--- another directory, sharing one history. They are how you look at a branch
--- without disturbing what you have open, and nothing in the editor knows
--- about them, so switching means leaving it.
---
--- This lists them, switches between them, and creates one from a branch. It
--- deliberately does not remove them: `git worktree remove` deletes a
--- directory, and a picker where one key is "delete my working copy" is a
--- picker that will eventually delete a working copy.

local M = {}

--- Run a git command in the current repository.
---@param args string[]
---@return string[] lines, boolean ok
--- One spelling for a directory: symlinks resolved, short names expanded,
--- separators forward.
---@param path string
---@return string
local function canonical(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local function git(args)
  local result = vim.system(vim.list_extend({ "git" }, args), { text = true }):wait()
  local lines = vim.split(result.stdout or "", "\n", { trimempty = true })
  return lines, result.code == 0
end

--- Every worktree of this repository.
---
--- `--porcelain` reports one record per worktree as `key value` lines with a
--- blank line between records, which is stable across git versions in a way
--- the human-readable output is not.
---@return { path: string, branch: string, head: string, bare: boolean, detached: boolean, locked: boolean, current: boolean }[]
function M.list()
  local lines, ok = git({ "worktree", "list", "--porcelain" })
  if not ok then
    return {}
  end

  -- Resolved and normalised, because the same directory is spelled several
  -- ways. git prints forward slashes on every platform; the editor's cwd uses
  -- the platform's separator; and Windows hands out short names, so the same
  -- worktree is C:/Users/runneradmin/... to git and C:\Users\RUNNER~1\... to
  -- the editor. Comparing them raw says you are standing in none of them.
  local cwd = canonical(vim.uv.cwd() or "")
  local trees = {}
  local current = nil

  local function flush()
    if current then
      table.insert(trees, current)
      current = nil
    end
  end

  for _, line in ipairs(lines) do
    local key, value = line:match("^(%S+)%s*(.*)$")

    if key == "worktree" then
      flush()
      value = canonical(value)
      current = {
        path = value,
        branch = "",
        head = "",
        bare = false,
        detached = false,
        locked = false,
        -- The worktree you are standing in, or one containing it.
        current = cwd == value or vim.startswith(cwd, value .. "/"),
      }
    elseif current then
      if key == "HEAD" then
        current.head = value:sub(1, 8)
      elseif key == "branch" then
        current.branch = value:gsub("^refs/heads/", "")
      elseif key == "bare" then
        current.bare = true
      elseif key == "detached" then
        current.detached = true
      elseif key == "locked" then
        current.locked = true
      end
    end
  end

  flush()
  return trees
end

--- Move to a worktree.
---@param path string
---@param in_tab? boolean open it in a new tab, leaving this one alone
function M.switch(path, in_tab)
  if vim.fn.isdirectory(path) ~= 1 then
    vim.notify("No such worktree: " .. path, vim.log.levels.ERROR, { title = "Worktree" })
    return
  end

  if in_tab then
    vim.cmd.tabnew()
    vim.cmd.tcd(path)
  else
    vim.cmd.cd(path)
  end

  vim.notify(vim.fn.fnamemodify(path, ":~"), vim.log.levels.INFO, { title = "Worktree" })

  -- Sessions, pickers and the file tree all key off the working directory, so
  -- open the picker again rather than leaving the old root on screen. Only
  -- when there is a picker: this module is also called from a spec, where
  -- the error arrived later as "attempt to index global 'Snacks'" from a
  -- scheduled callback, long after the test it belonged to had passed.
  vim.schedule(function()
    if Snacks and Snacks.picker then
      Snacks.picker.files()
    end
  end)
end

--- Create a worktree for a branch, beside the repository.
---
--- Beside, not inside: a worktree nested in the repository shows up in its own
--- file listings and grep results, which is exactly the noise this config
--- spends its search filters removing.
---@param branch string
---@param opts? { new: boolean }
function M.add(branch, opts)
  opts = opts or {}

  local root = git({ "rev-parse", "--show-toplevel" })[1]
  if not root then
    vim.notify("Not inside a git repository.", vim.log.levels.WARN, { title = "Worktree" })
    return
  end

  local name = branch:gsub("[/%s]", "-")
  local path = vim.fs.joinpath(vim.fs.dirname(root), vim.fs.basename(root) .. "-" .. name)

  local args = { "worktree", "add" }
  if opts.new then
    vim.list_extend(args, { "-b", branch, path })
    -- Without a base, git branches off whatever HEAD happens to be, which is
    -- rarely what was meant when the worktree is being made from a picker.
    if opts.base and opts.base ~= "" then
      table.insert(args, opts.base)
    end
  else
    vim.list_extend(args, { path, branch })
  end

  local result = vim.system(vim.list_extend({ "git" }, args), { text = true }):wait()

  if result.code ~= 0 then
    vim.notify((result.stderr or "git worktree add failed"):gsub("%s+$", ""), vim.log.levels.ERROR, { title = "Worktree" })
    return
  end

  vim.notify(("%s\n%s"):format(branch, vim.fn.fnamemodify(path, ":~")), vim.log.levels.INFO, {
    title = "Worktree created",
  })
  M.switch(path)
end

--- Pick a worktree.
function M.pick()
  local trees = M.list()

  if #trees == 0 then
    vim.notify("No worktrees, or not a git repository.", vim.log.levels.WARN, { title = "Worktree" })
    return
  end

  local items = {}
  for index, tree in ipairs(trees) do
    local label = tree.branch ~= "" and tree.branch or (tree.detached and "detached" or "bare")
    table.insert(items, {
      idx = index,
      score = 0,
      text = label .. " " .. tree.path,
      file = tree.path,
      tree = tree,
      label = label,
    })
  end

  Snacks.picker.pick({
    source = "worktrees",
    items = items,
    title = "Worktrees   <c-t> in a new tab   <a-n> new branch",
    layout = { preset = "select", layout = { width = 0.8, height = 0.6 } },
    format = function(item)
      local tree = item.tree
      return {
        { tree.current and "● " or "  ", "SnacksPickerSpecial" },
        { ("%-28s"):format(item.label:sub(1, 28)), "SnacksPickerLabel" },
        { "  ", "SnacksPickerComment" },
        { ("%-10s"):format(tree.head), "SnacksPickerComment" },
        { "  ", "SnacksPickerComment" },
        { vim.fn.fnamemodify(tree.path, ":~"), "SnacksPickerDir" },
        { tree.locked and "  locked" or "", "SnacksPickerComment" },
      }
    end,
    win = {
      input = {
        keys = {
          ["<c-t>"] = { "worktree_tab", mode = { "i", "n" }, desc = "Open in a new tab" },
          ["<a-n>"] = { "worktree_new", mode = { "i", "n" }, desc = "New branch and worktree" },
        },
      },
    },
    actions = {
      worktree_tab = function(picker, item)
        picker:close()
        if item then
          M.switch(item.tree.path, true)
        end
      end,
      worktree_new = function(picker)
        picker:close()
        -- Ask what to base it on before asking what to call it. A new branch
        -- always comes off something, and answering that from memory is how
        -- you end up branching off whatever happened to be checked out.
        M.pick_branch(function(base)
          vim.ui.input({ prompt = ("New branch off %s: "):format(base or "HEAD") }, function(branch)
            if branch and branch ~= "" then
              M.add(branch, { new = true, base = base })
            end
          end)
        end)
      end,
    },
    confirm = function(picker, item)
      picker:close()
      if item then
        M.switch(item.tree.path)
      end
    end,
  })
end

--- Pick a branch, and put a worktree on it.
---
--- With `on_pick`, the branch is handed back instead, which is how choosing a
--- base for a new branch reuses this list rather than growing a second one.
---@param on_pick? fun(branch: string)
function M.pick_branch(on_pick)
  local lines, ok = git({ "branch", "--all", "--format=%(refname:short)" })

  if not ok or #lines == 0 then
    vim.notify("No branches, or not a git repository.", vim.log.levels.WARN, { title = "Worktree" })
    return
  end

  -- A branch that already has a worktree cannot get a second one.
  local taken = {}
  for _, tree in ipairs(M.list()) do
    taken[tree.branch] = tree.path
  end

  local items = {}
  for index, branch in ipairs(lines) do
    table.insert(items, {
      idx = index,
      score = 0,
      text = branch,
      branch = branch,
      taken = taken[branch],
    })
  end

  Snacks.picker.pick({
    source = "branches",
    items = items,
    title = on_pick and "Base the new branch on which one?" or "A worktree for which branch?",
    layout = { preset = "select", layout = { width = 0.7, height = 0.6 } },
    format = function(item)
      return {
        { ("%-40s"):format(item.branch:sub(1, 40)), "SnacksPickerLabel" },
        {
          item.taken and ("already checked out at " .. vim.fn.fnamemodify(item.taken, ":~")) or "",
          "SnacksPickerComment",
        },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end

      if on_pick then
        -- A branch that already has a worktree is a perfectly good base, so
        -- the "taken" note is information here rather than a refusal.
        on_pick(item.branch)
        return
      end

      if item.taken then
        M.switch(item.taken)
        return
      end
      M.add(item.branch)
    end,
  })
end

return M
