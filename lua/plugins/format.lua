-- Formatting. LazyVim already wires conform.nvim to format on save and to
-- <leader>cf, so only the formatter choices are here.
--
-- biome first, prettierd second: conform runs the first formatter it finds,
-- so a project with a biome config gets biome and everything else falls back
-- to prettierd. A project can override this in its own `.nvim.lua`.

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
      -- C and C++ formatting is left to the LSP, because the project style
      -- there is rarely what a standalone formatter would produce.
      format_on_save = function(bufnr)
        local skip = { c = true, cpp = true }
        if skip[vim.bo[bufnr].filetype] then
          return nil
        end
        return { timeout_ms = 500, lsp_format = "fallback" }
      end,
    },
  },
}
