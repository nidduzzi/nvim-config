--- Asking about an untrusted project, and the menu that answers.
---
--- Trust decides whether a project's own programs run: its language servers,
--- its debug adapters, its formatters, and --- since git was gated --- its
--- git, which means the gutter signs and every diff. A configuration that
--- only tells you with a command is a configuration where the answer is "the
--- signs are missing again" and nothing explains it.
---
--- So: asked once per project, when you open one that has not been answered
--- for, and reachable on a key at any time. Nothing is shown for a project
--- that is already trusted, which is almost all of them after a while.

local M = {}

--- Projects asked about in this session, so moving between buffers of one
--- project does not ask again.
---@type table<string, boolean>
local asked = {}

--- Forget which projects have been asked, for when trust changes.
function M.forget()
  asked = {}
end

--- Is this a project at all?
---
--- A single file opened from somewhere unrelated has no project to trust, and
--- asking about a directory is noise.
---@param root string
---@return boolean
local function is_project(root)
  return vim.uv.fs_stat(vim.fs.joinpath(root, ".git")) ~= nil
end

--- What the machine-local settings file would need, written as Lua.
---@param path string
---@return string[]
local function always_run_git(path)
  local existing = {}
  if vim.uv.fs_stat(path) then
    existing = vim.fn.readfile(path)
  end

  -- An existing file is left alone apart from the one setting: it is yours,
  -- and this is not the place to reformat it.
  for index, line in ipairs(existing) do
    if line:match("^%s*git_project%s*=") then
      existing[index] = "  git_project = true,"
      return existing
    end
  end

  if #existing == 0 then
    return {
      "-- Settings for this machine only. See lua/util/settings.lua.",
      "return {",
      "  git_project = true,",
      "}",
    }
  end

  for index, line in ipairs(existing) do
    if line:match("^%s*return%s*{") then
      table.insert(existing, index + 1, "  git_project = true,")
      return existing
    end
  end

  return existing
end

--- The menu. Shown by the prompt and by the key, with the same choices.
---@param root string
function M.open(root)
  local trust = require("util.trust")
  local git = require("util.git")
  local private = require("util.private")

  local trusted = trust.is_trusted(root)
  local where = vim.fn.fnamemodify(root, ":~")

  ---@type { label: string, run: fun() }[]
  local choices = {}

  if trusted then
    choices[#choices + 1] = {
      label = "Stop trusting this project",
      run = function()
        trust.revoke(root)
        git.forget()
        M.forget()
        vim.notify(("%s is no longer trusted."):format(where), vim.log.levels.INFO, { title = "Trust" })
      end,
    }
  else
    choices[#choices + 1] = {
      label = "Trust this project: run its programs and its git",
      run = function()
        trust.allow(root)
        git.forget()
        M.forget()
        vim.cmd("silent! edit")
        vim.notify(
          ("%s is trusted.\n\nIts language servers, formatters, debug adapters and git will run."):format(where),
          vim.log.levels.INFO,
          { title = "Trust" }
        )
      end,
    }
    choices[#choices + 1] = {
      label = "Not now: ask again next time this project is opened",
      run = function() end,
    }
    choices[#choices + 1] = {
      label = "Trust every project on this machine (writes local.lua)",
      run = function()
        local path = require("util.settings").local_file()
        private.writefile(path, always_run_git(path))
        require("util.settings").reload()
        git.forget()
        M.forget()
        vim.cmd("silent! edit")
        vim.notify(
          ("git will run everywhere on this machine.\n\n%s now sets git_project = true."):format(vim.fn.fnamemodify(path, ":~")),
          vim.log.levels.INFO,
          { title = "Trust" }
        )
      end,
    }
  end

  local labels = {}
  for index, choice in ipairs(choices) do
    labels[index] = choice.label
  end

  vim.ui.select(labels, {
    prompt = trusted and ("Trusted: " .. where) or ("Not trusted: " .. where),
  }, function(_, index)
    if index then
      choices[index].run()
    end
  end)
end

--- Ask about this project, once, if it has not been trusted.
---
--- Deferred rather than immediate: a prompt that appears while the editor is
--- still drawing its dashboard is a prompt that eats the first keys you type.
---@param root? string
function M.ask_if_untrusted(root)
  if require("util.settings").get("git_project") ~= "ask" then
    return
  end

  root = require("util.lsp").root(root or vim.fn.getcwd())
  if asked[root] or not is_project(root) or require("util.trust").is_trusted(root) then
    return
  end
  asked[root] = true

  -- Immediately, because by the time a file has been read snacks already
  -- owns vim.ui.select and you have not had time to type anything. The first
  -- version waited a second and a half for snacks to be ready, and that delay
  -- was the whole problem: it landed on whatever you had started in the
  -- meantime, and took the keys meant for it.
  vim.schedule(function()
    M.open(root)
  end)
end

return M
