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
