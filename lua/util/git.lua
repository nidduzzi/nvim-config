--- Whether this project's git may be run.
---
--- git executes programs a repository names in its own `.git/config`:
--- `diff.<driver>.textconv` on any diff of a file `.gitattributes` matches,
--- `diff.external` in place of the diff machinery, `filter.<name>.clean` and
--- `smudge`, `core.pager`, and `core.fsmonitor` --- which almost every git
--- command runs, `status` included.
---
--- A clone cannot carry that config, so this is about a directory that
--- arrived some other way: an archive, a shared drive, a container volume.
--- The answer is the one already used for a project's language servers,
--- debug adapters and formatters --- it runs when you have said the project
--- is yours --- so there is one switch rather than two.
---
--- Gating any git command rather than only the diffs is deliberate:
--- `core.fsmonitor` turns `git status` into a program the repository chose.

local M = {}

--- Roots already answered, so a gutter redraw is not a file read.
---@type table<string, boolean>
local answered = {}

--- Forget the answers, for when a project has just been trusted.
function M.forget()
  answered = {}
end

--- May git run for this project?
---@param root? string
---@return boolean
function M.allowed(root)
  root = require("util.lsp").root(root or vim.fn.getcwd())

  if answered[root] == nil then
    answered[root] = require("util.trust").is_trusted(root)
  end
  return answered[root]
end

--- Roots already told about, so the message appears once per project rather
--- than once per keypress.
---@type table<string, boolean>
local told = {}

--- Say why a git feature did nothing, once.
---@param root? string
function M.say_refused(root)
  root = require("util.lsp").root(root or vim.fn.getcwd())
  if told[root] then
    return
  end
  told[root] = true

  vim.notify(
    table.concat({
      "git is not run in an untrusted project.",
      "",
      "A repository's own .git/config can name programs git will run:",
      "textconv on a diff, and core.fsmonitor on almost anything.",
      "",
      ":DotfilesTrustProject to use git here.",
    }, "\n"),
    vim.log.levels.WARN,
    { title = "Untrusted project" }
  )
end

--- Run `fn` when git is allowed here, and explain when it is not.
---@generic T
---@param fn fun(): T
---@param root? string
---@return T|nil
function M.guard(fn, root)
  if not M.allowed(root) then
    M.say_refused(root)
    return nil
  end
  return fn()
end

return M
