local repository = require("util.git_repository")

---@param config_lines string[]
---@return string root
local function repository_with(config_lines)
  local root = vim.fn.tempname()
  vim.fn.mkdir(vim.fs.joinpath(root, ".git", "hooks"), "p")
  vim.fn.writefile(config_lines, vim.fs.joinpath(root, ".git", "config"))
  return root
end

---@param entries git_repository.ConfigEntry[]
---@return string[]
local function keys_of(entries)
  return vim.tbl_map(function(entry)
    return entry.key
  end, entries)
end

describe("what a repository's own git config can make git run", function()
  local roots = {}

  local function make(config_lines)
    local root = repository_with(config_lines)
    roots[#roots + 1] = root
    return root
  end

  after_each(function()
    for _, root in ipairs(roots) do
      vim.fn.delete(root, "rf")
    end
    roots = {}
  end)

  it("names nothing in the config git init writes", function()
    local root = make({
      "[core]",
      "\trepositoryformatversion = 0",
      "\tfilemode = true",
      "\tbare = false",
      "\tlogallrefupdates = true",
    })
    assert.is_true(repository.names_no_programs(root))
  end)

  it("names nothing in a clone with remotes, branches, submodules and signing", function()
    local root = make({
      "[core]",
      "\tbare = false",
      '[remote "origin"]',
      "\turl = git@example.com:team/project.git",
      "\tfetch = +refs/heads/*:refs/remotes/origin/*",
      "\tglab-resolved-head = main",
      '[branch "main"]',
      "\tremote = origin",
      "\tmerge = refs/heads/main",
      '[submodule "backend"]',
      "\turl = git@example.com:team/backend.git",
      "\tactive = true",
      "[rerere]",
      "\tenabled = true",
      "[gpg]",
      "\tformat = ssh",
      "[user]",
      "\tsigningkey = ~/.ssh/id_ed25519.pub",
      "[secrets]",
      "\tpatterns = AKIA[0-9A-Z]{16}",
      "\tproviders = git secrets --aws-provider",
    })
    assert.is_true(repository.names_no_programs(root))
  end)

  it("lists every setting that can name a program", function()
    local root = make({
      "[core]",
      "\tbare = false",
      "\tfsmonitor = ./watch.sh",
      "\tpager = less",
      "\tsshCommand = ssh -i key",
      "\thooksPath = .githooks",
      '[diff "pdf"]',
      "\ttextconv = ./pdf2text",
      '[filter "lfs"]',
      "\tclean = ./clean",
      '[submodule "x"]',
      "\tupdate = !./run",
      "[alias]",
      "\tst = !./status",
      "[include]",
      "\tpath = ../elsewhere.gitconfig",
    })
    local location = assert(repository.locate(root))
    local named = keys_of(repository.programs(location).entries)
    assert.are.same({
      "core.fsmonitor",
      "core.pager",
      "core.sshcommand",
      "core.hookspath",
      "diff.pdf.textconv",
      "filter.lfs.clean",
      "submodule.x.update",
      "alias.st",
      "include.path",
    }, named)
    assert.is_false(repository.names_no_programs(root))
  end)

  it("does not follow an include while reading", function()
    local root = make({ "[include]", "\tpath = included.gitconfig" })
    vim.fn.writefile({ "[core]", "\tfsmonitor = ./watch.sh" }, vim.fs.joinpath(root, ".git", "included.gitconfig"))
    local location = assert(repository.locate(root))
    assert.are.same({ "include.path" }, keys_of(repository.programs(location).entries))
  end)

  it("counts a hook, and ignores the samples git init leaves", function()
    local root = make({ "[core]", "\tbare = false" })
    vim.fn.writefile({ "#!/bin/sh" }, vim.fs.joinpath(root, ".git", "hooks", "pre-commit.sample"))
    assert.is_true(repository.names_no_programs(root))

    vim.fn.writefile({ "#!/bin/sh" }, vim.fs.joinpath(root, ".git", "hooks", "post-checkout"))
    local location = assert(repository.locate(root))
    assert.are.same({ vim.fs.joinpath(location.commondir, "hooks", "post-checkout") }, repository.programs(location).hooks)
    assert.is_false(repository.names_no_programs(root))
  end)

  it("treats a config git cannot read as naming something", function()
    local root = make({ "[core", "\tbare = false" })
    local location = assert(repository.locate(root))
    assert.are.same({ "(unreadable)" }, keys_of(repository.programs(location).entries))
  end)

  it("reads a linked worktree's shared config and its own", function()
    local main = make({ "[core]", "\tbare = false" })
    local linked = vim.fn.tempname()
    roots[#roots + 1] = linked
    local gitdir = vim.fs.joinpath(main, ".git", "worktrees", "linked")
    vim.fn.mkdir(gitdir, "p")
    vim.fn.mkdir(linked, "p")
    vim.fn.writefile({ "gitdir: " .. gitdir }, vim.fs.joinpath(linked, ".git"))
    vim.fn.writefile({ "../.." }, vim.fs.joinpath(gitdir, "commondir"))

    local location = assert(repository.locate(linked))
    assert.equal(vim.fs.normalize(vim.fs.joinpath(main, ".git")), location.commondir)
    assert.is_true(repository.names_no_programs(linked))

    vim.fn.writefile({ "[core]", "\tpager = less" }, vim.fs.joinpath(gitdir, "config.worktree"))
    assert.is_false(repository.names_no_programs(linked))

    vim.fn.delete(vim.fs.joinpath(gitdir, "config.worktree"))
    vim.fn.writefile({ "[core]", "\tbare = false", "\tfsmonitor = ./watch.sh" }, vim.fs.joinpath(main, ".git", "config"))
    assert.is_false(repository.names_no_programs(linked))
  end)

  it("is no repository without a .git", function()
    local plain = vim.fn.tempname()
    vim.fn.mkdir(plain, "p")
    roots[#roots + 1] = plain
    assert.is_nil(repository.locate(plain))
    assert.is_false(repository.names_no_programs(plain))
  end)
end)
