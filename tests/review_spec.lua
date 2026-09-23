-- Review, delivered as diagnostics. agent.ask and M.open are stubbed
-- throughout: what is under test is what on_done does with an answer, not a
-- real request or a real picker to render findings into.

local review = require("util.agent.review")
local agent = require("util.agent")

---@param name string
---@param lines string[]
---@return integer
local function open(name, lines)
  -- A real directory, not just a unique name: the "function" and "file"
  -- scopes never look at the filesystem, but "changes" runs a real `git
  -- diff` with this as its cwd, and vim.system throws on a cwd that does
  -- not exist rather than letting git fail with an ordinary exit code.
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, vim.fs.joinpath(dir, name))
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
  return bufnr
end

--- The scope current is a module-level singleton, shared with every other
--- test in this process, and next_scope's own gather can come back with
--- nothing to ask about -- the "changes" scope with no diff calls agent.ask
--- zero times, on purpose, which is exactly what one test here checks for.
--- So position is read from next_scope's own announcement, which fires
--- unconditionally, rather than from whether a request happened to follow
--- it: an earlier version watched agent.ask instead and could never detect
--- landing on a scope that has nothing to ask about, and a version before
--- that reset with a while loop whose condition could never be false and so
--- reset nothing at all.
---@param name string
local function go_to_scope(name)
  local original_notify = vim.notify
  local announced
  vim.notify = function(message, _, opts)
    if opts and opts.title == "Review scope" then
      announced = message:match("^(%a+):")
    end
  end

  for _ = 1, #review.scopes do
    review.next_scope()
    if announced == name then
      vim.notify = original_notify
      return
    end
  end

  vim.notify = original_notify
  error("scope " .. name .. " was not reached in a full cycle")
end

