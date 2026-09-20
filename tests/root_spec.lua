local lsp = require("util.lsp")
local agent = require("util.agent")

--- Resolved, because macOS hands out /var/folders paths for temporary
--- directories and /var is a symlink to /private/var: the spec would be
--- comparing two spellings of one directory.
---@param path string
---@return string
local function resolved(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

---@param markers string[]
---@return string
local function project(markers)
  local root = vim.fn.tempname()
  vim.fn.mkdir(vim.fs.joinpath(root, "src", "deep"), "p")
  for _, marker in ipairs(markers) do
    vim.fn.writefile({ "" }, vim.fs.joinpath(root, marker))
  end
  return root
end

describe("the project root", function()
  local made = {}
  local previous_cwd

  before_each(function()
    previous_cwd = vim.fn.getcwd()
  end)

  after_each(function()
    vim.cmd.cd(previous_cwd)
    for _, path in ipairs(made) do
      vim.fn.delete(path, "rf")
    end
    made = {}
  end)

  ---@param markers string[]
  ---@return string
  local function open(markers)
    local root = project(markers)
    made[#made + 1] = root
    vim.cmd.cd(vim.fs.joinpath(root, "src", "deep"))
    return root
  end

  it("is the directory holding the marker, from anywhere below it", function()
    local root = open({ "pyproject.toml" })
    assert.equal(resolved(root), resolved(lsp.root(vim.fn.getcwd())))
  end)

  it("is the same answer the agent uses for a file inside it", function()
    -- The agent kept a list of five markers against this one's sixteen, so a
    -- Gradle project gave the two of them different roots, and an agent's
    -- cached prompt includes the directory it was started in.
    --
    -- The agent asks about the buffer rather than the working directory, so
    -- the comparison only means anything with a file open.
    for _, marker in ipairs({ "build.gradle", "composer.json", "mix.exs", "Gemfile" }) do
      local root = open({ marker })
      local file = vim.fs.joinpath(root, "src", "deep", "thing.lua")
      vim.fn.writefile({ "return {}" }, file)
      vim.cmd.edit(file)

      assert.equal(resolved(lsp.root(vim.fn.getcwd())), resolved(agent.root()), marker)
    end
    vim.cmd.enew()
  end)

  it("is the starting directory when nothing marks a root", function()
    local root = open({})
    local deep = vim.fs.joinpath(root, "src", "deep")
    assert.equal(resolved(deep), resolved(lsp.root(deep)))
  end)
end)

describe("a program reached through a symlink", function()
  local dir
  local path_before

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    path_before = vim.env.PATH
  end)

  after_each(function()
    vim.env.PATH = path_before
    vim.fn.delete(dir, "rf")
  end)

  it("keeps the name PATH gave it", function()
    -- A name no machine running this has installed: `julia` is on the Windows
    -- runner's PATH already, and PATH's own copy would answer instead.
    local windows = vim.fn.has("win32") == 1
    local real = vim.fs.joinpath(dir, "version-manager" .. (windows and ".bat" or ""))
    local shim = vim.fs.joinpath(dir, "harness-shimmed-tool" .. (windows and ".bat" or ""))
    vim.fn.writefile(windows and { "@echo off", "exit /b 0" } or { "#!/bin/sh", "exit 0" }, real)
    vim.fn.setfperm(real, "rwxr-xr-x")
    if not vim.uv.fs_symlink(real, shim) then
      -- Creating one needs a privilege Windows does not hand out by default.
      MiniTest.skip("no symlinks here")
    end

    vim.env.PATH = dir .. (vim.fn.has("win32") == 1 and ";" or ":") .. path_before

    -- A version manager's shim is a symlink to the manager, and the manager
    -- decides what to run from the name it was called by. Resolving the link
    -- hands back the manager, which is a different program.
    local elsewhere = vim.fn.tempname()
    vim.fn.mkdir(elsewhere, "p")
    assert.equal(shim, require("util.lsp").safe_exepath("harness-shimmed-tool", elsewhere))
    vim.fn.delete(elsewhere, "rf")
  end)
end)
