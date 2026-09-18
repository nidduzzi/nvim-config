--- Which coding agent answers, how much it is allowed to do, and what each
--- one can actually promise.
---
--- Nothing above this file is Claude-specific: the modes want an answer, a
--- conversation that persists, and a guarantee about what was reachable. Any
--- CLI that can do those three can sit here.
---
--- The third one is the difficult one, and it is the reason this file exists
--- rather than a `cmd` option. Every agent disables tools differently, some
--- cannot disable them at all, and one of them turns approvals *off* in the
--- same flag that makes it non-interactive.
---
--- The rungs
---
--- How much the agent may do is a setting rather than a property of this
--- configuration, because the honest amount changes with the task. Reading an
--- unfamiliar codebase and fixing a typo want different agents.
---
---   chat      no tools, and the prompt carries nothing but what you typed.
---             The rubber duck: it cannot see your code, so explaining it is
---             your job, which is the part that does the teaching.
---   context   no tools, and the editor gathers the function, file, diff or
---             diagnostic and puts it in the prompt. The agent still reads
---             nothing itself; you choose how much it sees.
---   explore   Read, Grep and Glob. It follows a call chain you did not think
---             to paste. It cannot write and cannot run a shell.
---   edit      the above plus Edit and Write, and still no shell.
---   normal    the CLI as the CLI runs, with its own defaults, and no promise
---             made here about any of it.
---
--- The rungs are flags rather than a mode, so they narrow an interactive
--- session exactly as they narrow a headless one. sidekick.nvim's terminal
--- runs the same command: see terminal_tools below, and lua/plugins/sidekick.
--- Without that the terminal would be the one place where "how much may it do"
--- had no answer, and the easiest way to reach the agent would be the way that
--- walks around the ladder.
---
--- A rung a backend cannot express is refused rather than approximated. Hermes
--- has one toolset covering reading and writing together, so it has no
--- `explore`: offering one would mean claiming a guarantee the flag does not
--- give.
---
--- Why the registry and not the flag that looks right
---
--- `--allowedTools Read Grep Glob` reads like the way to do this and does not
--- restrict anything. Asked for its registry under that flag, Claude reported
--- all twenty-nine tools, Bash, Write and Edit among them: it is a list of
--- permissions to grant without asking, not a list of tools to load. `--tools`
--- is the one that empties and narrows the registry, and it is what every rung
--- below is built from.
---
--- Prove it with tools/nvim-harness/agent-canary.sh, which checks the CLI's
--- own registry against the rung and then asks the agent to write anyway.

local M = {}

---@class agent.Backend
---@field cmd string executable to look for
---@field label string what to call it
---@field lockdown string[] flags for the tightest rung, kept for the canary
---@field rungs table<string, string[]|false> flags per rung; false means the backend cannot express it
---@field rung_proof table<string, string> what the guarantee on each rung rests on
---@field argv fun(self: agent.Backend, prompt: string, schema: table|nil, session: string|nil, model: string|nil, rung: string|nil): string[]
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

--- The rungs, tightest first. The order is the ladder: `<leader>a+` moves one
--- step along this list, and nothing skips.
---@type string[]
M.rungs = { "chat", "context", "explore", "edit", "normal" }

--- What each rung means, in one line, for the picker and the panel.
---@type table<string, string>
M.rung_desc = {
  chat = "no tools, and none of your code — you explain it",
  context = "no tools; the editor puts the code in the prompt",
  explore = "reads and greps for itself; cannot write",
  edit = "reads and writes files; still no shell",
  normal = "sidekick.nvim's terminal, with the agent's own defaults",
}

--- Whether a rung lets the editor gather code into the prompt.
---@param rung string
---@return boolean
function M.sends_context(rung)
  return rung ~= "chat"
end

--- Whether a rung is answered headlessly here rather than in a terminal.
---@param rung string
---@return boolean
function M.is_ours(rung)
  return rung ~= "normal"
end

