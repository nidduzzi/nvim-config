local dismiss = require("util.dismiss")

describe("one key closes what is open", function()
  local files = {}

  --- A real file, because what separates an overlay from a file is the
  --- buffer's type: a scratch buffer with a filetype set is an overlay, which
  --- is what this used to open and call a file.
  ---@return string
  local function a_file()
    local path = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "return {}" }, path)
    files[#files + 1] = path
    return path
  end

  before_each(function()
    vim.cmd("only")
    vim.cmd.edit(a_file())
  end)

  after_each(function()
    vim.cmd("only")
    for _, path in ipairs(files) do
      vim.fn.delete(path)
    end
    files = {}
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

    assert.are.same("", vim.bo.buftype)
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
    vim.cmd("split")
    vim.cmd.edit(a_file())
    assert.is_nil(dismiss.overlay_window())
  end)
end)
