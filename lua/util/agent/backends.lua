--- Which coding agent answers, and what each one can actually promise.
---
--- Nothing above this file is Claude-specific: the modes want an answer, a
--- conversation that persists, and a guarantee that nothing was written. Any
--- CLI that can do those three can sit here.
---
--- The third one is the difficult one, and it is the reason this file exists
--- rather than a `cmd` option. Every agent disables tools differently, some
--- cannot disable them at all, and one of them turns approvals *off* in the
--- same flag that makes it non-interactive. A backend that has not been shown
--- to refuse a write is not a backend this can use, so each one declares how it
--- is locked down and whether that has been proven on this machine.
---
--- Prove it with tools/nvim-harness/agent-canary.sh, which asks the agent to
--- overwrite a file and then looks at the file.

local M = {}

---@class agent.Backend
---@field cmd string executable to look for
---@field label string what to call it
---@field lockdown string[] flags that remove every tool
---@field argv fun(self: agent.Backend, prompt: string, schema: table|nil, session: string|nil, model: string|nil): string[]
---@field parse fun(self: agent.Backend, stdout: string): agent.Answer|nil
---@field session_by "id"|"name" how a conversation is resumed
---@field native_schema boolean whether the CLI constrains the output itself
---@field proven boolean whether the lockdown has been verified here
---@field proof string|nil what the verification rests on
---@field default_model string|nil model to pass when nothing overrides it
---@field timeout integer|nil milliseconds, when this agent is slower than most

---@class agent.Answer
---@field text string
---@field structured table|nil
---@field session_id string|nil
---@field cost number|nil