--- One step along the ladder, clamped at both ends.
---@param rung string
---@param by integer
---@return string
function M.step(rung, by)
  for i, name in ipairs(M.rungs) do
    if name == rung then
      return M.rungs[math.min(#M.rungs, math.max(1, i + by))] or rung
    end
  end
  return M.rungs[1]
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
  -- `--strict-mcp-config` on every rung, because `--tools` does not drop the
  -- MCP servers: without it Claude kept Drive, browser and codegraph whatever
  -- the built-in set was narrowed to.
  rungs = {
    chat = { "--tools", "", "--strict-mcp-config" },
    context = { "--tools", "", "--strict-mcp-config" },
    explore = { "--tools", "Read,Grep,Glob", "--strict-mcp-config" },
    edit = { "--tools", "Read,Grep,Glob,Edit,Write", "--strict-mcp-config" },
  },
  rung_proof = {
    chat = "startup registry reports tools=[] mcp_servers=[]",
    context = "startup registry reports tools=[] mcp_servers=[]",
    explore = "startup registry reports exactly Glob, Grep, Read",
    edit = "startup registry reports no Bash and no Task",
  },
  session_by = "id",
  native_schema = true,
  proven = true,
  proof = "the CLI's own startup registry reports tools=[] mcp_servers=[]",
  default_model = "sonnet",

  argv = function(self, prompt, schema, session, model, rung)
    local argv = { self.cmd, "-p", "--output-format", "json" }
    vim.list_extend(argv, self.rungs[rung or "context"] or self.lockdown)
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
  -- `file` is one toolset covering reading and writing, so there is no rung
  -- between "no tools" and "can write". `explore` is false rather than mapped
  -- to `file`, because mapping it would hand back a guarantee the flag does
  -- not make.
  rungs = {
    chat = { "-t", "todo" },
    context = { "-t", "todo" },
    explore = false,
    edit = { "-t", "file" },
  },
  rung_proof = {
    chat = "behaviour only: three write attempts and a shell attempt all failed",
    context = "behaviour only: three write attempts and a shell attempt all failed",
    edit = "not verified here; the file toolset is documented as file operations",
  },
  session_by = "name",
  native_schema = false,
  proven = true,
  proof = "behaviour only: three write attempts and a shell attempt all failed",
  default_model = nil,
  -- A local 35B answers a buffer review in about a minute, where Claude takes
  -- a couple of seconds. The shared timeout is tuned for the latter and would
  -- cut this off mid-answer.
  timeout = 300000,

  argv = function(self, prompt, schema, session, model, rung)
    local argv = { self.cmd }
    vim.list_extend(argv, self.rungs[rung or "context"] or self.lockdown)
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
  -- Written from the documentation, run against nothing. Every entry here is a
  -- guess until the canary has been pointed at it, which is what `proven =
  -- false` above says out loud.
  rungs = {
    chat = { "--sandbox", "read-only" },
    context = { "--sandbox", "read-only" },
    explore = { "--sandbox", "read-only" },
    edit = { "--sandbox", "workspace-write" },
  },
  rung_proof = {},
  session_by = "id",
  native_schema = false,
  proven = false,
  proof = nil,

  argv = function(self, prompt, schema, _, model, rung)
    local argv = { self.cmd, "exec" }
    vim.list_extend(argv, self.rungs[rung or "context"] or self.lockdown)
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

--- The command a terminal should run for this backend at this rung.
---
--- The rung flags are flags, not a mode, so the same ones that narrow a
--- headless request narrow an interactive session. That matters more than it
--- looks: without this the top of the ladder would be the only rung where
--- "how much may it do" had no answer, and the obvious way to use the terminal
--- would be the way that bypasses the ladder entirely.
---
--- `normal` is the exception on purpose. It runs the CLI the way the CLI runs,
--- and the absence of flags is the promise being withdrawn.
---@param backend agent.Backend
---@param rung string
---@return string[]|nil
function M.terminal_cmd(backend, rung)
  local cmd = { backend.cmd }
  if rung == "normal" then
    return cmd
  end
  local flags = (backend.rungs or {})[rung]
  if not flags then
    return nil
  end
  vim.list_extend(cmd, flags)
  return cmd
end

--- What sidekick.nvim should call this backend-and-rung pair.
---@param name string
---@param rung string
---@return string
function M.terminal_name(name, rung)
  return rung == "normal" and name or (name .. "_" .. rung)
end

--- Every backend-and-rung pair, as sidekick.nvim's tool table wants them.
---
--- Generated rather than written out, so a rung added above appears in the
--- terminal without being added twice and without the two drifting.
---@return table<string, table>
function M.terminal_tools()
  local tools = {}
  for _, name in ipairs({ "claude", "hermes", "codex" }) do
    local backend = M[name]
    for _, rung in ipairs(M.rungs) do
      local cmd = M.terminal_cmd(backend, rung)
      if cmd then
        tools[M.terminal_name(name, rung)] = {
          cmd = cmd,
          is_proc = ("\\<%s\\>"):format(backend.cmd),
          url = backend.url,
        }
      end
    end
  end
  return tools
end

--- Whether a backend can honestly offer a rung, and why not when it cannot.
---@param backend agent.Backend
---@param rung string
---@return boolean ok
---@return string|nil why_not
function M.supports(backend, rung)
  if rung == "normal" then
    -- Nothing here runs it, so there is nothing here to refuse.
    return true, nil
  end
  local flags = (backend.rungs or {})[rung]
  if flags == false then
    return false,
      ("%s has no %s rung: its toolsets do not separate reading from writing, and pretending otherwise would be a guarantee it cannot keep."):format(
        backend.label,
        rung
      )
  end
  if not flags then
    return false, ("%s does not define a %s rung."):format(backend.label, rung)
  end
  return true, nil
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
