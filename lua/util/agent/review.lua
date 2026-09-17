--- Review, delivered as diagnostics rather than as a patch.
---
--- This is the whole point of the integration. A review that arrives as prose
--- gets skimmed; a review that arrives as a diff gets accepted. A review that
--- arrives as diagnostics has to be navigated with ]d and fixed by typing,
--- which is the same motion as fixing anything the LSP found, so the findings
--- land in a habit that already exists.
---
--- The agent never sees your fix unless you ask again. Re-running is how you check
--- yourself, and a finding that disappears is one you actually resolved.

local agent = require("util.agent")
local context = require("util.agent.context")

local M = {}

M.namespace = vim.api.nvim_create_namespace("agent-review")

--- Findings, constrained so that what comes back can be placed in a buffer
--- without parsing prose. The schema is what stops the answer being an essay.
local SCHEMA = {
  type = "object",
  properties = {
    findings = {
      type = "array",
      items = {
        type = "object",
        properties = {
          line = { type = "integer", description = "the line number shown in the source" },
          severity = { type = "string", enum = { "error", "warn", "info" } },
          message = { type = "string", description = "the defect in one sentence, no code" },
        },
        required = { "line", "severity", "message" },
      },
    },
  },
  required = { "findings" },
}

---@type table<string, integer>
local LEVELS = {
  error = vim.diagnostic.severity.ERROR,
  warn = vim.diagnostic.severity.WARN,
  info = vim.diagnostic.severity.INFO,
}

--- Clear what the last review left behind.
---@param bufnr? integer
function M.clear(bufnr)
  vim.diagnostic.reset(M.namespace, bufnr or 0)
end

---@param ctx agent.Context
---@param instruction string
---@param label string
local function run(ctx, instruction, label)
  local prompt = table.concat({
    instruction,
    "",
    "Report only defects you can point at: a wrong result, a crash, a case that",
    "is not handled, a resource that leaks. Do not report style, naming or",
    "formatting. Do not suggest replacement code — name the problem and let the",
    "author fix it. If the code is sound, return no findings rather than",
    "inventing something.",
    "",
    "Line numbers must be the ones shown in the left column.",
    "",
    context.preamble(),
    ("Source (%s):"):format(ctx.name),
    ctx.text,
  }, "\n")

  agent.ask(prompt, {
    schema = SCHEMA,
    label = label,
    on_done = function(_, structured)
      local findings = structured and structured.findings or {}

      if #findings == 0 then
        M.clear(ctx.bufnr)
        vim.notify("Nothing found.", vim.log.levels.INFO, { title = "Review" })
        return
      end

      local last = vim.api.nvim_buf_line_count(ctx.bufnr)
      local items = {}
      for _, f in ipairs(findings) do
        -- A line outside the buffer would throw away the finding entirely, so
        -- clamp it and keep the message.
        local lnum = math.max(1, math.min(tonumber(f.line) or 1, last))
        table.insert(items, {
          bufnr = ctx.bufnr,
          lnum = lnum - 1,
          col = 0,
          severity = LEVELS[f.severity] or vim.diagnostic.severity.INFO,
          message = f.message,
          -- Name the agent, so a finding is attributable when two of them
          -- disagree and so it never looks like the language server's.
          source = require("util.agent.backends")[require("util.agent").config.backend].label,
        })
      end

      vim.diagnostic.set(M.namespace, ctx.bufnr, items)
      vim.notify(
        ("%d finding%s. ]d walks them."):format(#items, #items == 1 and "" or "s"),
        vim.log.levels.INFO,
        { title = "Review" }
      )
    end,
  })
end

--- Review the whole buffer.
function M.buffer()
  run(context.buffer(), "Review this source for defects.", "Reviewing the buffer")
end

--- Review the selection, or the function the cursor is in.
function M.here()
  run(context.here(), "Review this code for defects.", "Reviewing")
end

--- Review only what you have changed, which is the version worth running often:
--- it asks about your work rather than about the file's history.
function M.changes()
  local file = vim.fn.expand("%:p")
  if file == "" then
    vim.notify("This buffer is not a file.", vim.log.levels.WARN, { title = "Review" })
    return
  end

  local diff = vim.system({ "git", "diff", "-U10", "--", file }, { cwd = agent.root(), text = true }):wait()
  if diff.code ~= 0 or vim.trim(diff.stdout or "") == "" then
    vim.notify("No unstaged changes to this file.", vim.log.levels.INFO, { title = "Review" })
    return
  end

  -- The diff carries its own line numbers in the hunk headers, so the buffer is
  -- sent as well and the diff is described as the part to concentrate on.
  local ctx = context.buffer()
  run(
    {
      text = ("%s\n\nAnd the change under review, as a diff:\n%s"):format(ctx.text, diff.stdout),
      first = 1,
      name = ctx.name,
      bufnr = ctx.bufnr,
    },
    "Review only the lines this diff changes. Ignore defects in code it does not touch.",
    "Reviewing your changes"
  )
end

return M
