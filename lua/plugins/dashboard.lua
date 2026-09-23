-- The start screen, corrected on two counts.
--
-- LazyVim's dashboard runs `Snacks.dashboard.pick('live_grep')` for `g` and
-- `Snacks.dashboard.pick('files')` for `f`. Those are the stock pickers, and
-- this configuration's `<leader>sg` is not: it applies the documentation
-- filter, so the same-looking action returns a different set of results
-- depending on whether you started it from the dashboard or from a buffer.
-- Searching from the start screen found the openspec tree; searching a minute
-- later did not.
--
-- So the dashboard runs the same entry points, and says which key it is really
-- pressing. A start screen is the first thing anyone reads and the last place
-- to teach a key, so the keys are on it.
--
-- In the key column rather than beside the name. snacks renders `label` where
-- it would otherwise render `key`, so the column shows <leader>ff while `f`
-- stays bound — one key per row instead of two competing ones. Both work:
-- <leader>ff is a global mapping, so it is live on the start screen too, and
-- `f` remains the shortcut for anyone who already knows it.

local search = require("util.search")

return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          keys = {
            {
              icon = " ",
              key = "f",
              desc = "Find File",
              label = "<leader>ff",
              action = function()
                Snacks.picker.files()
              end,
            },
            {
              icon = " ",
              key = "n",
              desc = "New File",
              label = ":enew",
              action = ":ene | startinsert",
            },
            {
              icon = " ",
              key = "g",
              -- The whole reason this file exists.
              desc = "Find Text",
              label = "<leader>sg",
              action = function()
                Snacks.picker.grep(search.opts("code"))
              end,
            },
            {
              icon = " ",
              key = "r",
              desc = "Recent Files",
              label = "<leader>fr",
              action = function()
                Snacks.picker.recent()
              end,
            },
            {
              icon = " ",
              key = "c",
              desc = "Config",
              label = "<leader>fc",
              action = function()
                Snacks.picker.files({ cwd = vim.fn.stdpath("config") })
              end,
            },
            {
              icon = " ",
              key = "s",
              desc = "Restore Session",
              label = "<leader>qs",
              section = "session",
            },
            {
              icon = " ",
              key = "?",
              desc = "What can this editor do",
              label = "<leader>?",
              action = function()
                require("util.capabilities").open()
              end,
            },
            {
              icon = "󰒲 ",
              key = "l",
              desc = "Plugins",
              label = "<leader>l",
              action = ":Lazy",
            },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
      },
    },
  },
}
