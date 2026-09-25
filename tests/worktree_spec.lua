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
      vim.fn.delete(path .. "-fix", "rf")
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

  it("names a worktree made from another worktree after the main checkout", function()
    local root = open()
    worktree.add("feature-one")
    local main = vim.fs.basename(root)
    assert.equal(main .. "-feature-one", vim.fs.basename(vim.fn.getcwd()))

    worktree.add("fix", { new = true })
    local names = {}
    for _, tree in ipairs(worktree.list()) do
      names[vim.fs.basename(tree.path)] = true
    end
    assert.is_true(names[main .. "-fix"])
    assert.is_nil(names[main .. "-feature-one-fix"])
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

---@param cwd string
---@param args string[]
local function run(cwd, args)
  local out = vim.fn.system(vim.list_extend({ "git", "-C", cwd, "-c", "protocol.file.allow=always" }, args))
  assert.equal(0, vim.v.shell_error, table.concat(args, " ") .. ": " .. out)
end

---@param trees table[]
---@param path string
local function find(trees, path)
  path = vim.fs.normalize(vim.uv.fs_realpath(path) or path)
  for _, tree in ipairs(trees) do
    if tree.path == path then
      return tree
    end
  end
end

describe("every kind of worktree", function()
  local made, previous_cwd = {}, nil

  before_each(function()
    previous_cwd = vim.fn.getcwd()
  end)

  after_each(function()
    vim.cmd.cd(previous_cwd)
    vim.cmd("silent! %bwipeout!")
    for _, path in ipairs(made) do
      vim.fn.delete(path, "rf")
    end
    made = {}
  end)

  ---@return string base, string root
  local function sandbox()
    local base = vim.fn.tempname()
    vim.fn.mkdir(base, "p")
    made[#made + 1] = base
    local root = vim.fs.joinpath(base, "repo")
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({ "hello" }, vim.fs.joinpath(root, "a.txt"))
    run(root, { "init", "-q", "-b", "main" })
    run(root, { "add", "-A" })
    run(root, { "-c", "user.email=t@e.invalid", "-c", "user.name=t", "commit", "-qm", "init" })
    run(root, { "branch", "feature" })
    run(root, { "branch", "locked-one" })
    return base, vim.fs.normalize(vim.uv.fs_realpath(root))
  end

  it("lists detached, locked and prunable ones, flagged", function()
    local base, root = sandbox()
    run(root, { "worktree", "add", "-q", "--detach", base .. "/detached" })
    run(root, { "worktree", "add", "-q", base .. "/locked", "locked-one" })
    run(root, { "worktree", "lock", base .. "/locked" })
    run(root, { "worktree", "add", "-q", base .. "/gone", "feature" })
    vim.fn.delete(base .. "/gone", "rf")

    local trees = worktree.list(root)
    assert.equal(4, #trees)
    assert.is_true(trees[1].main)
    assert.is_true(find(trees, base .. "/detached").detached)
    assert.is_true(find(trees, base .. "/locked").locked)
    local gone
    for _, tree in ipairs(trees) do
      if vim.endswith(tree.path, "/gone") then
        gone = tree
      end
    end
    assert.is_true(gone.prunable)

    assert.is_true(worktree.prune(root))
    assert.equal(3, #worktree.list(root))
  end)

  it("lists the repository of the file you are looking at, not the working directory's", function()
    local base, root = sandbox()
    run(root, { "worktree", "add", "-q", base .. "/feature", "feature" })
    local other = vim.fs.joinpath(base, "other")
    vim.fn.mkdir(other, "p")
    run(other, { "init", "-q", "-b", "main" })

    vim.cmd.cd(other)
    vim.cmd.edit(vim.fs.joinpath(root, "a.txt"))
    assert.equal(root, worktree.root())
    assert.equal(2, #worktree.list())
    assert.is_true(worktree.list()[1].current)
  end)

  it("lists a submodule's own checkout, not its git directory", function()
    local base, root = sandbox()
    local super = vim.fs.joinpath(base, "super")
    vim.fn.mkdir(super, "p")
    run(super, { "init", "-q", "-b", "main" })
    run(super, { "submodule", "add", "-q", root, "sub" })
    local sub = vim.fs.normalize(vim.uv.fs_realpath(vim.fs.joinpath(super, "sub")))
    run(sub, { "worktree", "add", "-q", "-b", "side", base .. "/sub-side" })

    local trees = worktree.list(sub)
    assert.equal(2, #trees)
    assert.equal(sub, trees[1].path)
    assert.is_true(trees[1].current)
    assert.is_nil(trees[1].path:find("/.git/modules/", 1, true))
  end)

  it("refuses to remove the main, current or a locked tree, and asks before losing work", function()
    local base, root = sandbox()
    run(root, { "worktree", "add", "-q", base .. "/locked", "locked-one" })
    run(root, { "worktree", "lock", base .. "/locked" })
    run(root, { "worktree", "add", "-q", base .. "/feature", "feature" })

    local trees = worktree.list(root)
    assert.is_false((worktree.remove(trees[1], { root = root })))
    assert.is_false((worktree.remove(find(trees, base .. "/locked"), { root = root })))

    local feature = find(trees, base .. "/feature")
    local here = worktree.list(feature.path)
    assert.is_false((worktree.remove(find(here, base .. "/feature"), { root = feature.path })))

    vim.fn.writefile({ "unsaved thought" }, base .. "/feature/new.txt")
    assert.equal(1, #worktree.dirt(feature, root))
    assert.is_false((worktree.remove(feature, { root = root })))
    assert.equal(1, vim.fn.isdirectory(base .. "/feature"))

    assert.is_true((worktree.remove(feature, { root = root, force = true })))
    assert.equal(0, vim.fn.isdirectory(base .. "/feature"))
  end)

  it("takes the open files to the same place in the tree it switches to", function()
    local base, root = sandbox()
    run(root, { "worktree", "add", "-q", base .. "/feature", "feature" })
    vim.fn.writefile({ "only here" }, vim.fs.joinpath(root, "untracked.txt"))
    local feature = vim.fs.normalize(vim.uv.fs_realpath(base .. "/feature"))

    vim.cmd.cd(root)
    vim.cmd.edit(vim.fs.joinpath(root, "untracked.txt"))
    vim.cmd.edit(vim.fs.joinpath(root, "a.txt"))
    worktree.switch(feature)

    assert.equal(feature, vim.fs.normalize(vim.uv.fs_realpath(vim.fn.getcwd())))
    assert.equal(feature .. "/a.txt", vim.fs.normalize(vim.api.nvim_buf_get_name(0)))
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].buflisted then
        assert.is_true(vim.startswith(vim.fs.normalize(vim.api.nvim_buf_get_name(buf)), feature))
      end
    end
  end)

  it("keeps a buffer with unsaved changes where it is", function()
    local base, root = sandbox()
    run(root, { "worktree", "add", "-q", base .. "/feature", "feature" })
    vim.cmd.cd(root)
    vim.cmd.edit(vim.fs.joinpath(root, "a.txt"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })
    local buf = vim.api.nvim_get_current_buf()

    worktree.switch(base .. "/feature")
    assert.is_true(vim.api.nvim_buf_is_valid(buf))
    assert.equal(buf, vim.api.nvim_get_current_buf())
    assert.equal(root .. "/a.txt", vim.fs.normalize(vim.api.nvim_buf_get_name(buf)))
    vim.bo[buf].modified = false
  end)

  it("trusts a worktree it made, and nothing else", function()
    local base, root = sandbox()
    local trust = require("util.trust")
    run(root, { "worktree", "add", "-q", base .. "/by-hand", "feature" })
    local made_here = worktree.add("fresh", { new = true, root = root })

    assert.is_true(trust.is_trusted(made_here))
    assert.is_false(trust.is_trusted(base .. "/by-hand"))
    trust.revoke(made_here)
  end)
end)
