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

return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        javascript = { "biome", "prettierd", stop_after_first = true },
        javascriptreact = { "biome", "prettierd", stop_after_first = true },
        typescript = { "biome", "prettierd", stop_after_first = true },
        typescriptreact = { "biome", "prettierd", stop_after_first = true },
      },
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
