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
              desc = "Find File            <leader>ff",
              action = function()
                Snacks.picker.files()
              end,
            },
            {
              icon = " ",
              key = "n",
              desc = "New File             :enew",
              action = ":ene | startinsert",
            },
            {
              icon = " ",
              key = "g",
              -- The whole reason this file exists.
              desc = "Find Text            <leader>sg",
              action = function()
                Snacks.picker.grep(search.opts("code"))
              end,
            },
            {
              icon = " ",
              key = "r",
              desc = "Recent Files         <leader>fr",
              action = function()
                Snacks.picker.recent()
              end,
            },
            {
              icon = " ",
              key = "c",
              desc = "Config               <leader>fc",
              action = function()
                Snacks.picker.files({ cwd = vim.fn.stdpath("config") })
              end,
            },
            {
              icon = " ",
              key = "s",
              desc = "Restore Session      <leader>qs",
              section = "session",
            },
            {
              icon = " ",
              key = "?",
              desc = "What can this editor do",
              action = function()
                require("util.capabilities").open()
              end,
            },
            {
              icon = "󰒲 ",
              key = "l",
              desc = "Plugins              <leader>l",
              action = ":Lazy",
            },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
      },
    },
  },
}
