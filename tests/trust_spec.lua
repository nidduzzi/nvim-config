local settings = require("util.settings")
local trust = require("util.trust")

--- One spelling for a path, the way util.lsp.root produces it.
---
--- A temporary directory is handed out under a name that is not its own:
--- macOS gives /var/folders, which is really /private/var/folders, and
--- Windows gives C:\Users\RUNNER~1, which is really C:\Users\runneradmin.
--- The code resolves; a spec that compares against the name it was given is
--- comparing two spellings of one file.
---@param path string
---@return string
local function canonical(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

describe("trusting a project to run its own programs", function()
  local root
  local ruff

  -- A virtualenv is laid out differently on Windows: the programs are in
  -- Scripts rather than bin, and an executable is ruff.exe rather than ruff.
  -- util.lsp knows both; a fixture that only builds the POSIX one is testing
  -- the platform it was written on.
  local windows = vim.fn.has("win32") == 1
  local bin = windows and "Scripts" or "bin"
  local program = windows and "ruff.exe" or "ruff"

  before_each(function()
    root = vim.fn.tempname()
    ruff = table.concat({ root, ".venv", bin, program }, "/")
    vim.fn.mkdir(vim.fs.dirname(ruff), "p")
    vim.fn.writefile({ "home = /usr/bin", "version = 3.12.0" }, root .. "/.venv/pyvenv.cfg")
    vim.fn.writefile({ "#!/bin/sh", "exit 0" }, ruff)
    vim.fn.setfperm(ruff, "rwxr-xr-x")
    settings.clear("lsp_project_bin")
    trust.revoke(root)
  end)

  after_each(function()
    trust.revoke(root)
    settings.clear("lsp_project_bin")
    vim.fn.delete(root, "rf")
  end)

  it("does not trust a project it has never been told about", function()
    assert.is_false(trust.is_trusted(root))
  end)

  it("refuses a project binary by default", function()
    assert.is_nil(require("util.lsp").project_bin("ruff", root))
  end)

  it("runs it once the project is trusted", function()
    trust.allow(root)
    assert.are.same(canonical(ruff), canonical(require("util.lsp").project_bin("ruff", root)))
  end)

  it("refuses it again after the trust is revoked", function()
    trust.allow(root)
    trust.revoke(root)
    assert.is_nil(require("util.lsp").project_bin("ruff", root))
  end)

  it("derives the bin directory from the marker, not from a list", function()
    assert.are.same({ ".venv/" .. bin }, require("util.lsp").bin_dirs(root))

    vim.fn.delete(root .. "/.venv/pyvenv.cfg")
    assert.are.same({}, require("util.lsp").bin_dirs(root))
  end)

  it("never runs one when the setting says never", function()
    trust.allow(root)
    settings.set("lsp_project_bin", false)
    assert.is_nil(require("util.lsp").project_bin("ruff", root))
  end)

  it("always runs one when the setting says always", function()
    settings.set("lsp_project_bin", true)
    assert.are.same(canonical(ruff), canonical(require("util.lsp").project_bin("ruff", root)))
  end)
end)

describe("a path that is not the directory it was", function()
  local store

  before_each(function()
    store = vim.fn.tempname()
    vim.env.XDG_STATE_HOME = vim.fs.dirname(store)
  end)

  it("is not trusted after the directory is replaced", function()
    local path = vim.fn.tempname()
    vim.fn.mkdir(path, "p")

    trust.allow(path)
    assert.is_true(trust.is_trusted(path))

    -- The same path, a different directory: what happens when a project is
    -- deleted and something else is created where it was. Trust recorded
    -- against the path alone would follow, and here that means running
    -- programs out of a directory nobody vouched for.
    vim.fn.delete(path, "rf")
    vim.fn.mkdir(path, "p")

    assert.is_false(trust.is_trusted(path))
    vim.fn.delete(path, "rf")
  end)

  it("drops out of the list rather than lingering", function()
    local path = vim.fn.tempname()
    vim.fn.mkdir(path, "p")
    trust.allow(path)
    vim.fn.delete(path, "rf")

    assert.is_false(vim.tbl_contains(trust.all(), path))
  end)
end)
