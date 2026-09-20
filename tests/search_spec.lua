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
