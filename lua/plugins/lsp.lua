-- LSP servers. Only the settings that differ from what the LazyVim language
-- extras already configure.
--
-- Servers are configured here rather than installed automatically, which is
-- deliberate: the old config moved away from Mason auto-install so that
-- opening a file never triggers a download.

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- pylsp runs ruff for diagnostics and formatting. Its jedi plugins are
        -- all off because completion comes from elsewhere, and leaving them on
        -- makes pylsp slow enough to notice on a large file.
        pylsp = {
          capabilities = {
            textDocument = {
              completion = false,
            },
          },
          settings = {
            plugins = {
              ruff = {
                enabled = true,
                formatEnabled = true,
              },
              jedi_completion = { enabled = false },
              jedi_definition = { enabled = false },
              jedi_references = { enabled = false },
              jedi_hover = { enabled = false },
              jedi_signature_help = { enabled = false },
              jedi_symbols = { enabled = false },
              jedi_type_definition = { enabled = false },
              rope_completion = { enabled = false },
            },
          },
        },

        -- Pyrefly exits quietly when it fails, so say so rather than leaving
        -- the buffer with no type information and no explanation.
        pyrefly = {
          on_exit = function(code, _, _)
            vim.schedule(function()
              vim.notify("Pyrefly LSP exited with code: " .. code, vim.log.levels.INFO)
            end)
          end,
        },

        lua_ls = {
          settings = {
            Lua = {
              workspace = {
                library = { vim.env.VIMRUNTIME },
              },
              completion = {
                callSnippet = "Replace",
              },
            },
          },
        },
      },
    },
  },

  -- Install only what is wanted, when it is wanted. `:Mason` does the rest by
  -- hand.
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = { "stylua" },
    },
  },

  -- The LazyVim language extras turn on automatic server installation, which
  -- then tries to fetch servers Mason has no recipe for. pylsp and pyrefly are
  -- installed system-wide here, so opening a Python file announced two install
  -- failures and installed nothing. Servers are configured above and enabled
  -- from whatever is already on PATH.
  {
    "mason-org/mason-lspconfig.nvim",
    opts = {
      ensure_installed = {},
      automatic_enable = false,
    },
  },
}
