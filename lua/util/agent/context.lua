--- What the agent is allowed to see.
---
--- It has no tools, so it cannot go and read anything: whatever is sent here is
--- the whole of its knowledge for that question. That is a feature rather than
--- a limitation. Deciding what to show is the part where you think about the
--- problem, and a model that has read your entire repository is the one that
--- writes your code for you.
---
--- Everything is sent with line numbers, so a finding can name a real line in
--- your buffer and land there as a diagnostic.

local M = {}

--- Ask before sending a buffer that looks like it holds a credential.
---
--- Everything the agent is shown comes through this file, so one check here
--- covers the question, the review, and anything added later. The answer is
--- not remembered: the next question about the same file asks again, because
--- the cost of a wrong yes is a key in somebody else's logs.
---@param bufnr integer
---@return boolean
local function may_send(bufnr)
  local recognised = require("util.agent.secrets").found(bufnr)
  if not recognised then
    return true
  end

  local answer = vim.fn.confirm(
    ("This looks like %s.\n\nSending it puts its contents in the prompt."):format(recognised),
    "&Do not send\n&Send it anyway",
    1,
    "Warning"
  )
  return answer == 2
end

---@class agent.Context
---@field text string the numbered source
---@field first integer buffer line the snippet starts on, 1-based
---@field name string what to call it in the prompt
---@field bufnr integer

--- Number lines the way `cat -n` does, starting at the buffer line they came
--- from, so the agent's line numbers are the buffer's line numbers and no
--- arithmetic is needed to place a finding.
---@param lines string[]
---@param first integer
---@return string
local function numbered(lines, first)
  local out = {}
  for i, line in ipairs(lines) do
    out[i] = ("%6d\t%s"):format(first + i - 1, line)
  end
  return table.concat(out, "\n")
end

--- The whole buffer.
---@param bufnr? integer
---@return agent.Context|nil
function M.buffer(bufnr)
  bufnr = bufnr or 0
  if not may_send(bufnr) then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return {
    text = numbered(lines, 1),
    first = 1,
    name = vim.fn.expand("%:."),
    bufnr = bufnr,
  }
end

--- The last visual selection.
---@return agent.Context|nil
function M.selection()
  local from = vim.fn.getpos("'<")
  local to = vim.fn.getpos("'>")
  if from[2] == 0 or to[2] == 0 then
    return nil
  end

  if not may_send(0) then
    return nil
  end

  local first, last = math.min(from[2], to[2]), math.max(from[2], to[2])
  local lines = vim.api.nvim_buf_get_lines(0, first - 1, last, false)
  if #lines == 0 then
    return nil
  end

  return {
    text = numbered(lines, first),
    first = first,
    name = ("%s lines %d-%d"):format(vim.fn.expand("%:."), first, last),
    bufnr = 0,
  }
end

--- The function or block the cursor is in, found with treesitter, falling back
--- to a window of lines when there is no parser for the language.
---@return agent.Context|nil
function M.around_cursor()
  local bufnr = 0
  if not may_send(bufnr) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]

  local ok, node = pcall(vim.treesitter.get_node)
  if ok and node then
    -- Climb to something that is a unit of meaning rather than a token.
    local wanted = {
      function_definition = true,
      function_declaration = true,
      function_item = true,
      method_definition = true,
      method_declaration = true,
      class_definition = true,
      class_declaration = true,
      local_function = true,
      func_literal = true,
    }
    local at = node
    while at do
      if wanted[at:type()] then
        local from, _, to = at:range()
        local lines = vim.api.nvim_buf_get_lines(bufnr, from, to + 1, false)
        return {
          text = numbered(lines, from + 1),
          first = from + 1,
          name = ("%s lines %d-%d"):format(vim.fn.expand("%:."), from + 1, to + 1),
          bufnr = bufnr,
        }
      end
      at = at:parent()
    end
  end

  local first = math.max(1, row - 20)
  local last = math.min(vim.api.nvim_buf_line_count(bufnr), row + 20)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
  return {
    text = numbered(lines, first),
    first = first,
    name = ("%s lines %d-%d"):format(vim.fn.expand("%:."), first, last),
    bufnr = bufnr,
  }
end

--- Selection if there is one, otherwise the enclosing function.
---@return agent.Context
function M.here()
  return M.selection() or M.around_cursor()
end

--- Diagnostics on the current line, in plain text, so a question about an error
--- carries the error rather than a description of it.
---@return string
function M.diagnostics_here()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local found = vim.diagnostic.get(0, { lnum = row })
  if #found == 0 then
    return ""
  end

  local out = {}
  for _, d in ipairs(found) do
    table.insert(out, ("%s: %s"):format(d.source or "diagnostic", d.message))
  end
  return table.concat(out, "\n")
end

--- A short description of the language and file, so answers use the right
--- idiom without being told.
---@return string
function M.preamble()
  return ("File: %s\nLanguage: %s\n"):format(
    vim.fn.expand("%:.") ~= "" and vim.fn.expand("%:.") or "[no name]",
    vim.bo.filetype ~= "" and vim.bo.filetype or "unknown"
  )
end

return M
