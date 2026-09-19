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
