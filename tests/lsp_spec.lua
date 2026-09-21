-- Which language server attaches, with what command, and what gets said
-- when nothing can. vim.lsp.config accepts new names freely but never
-- forgets one once set, so each test below declares its own uniquely-named
-- fake server rather than resetting a shared one -- the same shape trust_spec
-- and bin_dirs_spec already use for real temp directories.

local lsp = require("util.lsp")
local settings = require("util.settings")
local trust = require("util.trust")

local windows = vim.fn.has("win32") == 1

---@param path string
local function make_executable(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(windows and { "@echo off", "exit /b 0" } or { "#!/bin/sh", "exit 0" }, path)
  vim.fn.setfperm(path, "rwxr-xr-x")
end

local counter = 0
---@return string a fake server name no other test has used
local function fake_name()
  counter = counter + 1
  return "lsp_spec_fake_" .. counter
end

describe("resolving where a server's command comes from", function()
  local path_before

  before_each(function()
    path_before = vim.env.PATH
  end)

  after_each(function()
    vim.env.PATH = path_before
  end)

  it("leaves alone a server that builds its own command", function()
    local name = fake_name()
    vim.lsp.config[name] = { cmd = function() end }
    assert.is_nil(lsp.resolve(name))
  end)

  it("finds nothing for a command that exists nowhere", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.env.PATH = dir

    local name = fake_name()
    vim.lsp.config[name] = { cmd = { "nonexistent-" .. name } }
    assert.is_nil(lsp.resolve(name))
    vim.fn.delete(dir, "rf")
  end)

  it("resolves to PATH when nothing in the project provides it", function()
    local dir = vim.fn.tempname()
    local program = windows and "fromPATH.bat" or "fromPATH"
    make_executable(vim.fs.joinpath(dir, program))
    vim.env.PATH = dir .. (windows and ";" or ":") .. path_before

    local name = fake_name()
    vim.lsp.config[name] = { cmd = { program } }
    local found = lsp.resolve(name)
    assert.is_truthy(found)
    assert.are.same("PATH", found.source)
    assert.are.same({ program }, found.cmd)
    vim.fn.delete(dir, "rf")
  end)

  it("prefers a trusted project's own copy over PATH", function()
    local root = vim.fn.tempname()
    local bin = windows and "Scripts" or "bin"
    local program = windows and "ruff.exe" or "ruff"
    local project_bin = vim.fs.joinpath(root, ".venv", bin, program)
    make_executable(project_bin)
    vim.fn.writefile({ "version = 3.12" }, vim.fs.joinpath(root, ".venv", "pyvenv.cfg"))
    trust.allow(root)

    -- Also on PATH, so the assertion proves preference, not absence of choice.
    local path_dir = vim.fn.tempname()
    make_executable(vim.fs.joinpath(path_dir, "ruff"))
    vim.env.PATH = path_dir .. (windows and ";" or ":") .. path_before

    local name = fake_name()
    vim.lsp.config[name] = { cmd = { "ruff", "server" } }

    -- resolve() takes no root; it asks project_bin() which uses cwd.
    local cwd_before = vim.uv.cwd()
    vim.cmd.cd(root)
    local found = lsp.resolve(name)
    vim.cmd.cd(cwd_before)

    assert.is_truthy(found)
    assert.are.same("project", found.source)
    assert.are.same(vim.uv.fs_realpath(project_bin), vim.uv.fs_realpath(found.cmd[1]))
    assert.are.same("server", found.cmd[2])

    trust.revoke(root)
    vim.fn.delete(root, "rf")
    vim.fn.delete(path_dir, "rf")
  end)
end)

describe("keeping only the servers a project can provide", function()
  local cwd_before, root

  before_each(function()
    cwd_before = vim.uv.cwd()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.cmd.cd(root)
    settings.clear("lsp_ignore")
  end)

  after_each(function()
    vim.cmd.cd(cwd_before)
    trust.revoke(root)
    settings.clear("lsp_ignore")
    vim.fn.delete(root, "rf")
  end)

  it("leaves the settings-shared '*' key untouched", function()
    local servers = { ["*"] = { on_attach = "shared" } }
    lsp.keep_available(servers)
    assert.are.same({ on_attach = "shared" }, servers["*"])
    assert.is_nil(lsp.status["*"])
  end)

  it("does not touch a server a caller already disabled", function()
    local name = fake_name()
    vim.lsp.config[name] = { cmd = { "does-not-matter" } }
    local servers = { [name] = { enabled = false } }
    lsp.keep_available(servers)
    assert.is_false(servers[name].enabled)
    assert.is_nil(lsp.status[name])
  end)

  it("keeps the baseline enabled even before Mason has installed it", function()
    local name = fake_name()
    lsp.baseline[#lsp.baseline + 1] = name
    vim.lsp.config[name] = { cmd = { "nonexistent-" .. name }, filetypes = { "lua" } }

    local servers = { [name] = {} }
    lsp.keep_available(servers)

    assert.is_not.same(false, servers[name].enabled)
    assert.is_false(servers[name].mason)
    assert.are.same("editor", lsp.status[name].status)

    lsp.baseline[#lsp.baseline] = nil
  end)

  it("disables a non-baseline server nothing provides", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local path_before = vim.env.PATH
    vim.env.PATH = dir

    local name = fake_name()
    vim.lsp.config[name] = { cmd = { "nonexistent-" .. name }, filetypes = { "rust" } }
    local servers = { [name] = {} }
    lsp.keep_available(servers)

    assert.is_false(servers[name].enabled)
    assert.are.same("missing", lsp.status[name].status)

    vim.env.PATH = path_before
    vim.fn.delete(dir, "rf")
  end)

  it("points a server at the project's own copy and tells Mason to stand down", function()
    local bin = windows and "Scripts" or "bin"
    local program = windows and "ruff.exe" or "ruff"
    local project_bin = vim.fs.joinpath(root, ".venv", bin, program)
    make_executable(project_bin)
    vim.fn.writefile({ "version = 3.12" }, vim.fs.joinpath(root, ".venv", "pyvenv.cfg"))
    trust.allow(root)

    local name = fake_name()
    vim.lsp.config[name] = { cmd = { "ruff", "server" }, filetypes = { "python" } }
    local servers = { [name] = {} }
    lsp.keep_available(servers)

    assert.is_false(servers[name].mason)
    assert.are.same("project", lsp.status[name].status)
    assert.are.same(vim.uv.fs_realpath(project_bin), vim.uv.fs_realpath(servers[name].cmd[1]))
  end)

  it("disables a server the project asked to ignore, even though it is provided", function()
    local path_dir = vim.fn.tempname()
    local path_before = vim.env.PATH
    make_executable(vim.fs.joinpath(path_dir, "sometool"))
    vim.env.PATH = path_dir .. (windows and ";" or ":") .. path_before

    local name = fake_name()
    vim.lsp.config[name] = { cmd = { "sometool" }, filetypes = { "python" } }
    settings.set("lsp_ignore", { name })

    local servers = { [name] = {} }
    lsp.keep_available(servers)

    assert.is_false(servers[name].enabled)
    assert.are.same("ignored", lsp.status[name].status)

    vim.env.PATH = path_before
    vim.fn.delete(path_dir, "rf")
  end)
end)

describe("saying which language server is missing", function()
  local original_notify

  before_each(function()
    original_notify = vim.notify
  end)

  after_each(function()
    vim.notify = original_notify
  end)

  it("says nothing for a filetype no server is configured for", function()
    lsp.status = {}
    local seen
    vim.notify = function(msg)
      seen = msg
    end
    lsp.warn_missing("lsp_spec_unconfigured_ft")
    assert.is_truthy(seen:match("none is configured"))
  end)

  it("says nothing for a filetype this config deliberately does not serve", function()
    local seen = false
    vim.notify = function()
      seen = true
    end
    lsp.warn_missing("gitcommit")
    assert.is_false(seen)
  end)

  it("names the missing server when the filetype is configured but unprovided", function()
    local name = fake_name()
    lsp.status[name] = { status = "missing", filetypes = { "lsp_spec_missing_ft" } }
    local seen
    vim.notify = function(msg)
      seen = msg
    end
    lsp.warn_missing("lsp_spec_missing_ft")
    assert.is_truthy(seen:match(name))
    assert.is_truthy(seen:match("Configured but not provided"))
  end)

  it("says nothing when every configured server for the filetype is available", function()
    local name = fake_name()
    lsp.status[name] = { status = "PATH", filetypes = { "lsp_spec_ok_ft" } }
    local seen = false
    vim.notify = function()
      seen = true
    end
    lsp.warn_missing("lsp_spec_ok_ft")
    assert.is_false(seen)
  end)

  it("warns only once per filetype", function()
    local name = fake_name()
    lsp.status[name] = { status = "missing", filetypes = { "lsp_spec_once_ft" } }
    local count = 0
    vim.notify = function()
      count = count + 1
    end
    lsp.warn_missing("lsp_spec_once_ft")
    lsp.warn_missing("lsp_spec_once_ft")
    assert.are.same(1, count)
  end)
end)
