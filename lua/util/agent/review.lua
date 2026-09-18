--- Review, delivered as diagnostics rather than as a patch.
---
--- This is the point of the integration. A review that arrives as prose gets
--- skimmed; a review that arrives as a diff gets accepted. A review that
--- arrives as diagnostics has to be navigated with ]d and fixed by typing,
--- which is the same motion as fixing anything the language server found, so
--- the findings land in a habit that already exists.
---
--- They also open in a picker, because diagnostics answer "what is wrong on
--- this line" and not "what is wrong overall", and because a review that spans
--- files has nowhere to put itself in a single buffer.
---
--- One key, with the scope switched inside it rather than one key per scope —
--- the same shape as the grep filter, so there is one idiom to learn instead
--- of two.
---
--- The agent never sees your fix unless you ask again. Re-running is how you
--- check yourself, and a finding that disappears is one you resolved.

local agent = require("util.agent")
local context = require("util.agent.context")

local M = {}

M.namespace = vim.api.nvim_create_namespace("agent-review")

-- A finding is a sentence, not a compiler's one-liner, and every place that
-- shows one by default cuts it off: virtual text ends at the window edge, and
-- the picker's list column is about half a screen wide. Virtual lines put the
-- whole message under the line it is about, wrapped, for the line the cursor
-- is on — so reading a finding in full is "move to it" rather than "find the
-- key that reveals the rest of it".
--
-- Scoped to this namespace, so it applies to the agent's findings and leaves
-- the language server's diagnostics rendering as they were.
--- Break a sentence into lines that fit, on word boundaries.
---@param text string
---@param width integer
---@return string
local function wrapped(text, width)
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    if line == "" then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. " " .. word
    else
      table.insert(lines, line)
      line = word
    end
  end
  if line ~= "" then
    table.insert(lines, line)
  end
  return table.concat(lines, "\n")
end

vim.diagnostic.config({
  virtual_text = false,
  virtual_lines = {
    current_line = true,
    -- Virtual lines do not wrap: a line longer than the window simply ends at
    -- its edge, which is the same clipping in a different place. Wrapping the
    -- message here turns one over-long virtual line into several that fit. The
    -- margin covers the tree glyphs virtual lines indent themselves by.
    format = function(diagnostic)
      return wrapped(diagnostic.message, math.max(40, vim.api.nvim_win_get_width(0) - 20))
    end,
  },
}, M.namespace)

--- What to look at. Ordered from tightest to widest, because `<a-s>` walks
--- them and widening is the usual direction when the narrow answer is thin.
---@type { name: string, desc: string, gather: fun(): agent.Context|nil, instruction: string }[]
M.scopes = {
  {
    name = "function",
    desc = "the function the cursor is in, or the selection",
    instruction = "Review this code for defects.",
    gather = function()
      return context.here()
    end,
  },
  {
    name = "file",
    desc = "the whole buffer",
    instruction = "Review this source for defects.",
    gather = function()
      return context.buffer()
    end,
  },
  {
    name = "changes",
    desc = "only the lines you have changed",
    instruction = "Review only the lines this diff changes. Ignore defects in code it does not touch.",
    gather = function()
      local file = vim.fn.expand("%:p")
      if file == "" then
        vim.notify("This buffer is not a file.", vim.log.levels.WARN, { title = "Review" })
        return nil
      end

      local diff = vim.system({ "git", "diff", "-U10", "--", file }, { cwd = agent.root(), text = true }):wait()
      if diff.code ~= 0 or vim.trim(diff.stdout or "") == "" then
        vim.notify("No unstaged changes to this file.", vim.log.levels.INFO, { title = "Review" })
        return nil
      end

      -- The buffer goes too, so a finding can be placed on a real line; the
      -- diff only says which lines are worth looking at.
      local ctx = context.buffer()
      return {
        text = ("%s\n\nAnd the change under review, as a diff:\n%s"):format(ctx.text, diff.stdout),
        first = 1,
        name = ctx.name,
        bufnr = ctx.bufnr,
      }
    end,
  },
}

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

--- The scope in force, remembered so that `<leader>ar` twice in a row means
--- the same thing twice in a row.
local current = 1

--- The last review's findings, so the picker can be reopened without paying
--- for the answer again.
---@type table[]
M.last = {}

--- Clear what the last review left behind.
---@param bufnr? integer
function M.clear(bufnr)
  vim.diagnostic.reset(M.namespace, bufnr or 0)
  M.last = {}
end

