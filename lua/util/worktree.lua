--- Work with git worktrees from inside the editor.
---
--- A worktree is a second checkout of the same repository: another branch, in
--- another directory, sharing one history. They are how you look at a branch
--- without disturbing what you have open, and nothing in the editor knows
--- about them, so switching means leaving it.
---
--- One picker lists them, switches between them, makes new ones, and removes
--- old ones. Removing is behind two refusals and a confirmation: never the
--- tree you are in, the main checkout or a locked one, and never one with
--- uncommitted work unless you confirm a second time that you mean to lose it.

local M = {}

--- One spelling for a directory: symlinks resolved, short names expanded,
--- separators forward.
---@param path string
---@return string
local function canonical(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

--- Run git in `cwd`. Always with an explicit directory: the editor's own cwd
--- is often a different repository from the file you are looking at.
---@param args string[]
---@param cwd string
---@return string[] lines, boolean ok, string stderr
local function git(args, cwd)
  local result = vim.system(vim.list_extend({ "git" }, args), { text = true, cwd = cwd }):wait()
  local lines = vim.split(result.stdout or "", "\n", { trimempty = true })
  return lines, result.code == 0, vim.trim(result.stderr or "")
end

---@param path string
---@param root string
---@return boolean
local function under(path, root)
  return path == root or vim.startswith(path, root .. "/")
end

--- The repository you are looking at: the one holding the current buffer's
--- file, or the working directory's when the buffer is not a file.
---
--- Found by looking for `.git` rather than asking git, so it can be answered
--- before anything has decided whether git may run here. A linked worktree
--- and a submodule both have a `.git` file rather than a directory, which
--- this finds just the same.
---@param buf? integer
---@return string|nil
function M.root(buf)
  local name = vim.api.nvim_buf_get_name(buf or 0)
  local start = vim.fn.getcwd()
  if name ~= "" and vim.bo[buf or 0].buftype == "" then
    local dir = vim.fs.dirname(name)
    if vim.uv.fs_stat(dir) then
      start = dir
    end
  end
  local found = vim.fs.find(".git", { path = start, upward = true })[1]
  return found and canonical(vim.fs.dirname(found)) or nil
end

--- A git directory's own checkout.
---
--- A submodule's main worktree is reported by `git worktree list` as its git
--- directory, `.git/modules/<name>` inside the superproject, because that is
--- where its repository lives. The checkout is recorded in that directory's
--- `core.worktree`, relative to it. Reading config runs nothing.
---@param path string
---@return string
local function checkout_of(path)
  if vim.uv.fs_stat(vim.fs.joinpath(path, ".git")) or not vim.uv.fs_stat(vim.fs.joinpath(path, "HEAD")) then
    return path
  end
  local lines, ok = git({ "--git-dir=" .. path, "config", "--get", "core.worktree" }, path)
  if not ok or not lines[1] then
    return path
  end
  local target = lines[1]
  if not target:match("^/") and not target:match("^%a:[/\\]") then
    target = vim.fs.joinpath(path, target)
  end
  return canonical(target)
end

---@class worktree.Tree
---@field path string
---@field branch string
---@field head string
---@field bare boolean
---@field detached boolean
---@field locked boolean
---@field prunable boolean
---@field main boolean the repository's own checkout, listed first by git
---@field current boolean the tree holding the file you are looking at

--- Every worktree of the repository you are looking at.
---
--- `--porcelain` reports one record per worktree as `key value` lines with a
--- blank line between records, which is stable across git versions in a way
--- the human-readable output is not.
---@param root? string the repository to list; default: `M.root()`
---@return worktree.Tree[]
function M.list(root)
  root = root or M.root()
  if not root then
    return {}
  end

  local lines, ok = git({ "worktree", "list", "--porcelain" }, root)
  if not ok then
    return {}
  end

  -- Resolved and normalised, because the same directory is spelled several
  -- ways. git prints forward slashes on every platform; the editor uses the
  -- platform's separator; and Windows hands out short names, so the same
  -- worktree is C:/Users/runneradmin/... to git and C:\Users\RUNNER~1\... to
  -- the editor. Comparing them raw says you are standing in none of them.
  local here = canonical(root)
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
      value = checkout_of(canonical(value))
      current = {
        path = value,
        branch = "",
        head = "",
        bare = false,
        detached = false,
        locked = false,
        prunable = false,
        main = #trees == 0,
        current = here == value,
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
      elseif key == "prunable" then
        current.prunable = true
      end
    end
  end

  flush()
  return trees
end

--- The worktree holding `path`, the deepest one when they nest.
---@param trees worktree.Tree[]
---@param path string
---@return worktree.Tree|nil
local function containing(trees, path)
  local best
  for _, tree in ipairs(trees) do
    if under(path, tree.path) and (not best or #tree.path > #best.path) then
      best = tree
    end
  end
  return best
end

--- Move every buffer under `from` to the same file under `to`.
---
--- A buffer whose file does not exist in the other tree is closed; one with
--- unsaved changes is left exactly where it is, because closing it would
--- lose them and moving it would put them on the wrong file.
---@param from string
---@param to string
---@return integer moved, string[] kept
local function carry_buffers(from, to)
  local moved, kept = 0, {}
  local replaced = {}

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" and name ~= "" then
      local path = canonical(name)
      if under(path, from) then
        if vim.bo[buf].modified then
          table.insert(kept, vim.fn.fnamemodify(name, ":~:."))
        else
          local target = to .. path:sub(#from + 1)
          local new
          if vim.uv.fs_stat(target) then
            new = vim.fn.bufadd(target)
            vim.bo[new].buflisted = true
            moved = moved + 1
          end
          replaced[buf] = new or false
        end
      end
    end
  end

  -- Windows first, so closing the old buffers does not close the layout.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local new = replaced[vim.api.nvim_win_get_buf(win)]
    if new then
      vim.api.nvim_win_set_buf(win, new)
    end
  end

  for buf in pairs(replaced) do
    if vim.api.nvim_buf_is_valid(buf) then
      -- Not Snacks.bufdelete: for a buffer no window shows (the windows were
      -- swapped above) it only unloads, leaving the old tree's file listed
      -- in the bufferline.
      pcall(vim.api.nvim_buf_delete, buf, {})
    end
  end

  return moved, kept
end

--- Stop the language servers rooted in `from`, so the files now open in the
--- other tree get servers of their own rather than answers about the old one.
---@param from string
local function stop_servers(from)
  for _, client in ipairs(vim.lsp.get_clients()) do
    local root = client.root_dir or (client.config and client.config.root_dir)
    if type(root) == "string" and under(canonical(root), from) then
      client:stop()
    end
  end
end

--- Save or load the session for the working directory, when sessions are in
--- use and git may run here: persistence names a session by the branch it
--- asks git for.
---@param action "save"|"load"
local function session(action)
  local persistence = package.loaded["persistence"]
  if not persistence or not persistence.active() then
    return false
  end
  if not require("util.git").allowed(vim.fn.getcwd()) then
    return false
  end
  if action == "save" then
    persistence.save()
    return true
  end
  if vim.fn.filereadable(persistence.current()) == 1 then
    persistence.load()
    return true
  end
  return false
end

--- Move to a worktree, taking the open files with you.
---@param path string
---@param opts? { tab: boolean, from: string }
function M.switch(path, opts)
  if type(opts) == "boolean" then
    opts = { tab = opts }
  end
  opts = opts or {}

  if vim.fn.isdirectory(path) ~= 1 then
    vim.notify("No such worktree: " .. path, vim.log.levels.ERROR, { title = "Worktree" })
    return
  end
  path = canonical(path)

  local from = opts.from or M.root()
  if from == path then
    return
  end

  if opts.tab then
    -- A new tab leaves this one exactly as it was.
    vim.cmd.tabnew()
    vim.cmd.tcd(path)
  else
    session("save")
    vim.cmd.cd(path)
  end

  local moved, kept = 0, {}
  if from and not opts.tab then
    stop_servers(from)
    moved, kept = carry_buffers(from, path)
  end

  -- LazyVim remembers each buffer's root; the buffers are new, but the cache
  -- is cleared too so nothing answers from the tree just left.
  if _G.LazyVim and LazyVim.root and LazyVim.root.cache then
    LazyVim.root.cache = {}
  end

  local message = vim.fn.fnamemodify(path, ":~")
  if #kept > 0 then
    message = message .. "\nLeft in the old tree, unsaved:\n  " .. table.concat(kept, "\n  ")
  end
  vim.notify(message, #kept > 0 and vim.log.levels.WARN or vim.log.levels.INFO, { title = "Worktree" })

  local restored = not opts.tab and session("load")

  -- Only when there is a picker: this module is also called from a spec,
  -- where the error arrived later as "attempt to index global 'Snacks'" from
  -- a scheduled callback, long after the test it belonged to had passed.
  if not restored and moved == 0 then
    vim.schedule(function()
      if Snacks and Snacks.picker then
        Snacks.picker.files()
      end
    end)
  end
end

--- Create a worktree for a branch, beside the repository, and move to it.
---
--- Beside, not inside: a worktree nested in the repository shows up in its own
--- file listings and grep results, which is exactly the noise this config
--- spends its search filters removing.
---
--- A worktree made here is trusted: it is a checkout you just asked for, of a
--- repository you were already allowed to run git in. One made some other
--- way still asks, since a branch can carry different code from the one you
--- trusted.
---@param branch string
---@param opts? { new: boolean, base: string, root: string }
---@return string|nil path
function M.add(branch, opts)
  opts = opts or {}

  local root = opts.root or M.root()
  if not root then
    vim.notify("Not inside a git repository.", vim.log.levels.WARN, { title = "Worktree" })
    return
  end

  local name = branch:gsub("[/%s]", "-")
  -- Named after the repository's own checkout, not the tree you are in, so
  -- a worktree made from a worktree is app-fix, not app-feature-fix.
  local main = M.list(root)[1]
  local base = main and main.main and not main.bare and main.path or root
  local path = vim.fs.joinpath(vim.fs.dirname(base), vim.fs.basename(base) .. "-" .. name)

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

  local _, ok, stderr = git(args, root)
  if not ok then
    vim.notify(stderr ~= "" and stderr or "git worktree add failed", vim.log.levels.ERROR, { title = "Worktree" })
    return
  end

  require("util.trust").allow(path)
  require("util.git").forget()

  vim.notify(("%s\n%s"):format(branch, vim.fn.fnamemodify(path, ":~")), vim.log.levels.INFO, {
    title = "Worktree created",
  })
  M.switch(path, { from = root })
  return canonical(path)
end

--- Why a worktree may not be removed, or nil when it may.
---@param tree worktree.Tree
---@return string|nil
function M.refusal(tree)
  if tree.main or tree.bare then
    return "the repository's own checkout is not a worktree to remove"
  end
  if tree.current then
    return "you are in it; switch to another worktree first"
  end
  if tree.locked then
    return "it is locked (git worktree unlock, if you mean it)"
  end
  return nil
end

--- Uncommitted work in a worktree, as `status --porcelain` lines.
---@param tree worktree.Tree
---@param root string
---@return string[]
function M.dirt(tree, root)
  if tree.prunable then
    return {}
  end
  local lines = git({ "-C", tree.path, "status", "--porcelain" }, root)
  return lines
end

--- Remove a worktree. Refuses what `M.refusal` refuses, and anything with
--- uncommitted work unless `force` is set.
---@param tree worktree.Tree
---@param opts? { force: boolean, root: string }
---@return boolean ok, string|nil why
function M.remove(tree, opts)
  opts = opts or {}
  local why = M.refusal(tree)
  if why then
    return false, why
  end

  local root = opts.root or M.root()
  if not root then
    return false, "not inside a git repository"
  end

  local args = { "worktree", "remove" }
  if opts.force then
    table.insert(args, "--force")
  end
  table.insert(args, tree.path)

  local _, ok, stderr = git(args, root)
  if not ok then
    return false, stderr ~= "" and stderr or "git worktree remove failed"
  end
  require("util.trust").revoke(tree.path)
  require("util.git").forget()
  return true
end

--- Forget worktrees whose directories are gone.
---@param root? string
---@return boolean ok, string|nil why
function M.prune(root)
  root = root or M.root()
  if not root then
    return false, "not inside a git repository"
  end
  local _, ok, stderr = git({ "worktree", "prune" }, root)
  return ok, not ok and stderr or nil
end

--- Run fn once the picker or prompt that just closed has finished closing.
---
--- Closing a picker puts the mode back on the next tick. Opening the next
--- picker or prompt synchronously lets that reset land on it, so typed text
--- runs as normal-mode commands, and a switch made from a prompt's callback
--- leaves the file in insert mode.
---@param fn fun()
local function after_close(fn)
  vim.schedule(function()
    vim.cmd.stopinsert()
    vim.schedule(fn)
  end)
end

--- Confirm and remove, from the picker.
---@param tree worktree.Tree
---@param root string
---@param done fun()
local function confirm_remove(tree, root, done)
  local why = M.refusal(tree)
  if why then
    vim.notify(("Not removing %s: %s."):format(vim.fn.fnamemodify(tree.path, ":~"), why), vim.log.levels.WARN, {
      title = "Worktree",
    })
    return done()
  end

  local shown = vim.fn.fnamemodify(tree.path, ":~")
  local dirt = M.dirt(tree, root)
  local question = ("Remove the worktree at %s?"):format(shown)
  if #dirt > 0 then
    question = ("%s\n\nIt has %d uncommitted change(s), which git will refuse to lose."):format(question, #dirt)
  end
  if vim.fn.confirm(question, "&Remove\n&Cancel", 2) ~= 1 then
    return done()
  end

  local ok, err = M.remove(tree, { root = root })
  if not ok and #dirt > 0 then
    local again = ("%s has uncommitted work:\n  %s\n\nDelete it anyway? This cannot be undone."):format(
      shown,
      table.concat(vim.list_slice(dirt, 1, 10), "\n  ")
    )
    if vim.fn.confirm(again, "&Delete anyway\n&Keep it", 2) == 1 then
      ok, err = M.remove(tree, { root = root, force = true })
    else
      return done()
    end
  end

  if ok then
    vim.notify("Removed " .. shown, vim.log.levels.INFO, { title = "Worktree" })
  else
    vim.notify(err or "git worktree remove failed", vim.log.levels.ERROR, { title = "Worktree" })
  end
  done()
end

--- Pick a worktree: switch, make, or remove one.
---@param root? string
function M.pick(root)
  root = root or M.root()
  local trees = root and M.list(root) or {}

  if #trees == 0 then
    vim.notify("No worktrees, or not a git repository.", vim.log.levels.WARN, { title = "Worktree" })
    return
  end

  local items = {}
  for index, tree in ipairs(trees) do
    local label = tree.branch ~= "" and tree.branch or (tree.detached and "detached" or "bare")
    local flags = {}
    for _, flag in ipairs({ "main", "locked", "detached", "prunable" }) do
      if tree[flag] then
        table.insert(flags, flag)
      end
    end
    table.insert(items, {
      idx = index,
      score = 0,
      text = label .. " " .. tree.path .. " " .. table.concat(flags, " "),
      file = tree.path,
      tree = tree,
      label = label,
      flags = table.concat(flags, " "),
    })
  end

  Snacks.picker.pick({
    source = "worktrees",
    items = items,
    title = "Worktrees   <c-t> tab  <a-n> new  <a-b> from branch  <a-d> remove  <a-p> prune",
    layout = { preset = "select", layout = { width = 0.85, height = 0.6 } },
    format = function(item)
      local tree = item.tree
      return {
        { tree.current and "● " or "  ", "SnacksPickerSpecial" },
        { ("%-28s"):format(item.label:sub(1, 28)), "SnacksPickerLabel" },
        { "  ", "SnacksPickerComment" },
        { ("%-10s"):format(tree.head), "SnacksPickerComment" },
        { "  ", "SnacksPickerComment" },
        { vim.fn.fnamemodify(tree.path, ":~"), "SnacksPickerDir" },
        { item.flags ~= "" and ("  " .. item.flags) or "", "SnacksPickerComment" },
      }
    end,
    win = {
      input = {
        keys = {
          ["<c-t>"] = { "worktree_tab", mode = { "i", "n" }, desc = "Open in a new tab" },
          ["<a-n>"] = { "worktree_new", mode = { "i", "n" }, desc = "New branch and worktree" },
          ["<a-b>"] = { "worktree_branch", mode = { "i", "n" }, desc = "Worktree for an existing branch" },
          ["<a-d>"] = { "worktree_remove", mode = { "i", "n" }, desc = "Remove this worktree" },
          ["<a-p>"] = { "worktree_prune", mode = { "i", "n" }, desc = "Forget worktrees whose directory is gone" },
        },
      },
    },
    actions = {
      worktree_tab = function(picker, item)
        picker:close()
        if item then
          M.switch(item.tree.path, { tab = true, from = root })
        end
      end,
      worktree_new = function(picker)
        picker:close()
        -- Ask what to base it on before asking what to call it. A new branch
        -- always comes off something, and answering that from memory is how
        -- you end up branching off whatever happened to be checked out.
        after_close(function()
          M.pick_branch(function(base)
            vim.ui.input({ prompt = ("New branch off %s: "):format(base or "HEAD") }, function(branch)
              if branch and branch ~= "" then
                after_close(function()
                  M.add(branch, { new = true, base = base, root = root })
                end)
              end
            end)
          end, root)
        end)
      end,
      worktree_branch = function(picker)
        picker:close()
        after_close(function()
          M.pick_branch(nil, root)
        end)
      end,
      worktree_remove = function(picker, item)
        picker:close()
        if item then
          confirm_remove(item.tree, root, function()
            vim.schedule(function()
              M.pick(root)
            end)
          end)
        end
      end,
      worktree_prune = function(picker)
        picker:close()
        local ok, err = M.prune(root)
        if not ok then
          vim.notify(err or "git worktree prune failed", vim.log.levels.ERROR, { title = "Worktree" })
        end
        vim.schedule(function()
          M.pick(root)
        end)
      end,
    },
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      if item.tree.prunable or item.tree.bare then
        vim.notify(
          item.tree.bare and "A bare repository has no files to switch to." or "Its directory is gone. <a-p> forgets it.",
          vim.log.levels.WARN,
          { title = "Worktree" }
        )
        return
      end
      M.switch(item.tree.path, { from = root })
    end,
  })
end

--- Pick a branch, and put a worktree on it.
---
--- With `on_pick`, the branch is handed back instead, which is how choosing a
--- base for a new branch reuses this list rather than growing a second one.
---@param on_pick? fun(branch: string)
---@param root? string
function M.pick_branch(on_pick, root)
  root = root or M.root()
  local lines, ok = {}, false
  if root then
    lines, ok = git({ "branch", "--all", "--format=%(refname:short)" }, root)
  end

  if not ok or #lines == 0 then
    vim.notify("No branches, or not a git repository.", vim.log.levels.WARN, { title = "Worktree" })
    return
  end

  -- A branch that already has a worktree cannot get a second one.
  local taken = {}
  for _, tree in ipairs(M.list(root)) do
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

      after_close(function()
        if on_pick then
          -- A branch that already has a worktree is a perfectly good base, so
          -- the "taken" note is information here rather than a refusal.
          on_pick(item.branch)
        elseif item.taken then
          M.switch(item.taken, { from = root })
        else
          M.add(item.branch, { root = root })
        end
      end)
    end,
  })
end

--- Remember the main checkout while lazygit is open, so that if lazygit
--- removes the worktree you are standing in, there is somewhere to go back to.
function M.watch_lazygit()
  local group = vim.api.nvim_create_augroup("dotfiles_worktree_lazygit", { clear = true })
  local main

  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    pattern = "term://*lazygit*",
    callback = function()
      main = nil
      local root = M.root()
      if root and require("util.git").allowed(root) then
        local trees = M.list(root)
        main = trees[1] and trees[1].path
      end
    end,
  })

  vim.api.nvim_create_autocmd("TermClose", {
    group = group,
    pattern = "term://*lazygit*",
    callback = function()
      vim.schedule(function()
        local cwd = vim.fn.getcwd()
        if vim.uv.fs_stat(cwd) or not main or not vim.uv.fs_stat(main) then
          return
        end
        local question = ("This worktree is gone:\n%s\n\nMove to the main checkout at %s?"):format(
          vim.fn.fnamemodify(cwd, ":~"),
          vim.fn.fnamemodify(main, ":~")
        )
        if vim.fn.confirm(question, "&Move\n&Stay", 1) == 1 then
          M.switch(main, { from = canonical(cwd) })
        end
      end)
    end,
  })
end

return M
