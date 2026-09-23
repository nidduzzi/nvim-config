-- The unified picker's own logic: what a mapping is called, how a key is
-- spelled, and which of three copies of the same thing wins.

local capabilities = require("util.capabilities")

--- A name for a synthetic mapping this spec owns, so cleanup never guesses at
--- what to remove.
---@return string
local function unique()
  return "<F13>" .. tostring(math.random(100000, 999999))
end

--- The spelling pretty_key would produce for a notation string, computed the
--- way the real code computes it: through actual termcodes, not through
--- keytrans on the notation itself. keytrans treats a raw "<" as a literal
--- character to escape, and only recognises a special key once it has been
--- turned into the byte sequence that key actually sends -- calling it
--- directly on "<F13>814785" reads the "<" as text and escapes it to "<lt>",
--- which is a mistake in how the expectation is built, not in pretty_key.
---@param lhs string
---@return string
local function expected_key(lhs)
  local key = vim.fn.keytrans(vim.api.nvim_replace_termcodes(lhs, true, true, true))
  key = key:gsub("^<Space>", "<leader>")
  return key
end

describe("pretty_key, read through the keymap list", function()
  local lhs

  after_each(function()
    if lhs then
      pcall(vim.keymap.del, "n", lhs)
      lhs = nil
    end
  end)

  local function key_for(description)
    for _, item in ipairs(capabilities.keymaps()) do
      if item.name == description then
        return item.key
      end
    end
  end

  it("un-escapes <lt>, so <Tab> reads as <Tab> and not <lt>Tab>", function()
    lhs = unique()
    vim.keymap.set("n", lhs .. "<Tab>", "<Nop>", { desc = "spec: tab key" })
    assert.are.same(expected_key(lhs .. "<Tab>"), key_for("spec: tab key"))
  end)

  it("writes the leader as <leader>, not as the space it is bound to", function()
    lhs = " "
    -- <leader> is a real space in this configuration, and a mapping on it
    -- alone reads back as <Space> from keytrans -- the same word a person
    -- reads as the leader key, not as the literal space bar.
    vim.keymap.set("n", lhs, "<Nop>", { desc = "spec: leader alone" })
    assert.are.same("<leader>", key_for("spec: leader alone"))
  end)

  it("writes a leader sequence with the rest of the key kept as typed", function()
    lhs = " " .. unique()
    vim.keymap.set("n", lhs, "<Nop>", { desc = "spec: leader sequence" })
    local got = key_for("spec: leader sequence")
    assert.is_truthy(got)
    assert.are.same("<leader>", got:sub(1, 8))
  end)
end)

describe("what a mapping is called, when it has no description", function()
  local lhs

  after_each(function()
    if lhs then
      pcall(vim.keymap.del, "n", lhs)
      lhs = nil
    end
  end)

  local function description_for(key)
    for _, item in ipairs(capabilities.keymaps()) do
      if item.key == key then
        return item.name
      end
    end
  end

  it("reads a <cmd>...<cr> right-hand side back as the command it runs", function()
    lhs = unique()
    vim.cmd(("noremap %s <cmd>tabonly<cr>"):format(lhs))
    assert.are.same("run :tabonly", description_for(expected_key(lhs)))
  end)

  it("shows plain keystrokes rather than dropping a mapping with no description", function()
    -- >gv had no description anywhere and used to vanish from this list
    -- entirely, which is a worse answer than showing what it sends.
    lhs = unique()
    vim.cmd(("noremap %s >gv"):format(lhs))
    assert.are.same("sends >gv", description_for(expected_key(lhs)))
  end)

  it("drops which-key's own trigger mappings rather than listing plumbing", function()
    lhs = unique()
    vim.keymap.set("n", lhs, function() end, { desc = "which-key-trigger" })
    assert.is_nil(description_for(expected_key(lhs)))
  end)

  it("keeps a mapping's own description over anything derived", function()
    lhs = unique()
    vim.keymap.set("n", lhs, "<cmd>tabonly<cr>", { desc = "spec: written by hand" })
    assert.are.same("spec: written by hand", description_for(expected_key(lhs)))
  end)
end)

describe("one entry per key, across features, keymaps and commands", function()
  it("keeps the feature's own copy over the plain keymap underneath it", function()
    -- <leader>gt is both a hand-written feature (M.features) and a real
    -- mapping bound in keymaps.lua. Before the dedupe favoured the feature,
    -- picking "Yank history" here reached the keymap copy of <leader>sy
    -- instead and fed the paste its own guard exists to prevent.
    local by_key = {}
    for _, item in ipairs(capabilities.items("everything")) do
      if item.key == "<leader>gt" then
        table.insert(by_key, item)
      end
    end

    assert.are.equal(1, #by_key)
    assert.are.same("feature", by_key[1].kind)
    assert.are.same("Trust this project, or stop trusting it", by_key[1].name)
  end)

  it("never lists a feature key twice, even once dropdown scopes are combined", function()
    local seen = {}
    for _, item in ipairs(capabilities.items("everything")) do
      if item.key and item.key ~= "" and item.key ~= "-" then
        assert.is_nil(seen[item.key], item.key .. " listed more than once")
        seen[item.key] = true
      end
    end
  end)
end)

describe("commands", function()
  it("finds the key bound to a command from the mapping that runs it", function()
    local lhs = unique()
    vim.cmd(("noremap %s <cmd>messages<cr>"):format(lhs))

    local found
    for _, item in ipairs(capabilities.commands()) do
      if item.name == ":messages" then
        found = item
        break
      end
    end

    pcall(vim.keymap.del, "n", lhs)

    assert.is_truthy(found)
    assert.are.same(expected_key(lhs), found.key)
  end)

  it("lists a built-in command getcompletion knows and nvim_get_commands does not", function()
    local names = {}
    for _, item in ipairs(capabilities.commands()) do
      names[item.name] = true
    end
    assert.is_true(names[":tabclose"])
  end)
end)
