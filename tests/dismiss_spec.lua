local dismiss = require("util.dismiss")

describe("one key closes what is open", function()
  local scratch

  before_each(function()
    vim.cmd("only")
    scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, scratch)
    vim.bo[scratch].filetype = "lua"
  end)

  after_each(function()
    vim.cmd("only")
  end)

  local function split_showing(filetype)
    vim.cmd("split")
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)
    vim.bo[buf].filetype = filetype
    return win
  end

  it("finds an overlay the cursor is not in", function()
    local overlay = split_showing("trouble")
    vim.cmd("wincmd p")

    assert.are.same("lua", vim.bo.filetype)
    assert.are.same(overlay, dismiss.overlay_window())
  end)

  it("closes it from a window that is not it", function()
    split_showing("trouble")
    vim.cmd("wincmd p")

    local before = #vim.api.nvim_tabpage_list_wins(0)
    assert.is_true(dismiss.dismiss())
    assert.are.same(before - 1, #vim.api.nvim_tabpage_list_wins(0))
  end)

  it("prefers the window the cursor is in", function()
    split_showing("trouble")
    local second = split_showing("help")

    assert.are.same(second, dismiss.overlay_window())
  end)

  it("finds nothing when only files are open", function()
    split_showing("lua")
    assert.is_nil(dismiss.overlay_window())
  end)
end)
