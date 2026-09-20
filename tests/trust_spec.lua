local settings = require("util.settings")
local trust = require("util.trust")

describe("trusting a project to run its own programs", function()
  local root

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.venv/bin", "p")
    vim.fn.writefile({ "home = /usr/bin", "version = 3.12.0" }, root .. "/.venv/pyvenv.cfg")
    vim.fn.writefile({ "#!/bin/sh", "exit 0" }, root .. "/.venv/bin/ruff")
    vim.fn.setfperm(root .. "/.venv/bin/ruff", "rwxr-xr-x")
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
    assert.are.same(root .. "/.venv/bin/ruff", require("util.lsp").project_bin("ruff", root))
  end)

  it("refuses it again after the trust is revoked", function()
    trust.allow(root)
    trust.revoke(root)
    assert.is_nil(require("util.lsp").project_bin("ruff", root))
  end)

  it("derives the bin directory from the marker, not from a list", function()
    assert.are.same({ ".venv/bin" }, require("util.lsp").bin_dirs(root))

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
    assert.are.same(root .. "/.venv/bin/ruff", require("util.lsp").project_bin("ruff", root))
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
