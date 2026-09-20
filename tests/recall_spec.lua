local recall = require("util.recall")

local function project(files, as_git_repo)
  local root = vim.fn.tempname()
  for _, name in ipairs(files) do
    local full = vim.fs.joinpath(root, name)
    vim.fn.mkdir(vim.fs.dirname(full), "p")
    vim.fn.writefile({ "x" }, full)
  end
  if as_git_repo then
    vim.fn.system({ "git", "-C", root, "init", "-q", "-b", "main" })
    vim.fn.system({ "git", "-C", root, "add", "-A" })
    vim.fn.system({ "git", "-C", root, "-c", "user.email=t@e.invalid", "-c", "user.name=t", "commit", "-qm", "init" })
  end
  return root
end

describe("the extensions a project contains", function()
  local roots = {}
  local previous_cwd

  before_each(function()
    previous_cwd = vim.fn.getcwd()
  end)

  local function make(files, as_git_repo)
    local root = project(files, as_git_repo)
    roots[#roots + 1] = root
    return root
  end

  after_each(function()
    vim.cmd.cd(previous_cwd)
    for _, root in ipairs(roots) do
      vim.fn.delete(root, "rf")
    end
    roots = {}
    recall.rescan()
  end)

  it("counts them, most common first", function()
    local root = make({ "a.py", "b.py", "c.py", "d.lua", "e.md" }, true)
    vim.cmd.cd(root)
    assert.are.same({ "py", "lua", "md" }, recall.extensions(3))
  end)

  it("gives the same answer without a git repository", function()
    local root = make({ "a.py", "b.py", "c.lua" }, false)
    vim.cmd.cd(root)
    assert.are.same({ "py", "lua" }, recall.extensions(2))
  end)

  it("reads only what git tracks when there is a repository", function()
    local root = make({ "tracked.py" }, true)
    vim.fn.writefile({ "x" }, vim.fs.joinpath(root, "untracked.rs"))
    vim.cmd.cd(root)
    assert.are.same({ "py" }, recall.extensions(5))
  end)

  it("offers the directories the project has, not the ones it ignores", function()
    local root = make({ "src/a.py", "docs/b.md", "node_modules/pkg/c.js" }, true)
    vim.cmd.cd(root)
    assert.are.same({ "docs/**", "node_modules/**", "src/**" }, recall.top_level_globs())
  end)

  it("leaves out a directory git does not track", function()
    local root = make({ "src/a.py" }, true)
    vim.fn.mkdir(vim.fs.joinpath(root, "build"), "p")
    vim.fn.writefile({ "x" }, vim.fs.joinpath(root, "build", "out.o"))
    vim.cmd.cd(root)
    assert.are.same({ "src/**" }, recall.top_level_globs())
  end)
end)
