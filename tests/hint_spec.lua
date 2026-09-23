-- The hint ladder: rationed on purpose, so a press gives up a little more
-- each time and the last rung stays put rather than handing over the answer.
-- What is under test here is the ladder itself -- climbing, resetting on a
-- move, capping at the top -- not the agent call a press ends in, which is
-- stubbed out so a test run spends no real request.

local hint = require("util.agent.hint")
local agent = require("util.agent")

---@param name string
---@param lines string[]
---@return integer
local function open(name, lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, vim.fs.joinpath(vim.fn.tempname(), name))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

describe("the hint ladder", function()
  local original_ask
  local asked

  before_each(function()
    original_ask = agent.ask
    asked = {}
    -- A no-op: on_done is never called, so nothing here reaches panel.show,
    -- which needs a real picker to render into. What's under test is that
    -- the rung advanced before agent.ask was ever reached, not what a real
    -- answer does with it.
    agent.ask = function(prompt, opts)
      table.insert(asked, { prompt = prompt, opts = opts })
    end
    hint.reset()
  end)

  after_each(function()
    agent.ask = original_ask
    hint.reset()
    vim.cmd("silent! %bwipeout!")
  end)

  it("starts at no rung until something is asked for", function()
    open("a.lua", { "x" })
    assert.are.same(0, hint.rung())
  end)

  it("climbs one rung per press", function()
    open("a.lua", { "x" })
    hint.next()
    assert.are.same(1, hint.rung())
    hint.next()
    assert.are.same(2, hint.rung())
  end)

  it("sends the rung's own name and instruction, not a later one", function()
    open("a.lua", { "x" })
    hint.next()
    assert.is_truthy(asked[1].prompt:match("what kind of problem"))
    assert.is_falsy(asked[1].prompt:match("the signature"))
  end)

  it("stays on the last rung rather than rolling over into an answer", function()
    open("a.lua", { "x" })
    for _ = 1, #hint.rungs do
      hint.next()
    end
    assert.are.same(#hint.rungs, hint.rung())

    local before = #asked
    hint.next()
    assert.are.same(#hint.rungs, hint.rung())
    -- No further request went out for the press that found the ladder
    -- already at the top.
    assert.are.same(before, #asked)
  end)

  it("resets to the first rung on request", function()
    open("a.lua", { "x" })
    hint.next()
    hint.next()
    hint.reset()
    assert.are.same(0, hint.rung())
  end)

  it("resets on its own once moving changes the window it hints against", function()
    -- The position it tracks is context.here()'s own start line, which -- with
    -- no treesitter parser in this test environment -- is a +/-20 line window
    -- around the cursor. Within that window the start does not move, so a
    -- small buffer moves the cursor without changing the position key at
    -- all; this needs a buffer wide enough for the window itself to shift.
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    open("a.lua", lines)

    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    hint.next()
    hint.next()
    assert.are.same(2, hint.rung())

    vim.api.nvim_win_set_cursor(0, { 80, 0 })
    assert.are.same(0, hint.rung())

    hint.next()
    assert.are.same(1, hint.rung())
  end)

  it("resets on its own once a different buffer is asked from", function()
    open("a.lua", { "x" })
    hint.next()
    assert.are.same(1, hint.rung())

    open("b.lua", { "y" })
    assert.are.same(0, hint.rung())
  end)

  it("keeps its own ladder measuring how stuck you are here, not overall", function()
    -- Moving away and coming back starts over: by the time you are back you
    -- have been thinking about something else, and the doc comment says so.
    open("a.lua", { "x" })
    hint.next()
    hint.next()
    open("b.lua", { "y" })
    hint.next()
    assert.are.same(1, hint.rung())
  end)
end)