--- Pull an object out of an answer that was asked for JSON but is not obliged
--- to return only JSON. Agents without a schema flag wrap it in prose, or in a
--- ```json fence, or both.
---@param text string
---@return table|nil
local function loose_json(text)
  local candidates = {}

  local fenced = text:match("```json%s*(.-)%s*```") or text:match("```%s*(.-)%s*```")
  if fenced then
    table.insert(candidates, fenced)
  end

  -- The outermost braces, which is right when the object is the whole answer
  -- and when it is buried in a sentence.
  local braced = text:match("(%b{})")
  if braced then
    table.insert(candidates, braced)
  end

  table.insert(candidates, text)

  for _, candidate in ipairs(candidates) do
    local ok, decoded = pcall(vim.json.decode, candidate)
    if ok and type(decoded) == "table" then
      return decoded
    end
  end
  return nil
end

--- Say in words what a schema asks for, for agents that cannot be handed one.
---@param schema table
---@return string
local function describe_schema(schema)
  return table.concat({
    "",
    "Reply with JSON and nothing else. No prose before or after, no code fence.",
    "It must match this JSON Schema:",
    vim.json.encode(schema),
  }, "\n")
end

--- Claude Code.
---
--- The strongest guarantee of the three, because it is the only one that can
--- be checked without asking the model. `--tools ""` empties the built-in set
--- and
--- `--strict-mcp-config` drops the MCP servers, which `--tools ""` leaves
--- behind: without it Claude still had Drive, browser and codegraph. Under both
--- flags the CLI's startup event reports `tools=[] mcp_servers=[]`, and the
--- canary file survives.
---
--- Do not ask the model instead. Asked to list its tools it named Write, Edit,
--- NotebookEdit and Bash while holding none of them, and asked to write it
--- produced fabricated tool-call markup. The registry is the witness.
---@type agent.Backend
M.claude = {
  cmd = "claude",
  label = "Claude Code",
  lockdown = { "--tools", "", "--strict-mcp-config" },
  session_by = "id",
  native_schema = true,
  proven = true,
  proof = "the CLI's own startup registry reports tools=[] mcp_servers=[]",
  default_model = "sonnet",

  argv = function(self, prompt, schema, session, model)
    local argv = { self.cmd, "-p", "--output-format", "json" }
    vim.list_extend(argv, self.lockdown)
    if model then
      vim.list_extend(argv, { "--model", model })
    end
    if session then
      vim.list_extend(argv, { "--resume", session })
    end
    if schema then
      vim.list_extend(argv, { "--json-schema", vim.json.encode(schema) })
    end
    table.insert(argv, prompt)
    return argv
  end,

  parse = function(_, stdout)
    local ok, decoded = pcall(vim.json.decode, stdout)
    if not ok or type(decoded) ~= "table" then
      return nil
    end
    if decoded.is_error then
      return { text = tostring(decoded.result or "error"), structured = nil }
    end
    return {
      text = tostring(decoded.result or ""),
      structured = decoded.structured_output,
      session_id = decoded.session_id,
      cost = tonumber(decoded.total_cost_usd),
    }
  end,
}

--- Hermes.
---
--- `-z` is the headless mode and `--continue <name>` resumes by name, which
--- suits this better than an id: the name can be the project, so there is
--- nothing to store.
---
--- The lockdown is `-t todo`, and the reason it is that rather than something
--- that reads like "no tools" is worth keeping written down.
---
--- `-z` documents that "approvals are auto-bypassed", so going headless turns
--- the safety prompt off rather than on, leaving the toolsets as the only
--- guard. `-t ""` does not empty them: the empty string is falsy, the flag is
--- ignored, and the configured defaults apply — here `file` and `terminal`. It
--- overwrote the canary on the first attempt. `-t none` is rejected as an
--- unknown toolset and the run then answers nothing at all. `-t todo` names a
--- real toolset that holds nothing dangerous, so the agent answers normally and
--- has no way to write.
---
--- Verified by behaviour rather than by a registry: three write attempts and a
--- shell attempt all left the file alone, and it replied "NO WRITE TOOL". That
--- is weaker than what Claude can show, because it demonstrates that it did not
--- write rather than that it cannot.
---
--- It has no schema flag either, so the review's findings come back as text to
--- be parsed, which is less reliable than a constrained answer.
---
--- Provider and model come from the environment, so an endpoint and a key never
--- land in this repository. Export them from the shell's local tier:
---   CUSTOM_BASE_URL, CUSTOM_API_KEY, HERMES_ALLOW_PRIVATE_URLS,
---   HERMES_INFERENCE_PROVIDER, HERMES_INFERENCE_MODEL
---@type agent.Backend
M.hermes = {
  cmd = "hermes",
  label = "Hermes",
  lockdown = { "-t", "todo" },
  session_by = "name",
  native_schema = false,
  proven = true,
  proof = "behaviour only: three write attempts and a shell attempt all failed",
  default_model = nil,
  -- A local 35B answers a buffer review in about a minute, where Claude takes
  -- a couple of seconds. The shared timeout is tuned for the latter and would
  -- cut this off mid-answer.
  timeout = 300000,

  argv = function(self, prompt, schema, session, model)
    local argv = { self.cmd }
    vim.list_extend(argv, self.lockdown)
    -- Skip AGENTS.md, memory and preloaded skills: this asks about the code in
    -- front of it, and the rest is prompt that has to be paid for every call.
    table.insert(argv, "--ignore-rules")

    -- The environment variables alone do not take on the -z path; they have to
    -- be forwarded as flags.
    local provider = vim.env.HERMES_INFERENCE_PROVIDER
    if provider and provider ~= "" then
      vim.list_extend(argv, { "--provider", provider })
    end
    local chosen = (vim.env.HERMES_INFERENCE_MODEL ~= "" and vim.env.HERMES_INFERENCE_MODEL) or model
    if chosen then
      vim.list_extend(argv, { "-m", chosen })
    end
    if session then
      vim.list_extend(argv, { "--continue", session })
    end
    vim.list_extend(argv, { "-z", schema and (prompt .. describe_schema(schema)) or prompt })
    return argv
  end,

  parse = function(_, stdout)
    -- -z prints the final response text and nothing else, so there is no
    -- envelope to read a cost or a session id out of. --usage-file would give
    -- the cost, at the price of a temporary file per call.
    local text = vim.trim(stdout)
    return { text = text, structured = loose_json(text) }
  end,
}

--- Codex.
---
--- `codex exec` is the headless mode and `--sandbox read-only` is the lockdown.
--- Neither is verified here, because codex is not installed on this machine.
---@type agent.Backend
M.codex = {
  cmd = "codex",
  label = "Codex",
  lockdown = { "--sandbox", "read-only" },
  session_by = "id",
  native_schema = false,
  proven = false,
  proof = nil,

  argv = function(self, prompt, schema, _, model)
    local argv = { self.cmd, "exec" }
    vim.list_extend(argv, self.lockdown)
    if model then
      vim.list_extend(argv, { "--model", model })
    end
    table.insert(argv, schema and (prompt .. describe_schema(schema)) or prompt)
    return argv
  end,

  parse = function(_, stdout)
    local text = vim.trim(stdout)
    return { text = text, structured = loose_json(text) }
  end,
}

--- Resolve a backend by name, with the reasons it might not be usable.
---@param name string
---@return agent.Backend|nil
---@return string|nil problem
function M.resolve(name)
  local backend = M[name]
  if not backend or type(backend) ~= "table" or not backend.cmd then
    return nil, ("There is no backend called %q. Known: claude, hermes, codex."):format(name)
  end
  if vim.fn.executable(backend.cmd) ~= 1 then
    return nil, ("%s is not on PATH. This drives a CLI rather than an API, so there is nothing to fall back to."):format(
      backend.cmd
    )
  end
  return backend, nil
end

--- Every backend, for health reporting.
---@return agent.Backend[]
function M.all()
  local out = {}
  for _, name in ipairs({ "claude", "hermes", "codex" }) do
    table.insert(out, M[name])
  end
  return out
end

return M
