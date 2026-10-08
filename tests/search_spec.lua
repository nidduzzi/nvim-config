local search = require("util.search")

describe("the search toggles", function()
  it("gives every toggle the fields the picker builds a key from", function()
    for _, toggle in ipairs(search.toggles) do
      for _, field in ipairs({ "name", "key", "desc", "flag", "label", "on", "off" }) do
        assert.is_truthy(toggle[field], toggle.name .. " has no " .. field)
      end
    end
  end)

  it("claims each key once, so one toggle cannot shadow another", function()
    local keys, names = {}, {}
    for _, toggle in ipairs(search.toggles) do
      assert.is_nil(keys[toggle.key], "two toggles bind " .. toggle.key)
      assert.is_nil(names[toggle.name], "two toggles are called " .. toggle.name)
      keys[toggle.key] = true
      names[toggle.name] = true
    end
  end)

  it("names a ripgrep flag, not a snacks option", function()
    for _, toggle in ipairs(search.toggles) do
      assert.is_truthy(toggle.flag:match("^%-%-[%w-]+$"), toggle.flag .. " is not a long option")
    end
  end)
end)

describe("a toggle applied to a picker", function()
  ---@return table
  local function picker()
    return {
      opts = { args = { "--glob=!*.md" }, search_preset = "code" },
      found = 0,
      find = function(self)
        self.found = self.found + 1
      end,
    }
  end

  it("adds its flag, and removes it again", function()
    local it_is = picker()
    search.toggle(it_is, "ignore_case")
    assert.is_true(vim.tbl_contains(it_is.opts.args, "--ignore-case"))

    search.toggle(it_is, "ignore_case")
    assert.is_false(vim.tbl_contains(it_is.opts.args, "--ignore-case"))
  end)

  it("keeps the arguments it did not come for", function()
    local it_is = picker()
    search.toggle(it_is, "ignore_case")
    assert.is_true(vim.tbl_contains(it_is.opts.args, "--glob=!*.md"))
  end)

  it("searches again", function()
    local it_is = picker()
    search.toggle(it_is, "ignore_case")
    assert.equal(1, it_is.found)
  end)

  it("names what is on in the title", function()
    local it_is = picker()
    search.toggle(it_is, "ignore_case")
    assert.equal("Grep (code, any case)", it_is.title)

    search.toggle(it_is, "ignore_case")
    assert.equal("Grep (code)", it_is.title)
  end)

  it("refuses a toggle that does not exist, rather than doing nothing", function()
    assert.has_error(function()
      search.toggle(picker(), "no_such_toggle")
    end)
  end)
end)

describe("ranking grep results by definition", function()
  local directory

  local function write(name, lines)
    local path = vim.fs.joinpath(directory, name)
    vim.fn.writefile(lines, path)
    return path
  end

  local function fake_picker(items, searched)
    local picker = {
      closed = false,
      finder = { items = items },
      matcher_runs = 0,
      finds = 0,
      list = { set_target = function() end },
    }
    picker.matcher = {
      tick = 1,
      run = function()
        picker.matcher_runs = picker.matcher_runs + 1
      end,
    }
    picker.find = function()
      picker.finds = picker.finds + 1
    end
    picker.filter = function()
      return { search = searched }
    end
    return picker
  end

  local function rank_all(ranking, picker, searched)
    for _, item in ipairs(picker.finder.items) do
      ranking:rank(item, { picker = picker, filter = { search = searched } })
    end
  end

  local function wait_for_drain(ranking)
    assert.is_true(vim.wait(2000, function()
      return not ranking.draining
    end, 10))
  end

  before_each(function()
    directory = vim.fn.tempname()
    vim.fn.mkdir(directory, "p")
    search.forget_definitions()
    vim.treesitter.query.set("lua", "locals", "(function_declaration name: (identifier) @local.definition.function)")
  end)

  after_each(function()
    vim.fn.delete(directory, "rf")
  end)

  it("remembers a file that has nothing to say, so it is never parsed again", function()
    local path = write("notes.txt", { "issueToken is mentioned here" })
    local picker = fake_picker({ { file = path, pos = { 1, 0 } } }, "issueToken")
    local ranking = search.Ranking.new({ delay_ms = 0 })

    rank_all(ranking, picker, "issueToken")
    wait_for_drain(ranking)
    assert.same({}, search.cached_definitions(path, vim.uv.fs_stat(path).mtime.sec))

    rank_all(ranking, picker, "issueToken")
    assert.same({}, ranking.pending)
    assert.is_false(ranking.draining)
  end)

  it("leaves a file it had no budget for unranked for that search, instead of queueing it again", function()
    local path = write("auth.lua", { "local function issueToken() end" })
    local picker = fake_picker({ { file = path, pos = { 1, 0 } } }, "issueToken")
    local ranking = search.Ranking.new({ budget_ms = 0 })
    ranking.search = "issueToken"
    ranking.pending[path] = true

    assert.same({}, ranking:parse_pending_within_budget())
    assert.same({}, ranking.pending)
    assert.is_true(ranking.unranked[path])

    rank_all(ranking, picker, "issueToken")
    assert.same({}, ranking.pending)
    assert.is_false(ranking.draining)

    ranking.draining = true
    rank_all(ranking, picker, "validateToken")
    assert.is_true(ranking.pending[path])
  end)

  it("re-ranks the results it already has instead of running the search again", function()
    local path = write("auth.lua", { "local function issueToken() end", "issueToken()" })
    local definition = { file = path, pos = { 1, 0 } }
    local call = { file = path, pos = { 2, 0 } }
    local picker = fake_picker({ definition, call }, "issueToken")
    local ranking = search.Ranking.new({ delay_ms = 0 })

    rank_all(ranking, picker, "issueToken")
    wait_for_drain(ranking)

    assert.equal(search.DEFINITION_SCORE_MUL, definition.score_mul)
    assert.is_nil(call.score_mul)
    assert.equal(1, picker.matcher_runs)
    assert.equal(2, picker.matcher.tick)
    assert.equal(0, picker.finds)
  end)

  it("does not re-rank when parsing changed nothing", function()
    local path = write("notes.txt", { "issueToken" })
    local picker = fake_picker({ { file = path, pos = { 1, 0 } } }, "issueToken")
    local ranking = search.Ranking.new({ delay_ms = 0 })

    rank_all(ranking, picker, "issueToken")
    wait_for_drain(ranking)

    assert.equal(0, picker.matcher_runs)
    assert.equal(0, picker.finds)
  end)

  it("does nothing to a picker that closed while it was parsing", function()
    local path = write("auth.lua", { "local function issueToken() end" })
    local picker = fake_picker({ { file = path, pos = { 1, 0 } } }, "issueToken")
    local ranking = search.Ranking.new({ delay_ms = 0 })

    rank_all(ranking, picker, "issueToken")
    picker.closed = true
    wait_for_drain(ranking)

    assert.equal(0, picker.matcher_runs)
  end)
end)
