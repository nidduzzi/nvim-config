local worktree = require("util.worktree")

---@return string
local function repository()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  vim.fn.writefile({ "hello" }, vim.fs.joinpath(root, "a.txt"))
  for _, args in ipairs({
    { "init", "-q", "-b", "main" },
    { "add", "-A" },
    { "-c", "user.email=t@e.invalid", "-c", "user.name=t", "commit", "-qm", "init" },
    { "branch", "feature-one" },
  }) do
    vim.fn.system(vim.list_extend({ "git", "-C", root }, args))
  end
  return root
end

describe("the worktree list", function()
  local made = {}
  local previous_cwd

  before_each(function()
    previous_cwd = vim.fn.getcwd()
  end)

  after_each(function()
    vim.cmd.cd(previous_cwd)
    for _, path in ipairs(made) do
      vim.fn.delete(path, "rf")
      vim.fn.delete(path .. "-feature-one", "rf")
      vim.fn.delete(path .. "-feat-slash", "rf")
    end
    made = {}
  end)

  ---@return string
  local function open()
    local root = repository()
    made[#made + 1] = root
    vim.cmd.cd(root)
    return root
  end

  it("has one entry in a repository with no worktrees, and you are in it", function()
    open()
    local trees = worktree.list()
    assert.equal(1, #trees)
    assert.equal("main", trees[1].branch)
    assert.is_true(trees[1].current)
  end)

  it("is empty outside a repository", function()
    local elsewhere = vim.fn.tempname()
    vim.fn.mkdir(elsewhere, "p")
    made[#made + 1] = elsewhere
    vim.cmd.cd(elsewhere)
    assert.same({}, worktree.list())
  end)

  it("puts a new worktree beside the repository, named for the branch", function()
    local root = open()
    worktree.add("feature-one")

    local trees = worktree.list()
    assert.equal(2, #trees)

    local paths = {}
    for _, tree in ipairs(trees) do
      paths[vim.fs.basename(tree.path)] = tree.branch
    end
    assert.equal("feature-one", paths[vim.fs.basename(root) .. "-feature-one"])
  end)

  it("keeps the branch name a slash would break as a directory", function()
    local root = open()
    worktree.add("feat/slash", { new = true })

    local branches = {}
    for _, tree in ipairs(worktree.list()) do
      branches[vim.fs.basename(tree.path)] = tree.branch
    end
    assert.equal("feat/slash", branches[vim.fs.basename(root) .. "-feat-slash"])
  end)
end)
