-- Telling a shadowed key from a stolen one.
--
-- A buffer-local mapping hides the global one inside that buffer and leaves it
-- bound everywhere else. Reporting that as a loss produced six warnings about
-- three keys that all still worked; missing a real global overwrite while a
-- shadow was in place was the same bug pointing the other way.

local keyguard = require("config.keyguard")

local function count(predicate)
  local n = 0
  for _, entry in ipairs(keyguard.overwrites) do
    if predicate(entry) then
      n = n + 1
    end
  end
  return n
end

describe("keyguard", function()
  local scratch

  before_each(function()
    keyguard.setup()
    keyguard.overwrites = {}
    scratch = vim.api.nvim_create_buf(false, true)
    vim.keymap.set("n", "<Plug>Guarded", function() end, { desc = "the original" })
  end)

  after_each(function()
    pcall(vim.keymap.del, "n", "<Plug>Guarded")
    if scratch and vim.api.nvim_buf_is_valid(scratch) then
      vim.api.nvim_buf_delete(scratch, { force = true })
    end
  end)

  it("records a buffer-local mapping as a shadow", function()
    vim.api.nvim_buf_call(scratch, function()
      vim.keymap.set("n", "<Plug>Guarded", function() end, { desc = "the shadow", buffer = scratch })
    end)
    vim.wait(200, function()
      return #keyguard.overwrites > 0
    end)

    assert.is_true(count(function(e)
      return e.lhs == "<Plug>Guarded" and e.shadow == true
    end) > 0)
  end)

  it("leaves the global mapping alone when it is only shadowed", function()
    vim.api.nvim_buf_call(scratch, function()
      vim.keymap.set("n", "<Plug>Guarded", function() end, { desc = "the shadow", buffer = scratch })
    end)
    vim.wait(200)

    local still
    for _, map in ipairs(vim.api.nvim_get_keymap("n")) do
      if map.lhs == "<Plug>Guarded" then
        still = map.desc
      end
    end
    assert.are.same("the original", still)
  end)

  it("records a global overwrite as a theft, not a shadow", function()
    vim.keymap.set("n", "<Plug>Guarded", function() end, { desc = "taken" })
    vim.wait(200, function()
      return #keyguard.overwrites > 0
    end)

    assert.is_true(count(function(e)
      return e.lhs == "<Plug>Guarded" and not e.shadow and e.before == "the original" and e.after == "taken"
    end) > 0)
  end)

  it("sees a global overwrite even while a shadow is in place", function()
    -- The miss that the false alarms were hiding: maparg answers with the
    -- buffer-local mapping, so before and after a global set looked identical.
    vim.api.nvim_buf_call(scratch, function()
      vim.keymap.set("n", "<Plug>Guarded", function() end, { desc = "the shadow", buffer = scratch })
      vim.wait(200)
      keyguard.overwrites = {}
      vim.keymap.set("n", "<Plug>Guarded", function() end, { desc = "taken from under a shadow" })
      vim.wait(200)
    end)

    assert.is_true(count(function(e)
      return e.lhs == "<Plug>Guarded" and not e.shadow and e.after == "taken from under a shadow"
    end) > 0)
  end)
end)
