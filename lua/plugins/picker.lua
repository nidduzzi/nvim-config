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

-- One definition per toggle, in lua/util/search.lua: the key, the action and
-- the ripgrep flag it adds. Written out here three times, they drifted — the
-- tour drove <a-r> for a year against a key that was never bound.
local toggle_keys = {}
local toggle_actions = {}
for _, toggle in ipairs(search.toggles) do
  local action = "search_toggle_" .. toggle.name
  toggle_keys[toggle.key] = { action, mode = { "i", "n" }, desc = toggle.desc }
  toggle_actions[action] = function(picker)
    search.toggle(picker, toggle.name)
  end
end

return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        -- Per source, because the explorer sets its own list keys and they win
        -- over the shared ones. It binds <c-c> to tcd, which changes the tab's
        -- working directory: pressing it to leave the explorer moved the whole
        -- tab somewhere else and left the explorer open, and the only sign was
        -- the item count dropping from 21 to 12.
        --
        -- tcd is still reachable on <c-w>, which the explorer already binds to
        -- it, so nothing is lost.
        sources = {
          explorer = {
            win = {
              list = {
                keys = {
                  ["<c-c>"] = { "close", mode = { "n", "x" }, desc = "Close whatever is open" },
                },
              },
            },
          },
        },

        -- How results are ranked.
        --
        -- frecency and the cwd bonus are both off by default, so a file you
        -- open twenty times a day ranks exactly like one you have never
        -- opened. Turning them on makes the ordering depend on your history,
        -- which is the point: the thing you want is usually the thing you
        -- wanted before.
        matcher = {
          frecency = true,
          cwd_bonus = true,
        },

        -- The keys that exist only inside a picker. which-key cannot show
        -- them — it needs a prefix to wait on, and these have none — and the
        -- capability list reads global and buffer mappings, not picker ones.
        -- So the picker says them itself, in its own footer.
        formatters = {
          file = { filename_first = false },
        },

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
          list = {
            keys = {
              ["<c-c>"] = { "close", mode = { "n", "x" }, desc = "Close whatever is open" },
            },
          },
          input = {
            keys = vim.tbl_extend("error", {
              -- Not <a-d> or <a-p>: those are snacks' own inspect and
              -- toggle-preview, and taking them removed working features.
              ["<a-s>"] = { "search_cycle_filter", mode = { "i", "n" }, desc = "Cycle search scope" },
              ["<a-S>"] = { "search_choose_filter", mode = { "i", "n" }, desc = "Choose search scope" },
              ["<a-e>"] = { "search_by_extension", mode = { "i", "n" }, desc = "Filter by extension" },
              ["<a-G>"] = { "search_by_glob", mode = { "i", "n" }, desc = "Filter by path glob" },
              -- snacks already builds this list from the live keymap table.
              -- A hand-written one was the third time in this work that
              -- writing down what could be derived went stale on contact.
              -- It is bound here only because the built-in `?` is normal-mode
              -- and the picker opens in insert, so nobody ever reaches it.
              ["<a-/>"] = { "toggle_help_input", mode = { "i", "n" }, desc = "What can I press in here" },
              ["<a-q>"] = { "close", mode = { "i", "n" }, desc = "Close whatever is open" },
              -- snacks binds <c-c> in the list to tcd, which changes the tab's
              -- directory. Pressing it to leave the explorer silently moved
              -- the whole tab somewhere else and left the explorer open — the
              -- item count changing from 21 to 12 was the only sign.
              ["<c-c>"] = { "close", mode = { "i", "n" }, desc = "Close whatever is open" },
            }, toggle_keys),
          },
        },
        actions = vim.tbl_extend("error", toggle_actions, {
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
        }),
      },
    },
    keys = {
      {
        -- Buffers, where the old configuration had them. LazyVim puts Find
        -- Files here, but files already answer to <leader>ff and <leader>fF
        -- while buffers had only <leader>, and the crowded <leader>f group.
        "<leader><leader>",
        function()
          Snacks.picker.buffers()
        end,
        desc = "Buffers",
      },
      {
        "<leader>/",
        function()
          Snacks.picker.grep(search.opts("code"))
        end,
        desc = "Grep (no docs)",
      },
      {
        -- One grep, not three. Which files it searches is a decision made
        -- while reading the results, not before opening the picker, so the
        -- filter is a key inside it: <a-s> cycles code, everything and
        -- documentation, <a-S> picks from the list. Three keys on a prefix
        -- that already holds thirty-five bought nothing that <a-s> did not.
        "<leader>sg",
        function()
          Snacks.picker.grep(search.opts("code"))
        end,
        desc = "Grep (a-s cycles the scope)",
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
