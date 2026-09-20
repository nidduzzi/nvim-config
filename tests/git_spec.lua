local git = require("util.git")
local trust = require("util.trust")
local settings = require("util.settings")

describe("running git in a project", function()
  local root

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(vim.fs.joinpath(root, ".git"), "p")
    git.forget()
  end)

  after_each(function()
    trust.revoke(root)
    settings.clear("git_project")
    git.forget()
    vim.fn.delete(root, "rf")
  end)

  it("is refused in a project nobody has vouched for", function()
    assert.is_false(git.allowed(root))
  end)

  it("is allowed once the project is trusted", function()
    trust.allow(root)
    git.forget()
    assert.is_true(git.allowed(root))
  end)

  it("stops again when the trust is revoked", function()
    trust.allow(root)
    git.forget()
    assert.is_true(git.allowed(root))

    trust.revoke(root)
    git.forget()
    assert.is_false(git.allowed(root))
  end)

  it("runs everywhere when the setting says so, for a machine of your own repositories", function()
    settings.set("git_project", true)
    assert.is_true(git.allowed(root))
  end)

  it("runs nowhere when the setting says so, whatever the trust store holds", function()
    trust.allow(root)
    git.forget()
    settings.set("git_project", false)
    assert.is_false(git.allowed(root))
  end)

  it("does not run what it guards when it is refused", function()
    local ran = false
    git.guard(function()
      ran = true
    end, root)
    assert.is_false(ran)
  end)

  it("runs what it guards, and hands back the answer", function()
    trust.allow(root)
    git.forget()
    assert.equal(
      "the answer",
      git.guard(function()
        return "the answer"
      end, root)
    )
  end)
end)
