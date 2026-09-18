--- Talk to a coding agent without letting it touch anything.
---
--- The established integrations are chat-and-apply: a terminal split
--- (sidekick.nvim, driving any of a dozen CLIs), the reverse-engineered IDE
--- websocket (claudecode.nvim, which LazyVim ships as an extra), or an ACP
--- chat buffer (avante.nvim, codecompanion.nvim, agentic.nvim). In all of them
--- the agent edits files with its own tools and the plugin reloads the buffer
--- afterwards; applying the diff is the feature, and none of them models
--- tool-disablement at all.
---
--- One project does make the same never-writes promise — aporia.nvim, "an AI
--- tutor for Neovim that never writes code", which has a hint ladder too. It
--- reaches an OpenAI-compatible endpoint with an API key, and answers into a
--- chat buffer.
---
--- What is not covered by either: read-only against a subscription CLI. The
--- CLI-driven plugins all write; the read-only one needs an API key. This sits
--- in the gap. No tool ever exists, and what comes back is a finding, a hint or
--- an explanation, never a patch. The typing stays yours.
---
--- Which agent answers is a setting — see backends.lua — but the read-only
--- property is not something a backend gets to claim. It has to be shown, with
--- tools/nvim-harness/agent-canary.sh, and an unproven backend says so out loud
--- every time it is used.

local backends = require("util.agent.backends")

local M = {}

--- Which agent answers, and how, read through the settings tiers rather than
--- held here. Choosing a backend used to last until you quit, and a project
--- had no way to say "this one uses the local model".
---
---   agent_backend          claude, hermes, codex
---   agent_model            nil means whatever that backend prefers
---   agent_timeout          milliseconds; a local model needs far more
---   agent_allow_unproven   use one not shown to be unable to write
---
--- Set any of them in a project's .nvim.lua as vim.g.agent_backend, in
--- <config>/local.lua for this machine, or with <leader>au for right now.
M.config = setmetatable({}, {
  __index = function(_, key)
    return require("util.settings").get("agent_" .. key)
  end,
  -- Assigning still works and means "for this session", which is what anything
  -- already doing `config.backend = "hermes"` meant.
  __newindex = function(_, key, value)
    require("util.settings").set("agent_" .. key, value)
  end,
})

--- The job in flight, so a second request replaces the first rather than
--- racing it.
---@type vim.SystemObj|nil
local running = nil

--- What this editor session has spent. The cost is real money, and an
--- integration that hides it is how you end up surprised by a bill.
M.spend = { calls = 0, usd = 0.0 }

--- The project this buffer belongs to.
---
--- The conversation is per project because an agent's cached prompt includes
--- the working directory. Measured with Claude: a call that misses that cache
--- costs $0.119 and takes 10.8s, and the same call resumed with identical flags
--- from the same directory costs $0.0098 and takes 2.6s. Twelve times cheaper
--- and four times faster, which is why the flags are fixed per backend and the
--- directory is pinned here.
---@return string
function M.root()
  local markers = { ".git", "pyproject.toml", "package.json", "Cargo.toml", "go.mod" }
  local from = vim.fn.expand("%:p:h")
  if from == "" then
    from = assert(vim.uv.cwd())
  end
  local found = vim.fs.find(markers, { upward = true, path = from })[1]
  return found and vim.fs.dirname(found) or assert(vim.uv.cwd())
end

--- Where this project's conversation is remembered between editor sessions.
---@param root string
---@return string
local function session_file(root)
  local dir = vim.fs.joinpath(vim.fn.stdpath("state") --[[@as string]], "nvim-agent")
  vim.fn.mkdir(dir, "p")
  return vim.fs.joinpath(dir, ("%s-%s"):format(M.config.backend, vim.fn.sha256(root):sub(1, 16)))
end

--- The conversation to resume, which is an id for agents that mint one and a
--- stable name for agents that resume by name.
---@param root string
---@param backend agent.Backend
---@return string|nil
local function read_session(root, backend)
  if backend.session_by == "name" then
    return "nvim-" .. vim.fn.sha256(root):sub(1, 12)
  end

  local fd = io.open(session_file(root), "r")
  if not fd then
    return nil
  end
  local id = vim.trim(fd:read("*a") or "")
  fd:close()
  return id ~= "" and id or nil
end

---@param root string
---@param id string
local function write_session(root, id)
  local fd = io.open(session_file(root), "w")
  if fd then
    fd:write(id)
    fd:close()
  end
end

