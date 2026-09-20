local python = require("util.python")

describe("finding a Python that can make a virtualenv", function()
  it("asks the interpreter rather than reading its version", function()
    -- What is missing on a Debian-like machine is ensurepip, which the
    -- distribution ships separately. The version says nothing about it.
    assert.is_false(python.makes_venvs("/nonexistent/python3"))
  end)

  it("looks where the version managers put them", function()
    for _, pattern in ipairs(python.managed) do
      assert.is_truthy(pattern:match("python3$"), pattern)
      assert.is_truthy(pattern:match("%*"), pattern)
    end
  end)

  it("prefers a newer version of the same manager", function()
    local candidates = python.candidates()
    local mise = {}
    for _, path in ipairs(candidates) do
      if path:match("mise") then
        mise[#mise + 1] = path
      end
    end
    if #mise > 1 then
      assert.is_true(mise[1] > mise[2])
    end
  end)

  it("leaves PATH alone when the one on it works", function()
    local before = vim.env.PATH
    if python.makes_venvs(vim.fn.exepath("python3")) then
      assert.is_nil(python.prefer_usable())
      assert.equal(before, vim.env.PATH)
    end
  end)
end)
