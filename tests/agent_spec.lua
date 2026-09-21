-- The parts of util/agent/init.lua besides refusal() (which rung_spec.lua
-- already covers) and ask() (which needs a real process and is exercised end
-- to end by tools/nvim-harness/check-agent.sh instead): switching backend,
-- moving the trust rung, and reporting what the session has cost.

local agent = require("util.agent")
local backends = require("util.agent.backends")
local settings = require("util.settings")

local original_notify, original_select
local notified

before_each(function()
  original_notify = vim.notify
  original_select = vim.ui.select
  notified = {}
  vim.notify = function(message, level)
    table.insert(notified, { message = message, level = level })
  end
end)

after_each(function()
  vim.notify = original_notify
  vim.ui.select = original_select
  settings.clear("agent_backend")
  settings.clear("agent_trust")
end)

describe("switching backend", function()
  -- Whether the real CLIs are installed is a fact about this machine, not
  -- about the logic under test, and CI runners have none of them: the first
  -- version of this asked for "claude" directly and failed everywhere but
  -- here. claude.cmd is pointed at a real, portable executable for the
  -- length of this block instead, so resolve() has something genuine to
  -- find regardless of what is actually installed.
  local dir, path_before, cmd_before, proven_before

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    path_before = vim.env.PATH

    local windows = vim.fn.has("win32") == 1
    local program = vim.fs.joinpath(dir, "spec-fake-backend" .. (windows and ".bat" or ""))
    vim.fn.writefile(windows and { "@echo off", "exit /b 0" } or { "#!/bin/sh", "exit 0" }, program)
    vim.fn.setfperm(program, "rwxr-xr-x")
    vim.env.PATH = dir .. (windows and ";" or ":") .. path_before

    cmd_before = backends.claude.cmd
    proven_before = backends.claude.proven
    backends.claude.cmd = vim.fs.basename(program)
  end)

  after_each(function()
    vim.env.PATH = path_before
    vim.fn.delete(dir, "rf")
    backends.claude.cmd = cmd_before
    backends.claude.proven = proven_before
  end)

  it("switches to a real, resolvable backend named directly", function()
    agent.use("claude")
    assert.are.same("claude", settings.get("agent_backend"))
    assert.are.equal(1, #notified)
    assert.is_truthy(notified[1].message:match("^Now asking Claude"))
  end)

  it("does not switch on a name nothing here knows", function()
    settings.set("agent_backend", "claude")
    agent.use("not-a-real-backend")
    assert.are.same("claude", settings.get("agent_backend"))
    assert.are.equal(vim.log.levels.ERROR, notified[1].level)
  end)

  it("does not switch to a known backend that is not on this machine's PATH", function()
    -- codex is a real entry in backends.lua and genuinely not installed on
    -- any machine this runs on -- the case the "not on PATH" branch exists
    -- for, not a fake one.
    settings.set("agent_backend", "claude")
    agent.use("codex")
    assert.are.same("claude", settings.get("agent_backend"))
    assert.is_truthy(notified[1].message:match("not on PATH"))
  end)

  it("says plainly when the backend has not been shown to refuse a write", function()
    backends.claude.proven = false
    agent.use("claude")
    assert.is_truthy(notified[1].message:match("unproven"))
    assert.are.equal(vim.log.levels.WARN, notified[1].level)
  end)

  it("does nothing at all for an empty choice", function()
    settings.set("agent_backend", "claude")
    agent.use("")
    assert.are.same("claude", settings.get("agent_backend"))
    assert.are.equal(0, #notified)
  end)

  it("offers only the backends actually on PATH, with none chosen", function()
    local offered
    vim.ui.select = function(items, _, on_choice)
      offered = items
      on_choice(nil)
    end
    agent.use()
    assert.is_truthy(vim.tbl_contains(offered, backends.claude.cmd))
    assert.is_falsy(vim.tbl_contains(offered, backends.codex.cmd))
  end)
end)

describe("moving the trust rung", function()
  before_each(function()
    settings.set("agent_backend", "claude")
  end)

  it("moves to a rung named directly", function()
    agent.trust("explore")
    assert.are.same("explore", settings.get("agent_trust"))
  end)

  it("refuses a name that is not a real rung", function()
    settings.set("agent_trust", "context")
    agent.trust("not-a-real-rung")
    assert.are.same("context", settings.get("agent_trust"))
    assert.are.equal(vim.log.levels.ERROR, notified[1].level)
  end)

  it("names the highest rung as a warning, everything else as information", function()
    agent.trust("normal")
    assert.are.equal(vim.log.levels.WARN, notified[1].level)

    notified = {}
    agent.trust("context")
    assert.are.equal(vim.log.levels.INFO, notified[1].level)
  end)

  it("steps rather than jumping, when asked by a count instead of a name", function()
    settings.set("agent_trust", "context")
    agent.trust(nil, 1)
    assert.are.same("explore", settings.get("agent_trust"))
  end)

  it("offers every rung by name when asked with neither a name nor a count", function()
    local offered
    vim.ui.select = function(items, _, on_choice)
      offered = items
      on_choice(nil)
    end
    agent.trust()
    assert.are.same(backends.rungs, offered)
  end)
end)

describe("what this session has cost", function()
  it("names the current backend, rung and project", function()
    settings.set("agent_backend", "claude")
    settings.set("agent_trust", "explore")
    agent.report()

    local message = notified[1].message
    assert.is_truthy(message:match("agent: Claude"))
    assert.is_truthy(message:match("rung: explore"))
    assert.is_truthy(message:match("project: "))
  end)

  it("says plainly when nothing has been spent yet, rather than $0.0000", function()
    -- Real, not assumed: nothing in this whole suite calls the actual
    -- agent.ask -- every spec that reaches it replaces the function first --
    -- so M.spend is still at the value it loaded with, and this can assert
    -- the exact wording rather than tolerate either branch.
    settings.set("agent_backend", "claude")
    agent.report()
    assert.is_truthy(notified[1].message:match("spent: not reported by this agent"))
    assert.is_truthy(notified[1].message:match("last call: none yet"))
  end)
end)

describe("cancelling", function()
  it("says plainly when nothing is running, rather than erroring", function()
    assert.is_false(agent.is_running())
    agent.cancel()
    assert.is_truthy(notified[1].message:match("Nothing running"))
  end)
end)

describe("starting a new conversation", function()
  -- session_file() is private to util/agent/init.lua, with no accessor of
  -- its own -- the file it names is reconstructed here from the same public
  -- pieces the module builds it from (M.config.backend, the project root,
  -- vim.fn.stdpath("state")), the only way to prove reset() actually removes
  -- the right file rather than trusting that it does.
  local root, cwd_before

  before_each(function()
    settings.set("agent_backend", "claude")
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    cwd_before = vim.uv.cwd()
    vim.cmd.cd(root)
  end)

  after_each(function()
    vim.cmd.cd(cwd_before)
    vim.fn.delete(root, "rf")
  end)

  ---@return string
  local function session_path()
    local resolved = agent.root()
    local dir = vim.fs.joinpath(vim.fn.stdpath("state") --[[@as string]], "nvim-agent")
    vim.fn.mkdir(dir, "p")
    return vim.fs.joinpath(dir, ("%s-%s"):format(settings.get("agent_backend"), vim.fn.sha256(resolved):sub(1, 16)))
  end

  it("removes the remembered conversation for this project", function()
    local path = session_path()
    vim.fn.writefile({ "a-real-session-id" }, path)
    assert.are.equal(1, vim.fn.filereadable(path))

    agent.reset()

    assert.are.equal(0, vim.fn.filereadable(path))
    assert.is_truthy(notified[1].message:match("^Starting a new conversation for"))
  end)

  it("says so even when there was nothing to forget", function()
    local path = session_path()
    vim.fn.delete(path)

    agent.reset()

    assert.are.equal(0, vim.fn.filereadable(path))
    assert.is_truthy(notified[1].message:match("^Starting a new conversation for"))
  end)
end)
