local python = require("util.python")

describe("finding a Python that can make a virtualenv", function()
  it("asks the interpreter rather than reading its version", function()
    -- What is missing on a Debian-like machine is ensurepip, which the
    -- distribution ships separately. The version says nothing about it.
    assert.is_false(python.makes_venvs("/nonexistent/python3"))
  end)

  it("looks where each version manager installs by default", function()
    for _, pattern in ipairs(python.managed_patterns()) do
      assert.is_truthy(pattern:match("python3$"), pattern)
      assert.is_truthy(pattern:match("%*"), pattern)
    end
  end)

  it("follows a version manager's own setting for where it installs", function()
    local original = vim.env.UV_PYTHON_INSTALL_DIR
    vim.env.UV_PYTHON_INSTALL_DIR = "/elsewhere/uv"
    local patterns = python.managed_patterns()
    vim.env.UV_PYTHON_INSTALL_DIR = original
    assert.is_true(vim.tbl_contains(patterns, "/elsewhere/uv/*/bin/python3"))
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

  it("offers no replacement for a python3 that makes virtualenvs", function()
    local on_path = vim.fn.exepath("python3")
    if python.makes_venvs(on_path) then
      assert.is_nil(python.replacement_for(on_path))
    end
  end)

  it("removes only the first matching PATH entry", function()
    assert.equal("/b:/a", python.path_without("/a:/b:/a", "/a"))
    assert.equal("/a:/b", python.path_without("/a:/b", "/c"))
  end)

  it("changes PATH only while a Mason install is running", function()
    local original_replacement_for = python.replacement_for
    python.replacement_for = function()
      return "/managed/python/bin/python3"
    end
    local install_handler
    local registry = {
      on = function(_, event, handler)
        assert.equal("package:install:handle", event)
        install_handler = handler
      end,
    }
    local function new_handle()
      local closed_handler
      return {
        once = function(_, event, handler)
          assert.equal("closed", event)
          closed_handler = handler
        end,
        close = function()
          closed_handler()
        end,
      }
    end
    local path_before = vim.env.PATH

    python.prefer_usable_while_installing(registry)
    local first, second = new_handle(), new_handle()
    install_handler(first)
    install_handler(second)
    assert.equal("/managed/python/bin:" .. path_before, vim.env.PATH)

    first.close()
    vim.wait(100, function()
      return false
    end)
    assert.equal("/managed/python/bin:" .. path_before, vim.env.PATH)

    second.close()
    vim.wait(1000, function()
      return vim.env.PATH == path_before
    end)
    python.replacement_for = original_replacement_for
    assert.equal(path_before, vim.env.PATH)
  end)
end)
