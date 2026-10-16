local git = require("util.git")
local trust = require("util.trust")
local settings = require("util.settings")

describe("running git in a project", function()
  local root

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(vim.fs.joinpath(root, ".git"), "p")
    vim.fn.writefile({ "[core]", "\tpager = cat" }, vim.fs.joinpath(root, ".git", "config"))
  end)

  after_each(function()
    trust.revoke(root)
    settings.clear("git_project")
    vim.fn.delete(root, "rf")
  end)

  it("is refused in an untrusted project whose git config names a program", function()
    assert.is_false(git.allowed(root))
  end)

  it("is allowed without trust when the repository's config and hooks name no programs", function()
    vim.fn.writefile({ "[core]", "\trepositoryformatversion = 0", "\tbare = false" }, vim.fs.joinpath(root, ".git", "config"))
    assert.is_true(git.allowed(root))
  end)

  it("is refused again as soon as a program-naming setting appears", function()
    vim.fn.writefile({ "[core]", "\tbare = false" }, vim.fs.joinpath(root, ".git", "config"))
    assert.is_true(git.allowed(root))
    vim.fn.writefile({ "[core]", "\tbare = false", "\tfsmonitor = /tmp/anything" }, vim.fs.joinpath(root, ".git", "config"))
    assert.is_false(git.allowed(root))
  end)

  it("stays off with git_project false even in a harmless repository", function()
    vim.fn.writefile({ "[core]", "\tbare = false" }, vim.fs.joinpath(root, ".git", "config"))
    settings.set("git_project", false)
    assert.is_false(git.allowed(root))
  end)

  it("is allowed once the project is trusted", function()
    trust.allow(root)
    assert.is_true(git.allowed(root))
  end)

  it("stops again when the trust is revoked", function()
    trust.allow(root)
    assert.is_true(git.allowed(root))

    trust.revoke(root)
    assert.is_false(git.allowed(root))
  end)

  it("runs everywhere when the setting says so, for a machine of your own repositories", function()
    settings.set("git_project", true)
    assert.is_true(git.allowed(root))
  end)

  it("runs nowhere when the setting says so, whatever the trust store holds", function()
    trust.allow(root)
    settings.set("git_project", false)
    assert.is_false(git.allowed(root))
  end)

  it("asks whether to trust the project instead of running what it guards", function()
    local trust_menu = require("util.trust_menu")
    local original_open = trust_menu.open
    local asked_about
    trust_menu.open = function(asked_root)
      asked_about = asked_root
    end
    local ran = false
    git.guard(function()
      ran = true
    end, root)
    trust_menu.open = original_open
    assert.is_false(ran)
    assert.equal(require("util.lsp").root(root), asked_about)
  end)

  it("asks again on every refused press", function()
    local trust_menu = require("util.trust_menu")
    local original_open = trust_menu.open
    local times_asked = 0
    trust_menu.open = function()
      times_asked = times_asked + 1
    end
    git.guard(function() end, root)
    git.guard(function() end, root)
    trust_menu.open = original_open
    assert.equal(2, times_asked)
  end)

  it("does not offer trust when git is turned off on this machine", function()
    settings.set("git_project", false)
    local trust_menu = require("util.trust_menu")
    local original_open = trust_menu.open
    local asked = false
    trust_menu.open = function()
      asked = true
    end
    git.guard(function() end, root)
    trust_menu.open = original_open
    assert.is_false(asked)
  end)

  it("runs what it guards, and hands back the answer", function()
    trust.allow(root)
    assert.equal(
      "the answer",
      git.guard(function()
        return "the answer"
      end, root)
    )
  end)
end)
