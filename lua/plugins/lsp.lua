-- LSP servers. Only the settings that differ from what the LazyVim language
-- extras already configure.
--
Both pyrefly and python-lsp-server are in Mason's registry, but they are pip
-- packages, so Mason builds a virtual environment for them and that needs the
-- venv module:
--
--   The virtual environment was not created successfully because ensurepip is
--   not available. … apt install python3.12-venv
--
-- That cannot be fixed from inside the editor, and retrying it announces a
-- failure on every Python file. Python tools are installed with uv here, so
-- these servers are marked `mason = false` and the editor only reports what is
-- missing. See lua/util/tools.lua and :checkhealth dotfiles.

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- pylsp runs ruff for diagnostics and formatting. Its jedi plugins are
        -- all off because completion comes from elsewhere, and leaving them on
        -- makes pylsp slow enough to notice on a large file.
        pylsp = {
          -- Provided by uv, not Mason:
          --   uv tool install python-lsp-server --with python-lsp-ruff
          mason = false,
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
          -- Provided by uv, not Mason: uv tool install pyrefly
          mason = false,
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
