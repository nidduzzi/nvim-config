-- Diffview toggling. diffview.nvim is not loaded in this test environment,
-- so is_open() always answers false here and the interesting half of
-- toggle_merge() -- counting real conflicts with a real git repository -- is
-- what this proves; the Diffview* commands themselves are intercepted rather
-- than run, since the plugin that provides them is not present to run them.

local diff = require("util.diff")

---@return string
local function make_repo()
  local repo = vim.fn.tempname()
  vim.fn.mkdir(repo, "p")
  vim.system({ "git", "init", "-q", "-b", "main" }, { cwd = repo }):wait()
  vim.system({ "git", "config", "user.email", "spec@example.invalid" }, { cwd = repo }):wait()
  vim.system({ "git", "config", "user.name", "Spec" }, { cwd = repo }):wait()
  return repo
end

---@param repo string
local function leave_a_conflict(repo)
  local path = vim.fs.joinpath(repo, "conflict.txt")
  vim.fn.writefile({ "base" }, path)
  vim.system({ "git", "add", "-A" }, { cwd = repo }):wait()
  vim.system({ "git", "commit", "-q", "-m", "base" }, { cwd = repo }):wait()

  vim.system({ "git", "checkout", "-q", "-b", "other" }, { cwd = repo }):wait()
  vim.fn.writefile({ "changed on other" }, path)
  vim.system({ "git", "commit", "-q", "-am", "on other" }, { cwd = repo }):wait()

  vim.system({ "git", "checkout", "-q", "main" }, { cwd = repo }):wait()
  vim.fn.writefile({ "changed on main" }, path)
  vim.system({ "git", "commit", "-q", "-am", "on main" }, { cwd = repo }):wait()

  -- Expected to fail: that is what leaves the conflict markers and the
  -- unmerged entry `git diff --diff-filter=U` reads.
  vim.system({ "git", "merge", "-q", "other" }, { cwd = repo }):wait()
end

describe("the merge conflict view", function()
  local repo, cwd_before, cmd_before, run

  before_each(function()
    cwd_before = vim.uv.cwd()
    cmd_before = vim.cmd
    run = {}
    vim.cmd = setmetatable({}, {
      __call = function(_, command)
        if type(command) == "string" and command:match("^Diffview") then
          table.insert(run, command)
        else
          cmd_before(command)
        end
      end,
      __index = cmd_before,
    })
  end)

  after_each(function()
    vim.cmd = cmd_before
    vim.cmd.cd(cwd_before)
    if repo then
      vim.fn.delete(repo, "rf")
      repo = nil
    end
  end)

  it("says so plainly outside a git repository, and opens nothing", function()
    repo = vim.fn.tempname()
    vim.fn.mkdir(repo, "p")
    vim.cmd.cd(repo)

    local notified
    local original_notify = vim.notify
    vim.notify = function(message)
      notified = message
    end
    diff.toggle_merge()
    vim.notify = original_notify

    assert.is_truthy(notified:match("Not inside a git repository"))
    assert.are.same({}, run)
  end)

  it("opens the ordinary diff and says there is nothing to resolve, with no conflict", function()
    repo = make_repo()
    vim.fn.writefile({ "x" }, vim.fs.joinpath(repo, "clean.txt"))
    vim.system({ "git", "add", "-A" }, { cwd = repo }):wait()
    vim.system({ "git", "commit", "-q", "-m", "clean" }, { cwd = repo }):wait()
    vim.cmd.cd(repo)

    local notified
    local original_notify = vim.notify
    vim.notify = function(message)
      notified = message
    end
    diff.toggle_merge()
    vim.notify = original_notify

    assert.is_truthy(notified:match("No conflicts to resolve"))
    assert.are.same({ "DiffviewOpen" }, run)
  end)

  it("counts a real conflict left by a real failed merge, singular", function()
    repo = make_repo()
    leave_a_conflict(repo)
    vim.cmd.cd(repo)

    local notified
    local original_notify = vim.notify
    vim.notify = function(message)
      notified = message
    end
    diff.toggle_merge()
    vim.notify = original_notify

    assert.is_truthy(notified:match("^1 file with conflicts"))
    assert.are.same({ "DiffviewOpen" }, run)
  end)

  it("closes rather than reopening, once a view is already open", function()
    -- is_open() answers through diffview.lib, which is not loaded in this
    -- test environment and so always answers false -- forced true here to
    -- reach the close branch at all, the one thing this file cannot prove
    -- against the real plugin.
    local original_is_open = diff.is_open
    diff.is_open = function()
      return true
    end
    diff.toggle_merge()
    diff.is_open = original_is_open

    assert.are.same({ "DiffviewClose" }, run)
  end)
end)

describe("toggle", function()
  local cmd_before, run

  before_each(function()
    cmd_before = vim.cmd
    run = {}
    vim.cmd = setmetatable({}, {
      __call = function(_, command)
        table.insert(run, command)
      end,
      __index = cmd_before,
    })
  end)

  after_each(function()
    vim.cmd = cmd_before
  end)

  it("runs the command handed to it, when nothing is open", function()
    diff.toggle("DiffviewFileHistory %")
    assert.are.same({ "DiffviewFileHistory %" }, run)
  end)

  it("closes instead, once something is open", function()
    local original_is_open = diff.is_open
    diff.is_open = function()
      return true
    end
    diff.toggle("DiffviewFileHistory %")
    diff.is_open = original_is_open

    assert.are.same({ "DiffviewClose" }, run)
  end)
end)
