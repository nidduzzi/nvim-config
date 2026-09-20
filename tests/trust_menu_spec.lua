local menu = require("util.trust_menu")
local trust = require("util.trust")
local settings = require("util.settings")

---@return string
local function repository()
  local root = vim.fn.tempname()
  vim.fn.mkdir(vim.fs.joinpath(root, ".git"), "p")
  return root
end

describe("asking about a project", function()
  local asked
  local previous_select
  local root

  before_each(function()
    root = repository()
    asked = {}
    previous_select = vim.ui.select
    vim.ui.select = function(items, opts)
      asked[#asked + 1] = { items = items, prompt = opts and opts.prompt }
    end
    menu.forget()
    require("util.git").forget()
  end)

  after_each(function()
    vim.ui.select = previous_select
    trust.revoke(root)
    settings.clear("git_project")
    menu.forget()
    require("util.git").forget()
    vim.fn.delete(root, "rf")
  end)

  it("asks about a project nobody has answered for", function()
    menu.ask_if_untrusted(root)
    vim.wait(2500, function()
      return #asked > 0
    end, 50)

    assert.equal(1, #asked)
    assert.is_truthy(asked[1].prompt:match("^Not trusted"))
  end)

  it("says nothing about a project that is already trusted", function()
    trust.allow(root)
    require("util.git").forget()

    menu.ask_if_untrusted(root)
    vim.wait(2500)
    assert.equal(0, #asked)
  end)

  it("says nothing when the setting has already decided", function()
    settings.set("git_project", true)

    menu.ask_if_untrusted(root)
    vim.wait(2500)
    assert.equal(0, #asked)
  end)

  it("says nothing about a directory that is not a repository", function()
    local plain = vim.fn.tempname()
    vim.fn.mkdir(plain, "p")

    menu.ask_if_untrusted(plain)
    vim.wait(2500)
    assert.equal(0, #asked)
    vim.fn.delete(plain, "rf")
  end)

  it("asks once per project, however many buffers it has", function()
    menu.ask_if_untrusted(root)
    vim.wait(2500, function()
      return #asked > 0
    end, 50)
    menu.ask_if_untrusted(root)
    vim.wait(2000)

    assert.equal(1, #asked)
  end)

  it("offers trusting, waiting, and never asking on this machine", function()
    menu.open(root)
    assert.equal(3, #asked[1].items)
    assert.is_truthy(asked[1].items[1]:match("Trust this project"))
    assert.is_truthy(asked[1].items[3]:match("every project on this machine"))
  end)

  it("writes the machine-wide answer into local.lua", function()
    local settings_file = settings.local_file()
    local before = vim.uv.fs_stat(settings_file) and vim.fn.readfile(settings_file) or nil

    vim.ui.select = function(items, _, choose)
      choose(items[3], 3)
    end
    menu.open(root)

    local written = table.concat(vim.fn.readfile(settings_file), "\n")
    assert.is_truthy(written:match("git_project%s*=%s*true"))

    if before then
      vim.fn.writefile(before, settings_file)
    else
      vim.fn.delete(settings_file)
    end
    settings.reload()
  end)

  it("keeps the rest of a local.lua it did not write", function()
    local settings_file = settings.local_file()
    local before = vim.uv.fs_stat(settings_file) and vim.fn.readfile(settings_file) or nil

    vim.fn.writefile({
      "-- my own notes",
      "return {",
      '  agent_backend = "hermes",',
      "}",
    }, settings_file)

    vim.ui.select = function(items, _, choose)
      choose(items[3], 3)
    end
    menu.open(root)

    local written = table.concat(vim.fn.readfile(settings_file), "\n")
    assert.is_truthy(written:match("my own notes"))
    assert.is_truthy(written:match('agent_backend = "hermes"'))
    assert.is_truthy(written:match("git_project%s*=%s*true"))

    if before then
      vim.fn.writefile(before, settings_file)
    else
      vim.fn.delete(settings_file)
    end
    settings.reload()
  end)

  it("offers untrusting a project that is trusted", function()
    trust.allow(root)
    menu.open(root)

    assert.equal(1, #asked[1].items)
    assert.is_truthy(asked[1].items[1]:match("Stop trusting"))
  end)
end)
