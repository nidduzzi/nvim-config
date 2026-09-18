--- The questions that make you faster without doing the work for you.
---
--- Three of them, and the difference between them matters:
---
---   look up   recall you would otherwise have gone to a browser for — a
---             signature, an argument order, which of two similar functions is
---             the right one. This costs no skill, because remembering an
---             argument order was never the skill. It is the mode that makes
---             typing faster.
---
---   explain   what this code does, or what this error means. Understanding is
---             the thing being transferred, and you still write the fix.
---
---   ask       anything else, about the code in front of you.
---
--- None of them returns your solution. Each prompt says so, because a model
--- asked a question about code will write the code unless told not to.

local agent = require("util.agent")
local context = require("util.agent.context")
local panel = require("util.agent.panel")
local recall = require("util.recall")

local M = {}

--- The rule every mode here repeats. Saying it once is not enough: asked about
--- a function, the answer arrives as a rewritten version of that function.
local NO_CODE = table.concat({
  "Answer the question and stop. Do not rewrite, refactor or complete their",
  "code, and do not offer to. Short, concrete illustrative snippets with",
  "placeholder names are fine; their actual solution is not.",
}, "\n")

--- Look something up: a signature, an argument order, the idiomatic call.
---
--- Deliberately terse. This is the mode you reach for mid-keystroke, and a
--- paragraph would cost more time than it saves.
---@param query? string
function M.lookup(query)
  local function run(q)
    if not q or vim.trim(q) == "" then
      return
    end

    local prompt = table.concat({
      "Answer as a reference would: the signature, the argument order, the",
      "return, and one line on which to reach for when two are similar. At most",
      "six lines. No preamble, no encouragement, no summary at the end.",
      "",
      NO_CODE,
      "",
      context.preamble(),
      "Question: " .. q,
    }, "\n")

    agent.ask(prompt, {
      label = "Looking up",
      on_done = function(text)
        panel.show("Look up", text, { footer = ("$%.4f"):format(agent.spend.usd) })
      end,
    })
  end

  if query then
    run(query)
  else
    -- Look-ups repeat far more than questions do: the same signature gets
    -- forgotten twice a week. Offering the last ones back is most of the value.
    recall.input({ kind = "lookup", prompt = "Look up" }, run)
  end
end

--- Explain the code in front of you, or the error on this line.
---
--- When there is a diagnostic under the cursor it explains that instead, since
--- that is almost always the question when there is one.
function M.explain()
  local diagnostics = context.diagnostics_here()
  local ctx = context.here()

  local prompt = table.concat({
    diagnostics ~= "" and "Explain what this error means and what causes it." or "Explain what this code does.",
    "Be specific to what is written here. At most one short paragraph, plus a",
    "list only if the code really has distinct steps.",
    "",
    NO_CODE,
    "",
    context.preamble(),
    diagnostics ~= "" and ("Error:\n" .. diagnostics) or "",
    "",
    ("Code (%s):"):format(ctx.name),
    ctx.text,
  }, "\n")

  agent.ask(prompt, {
    uses_code = true,
    label = diagnostics ~= "" and "Explaining the error" or "Explaining",
    on_done = function(text)
      panel.show(diagnostics ~= "" and "What this error means" or "What this does", text)
    end,
  })
end

--- Ask anything about the code in front of you.
---@param question? string
function M.ask(question)
  local function run(q)
    if not q or vim.trim(q) == "" then
      return
    end

    -- The one mode that works on every rung, because on the first one it is
    -- the whole point: no code goes out, so the question has to carry your
    -- understanding of it. That is rubber-ducking, and the explaining is the
    -- part that teaches.
    local backends = require("util.agent.backends")
    local with_code = backends.sends_context(agent.config.trust)

    local lines = {
      with_code and "Answer this question about the code below."
        or "Answer this question. You have not been shown the code, so answer from the description, and say plainly which part you are guessing at.",
      "",
      NO_CODE,
      "",
      context.preamble(),
      "Question: " .. q,
    }
    if with_code then
      local ctx = context.here()
      vim.list_extend(lines, { "", ("Code (%s):"):format(ctx.name), ctx.text })
    end

    agent.ask(table.concat(lines, "\n"), {
      label = with_code and "Asking" or "Asking, without your code",
      on_done = function(text)
        panel.show(with_code and "Answer" or "Answer, from your description alone", text)
      end,
    })
  end

  if question then
    run(question)
  else
    recall.input({ kind = "ask", prompt = "Ask about this code" }, run)
  end
end

return M
