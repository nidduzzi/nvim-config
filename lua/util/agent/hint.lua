--- Help, rationed on purpose.
---
--- The reason a coding model erodes the skill it is helping with is that it
--- answers at full strength every time. Ask how to do something and you are
--- handed the doing of it, so the part where you would have worked it out never
--- happens.
---
--- So the answer is delivered in rungs. The first press says what kind of
--- problem you are looking at and nothing more. Each further press gives up a
--- little more, and the last one names the function and its signature — which
--- is also the rung that makes you faster, because naming the right API is the
--- lookup you would otherwise have gone to a browser for.
---
--- The ladder resets when you move somewhere else, so it measures how stuck you
--- are here, not how many times you have pressed the key today.

local agent = require("util.agent")
local context = require("util.agent.context")
local panel = require("util.agent.panel")

local M = {}

--- The rungs. Each one says what may be given and, as importantly, what may
--- not: without the second half the model answers the whole question on rung
--- one every time.
---@type { name: string, instruction: string }[]
M.rungs = {
  {
    name = "what kind of problem",
    instruction = "Say what CLASS of problem this is, in at most two sentences. "
      .. "Name the category, not the solution. Do not name any function, method, "
      .. "library or algorithm. Do not describe the steps. The reader wants to "
      .. "recognise the shape of the problem and go and think about it.",
  },
  {
    name = "the approach",
    instruction = "Describe the approach in prose, in at most four sentences. "
      .. "Say what has to happen and in what order. Do not name a specific "
      .. "function, method or library, and do not write any code.",
  },
  {
    name = "what to look up",
    instruction = "Name the specific function, method, module or concept to look "
      .. "up, and say in one sentence what it does. Do not show its signature and "
      .. "do not write any code.",
  },
  {
    name = "the signature",
    instruction = "Give the signature of the relevant function or method and one "
      .. "line showing the shape of a call, using placeholder names. Do not write "
      .. "the caller's code, and do not apply it to their specific case.",
  },
}

--- Where the ladder currently stands. Keyed on the position, so moving away and
--- coming back starts over — which is usually what you want, because by then
--- you have been thinking about something else.
---@type { key: string, rung: integer }
local at = { key = "", rung = 0 }

---@return string
local function position()
  local ctx = context.here()
  return ("%s:%d"):format(vim.api.nvim_buf_get_name(0), ctx and ctx.first or 1)
end

--- Take the next rung. Press again to climb; the last rung stays put rather
--- than rolling over into giving you the answer.
---@param question? string what you are trying to do, if the code does not say
function M.next(question)
  local key = position()
  if key ~= at.key then
    at = { key = key, rung = 0 }
  end

  if at.rung >= #M.rungs then
    vim.notify("That is the last rung. Nothing further is coming — write it, then review it with <leader>ar.", vim.log.levels.WARN, { title = "Hint" })
    return
  end

  at.rung = at.rung + 1
  local rung = M.rungs[at.rung]
  local ctx = context.here()

  local prompt = table.concat({
    "Someone is writing this code and is stuck. Give them exactly one rung of a",
    "hint ladder, no more. They have asked for rung " .. at.rung .. " of " .. #M.rungs .. ".",
    "",
    "Rung " .. at.rung .. " (" .. rung.name .. "): " .. rung.instruction,
    "",
    "Do not exceed the rung, even if the full answer seems obvious or kind. They",
    "are rationing this on purpose so they still learn the material.",
    "",
    context.preamble(),
    question and ("They are trying to: " .. question) or "",
    "",
    ("Code (%s):"):format(ctx.name),
    ctx.text,
    "",
    (function()
      local d = context.diagnostics_here()
      return d ~= "" and ("Errors on the current line:\n" .. d) or ""
    end)(),
  }, "\n")

  agent.ask(prompt, {
    uses_code = true,
    label = ("Hint %d of %d"):format(at.rung, #M.rungs),
    on_done = function(text)
      panel.show(("Hint %d of %d — %s"):format(at.rung, #M.rungs, rung.name), text, { footer = at.rung < #M.rungs and "press again for more" or "last rung" })
    end,
  })
end

--- Ask for the first rung again, having got somewhere.
function M.reset()
  at = { key = "", rung = 0 }
  vim.notify("Hint ladder back to the first rung.", vim.log.levels.INFO, { title = "Hint" })
end

--- Which rung this position is on, for the statusline or for curiosity.
---@return integer
function M.rung()
  return position() == at.key and at.rung or 0
end

return M
