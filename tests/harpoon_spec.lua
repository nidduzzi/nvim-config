-- The pinned-files picker. harpoon.nvim is not loaded in this test
-- environment, so require("harpoon") is faked through package.loaded --
-- Lua's own require checks there before ever touching the filesystem -- and
-- Snacks.picker.pick is a plain global stub that records what it was given,
-- since the plugin providing the real one is not present either.

local harpoon_picker = require("util.harpoon")

local package_loaded_before, snacks_before

before_each(function()
  package_loaded_before = package.loaded["harpoon"]
  snacks_before = _G.Snacks
end)

after_each(function()
  package.loaded["harpoon"] = package_loaded_before
  _G.Snacks = snacks_before
end)

describe("pinned files, when harpoon is not installed", function()
  it("says so plainly rather than erroring", function()
    package.loaded["harpoon"] = nil -- genuinely not present in this runtime

    local notified
    local original_notify = vim.notify
    vim.notify = function(message, level)
      notified = { message = message, level = level }
    end
    harpoon_picker.pick()
    vim.notify = original_notify

    assert.is_truthy(notified)
    assert.is_truthy(notified.message:match("Harpoon is not installed"))
    assert.are.same(vim.log.levels.WARN, notified.level)
  end)
end)

describe("pinned files, with harpoon installed", function()
  ---@param items table[]
  local function fake_harpoon(items)
    package.loaded["harpoon"] = {
      list = function()
        return { items = items }
      end,
    }
  end

  it("says nothing is pinned yet, rather than opening an empty picker", function()
    fake_harpoon({})

    local notified
    local original_notify = vim.notify
    vim.notify = function(message)
      notified = message
    end
    -- No Snacks stub at all: reaching it here would error on indexing a nil
    -- global, which is itself proof this path never tries to.
    harpoon_picker.pick()
    vim.notify = original_notify

    assert.is_truthy(notified:match("Nothing pinned here yet"))
  end)

  it("skips a slot that exists but holds no value, without disturbing the rest", function()
    -- harpoon.lua's own guard, `if entry and entry.value then`, only makes
    -- sense against an entry that is present but valueless -- a literal nil
    -- in the middle of the array was tried here first and ipairs stopped at
    -- it immediately, which is ipairs' documented behaviour and not
    -- something a slot-numbered list can rely on to represent a gap.
    fake_harpoon({
      { value = "one.lua", context = { row = 5, col = 2 } },
      { context = { row = 1 } }, -- present, but nothing pinned here yet
      { value = "two.lua" },
    })

    local picked
    _G.Snacks = {
      picker = {
        pick = function(opts)
          picked = opts
        end,
      },
    }
    harpoon_picker.pick()

    assert.is_truthy(picked)
    assert.are.equal(2, #picked.items)

    assert.are.same(1, picked.items[1].slot)
    assert.are.same("one.lua", picked.items[1].file)
    assert.are.same({ 5, 2 }, picked.items[1].pos)

    assert.are.same(3, picked.items[2].slot)
    assert.are.same("two.lua", picked.items[2].file)
    assert.is_nil(picked.items[2].pos)
  end)

  it("defaults a missing column to the start of the line, not to nothing", function()
    fake_harpoon({ { value = "one.lua", context = { row = 5 } } })

    local picked
    _G.Snacks = { picker = { pick = function(opts)
      picked = opts
    end } }
    harpoon_picker.pick()

    assert.are.same({ 5, 0 }, picked.items[1].pos)
  end)
end)
