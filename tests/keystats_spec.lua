-- The mapping-usage recorder. The matcher is fed keys by hand against a
-- made-up set of mappings, which is the part that decides what gets stored;
-- on_key itself only runs with a UI and is checked through the harness.

local keystats = require("util.keystats")

---@param maps table<string, string> lhs -> desc
local function set(maps)
  local list = {}
  for lhs, desc in pairs(maps) do
    list[#list + 1] = { lhs = lhs, desc = desc }
  end
  return keystats.index(list)
end

local function matcher(maps)
  local index = set(maps)
  return keystats.matcher(function()
    return index
  end)
end

---@return string[] the lhs of every completed mapping
local function feed(m, keys, mode)
  local got = {}
  for _, key in ipairs(keystats.tokens(keys)) do
    for _, hit in ipairs(m.feed(mode or "n", key)) do
      got[#got + 1] = hit[2]
    end
  end
  return got
end

describe("the key usage matcher", function()
  it("counts an exact mapping", function()
    local m = matcher({ ["<Space>gw"] = "Worktrees" })
    assert.same({ "<Space>gw" }, feed(m, "<Space>gw"))
  end)

  it("waits when a longer mapping could follow, then takes the longer one", function()
    local m = matcher({ ["<Space>g"] = "git", ["<Space>gw"] = "Worktrees" })
    assert.same({}, feed(m, "<Space>g"))
    assert.is_true(m.waiting())
    assert.same({ "<Space>gw" }, feed(m, "w"))
  end)

  it("takes the shorter mapping when the next key does not extend it", function()
    local m = matcher({ ["<Space>g"] = "git", ["<Space>gw"] = "Worktrees", ["j"] = "down" })
    assert.same({}, feed(m, "<Space>g"))
    assert.same({ "<Space>g", "j" }, feed(m, "j"))
  end)

  it("takes the shorter mapping when the wait runs out", function()
    local m = matcher({ ["<Space>g"] = "git", ["<Space>gw"] = "Worktrees" })
    feed(m, "<Space>g")
    local hits = m.flush()
    assert.same(1, #hits)
    assert.same("<Space>g", hits[1][2])
    assert.same("git", hits[1][3])
  end)

  it("drops a prefix and the key after it when together they are no mapping", function()
    local m = matcher({ ["gd"] = "definition", ["g]"] = "around", ["]p"] = "put" })
    -- g then g is Vim's own gg; the second g must not start a g] later.
    assert.same({}, feed(m, "gg"))
    assert.same({ "]p" }, feed(m, "]p"))
  end)

  it("forgets what is pending when told to, counting nothing", function()
    local m = matcher({ ["<Space>"] = "leader", ["<Space><Space>"] = "Buffers", ["<Space>uw"] = "wrap" })
    feed(m, "<Space>")
    m.drop()
    assert.same({ "<Space>uw" }, feed(m, "<Space>uw"))
  end)

  it("stores nothing for keys that are not a mapping", function()
    local m = matcher({ ["<Space>gw"] = "Worktrees", ["gsa"] = "Add surrounding" })
    assert.same({}, feed(m, "hello world"))
    assert.same({}, feed(m, "<Space>gx"))
    assert.same({}, feed(m, "gs"))
    assert.same({}, m.flush())
  end)

  it("drops a prefix that is not itself a mapping when the mode changes", function()
    local m = matcher({ ["<Space>gw"] = "Worktrees" })
    feed(m, "<Space>g")
    assert.same({}, feed(m, "w", "x"))
  end)

  it("reads <leader> as one key", function()
    assert.same(3, #keystats.tokens(vim.fn.keytrans(" gw")))
    assert.same({ "<C-N>", "x", "<Space>" }, keystats.tokens("<C-N>x<Space>"))
  end)

  it("ignores <Plug> maps, which cannot be typed", function()
    local index = set({ ["<Plug>(foo)"] = "plug", ["gp"] = "put" })
    assert.is_nil(index.lhs["<Plug>(foo)"])
    assert.same("put", index.lhs["gp"])
  end)
end)

describe("the key usage file", function()
  local path

  before_each(function()
    path = vim.fn.tempname() .. "/keystats.json"
    keystats._reset_delta()
  end)

  it("adds to counts already in the file rather than replacing them", function()
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({
      vim.json.encode({ version = 1, since = "2026-01-01", counts = { n = { ["<Space>gw"] = { count = 5, desc = "Worktrees" } } } }),
    }, path)

    keystats.record({ { "n", "<Space>gw", "Worktrees" }, { "n", "<Space>gw", "Worktrees" }, { "x", "gsa", "Add surrounding" } })
    keystats.flush(path)

    local data = keystats.load(path)
    assert.same("2026-01-01", data.since)
    assert.same(7, data.counts.n["<Space>gw"].count)
    assert.same(1, data.counts.x.gsa.count)
  end)

  it("sets a corrupt file aside and starts again", function()
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({ "{ not json" }, path)

    keystats.record({ { "n", "<Space>ff", "Find files" } })
    keystats.flush(path)

    assert.same(1, keystats.load(path).counts.n["<Space>ff"].count)
    local aside = vim.fn.glob(path .. ".corrupt-*", false, true)
    assert.same(1, #aside)
    assert.same({ "{ not json" }, vim.fn.readfile(aside[1]))
  end)

  it("writes nothing when nothing was counted", function()
    keystats.flush(path)
    assert.is_nil(vim.uv.fs_stat(path))
  end)
end)

describe("the key usage report", function()
  it("ranks by count, lists deep ones and the described mappings never used", function()
    local data = {
      since = "2026-09-01",
      counts = {
        n = {
          ["<Space>gw"] = { count = 40, desc = "Worktrees" },
          ["gd"] = { count = 90, desc = "Go to definition" },
          ["<Space>xx"] = { count = 2, desc = "Diagnostics" },
        },
      },
    }
    local current = {
      n = set({
        ["<Space>gw"] = "Worktrees",
        ["gd"] = "Go to definition",
        ["<Space>ss"] = "Symbols",
        ["zz"] = "",
        ["&"] = ":help &-default",
        ["'"] = "which-key-trigger marks",
      }),
    }
    local text = table.concat(keystats.report(data, current), "\n")

    assert.is_truthy(text:find("gd", 1, true) < text:find("<Space>gw", 1, true) or text:find("<leader>gw", 1, true))
    local deep = text:match("Used often but deep.-\n\n")
    assert.is_truthy(deep:find("gw", 1, true))
    assert.is_nil(deep:find("xx", 1, true))
    local unused = text:match("Mapped but never used.*$")
    assert.is_truthy(unused:find("Symbols", 1, true))
    assert.is_nil(unused:find("Worktrees", 1, true))
    assert.is_nil(unused:find("zz", 1, true))
    assert.is_nil(unused:find("help", 1, true))
    assert.is_nil(unused:find("which-key", 1, true))
  end)
end)
