-- Picker: snacks.picker, with search filters and a tree view for results.
--
-- Two things are added on top of the LazyVim default:
--
--   1. Filter presets, so documentation can be excluded, included or searched
--      on its own, switched while the picker is open. See lua/util/search.lua.
--   2. A visible hint line, because snacks does not advertise its toggles the
--      way fzf-lua does, and a toggle nobody can see is a toggle nobody uses.
--
-- Results can be viewed flat or as a tree. The picker list is the flat view.
-- `<c-t>` sends the same results to Trouble, which groups them by file, which
-- is the tree view.

local search = require("util.search")

return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        -- Flags shown in the picker title. `regex` and `docs` are the two
        -- worth seeing at a glance while searching.
        toggles = {
          follow = "f",
          hidden = "h",
          ignored = "i",
          modified = "m",
          regex = { icon = "R", value = false },
        },
        win = {
          input = {
            keys = {
              ["<a-d>"] = { "search_cycle_filter", mode = { "i", "n" }, desc = "Cycle search filter" },
              ["<a-p>"] = { "search_choose_filter", mode = { "i", "n" }, desc = "Choose search filter" },
              ["<a-e>"] = { "search_by_extension", mode = { "i", "n" }, desc = "Filter by extension" },
              ["<a-G>"] = { "search_by_glob", mode = { "i", "n" }, desc = "Filter by path glob" },
            },
          },
        },
        actions = {
          search_cycle_filter = function(picker)
            search.cycle(picker)
          end,
          search_choose_filter = function(picker)
            search.choose(picker)
          end,
          search_by_extension = function(picker)
            search.by_extension(picker)
          end,
          search_by_glob = function(picker)
            search.by_glob(picker)
          end,
        },
      },
    },
    keys = {
      {
        "<leader>/",
        function()
          Snacks.picker.grep(search.opts("code"))
        end,
        desc = "Grep (no docs)",
      },
      {
        "<leader>sg",
        function()
          Snacks.picker.grep(search.opts("code"))
        end,
        desc = "Grep (no docs)",
      },
      {
        "<leader>sG",
        function()
          Snacks.picker.grep(search.opts("all"))
        end,
        desc = "Grep (everything)",
      },
      {
        -- Not <leader>sD: that is LazyVim's workspace diagnostics, and taking
        -- it silently removed a feature that had nothing to do with grep.
        "<leader>sO",
        function()
          Snacks.picker.grep(search.opts("docs"))
        end,
        desc = "Grep (docs only)",
      },
      {
        -- Searching the editor itself, not the project. A feature used once a
        -- month is otherwise a feature you have to remember a key for.
        "<leader>sx",
        function()
          require("util.capabilities").open()
        end,
        desc = "Search what this editor can do",
      },
      {
        "<leader>sw",
        function()
          Snacks.picker.grep_word(search.opts("code"))
        end,
        mode = { "n", "x" },
        desc = "Grep word under cursor (no docs)",
      },
    },
  },

  -- Trouble is the tree view: it groups the picker's results by file, which a
  -- flat list cannot do. LazyVim already installs it, so this only adds the
  -- key that hands results over.
  {
    "folke/trouble.nvim",
    optional = true,
    specs = {
      {
        "folke/snacks.nvim",
        opts = {
          picker = {
            actions = {
              -- Resolved lazily inside the action, because requiring trouble
              -- while the picker spec is being built loads it at startup.
              trouble_open = function(...)
                return require("trouble.sources.snacks").actions.trouble_open.action(...)
              end,
            },
            win = {
              input = {
                keys = {
                  ["<c-t>"] = {
                    "trouble_open",
                    mode = { "n", "i" },
                    desc = "Send results to Trouble (grouped by file)",
                  },
                },
              },
            },
          },
        },
      },
    },
  },
}
