-- What the agent is allowed to see. The whole of its knowledge for a question
-- passes through here, and this is the thing standing between a buffer that
-- looks like a credential and a prompt sent to a model with no tools of its
-- own to have read it any other way.

local context = require("util.agent.context")

---@param name string
---@param lines string[]
---@return integer
local function open(name, lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  if name ~= "" then
    vim.api.nvim_buf_set_name(bufnr, vim.fs.joinpath(vim.fn.tempname(), name))
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

describe("ordinary buffers, which never ask", function()
  local original_confirm
  local asked

  before_each(function()
    original_confirm = vim.fn.confirm
    asked = false
    vim.fn.confirm = function(...)
      asked = true
      return 1
    end
  end)

  after_each(function()
    vim.fn.confirm = original_confirm
    vim.cmd("silent! %bwipeout!")
  end)

  it("numbers the buffer starting at line 1, cat -n style", function()
    open("plain.lua", { "local a = 1", "local b = 2" })
    local sent = context.buffer()
    assert.is_truthy(sent)
    assert.are.same(1, sent.first)
    assert.are.same("     1\tlocal a = 1\n     2\tlocal b = 2", sent.text)
    assert.is_false(asked)
  end)

  it("names it by the path relative to where the editor was started", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "plain-name.lua")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x" })
    vim.api.nvim_set_current_buf(bufnr)

    local sent = context.buffer()
    assert.are.same("plain-name.lua", sent.name)
    vim.cmd("silent! bwipeout! plain-name.lua")
  end)
end)

describe("a buffer that looks like a credential", function()
  local original_confirm
  local prompt

  before_each(function()
    original_confirm = vim.fn.confirm
    prompt = nil
  end)

  after_each(function()
    vim.fn.confirm = original_confirm
    vim.cmd("silent! %bwipeout!")
  end)

  local function refusing()
    vim.fn.confirm = function(text)
      prompt = text
      return 1 -- "&Do not send"
    end
  end

  local function allowing()
    vim.fn.confirm = function(text)
      prompt = text
      return 2 -- "&Send it anyway"
    end
  end

  it("asks before sending, naming what it recognised", function()
    refusing()
    open(".env", { "SECRET=1" })
    context.buffer()
    assert.is_truthy(prompt)
    assert.is_truthy(prompt:match("%.env"))
  end)

  it("sends nothing when the answer is to refuse", function()
    refusing()
    open(".env", { "SECRET=1" })
    assert.is_nil(context.buffer())
  end)

  it("sends it, unnumbered content and all, only on an explicit yes", function()
    allowing()
    open(".env", { "SECRET=1" })
    local sent = context.buffer()
    assert.is_truthy(sent)
    assert.is_truthy(sent.text:match("SECRET=1"))
  end)

  it("asks again next time, rather than remembering the answer", function()
    -- The cost of a wrong yes is a key in somebody else's logs, so nothing
    -- here is allowed to make that decision permanent by caching it.
    local asked = 0
    vim.fn.confirm = function()
      asked = asked + 1
      return 1
    end
    open(".env", { "SECRET=1" })
    context.buffer()
    context.buffer()
    assert.are.same(2, asked)
  end)
end)

describe("the last visual selection", function()
  after_each(function()
    vim.cmd("silent! %bwipeout!")
  end)

  it("is nothing in a buffer that was never selected in", function()
    -- A fresh scratch buffer has no '< or '> marks at all -- getpos answers
    -- { 0, 0, 0, 0 } for a mark that was never set, and the row is what
    -- selection() reads to tell "no selection" from "selected line one".
    open("plain.lua", { "a", "b", "c" })
    assert.is_nil(context.selection())
  end)

  it("covers the marked lines regardless of which end the cursor left on", function()
    open("plain.lua", { "one", "two", "three", "four" })
    vim.api.nvim_buf_set_mark(0, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 3, 0, {})

    local sent = context.selection()
    assert.is_truthy(sent)
    assert.are.same(2, sent.first)
    assert.are.same("     2\ttwo\n     3\tthree", sent.text)
    assert.is_truthy(sent.name:match("lines 2%-3"))
  end)
end)

describe("the function around the cursor", function()
  after_each(function()
    vim.cmd("silent! %bwipeout!")
  end)

  it("falls back to a window of lines when there is no parser for it", function()
    local lines = {}
    for i = 1, 60 do
      lines[i] = "line " .. i
    end
    open("plain.txt", lines)
    vim.api.nvim_win_set_cursor(0, { 30, 0 })

    local sent = context.around_cursor()
    assert.is_truthy(sent)
    -- +/- 20 around line 30 is 10 through 50.
    assert.are.same(10, sent.first)
    assert.is_truthy(sent.text:match("^    10\tline 10"))
    assert.is_truthy(sent.text:match("50\tline 50$"))
  end)
end)

describe("diagnostics on the current line", function()
  after_each(function()
    vim.cmd("silent! %bwipeout!")
    vim.diagnostic.reset()
  end)

  it("is empty text when there is nothing on this line", function()
    local bufnr = open("plain.lua", { "a", "b" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    assert.are.same("", context.diagnostics_here())
  end)

  it("carries the error itself, not a description of it", function()
    local bufnr = open("plain.lua", { "a", "b" })
    vim.diagnostic.set(vim.api.nvim_create_namespace("context_spec"), bufnr, {
      { lnum = 1, col = 0, message = "undefined variable b", source = "spec-linter", severity = vim.diagnostic.severity.ERROR },
    })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    assert.are.same("spec-linter: undefined variable b", context.diagnostics_here())
  end)
end)

describe("preamble", function()
  after_each(function()
    vim.cmd("silent! %bwipeout!")
  end)

  it("names the file and the language", function()
    open("preamble.py", { "x = 1" })
    vim.bo.filetype = "python"
    assert.is_truthy(context.preamble():match("File: .*preamble%.py"))
    assert.is_truthy(context.preamble():match("Language: python"))
  end)

  it("says so plainly when there is neither", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo.filetype = ""
    assert.is_truthy(context.preamble():match("File: %[no name%]"))
    assert.is_truthy(context.preamble():match("Language: unknown"))
  end)
end)
