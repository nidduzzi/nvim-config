-- The four settings tiers, which are the thing everything else reads through.

local settings = require("util.settings")

describe("settings tiers", function()
  local saved

  before_each(function()
    saved = vim.deepcopy(settings.defaults)
    settings.clear("agent_backend")
    settings.clear("agent_trust")
    vim.g.agent_backend = nil
  end)

  after_each(function()
    settings.defaults = saved
    settings.clear("agent_backend")
    settings.clear("agent_trust")
    vim.g.agent_backend = nil
  end)

  it("falls back to the built-in default", function()
    local value, source = settings.resolve("agent_backend")
    assert.are.same("claude", value)
    assert.are.same("built in", source)
  end)

  it("lets a project override the default", function()
    vim.g.agent_backend = "hermes"
    local value, source = settings.resolve("agent_backend")
    assert.are.same("hermes", value)
    assert.are.same("this project's .nvim.lua", source)
  end)

  it("lets the session override the project", function()
    vim.g.agent_backend = "hermes"
    settings.set("agent_backend", "codex")
    local value, source = settings.resolve("agent_backend")
    assert.are.same("codex", value)
    assert.are.same("set for this session", source)
  end)

  it("puts it back when the session value is cleared", function()
    vim.g.agent_backend = "hermes"
    settings.set("agent_backend", "codex")
    settings.clear("agent_backend")
    local value, source = settings.resolve("agent_backend")
    assert.are.same("hermes", value)
    assert.are.same("this project's .nvim.lua", source)
  end)

  it("lists a setting whose default is nil", function()
    -- agent_model has no built-in value, so vim.tbl_keys could not see it and
    -- it was missing from the panel entirely.
    local names = {}
    for _, row in ipairs(settings.all()) do
      names[row.name] = row
    end
    assert.is_truthy(names.agent_model)
    assert.are.same("(unset)", names.agent_model.value)
    assert.are.same("the backend decides", names.agent_model.source)
  end)

  it("reports every settable name", function()
    local listed = {}
    for _, row in ipairs(settings.all()) do
      listed[row.name] = true
    end
    for _, name in ipairs(settings.names) do
      assert.is_true(listed[name], name .. " is settable but not listed")
    end
  end)
end)
