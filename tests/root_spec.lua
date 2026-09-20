local lsp = require("util.lsp")
local agent = require("util.agent")

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
    assert.equal(vim.fs.normalize(root), vim.fs.normalize(lsp.root(vim.fn.getcwd())))
  end)

  it("is the same answer the agent uses", function()
    -- The agent kept a list of five markers against this one's sixteen, so a
    -- Gradle project gave the two of them different roots and the agent's
    -- conversation was cached against a directory nothing else agreed on.
    for _, marker in ipairs({ "build.gradle", "composer.json", "mix.exs", "Gemfile" }) do
      local root = open({ marker })
      assert.equal(vim.fs.normalize(lsp.root(vim.fn.getcwd())), vim.fs.normalize(agent.root()), marker)
    end
  end)

  it("is the starting directory when nothing marks a root", function()
    local root = open({})
    local deep = vim.fs.joinpath(root, "src", "deep")
    assert.equal(vim.fs.normalize(deep), vim.fs.normalize(lsp.root(deep)))
  end)
end)
