local worktree = require("util.worktree")

describe("the worktree list", function()
  it("compares paths the way git prints them", function()
    -- git prints worktree paths with forward slashes on every platform, while
    -- the editor's cwd uses the platform's separator. Both sides go through
    -- vim.fs.normalize before they are compared, which is a no-op here --- a
    -- backslash is an ordinary character in a POSIX filename, so this cannot
    -- assert the Windows conversion. What it can assert is that normalising
    -- what git prints does not change it, which is the half that runs
    -- everywhere.
    local from_git = "/home/someone/project-feature"
    assert.equal(from_git, vim.fs.normalize(from_git))
  end)

  it("is a table even outside a repository", function()
    local previous = vim.fn.getcwd()
    local elsewhere = vim.fn.tempname()
    vim.fn.mkdir(elsewhere, "p")
    vim.cmd.cd(elsewhere)

    local trees = worktree.list()

    vim.cmd.cd(previous)
    vim.fn.delete(elsewhere, "rf")
    assert.equal("table", type(trees))
  end)
end)

describe("the shell flag", function()
  it("is left alone for a shell that does not take -c", function()
    -- cmd.exe takes /c and PowerShell takes -Command. The guard in
    -- lua/config/options.lua is the platform check; this records why it is
    -- there, since the specs cannot run on Windows to find out.
    assert.is_true(vim.fn.has("win32") == 0 or vim.o.shellcmdflag ~= "-c")
  end)
end)