--- Forget this project's conversation, so the next call starts clean.
---
--- Worth doing when it has drifted: the conversation carries every earlier
--- question, which is what makes follow-ups cheap and also what makes a long
--- one gradually less focused. It will answer a repeated question with "same
--- question, same rung" rather than afresh.
function M.reset()
  local root = M.root()
  os.remove(session_file(root))
  vim.notify(
    "Starting a new conversation for " .. vim.fn.fnamemodify(root, ":~"),
    vim.log.levels.INFO,
    { title = "Agent" }
  )
end

--- Take down the pending toast.
---
--- snacks.nvim hides by the id the toast was given. It has to be an id we
--- chose: vim.notify answers with a table ({ id = 2 }), not the id, so handing
--- that back hides nothing and fails silently. Two versions of this left a
--- permanent "Reviewing the buffer..." in the corner for exactly that reason.
---@param notice string
local function dismiss(notice)
  pcall(function()
    Snacks.notifier.hide(notice)
  end)
end

--- Ask the configured agent something, with exactly the tools the current rung
--- allows and no more.
---
---@param prompt string
---@param opts { schema?: table, on_done: fun(text: string, structured: table|nil), label?: string, uses_code?: boolean }
function M.ask(prompt, opts)
  local backend, problem = backends.resolve(M.config.backend)
  if not backend then
    vim.notify(problem or "No backend.", vim.log.levels.ERROR, { title = "Agent" })
    return
  end

  local rung = M.config.trust

  -- The top rung is a terminal someone else runs. Answering it here would be
  -- this file quietly doing something it makes no promise about.
  if not backends.is_ours(rung) then
    vim.notify(
      ("The %s rung is sidekick.nvim's terminal, not this. Open it with <leader>an, or step back down with <leader>a-."):format(
        rung
      ),
      vim.log.levels.WARN,
      { title = "Agent" }
    )
    return
  end

  local can, why_not = backends.supports(backend, rung)
  if not can then
    vim.notify(why_not or "That rung is unavailable.", vim.log.levels.ERROR, { title = "Agent" })
    return
  end

  -- On the first rung the agent sees no code at all, so the modes that exist
  -- to talk about code have nothing to say. Refusing is the point of the rung
  -- rather than a limitation of it: the explaining is yours to do.
  if opts.uses_code and not backends.sends_context(rung) then
    vim.notify(
      "The chat rung sends none of your code, so there is nothing here to review or explain.\n\nAsk a question with <leader>aa, or step up to context with <leader>a+.",
      vim.log.levels.WARN,
      { title = "Agent" }
    )
    return
  end

  -- The whole design rests on the agent being unable to write. A backend that
  -- has not been shown to refuse is not something to find out about from a
  -- changed file, so it has to be opted into and it says so every time.
  if not backend.proven then
    if not M.config.allow_unproven then
      vim.notify(
        ("%s has not been shown to refuse a write on this machine.\n\nProve it with tools/nvim-harness/agent-canary.sh, or set allow_unproven if you have satisfied yourself another way."):format(
          backend.label
        ),
        vim.log.levels.ERROR,
        { title = "Agent" }
      )
      return
    end
    vim.notify(
      ("%s is unproven: nothing here can stop it writing."):format(backend.label),
      vim.log.levels.WARN,
      { title = "Agent" }
    )
  end

  if running then
    running:kill("sigterm")
    running = nil
  end

  local root = M.root()
  local session = read_session(root, backend)
  local argv = backend:argv(prompt, opts.schema, session, M.config.model or backend.default_model, rung)

  -- A toast with no timeout, so it stays while the call is out.
  local notice = "nvim-agent-pending"
  vim.notify((opts.label or "Thinking") .. "...", vim.log.levels.INFO, {
    title = backend.label,
    timeout = false,
    id = notice,
  })
  local started = vim.uv.hrtime()

  running = vim.system(argv, {
    cwd = root,
    text = true,
    -- Without this the CLI waits on stdin and warns after three seconds.
    stdin = false,
    timeout = backend.timeout or M.config.timeout,
  }, function(result)
    running = nil

    vim.schedule(function()
      dismiss(notice)

      if result.code ~= 0 then
        vim.notify(
          ("%s exited %d\n%s"):format(backend.label, result.code, vim.trim(result.stderr or "")),
          vim.log.levels.ERROR,
          { title = "Agent" }
        )
        return
      end

      local answer = backend:parse(result.stdout or "")
      if not answer then
        vim.notify(
          ("Could not read %s's answer."):format(backend.label),
          vim.log.levels.ERROR,
          { title = "Agent" }
        )
        return
      end

      -- Remember the conversation, so the next call reads the cache rather than
      -- rebuilding it. Backends that resume by name have nothing to store.
      if answer.session_id and backend.session_by == "id" then
        write_session(root, answer.session_id)
      end

      M.spend.calls = M.spend.calls + 1
      M.spend.usd = M.spend.usd + (answer.cost or 0)
      M.spend.last_ms = math.floor((vim.uv.hrtime() - started) / 1e6)

      opts.on_done(answer.text, answer.structured)
    end)
  end)
