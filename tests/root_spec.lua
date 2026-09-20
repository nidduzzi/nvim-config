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