--- Run a review at the current scope and return the answer it was given,
--- so a test can drive on_done directly without a real backend.
---@param structured table|nil
---@param text? string
local function answer(structured, text)
  review.run()
  local call = agent.ask.calls[#agent.ask.calls]
  call.opts.on_done(text or "", structured)
end

describe("review", function()
  local original_ask, original_open

  before_each(function()
    original_ask = agent.ask
    original_open = review.open

    local calls = {}
    agent.ask = setmetatable({ calls = calls }, {
      __call = function(self, prompt, opts)
        table.insert(self.calls, { prompt = prompt, opts = opts })
      end,
    })
    review.open = function() end

    review.clear()

    -- Pinned before any test's own buffer is opened, so the walk this takes
    -- has a real buffer to gather from whatever scope was left current by
    -- whatever ran before this test.
    open("pin.lua", { "x" })
    go_to_scope("function")
    agent.ask.calls = {}
  end)

  after_each(function()
    agent.ask = original_ask
    review.open = original_open
    review.clear()
    vim.cmd("silent! %bwipeout!")
  end)

  it("never reports a clean answer for one it could not read", function()
    -- Documented in the source as a real incident: an HTTP 401 with no
    -- schema flag came back as prose, prose that failed to parse looked
    -- exactly like zero findings, and it was read as a clean review.
    open("a.lua", { "local x = 1" })

    local notified
    local original_notify = vim.notify
    vim.notify = function(message, level)
      notified = { message = message, level = level }
    end
    answer(nil, "HTTP 401: Unauthorized")
    vim.notify = original_notify

    assert.are.same({}, review.last)
    assert.is_truthy(notified)
    assert.are.same(vim.log.levels.ERROR, notified.level)
    assert.is_truthy(notified.message:match("Could not read the answer"))
  end)

  it("clears any stale findings on a clean review, rather than leaving them", function()
    open("a.lua", { "local x = 1" })
    answer({
      findings = { { line = 1, severity = "warn", message = "stale finding" } },
    })
    assert.are.equal(1, #review.last)

    answer({ findings = {} })
    assert.are.same({}, review.last)
  end)

  it("sets a diagnostic per finding, mapped to the right severity", function()
    local bufnr = open("a.lua", { "local x = 1", "local y = 2" })
    answer({
      findings = {
        { line = 1, severity = "error", message = "first" },
        { line = 2, severity = "info", message = "second" },
      },
    })

    local diagnostics = vim.diagnostic.get(bufnr, { namespace = review.namespace })
    assert.are.equal(2, #diagnostics)
    assert.are.equal(2, #review.last)

    local by_message = {}
    for _, d in ipairs(diagnostics) do
      by_message[d.message] = d
    end
    assert.are.same(vim.diagnostic.severity.ERROR, by_message["first"].severity)
    assert.are.same(0, by_message["first"].lnum)
    assert.are.same(vim.diagnostic.severity.INFO, by_message["second"].severity)
  end)

  it("clamps a line outside the buffer rather than dropping the finding", function()
    local bufnr = open("a.lua", { "local x = 1" })
    answer({
      findings = { { line = 9999, severity = "warn", message = "out of range" } },
    })
    local diagnostics = vim.diagnostic.get(bufnr, { namespace = review.namespace })
    assert.are.equal(1, #diagnostics)
    assert.are.equal(0, diagnostics[1].lnum)
  end)

  it("falls back to info for a severity the schema did not constrain to a known one", function()
    local bufnr = open("a.lua", { "local x = 1" })
    answer({
      findings = { { line = 1, severity = "made up", message = "odd severity" } },
    })
    local diagnostics = vim.diagnostic.get(bufnr, { namespace = review.namespace })
    assert.are.same(vim.diagnostic.severity.INFO, diagnostics[1].severity)
  end)

  it("clears the diagnostics it set, not just its own list", function()
    local bufnr = open("a.lua", { "local x = 1" })
    answer({ findings = { { line = 1, severity = "warn", message = "x" } } })
    assert.are.equal(1, #vim.diagnostic.get(bufnr, { namespace = review.namespace }))

    review.clear(bufnr)
    assert.are.equal(0, #vim.diagnostic.get(bufnr, { namespace = review.namespace }))
    assert.are.same({}, review.last)
  end)
end)

describe("review scope", function()
  local original_ask

  before_each(function()
    original_ask = agent.ask
    agent.ask = setmetatable({ calls = {} }, {
      __call = function(self, prompt, opts)
        table.insert(self.calls, { prompt = prompt, opts = opts })
      end,
    })
    open("a.lua", { "local x = 1" })
    go_to_scope("function")
    agent.ask.calls = {}
  end)

  after_each(function()
    agent.ask = original_ask
    review.clear()
    vim.cmd("silent! %bwipeout!")
  end)

  it("reviews the function or selection first", function()
    review.run()
    assert.is_truthy(agent.ask.calls[1].prompt:match("Review this code for defects%."))
  end)

  it("cycles outward, and back to the start", function()
    -- Read from next_scope's own announcement rather than from agent.ask:
    -- "changes" against this plain, non-repo buffer has no diff to ask
    -- about and calls agent.ask zero times, which is real behaviour and not
    -- something this test is about -- the dedicated real-git-repo describe
    -- block below covers what "changes" actually sends.
    local original_notify = vim.notify
    local announced = {}
    vim.notify = function(message, _, opts)
      if opts and opts.title == "Review scope" then
        table.insert(announced, message:match("^(%a+):"))
      end
    end

    review.next_scope()
    review.next_scope()
    review.next_scope()

    vim.notify = original_notify
    assert.are.same({ "file", "changes", "function" }, announced)
  end)

  it("chooses a scope by index rather than walking to it", function()
    local original_select = vim.ui.select
    vim.ui.select = function(_, _, on_choice)
      on_choice(nil, 2) -- "file"
    end
    review.choose_scope()
    vim.ui.select = original_select

    assert.is_truthy(agent.ask.calls[1].prompt:match("Review this source for defects%."))
  end)
end)

describe("the changes scope, against a real git diff", function()
  local original_ask
  local repo

  before_each(function()
    original_ask = agent.ask
    agent.ask = setmetatable({ calls = {} }, {
      __call = function(self, prompt, opts)
        table.insert(self.calls, { prompt = prompt, opts = opts })
      end,
    })

    repo = vim.fn.tempname()
    vim.fn.mkdir(repo, "p")
    vim.system({ "git", "init", "-q", "-b", "main" }, { cwd = repo }):wait()
    vim.system({ "git", "config", "user.email", "spec@example.invalid" }, { cwd = repo }):wait()
    vim.system({ "git", "config", "user.name", "Spec" }, { cwd = repo }):wait()
  end)

  after_each(function()
    agent.ask = original_ask
    review.clear()
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(repo, "rf")
  end)

  it("has nothing to review when the file has no unstaged change", function()
    local path = vim.fs.joinpath(repo, "main.lua")
    vim.fn.writefile({ "local x = 1" }, path)
    vim.system({ "git", "add", "-A" }, { cwd = repo }):wait()
    vim.system({ "git", "commit", "-q", "-m", "init" }, { cwd = repo }):wait()

    vim.cmd.edit(path)
    -- go_to_scope's own probing walks through and past "changes" once
    -- gather() there gives it nothing to ask about, same as the real key
    -- would -- which is the behaviour under test, not a side effect of
    -- getting there.
    local before = #agent.ask.calls
    go_to_scope("changes")
    assert.are.equal(before, #agent.ask.calls)
  end)

  it("sends the diff alongside the buffer, for a real unstaged change", function()
    local path = vim.fs.joinpath(repo, "main.lua")
    vim.fn.writefile({ "local x = 1" }, path)
    vim.system({ "git", "add", "-A" }, { cwd = repo }):wait()
    vim.system({ "git", "commit", "-q", "-m", "init" }, { cwd = repo }):wait()

    vim.fn.writefile({ "local x = 2" }, path)
    vim.cmd.edit(path)
    go_to_scope("changes")

    local prompt = agent.ask.calls[#agent.ask.calls].prompt
    assert.is_truthy(prompt:match("local x = 2"))
    assert.is_truthy(prompt:match("diff"))
    assert.is_truthy(prompt:match("%-local x = 1"))
  end)
end)