end

--- Switch agent, for the length of this editor session.
---@param name? string
function M.use(name)
  local function apply(choice)
    if not choice or choice == "" then
      return
    end
    local backend, problem = backends.resolve(choice)
    if not backend then
      vim.notify(problem or "Unknown backend.", vim.log.levels.ERROR, { title = "Agent" })
      return
    end
    M.config.backend = choice
    vim.notify(
      ("Now asking %s.%s"):format(backend.label, backend.proven and "" or " Its lockdown is unproven here."),
      backend.proven and vim.log.levels.INFO or vim.log.levels.WARN,
      { title = "Agent" }
    )
  end

  if name then
    apply(name)
    return
  end

  local names = {}
  for _, backend in ipairs(backends.all()) do
    if vim.fn.executable(backend.cmd) == 1 then
      table.insert(names, backend.cmd)
    end
  end

  vim.ui.select(names, { prompt = "Ask which agent?" }, apply)
end

--- Move one rung along the ladder, or pick one outright.
---
--- Escalation is deliberate and one step at a time. Anything that jumped
--- straight to the top would make the ladder decoration: the point is that
--- letting an agent read your repository, and then write to it, are two
--- separate decisions you make on purpose.
---@param to? string a rung name, or nil to pick from a list
---@param by? integer steps along the ladder, when `to` is nil
function M.trust(to, by)
  local function apply(choice)
    if not choice or choice == "" then
      return
    end
    if not vim.tbl_contains(backends.rungs, choice) then
      vim.notify(
        ("There is no %q rung. Known: %s."):format(choice, table.concat(backends.rungs, ", ")),
        vim.log.levels.ERROR,
        { title = "Agent" }
      )
      return
    end

    local backend = backends[M.config.backend]
    if backend then
      local can, why_not = backends.supports(backend, choice)
      if not can then
        vim.notify(why_not or "That rung is unavailable.", vim.log.levels.ERROR, { title = "Agent" })
        return
      end
    end

    M.config.trust = choice
    local proof = backend and (backend.rung_proof or {})[choice]
    vim.notify(
      table.concat({
        ("%s: %s"):format(choice, backends.rung_desc[choice] or ""),
        proof and ("verified by: " .. proof) or "no verification recorded for this rung",
      }, "\n"),
      choice == "normal" and vim.log.levels.WARN or vim.log.levels.INFO,
      { title = "Agent" }
    )
  end

  if to then
    apply(to)
    return
  end
  if by then
    apply(backends.step(M.config.trust, by))
    return
  end

  local items = {}
  for _, rung in ipairs(backends.rungs) do
    table.insert(items, rung)
  end
  vim.ui.select(items, {
    prompt = "How much may the agent do?",
    format_item = function(rung)
      return ("%-8s %s"):format(rung, backends.rung_desc[rung] or "")
    end,
  }, apply)
end

--- What this editor session has cost so far.
function M.report()
  local backend = backends[M.config.backend]
  vim.notify(
    table.concat({
      ("agent: %s"):format(backend and backend.label or M.config.backend),
      ("rung: %s — %s"):format(M.config.trust, backends.rung_desc[M.config.trust] or ""),
      ("guarantee: %s"):format(
        (backend and (backend.rung_proof or {})[M.config.trust]) or "NOT VERIFIED for this rung"
      ),
      ("calls this session: %d"):format(M.spend.calls),
      ("spent: %s"):format(M.spend.usd > 0 and ("$%.4f"):format(M.spend.usd) or "not reported by this agent"),
      ("last call: %s"):format(M.spend.last_ms and (M.spend.last_ms .. "ms") or "none yet"),
      ("project: %s"):format(vim.fn.fnamemodify(M.root(), ":~")),
    }, "\n"),
    vim.log.levels.INFO,
    { title = "Agent" }
  )
end

--- Whether a request is in flight.
---
--- Exists for anything that has to wait for the answer rather than guess how
--- long it takes. The tour recorder used a fixed pause, which is wrong in both
--- directions: a local 35B answered a hint in 151 seconds against a 150 second
--- pause, so the film recorded an empty screen, and every faster answer than
--- that sat idle for the remainder.
---@return boolean
function M.is_running()
  return running ~= nil
end

--- Stop whatever is in flight.
function M.cancel()
  if running then
    running:kill("sigterm")
    running = nil
    vim.notify("Cancelled.", vim.log.levels.INFO, { title = "Agent" })
  else
    vim.notify("Nothing running.", vim.log.levels.INFO, { title = "Agent" })
  end
end

return M
