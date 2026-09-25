-- The last-change mark across a format. The "formatter" here is a function
-- that edits the buffer the way a real one does -- a change near the top --
-- since '. and the changelist only care that a change happened, not who made
-- it. The real formatters (stylua, ruff and vtsls over LSP) were checked by
-- hand; see DECISIONS.md.

local marks = require("util.format_marks")

---@param lines string[]
---@return integer
local function scratch(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function dot()
  return vim.api.nvim_buf_get_mark(0, ".")[1]
end

local function numbered(n)
  local lines = {}
  for i = 1, n do
    lines[i] = "line " .. i
  end
  return lines
end

describe("the last change across a format", function()
  it("stays on the edit, not on the formatter's change at the top", function()
    local buf = scratch(numbered(30))
    vim.api.nvim_win_set_cursor(0, { 20, 0 })
    vim.cmd("normal! Aedited")
    assert.same(20, dot())

    marks.preserve(buf, function()
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "LINE 1" })
    end)

    assert.same("LINE 1", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    assert.same(20, dot())
    local changes = vim.fn.getchangelist(buf)[1]
    assert.same(20, changes[#changes].lnum)
  end)

  it("follows the edit when the formatter adds lines above it", function()
    local buf = scratch(numbered(30))
    vim.api.nvim_win_set_cursor(0, { 20, 0 })
    vim.cmd("normal! Aedited")

    marks.preserve(buf, function()
      vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "", "" })
    end)

    assert.same(22, dot())
    assert.same("line 20edited", vim.api.nvim_buf_get_lines(buf, 21, 22, false)[1])
  end)

  it("changes no text and adds no undo step of its own", function()
    local buf = scratch(numbered(30))
    vim.api.nvim_win_set_cursor(0, { 20, 0 })
    vim.cmd("normal! Aedited")
    local before = vim.fn.undotree().seq_last

    marks.preserve(buf, function()
      vim.cmd("undojoin")
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "LINE 1" })
    end)

    assert.same(before, vim.fn.undotree().seq_last)
    local expected = numbered(30)
    expected[1] = "LINE 1"
    expected[20] = "line 20edited"
    assert.same(expected, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("does nothing when the formatter changed nothing", function()
    local buf = scratch(numbered(5))
    local before, seq = dot(), vim.fn.undotree().seq_last
    local ran = false
    marks.preserve(buf, function()
      ran = true
    end)
    assert.is_true(ran)
    assert.same(before, dot())
    assert.same(seq, vim.fn.undotree().seq_last)
  end)

  it("still raises what the formatter raised", function()
    local buf = scratch(numbered(5))
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.cmd("normal! Ax")
    local ok, err = pcall(marks.preserve, buf, function()
      error("formatter broke")
    end)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("formatter broke"))
    assert.same(3, dot())
  end)

  -- Each case: an edit that leaves "z" at line 5, then a formatter that
  -- rewrites the text around it. `. must land on that same "z".
  describe("follows the edited character when the formatter", function()
    local cases = {
      {
        "replaces the whole buffer and adds lines on top",
        function(buf)
          local l = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          table.insert(l, 1, "-- header")
          table.insert(l, 1, "-- header")
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, l)
        end,
      },
      {
        "splits the edited line into several",
        function(buf)
          vim.api.nvim_buf_set_lines(buf, 4, 5, false, { "foo(", "  bar(xz,", "  y)" })
        end,
      },
      {
        "joins lines above into the edited one",
        function(buf)
          vim.api.nvim_buf_set_lines(buf, 2, 5, false, { "c d foo(bar(xz, y)" })
        end,
      },
      {
        "removes characters before it",
        function(buf)
          vim.api.nvim_buf_set_lines(buf, 4, 5, false, { "bar(xz, y)" })
        end,
      },
      {
        "removes characters after it",
        function(buf)
          vim.api.nvim_buf_set_lines(buf, 4, 5, false, { "foo bar(xz, y" })
        end,
      },
      {
        "re-indents it",
        function(buf)
          vim.api.nvim_buf_set_lines(buf, 4, 5, false, { "    foo( bar( xz ,  y )" })
        end,
      },
    }
    for _, case in ipairs(cases) do
      it(case[1], function()
        local buf = scratch({ "a", "b", "c", "d", "foo(bar(x), y)", "f", "g" })
        vim.api.nvim_win_set_cursor(0, { 5, 9 })
        vim.cmd("normal! rz")
        marks.preserve(buf, function()
          case[2](buf)
        end)
        local pos = vim.api.nvim_buf_get_mark(0, ".")
        local line = vim.api.nvim_buf_get_lines(buf, pos[1] - 1, pos[1], true)[1]
        assert.same("z", line:sub(pos[2] + 1, pos[2] + 1))
      end)
    end

    it("moves to the next line when the edited line is deleted", function()
      local buf = scratch({ "a", "b", "c", "d", "foo(bar(x), y)", "f", "g" })
      vim.api.nvim_win_set_cursor(0, { 5, 9 })
      vim.cmd("normal! rz")
      marks.preserve(buf, function()
        vim.api.nvim_buf_set_lines(buf, 4, 5, false, {})
      end)
      assert.same({ 5, 0 }, vim.api.nvim_buf_get_mark(0, "."))
      assert.same("f", vim.api.nvim_buf_get_lines(buf, 4, 5, true)[1])
    end)
  end)
end)
