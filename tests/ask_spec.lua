-- Three ways of asking, and the rule each one repeats: none of them writes
-- your code for you. agent.ask is stubbed throughout, since what is under
-- test is which prompt gets built and whether the call happens at all, not
-- what a real answer does with it.

local ask = require("util.agent.ask")
local agent = require("util.agent")
local settings = require("util.settings")

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

local original_ask, original_input, original_confirm
local asked, offered_input

before_each(function()
  original_ask = agent.ask
  original_input = vim.ui.input
  original_confirm = vim.fn.confirm

  asked = {}
  agent.ask = function(prompt, opts)
    table.insert(asked, { prompt = prompt, opts = opts })
  end

  -- Answers whatever recall.input's picker was given, so a query typed at
  -- the prompt and a query passed as an argument go through the same path.
  offered_input = nil
  vim.ui.input = function(_, on_confirm)
    on_confirm(offered_input)
  end

  vim.fn.confirm = function()
    return 2 -- "&Send it anyway", so a credential-named buffer never
    -- silences a test about prompt content specifically.
  end
end)

after_each(function()
  agent.ask = original_ask
  vim.ui.input = original_input
  vim.fn.confirm = original_confirm
  settings.clear("agent_trust")
  vim.cmd("silent! %bwipeout!")
end)

describe("look up", function()
  it("asks immediately when a query is given", function()
    open("a.lua", { "x" })
    ask.lookup("bisect.insort")
    assert.are.equal(1, #asked)
    assert.is_truthy(asked[1].prompt:match("bisect%.insort"))
    assert.is_truthy(asked[1].prompt:match("the signature, the argument order"))
  end)

  it("repeats the no-code rule every mode carries", function()
    open("a.lua", { "x" })
    ask.lookup("bisect.insort")
    assert.is_truthy(asked[1].prompt:match("Do not rewrite, refactor or complete"))
  end)

  it("asks nothing for an empty or blank query", function()
    open("a.lua", { "x" })
    ask.lookup("")
    ask.lookup("   ")
    assert.are.equal(0, #asked)
  end)

  it("offers the input prompt when called with no query, and asks with what it returns", function()
    open("a.lua", { "x" })
    offered_input = "str.split"
    ask.lookup()
    assert.are.equal(1, #asked)
    assert.is_truthy(asked[1].prompt:match("str%.split"))
  end)

  it("asks nothing when the input prompt is cancelled", function()
    open("a.lua", { "x" })
    offered_input = nil
    ask.lookup()
    assert.are.equal(0, #asked)
  end)
end)

describe("explain", function()
  it("explains the code when there is no diagnostic on this line", function()
    local bufnr = open("a.lua", { "local x = 1" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    ask.explain()
    assert.are.equal(1, #asked)
    assert.is_truthy(asked[1].prompt:match("^Explain what this code does%."))
  end)

  it("explains the diagnostic instead, when there is one on this line", function()
    local bufnr = open("a.lua", { "local x = y" })
    vim.diagnostic.set(vim.api.nvim_create_namespace("ask_spec"), bufnr, {
      { lnum = 0, col = 0, message = "undefined y", source = "spec-linter", severity = vim.diagnostic.severity.ERROR },
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    ask.explain()

    assert.are.equal(1, #asked)
    assert.is_truthy(asked[1].prompt:match("^Explain what this error means"))
    assert.is_truthy(asked[1].prompt:match("undefined y"))
    vim.diagnostic.reset()
  end)

  it("asks nothing when the credential prompt is refused", function()
    vim.fn.confirm = function()
      return 1 -- "&Do not send"
    end
    open(".env", { "SECRET=1" })
    ask.explain()
    assert.are.equal(0, #asked)
  end)
end)

describe("ask, on a rung that sends no code", function()
  before_each(function()
    settings.set("agent_trust", "chat")
  end)

  it("says plainly that no code was shown, rather than silently omitting it", function()
    open("a.lua", { "local x = 1" })
    ask.ask("what does this pattern do")
    assert.are.equal(1, #asked)
    assert.is_truthy(asked[1].prompt:match("You have not been shown the code"))
    assert.is_falsy(asked[1].prompt:match("local x = 1"))
  end)

  it("works even on a buffer a credential prompt would otherwise gate", function()
    -- The whole point of the chat rung: no code is gathered, so there is
    -- nothing here for a credential check to ask about in the first place.
    vim.fn.confirm = function()
      error("a credential prompt should never be reached on the chat rung")
    end
    open(".env", { "SECRET=1" })
    ask.ask("what is this file for")
    assert.are.equal(1, #asked)
  end)
end)

describe("ask, on a rung that sends code", function()
  before_each(function()
    settings.set("agent_trust", "context")
  end)

  it("includes the code and says so, rather than the chat-rung wording", function()
    open("a.lua", { "local x = 1" })
    ask.ask("what does this do")
    assert.are.equal(1, #asked)
    assert.is_truthy(asked[1].prompt:match("Answer this question about the code below%."))
    assert.is_truthy(asked[1].prompt:match("local x = 1"))
  end)

  it("asks nothing with no question and a cancelled prompt", function()
    open("a.lua", { "local x = 1" })
    offered_input = nil
    ask.ask()
    assert.are.equal(0, #asked)
  end)
end)
