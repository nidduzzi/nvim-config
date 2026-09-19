-- The rung ladder. Every claim here is one the canary checks against a real
-- CLI; these tests check that the table the canary is kept in step with says
-- what it is supposed to say.

local backends = require("util.agent.backends")

describe("the rung ladder", function()
  it("is ordered from least to most", function()
    assert.are.same({ "chat", "context", "explore", "edit", "normal" }, backends.rungs)
  end)

  it("steps one rung at a time and stops at both ends", function()
    assert.are.same("explore", backends.step("context", 1))
    assert.are.same("context", backends.step("explore", -1))
    assert.are.same("chat", backends.step("chat", -1))
    assert.are.same("normal", backends.step("normal", 1))
  end)

  it("sends no code on the first rung and code on every other", function()
    assert.is_false(backends.sends_context("chat"))
    for _, rung in ipairs({ "context", "explore", "edit", "normal" }) do
      assert.is_true(backends.sends_context(rung))
    end
  end)

  it("answers the top rung somewhere else", function()
    assert.is_false(backends.is_ours("normal"))
    for _, rung in ipairs({ "chat", "context", "explore", "edit" }) do
      assert.is_true(backends.is_ours(rung))
    end
  end)
end)

describe("claude's rungs", function()
  it("empties the registry on chat and context", function()
    for _, rung in ipairs({ "chat", "context" }) do
      assert.are.same({ "--tools", "", "--strict-mcp-config" }, backends.claude.rungs[rung])
    end
  end)

  it("names exactly the reading tools on explore", function()
    assert.are.same({ "--tools", "Read,Grep,Glob", "--strict-mcp-config" }, backends.claude.rungs.explore)
  end)

  it("adds writing but never a shell on edit", function()
    local flags = backends.claude.rungs.edit
    assert.are.same({ "--tools", "Read,Grep,Glob,Edit,Write", "--strict-mcp-config" }, flags)
    assert.is_falsy(table.concat(flags, " "):find("Bash"))
  end)

  it("drops the MCP servers on every rung", function()
    -- --tools narrows the built-in set and leaves MCP alone, so without this
    -- Claude kept Drive, browser and codegraph whatever the rung said.
    for rung, flags in pairs(backends.claude.rungs) do
      assert.is_truthy(vim.tbl_contains(flags, "--strict-mcp-config"), rung .. " does not drop MCP")
    end
  end)

  it("builds the argv for the rung it was asked for", function()
    local argv = backends.claude:argv("hi", nil, nil, nil, "explore")
    assert.are.same("claude", argv[1])
    assert.is_truthy(table.concat(argv, " "):find("--tools Read,Grep,Glob", 1, true))
  end)
end)

describe("a rung a backend cannot express", function()
  it("is refused rather than approximated", function()
    -- Hermes has one toolset covering reading and writing together.
    local ok, why = backends.supports(backends.hermes, "explore")
    assert.is_false(ok)
    assert.is_truthy(why:find("explore"))
  end)

  it("is still offered where it exists", function()
    for _, rung in ipairs({ "chat", "context", "edit" }) do
      assert.is_true((backends.supports(backends.hermes, rung)))
    end
  end)

  it("has no terminal either", function()
    assert.is_nil(backends.terminal_cmd(backends.hermes, "explore"))
    assert.is_nil(backends.terminal_tools()["hermes_explore"])
  end)
end)

describe("the terminal", function()
  it("runs the same flags as the headless path", function()
    local cmd = backends.terminal_cmd(backends.claude, "explore")
    assert.are.same({ "claude", "--tools", "Read,Grep,Glob", "--strict-mcp-config" }, cmd)
  end)

  it("withdraws the promise on the top rung", function()
    assert.are.same({ "claude" }, backends.terminal_cmd(backends.claude, "normal"))
  end)

  it("registers one tool per backend and rung", function()
    local tools = backends.terminal_tools()
    for _, name in ipairs({ "claude_chat", "claude_explore", "claude_edit", "hermes_edit", "claude" }) do
      assert.is_truthy(tools[name], name .. " is missing")
    end
  end)
end)
