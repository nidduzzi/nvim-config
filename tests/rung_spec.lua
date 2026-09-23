local agent = require("util.agent")
local backends = require("util.agent.backends")
local trust = require("util.trust")

local function reason(rung, opts, root)
  local why = agent.refusal(backends.claude, rung, opts or {}, root)
  return why
end

describe("what a rung refuses", function()
  local untrusted, trusted

  before_each(function()
    untrusted = vim.fn.tempname()
    trusted = vim.fn.tempname()
    vim.fn.mkdir(untrusted, "p")
    vim.fn.mkdir(trusted, "p")
    trust.allow(trusted)
  end)

  after_each(function()
    trust.revoke(trusted)
    trust.revoke(untrusted)
    vim.fn.delete(untrusted, "rf")
    vim.fn.delete(trusted, "rf")
  end)

  it("sends nothing on a rung this does not answer", function()
    assert.is_truthy(reason("normal", {}, trusted))
  end)

  it("refuses code on the chat rung", function()
    assert.is_truthy(reason("chat", { uses_code = true }, trusted))
  end)

  it("allows a question on the chat rung", function()
    assert.is_nil(reason("chat", { uses_code = false }, trusted))
  end)

  it("allows code from the context rung up", function()
    for _, rung in ipairs({ "context", "explore" }) do
      assert.is_nil(reason(rung, { uses_code = true }, trusted))
    end
  end)

  it("refuses the edit rung in a project that was never trusted", function()
    assert.is_truthy(reason("edit", { uses_code = true }, untrusted))
  end)

  it("allows the edit rung once the project is trusted", function()
    assert.is_nil(reason("edit", { uses_code = true }, trusted))
  end)

  it("refuses the edit rung again after trust is revoked", function()
    trust.revoke(trusted)
    assert.is_truthy(reason("edit", { uses_code = true }, trusted))
  end)

  it("refuses a rung the backend cannot express", function()
    assert.is_truthy(agent.refusal(backends.hermes, "explore", {}, trusted))
  end)
end)
