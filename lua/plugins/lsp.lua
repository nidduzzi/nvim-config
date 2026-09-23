-- Language servers.
--
-- Nothing here is installed automatically. A server attaches when the project
-- provides it, from its own environment or from PATH, and is disabled quietly
-- when nothing does. See lua/util/lsp.lua for how that is decided, and
-- :checkhealth dotfiles for what it decided.
--
-- The settings below therefore describe how a server should behave *if* it is
-- present. Declaring one costs nothing on a machine that does not have it.

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}

      opts.servers = vim.tbl_deep_extend("force", opts.servers, {
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

        -- Pyrefly exits quietly when it fails. Every server here now says so
        -- --- see report_exit in util/lsp.lua --- so this needs nothing of
        -- its own.
        pyrefly = {},

        -- ty: Astral's Python type checker. Like the others, it starts only
        -- where the project provides it.
        ty = {},

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
      })

      -- Last, so that it sees every server the config and the extras asked for.
      require("util.lsp").keep_available(opts.servers)

      return opts
    end,
  },

  -- Mason installs the editor's own toolchain and nothing else. This config is
  -- written in Lua, so editing it has to work in any checkout, including ones
  -- with nothing to do with Lua. Everything beyond this list is the project's
  -- business: a server that appears without being asked for is a server that
  -- starts disagreeing with another one in some project months later.
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      -- Mason installs a Python package by making a virtualenv with the
      -- python3 it finds on PATH. A distribution python3 often cannot make
      -- one --- ensurepip is a separate package on Debian and its
      -- descendants --- and :MasonInstall debugpy fails with "spawn: python3
      -- failed with exit code 1", which says nothing about what is missing.
      -- If this machine has an interpreter that can, it goes first.
      require("util.python").prefer_usable()

      opts.ensure_installed = { "lua-language-server", "stylua" }
      return opts
    end,
  },
  {
    "mason-org/mason-lspconfig.nvim",
    opts = function(_, opts)
      opts.ensure_installed = {}
      opts.automatic_enable = false
      return opts
    end,
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = {}
      opts.auto_update = false
      opts.run_on_start = false
      return opts
    end,
  },
}
