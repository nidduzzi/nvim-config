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

-- The tier nothing above touches: a real local.lua on disk, read back by the
-- same resolve() the other three tiers already prove. "Machine-specific
-- config with local overrides winning over the GitHub-stored ones" is the
-- standing request this tier exists for, and until now nothing asserted that
-- the file is ever actually read.
describe("the machine tier, from a real local.lua", function()
  local settings_file
  local before

  before_each(function()
    settings_file = settings.local_file()
    before = vim.uv.fs_stat(settings_file) and vim.fn.readfile(settings_file) or nil
    settings.clear("agent_backend")
    vim.g.agent_backend = nil
  end)

  after_each(function()
    if before then
      vim.fn.writefile(before, settings_file)
    else
      vim.fn.delete(settings_file)
    end
    settings.reload()
    settings.clear("agent_backend")
    vim.g.agent_backend = nil
  end)

  it("is read from the file beside init.lua, not somewhere hidden", function()
    -- The doc comment promises this location on purpose: a setting you
    -- cannot find is a setting you will set twice.
    assert.are.same(vim.fs.joinpath(vim.fn.stdpath("config"), "local.lua"), settings_file)
  end)

  it("overrides the built-in default", function()
    vim.fn.writefile({ "return { agent_backend = 'hermes' }" }, settings_file)
    settings.reload()

    local value, source = settings.resolve("agent_backend")
    assert.are.same("hermes", value)
    assert.are.same(vim.fn.fnamemodify(settings_file, ":~"), source)
  end)

  it("loses to a project's .nvim.lua, per the documented tier order", function()
    vim.fn.writefile({ "return { agent_backend = 'hermes' }" }, settings_file)
    settings.reload()
    vim.g.agent_backend = "codex"

    local value, source = settings.resolve("agent_backend")
    assert.are.same("codex", value)
    assert.are.same("this project's .nvim.lua", source)
  end)

  it("does not reread the file until told to", function()
    vim.fn.writefile({ "return { agent_backend = 'hermes' }" }, settings_file)
    settings.reload()
    assert.are.same("hermes", settings.resolve("agent_backend"))

    vim.fn.writefile({ "return { agent_backend = 'codex' }" }, settings_file)
    assert.are.same("hermes", (settings.resolve("agent_backend")))

    settings.reload()
    assert.are.same("codex", (settings.resolve("agent_backend")))
  end)

  it("notifies, and falls through to the default, on a file that does not return a table", function()
    vim.fn.writefile({ "error('not a real settings file')" }, settings_file)
    settings.reload()

    local notified
    local original = vim.notify
    vim.notify = function(message, level)
      notified = { message = message, level = level }
    end

    local value, source = settings.resolve("agent_backend")
    -- machine() reports the read failure through vim.schedule, since it can
    -- run before the editor has finished starting; a synchronous assertion
    -- right after resolve() would check before that callback ever ran.
    vim.wait(200, function()
      return notified ~= nil
    end, 10)
    vim.notify = original

    assert.are.same("claude", value)
    assert.are.same("built in", source)
    assert.is_truthy(notified)
    assert.are.same(vim.log.levels.ERROR, notified.level)
  end)

  it("has no file in the ordinary case, and that is not an error", function()
    vim.fn.delete(settings_file)
    settings.reload()

    local value, source = settings.resolve("agent_backend")
    assert.are.same("claude", value)
    assert.are.same("built in", source)
  end)
end)
