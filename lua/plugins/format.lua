-- Formatting. LazyVim already wires conform.nvim to format on save and to
-- <leader>cf, so only the formatter choices are here.
--
-- Setting format_on_save here is what the old config did, and conform now
-- refuses it: LazyVim owns that key so it can offer <leader>uf to toggle
-- autoformatting, and setting it directly produces
--
--   Don't set `opts.format_on_save` for `conform.nvim`
--
-- on every buffer. Per-filetype exceptions go through vim.b.autoformat instead,
-- which is the switch LazyVim's own toggle uses.
--
-- biome first, prettierd second: conform runs the first formatter it finds, so
-- a project with a biome config gets biome and everything else falls back to
-- prettierd. A project can override this in its own `.nvim.lua`.

local formatters_by_ft = {
  lua = { "stylua" },
  javascript = { "biome", "prettierd", stop_after_first = true },
  javascriptreact = { "biome", "prettierd", stop_after_first = true },
  typescript = { "biome", "prettierd", stop_after_first = true },
  typescriptreact = { "biome", "prettierd", stop_after_first = true },
}

--- Where a formatter comes from, asked the same way a language server is.
---
--- conform looks in node_modules/.bin before it looks at PATH, which is the
--- right default for a project you wrote and an execution path for one you
--- cloned: opening a JavaScript file in an untrusted repository and saving it
--- ran that repository's prettierd. The formatter is a program in the project,
--- exactly like a language server, and the answer is the same one --- it runs
--- when the project is trusted, and PATH is used when it is not.
---@param name string
---@return fun(self: table, ctx: table): string
local function guarded(name)
  return function(_, ctx)
    local lsp = require("util.lsp")
    local from_project = lsp.project_bin(name, ctx and ctx.dirname or nil)
    if from_project then
      return from_project
    end
    -- exepath is empty when nothing on PATH answers, and conform reports the
    -- formatter as unavailable rather than running something unintended.
    return vim.fn.exepath(name)
  end
end

--- Every formatter named above, each resolved through the trust gate.
---@return table<string, table>
local function guarded_formatters()
  local guards = {}
  for _, names in pairs(formatters_by_ft) do
    for key, name in pairs(names) do
      if type(key) == "number" then
        guards[name] = { command = guarded(name) }
      end
    end
  end
  return guards
end

return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = formatters_by_ft,
      formatters = guarded_formatters(),
    },
  },

  -- C and C++ formatting is left to the language server, because the project
  -- style there is rarely what a standalone formatter would produce.
  {
    "LazyVim/LazyVim",
    opts = function()
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("autoformat-exceptions", { clear = true }),
        pattern = { "c", "cpp" },
        callback = function()
          vim.b.autoformat = false
        end,
      })
    end,
  },
}