---@return string
local function scope_line()
  local parts = {}
  for i, scope in ipairs(M.scopes) do
    table.insert(parts, i == current and ("[" .. scope.name .. "]") or scope.name)
  end
  return table.concat(parts, "  ")
end

--- Show the findings in a picker: fuzzy over the messages, preview of the
--- line, enter to go there. `<a-s>` cycles the scope and reviews again.
function M.open()
  if #M.last == 0 then
    vim.notify("No findings. <leader>ar reviews.", vim.log.levels.INFO, { title = "Review" })
    return
  end

  local items = {}
  for i, finding in ipairs(M.last) do
    table.insert(items, {
      idx = i,
      score = 0,
      text = finding.message,
      file = finding.file,
      pos = { finding.lnum + 1, 0 },
      severity = finding.severity,
      message = finding.message,
    })
  end

  Snacks.picker.pick({
    title = "Findings — " .. scope_line(),
    items = items,
    format = function(item)
      local marks = {
        vim.diagnostic.severity.ERROR,
        vim.diagnostic.severity.WARN,
        vim.diagnostic.severity.INFO,
      }
      local highlight = "DiagnosticInfo"
      for _, level in ipairs(marks) do
        if item.severity == level then
          highlight = "Diagnostic" .. vim.diagnostic.severity[level]:sub(1, 1) .. vim.diagnostic.severity[level]:sub(2):lower()
        end
      end
      return {
        { ("%4d  "):format(item.pos[1]), "SnacksPickerIdx" },
        { item.message, highlight },
      }
    end,
    actions = {
      cycle_scope = function(picker)
        picker:close()
        M.next_scope()
      end,
    },
    win = {
      input = {
        keys = {
          ["<a-s>"] = { "cycle_scope", mode = { "i", "n" }, desc = "Review the next scope out" },
        },
      },
    },
  })
end

--- Review at the current scope.
function M.run()
  local scope = M.scopes[current]
  local ctx = scope.gather()
  if not ctx then
    return
  end

  local prompt = table.concat({
    scope.instruction,
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
    label = "Reviewing " .. scope.name,
    on_done = function(text, structured)
      -- An answer that could not be read is not an answer of "nothing wrong".
      --
      -- Reported as one, it is the most dangerous message this can print: it
      -- says the code is fine when nothing was checked. A backend with no
      -- schema flag returns prose, and prose that fails to parse looked
      -- exactly like a clean review — which is how `HTTP 401: Unauthorized`
      -- spent an afternoon being read as "Nothing found in function".
      if not structured or type(structured.findings) ~= "table" then
        vim.notify(
          ("Could not read the answer, so nothing was checked.\n\n%s"):format(
            vim.trim(text or ""):sub(1, 300)
          ),
          vim.log.levels.ERROR,
          { title = "Review failed" }
        )
        return
      end

      local findings = structured.findings

      if #findings == 0 then
        M.clear(ctx.bufnr)
        vim.notify(
          ("Nothing found in %s. <a-s> from the findings list widens the scope."):format(scope.name),
          vim.log.levels.INFO,
          { title = "Review" }
        )
        return
      end

      local last_line = vim.api.nvim_buf_line_count(ctx.bufnr)
      local file = vim.api.nvim_buf_get_name(ctx.bufnr)
      local items = {}

      for _, f in ipairs(findings) do
        -- A line outside the buffer would throw the finding away entirely, so
        -- clamp it and keep the message.
        local lnum = math.max(1, math.min(tonumber(f.line) or 1, last_line))
        table.insert(items, {
          bufnr = ctx.bufnr,
          file = file,
          lnum = lnum - 1,
          col = 0,
          severity = LEVELS[f.severity] or vim.diagnostic.severity.INFO,
          message = f.message,
          source = require("util.agent.backends")[agent.config.backend].label,
        })
      end

      vim.diagnostic.set(M.namespace, ctx.bufnr, items)
      M.last = items
      M.open()
    end,
  })
end

--- Move to the next scope out and review again.
function M.next_scope()
  current = (current % #M.scopes) + 1
  local scope = M.scopes[current]
  vim.notify(scope.name .. ": " .. scope.desc, vim.log.levels.INFO, { title = "Review scope" })
  M.run()
end

--- Choose a scope by name rather than walking to it.
function M.choose_scope()
  local labels = {}
  for _, scope in ipairs(M.scopes) do
    table.insert(labels, ("%-9s %s"):format(scope.name, scope.desc))
  end

  vim.ui.select(labels, { prompt = "Review scope" }, function(_, index)
    if index then
      current = index
      M.run()
    end
  end)
end

return M
