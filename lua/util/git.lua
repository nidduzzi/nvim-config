local M = {}

M.permission_changed_event = "DotfilesGitPermissionChanged"

function M.notify_permission_changed()
  vim.api.nvim_exec_autocmds("User", { pattern = M.permission_changed_event, modeline = false })
end

---@param root? string
---@return boolean
function M.allowed(root)
  local allowed = require("util.settings").get("git_project")
  if allowed == true or allowed == false then
    return allowed
  end

  root = require("util.lsp").root(root or vim.fn.getcwd())
  return require("util.trust").is_trusted(root) or require("util.git_repository").names_no_programs(root)
end

---@generic T
---@param fn fun(): T
---@param root? string
---@return T|nil
function M.guard(fn, root)
  if M.allowed(root) then
    return fn()
  end

  if require("util.settings").get("git_project") == false then
    vim.notify("git is turned off on this machine: git_project is false.", vim.log.levels.WARN, { title = "git" })
    return nil
  end

  require("util.trust_menu").open(require("util.lsp").root(root or vim.fn.getcwd()))
  return nil
end

return M
