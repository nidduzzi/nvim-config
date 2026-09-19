--- Open and close the diff views that the plugin cannot toggle itself.
---
--- Diffview opens in a tab of its own, so a plain "open" mapping leaves you
--- hunting for :DiffviewClose, or accumulating tabs. Every key here is a
--- toggle: the key that opened the view closes it, from inside the view as
--- well as from the file you started in.
---
--- The working-tree diff no longer goes through here. diffview-plus ships
--- `:DiffviewToggle`, documented as an alias for `:DiffviewOpen` outside a
--- Diffview tab and for `:DiffviewClose` inside one, which is this behaviour
--- with none of this code.
---
--- It does not cover the other two, and the reason is worth writing down so
--- nobody deletes them expecting it to. `:DiffviewToggle` takes `:DiffviewOpen`'s
--- arguments, and file history is a separate command rather than an option of
--- it: the documented list has `:DiffviewFileHistory` and no toggling form. The
--- merge view is not a command at all, it is `:DiffviewOpen` plus knowing
--- whether there is anything to resolve.

local M = {}

--- Is a diffview tab currently open?
---@return boolean
function M.is_open()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then
    return false
  end
  return lib.get_current_view() ~= nil
end

--- Run a Diffview command, or close the view if one is already open.
---@param command string the :Diffview… command to open with
function M.toggle(command)
  if M.is_open() then
    vim.cmd("DiffviewClose")
    return
  end
  vim.cmd(command)
end

--- Open the three-way view for a merge or rebase in progress.
---
--- During a merge, `:DiffviewOpen` already lists the conflicted files, so the
--- work here is telling you when there is nothing to resolve, rather than
--- opening an empty panel that looks broken.
function M.toggle_merge()
  if M.is_open() then
    vim.cmd("DiffviewClose")
    return
  end

  local conflicts = vim.fn.systemlist("git diff --name-only --diff-filter=U")

  if vim.v.shell_error ~= 0 then
    vim.notify("Not inside a git repository.", vim.log.levels.WARN, { title = "Diff" })
    return
  end

  if #conflicts == 0 then
    vim.notify("No conflicts to resolve.\nOpening the working tree diff instead.", vim.log.levels.INFO, { title = "Diff" })
    vim.cmd("DiffviewOpen")
    return
  end

  vim.notify(
    ("%d file%s with conflicts.\n\nIn the middle file: <leader>co takes ours, <leader>ct theirs,\n<leader>cb the base, <leader>ca all of them, dx none.\n]x and [x jump between conflicts."):format(
      #conflicts,
      #conflicts == 1 and "" or "s"
    ),
    vim.log.levels.INFO,
    { title = "Merge conflicts" }
  )

  vim.cmd("DiffviewOpen")
end

return M
