local private = require("util.private")

-- Windows has no POSIX mode bits: NTFS reports 666 whatever chmod was asked
-- for, and privacy there is an ACL question. What these check on Windows is
-- that the calls do what they say and write the file; the mode is asserted
-- where the filesystem has one.
local posix = vim.fn.has("win32") == 0

describe("state this editor writes about you", function()
  ---@param mode integer
  ---@return string
  local function octal(mode)
    return ("%o"):format(bit.band(mode, tonumber("777", 8)))
  end

  it("writes a file only you can read", function()
    local path = vim.fn.tempname()
    private.writefile(path, { "what you asked the agent" })

    assert.is_truthy(vim.uv.fs_stat(path))
    if posix then
      assert.equal("600", octal(vim.uv.fs_stat(path).mode))
    end
    vim.fn.delete(path)
  end)

  it("makes a directory only you can enter", function()
    local path = vim.fs.joinpath(vim.fn.tempname(), "recall", "ask")
    private.mkdir(path)

    assert.is_truthy(vim.uv.fs_stat(path))
    if posix then
      assert.equal("700", octal(vim.uv.fs_stat(path).mode))
    end
    vim.fn.delete(path, "rf")
  end)

  it("narrows a file written by something else", function()
    local path = vim.fn.tempname()
    local fd = assert(io.open(path, "w"))
    fd:write("a conversation id")
    fd:close()

    private.narrow(path)

    assert.is_truthy(vim.uv.fs_stat(path))
    if posix then
      assert.equal("600", octal(vim.uv.fs_stat(path).mode))
    end
    vim.fn.delete(path)
  end)
end)

describe("the trust store", function()
  it("is written only for you", function()
    local trust = require("util.trust")
    local state = vim.fn.tempname()
    vim.env.XDG_STATE_HOME = state

    local project = vim.fn.tempname()
    vim.fn.mkdir(project, "p")
    trust.allow(project)

    assert.is_truthy(vim.uv.fs_stat(trust.store()))
    if posix then
      local mode = vim.uv.fs_stat(trust.store()).mode
      assert.equal("600", ("%o"):format(bit.band(mode, tonumber("777", 8))))
    end

    vim.fn.delete(project, "rf")
    vim.fn.delete(state, "rf")
  end)
end)
