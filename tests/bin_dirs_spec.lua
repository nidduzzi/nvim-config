local lsp = require("util.lsp")

local function make(layout)
  local root = vim.fn.tempname()
  for path, contents in pairs(layout) do
    local full = vim.fs.joinpath(root, path)
    vim.fn.mkdir(vim.fs.dirname(full), "p")
    vim.fn.writefile(contents == true and { "#!/bin/sh", "exit 0" } or { contents }, full)
    if contents == true then
      vim.fn.setfperm(full, "rwxr-xr-x")
    end
  end
  return root
end

describe("where a project keeps its programs", function()
  local roots = {}

  local function root_with(layout)
    local root = make(layout)
    roots[#roots + 1] = root
    return root
  end

  after_each(function()
    for _, root in ipairs(roots) do
      vim.fn.delete(root, "rf")
    end
    roots = {}
  end)

  it("finds a posix virtualenv by its marker", function()
    local root = root_with({ [".venv/pyvenv.cfg"] = "version = 3.13", [".venv/bin/python"] = true })
    assert.are.same({ ".venv/bin" }, lsp.bin_dirs(root))
  end)

  it("finds a windows virtualenv, which uses Scripts", function()
    local root = root_with({ [".venv/pyvenv.cfg"] = "version = 3.13", [".venv/Scripts/python.exe"] = true })
    assert.are.same({ ".venv/Scripts" }, lsp.bin_dirs(root))
  end)

  it("matches an executable whatever extension the platform gives it", function()
    local root = root_with({ [".venv/pyvenv.cfg"] = "version = 3.13", [".venv/Scripts/python.exe"] = true })
    local found = lsp.executables_named(root, ".venv/Scripts", "python")
    assert.are.same(1, #found)
    assert.is_truthy(found[1]:match("python%.exe$"))
  end)

  it("derives nothing from a virtualenv with neither directory", function()
    local root = root_with({ [".venv/pyvenv.cfg"] = "version = 3.13" })
    assert.are.same({}, lsp.bin_dirs(root))
  end)

  it("finds node_modules only when a package.json says so", function()
    local without = root_with({ ["node_modules/.bin/tsc"] = true })
    assert.are.same({}, lsp.bin_dirs(without))

    local with = root_with({ ["package.json"] = "{}", ["node_modules/.bin/tsc"] = true })
    assert.are.same({ "node_modules/.bin" }, lsp.bin_dirs(with))
  end)

  it("does not offer a bare bin directory", function()
    local root = root_with({ ["bin/anything"] = true })
    assert.are.same({}, lsp.bin_dirs(root))
  end)
end)
