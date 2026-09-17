-- Harpoon: a short list of files you return to, pinned by hand.
--
-- A picker answers "where is that file"; harpoon answers "the four files I am
-- working in right now", which is a different question and a much shorter
-- list. The files are reachable by position, so the fourth file is always
-- <leader>4, whatever it is called.
--
-- Harpoon keys its lists by directory, which means each git worktree gets its
-- own list: the same repository, checked out twice for two pieces of work,
-- remembers a different four files in each. That is the pairing that makes
-- worktrees comfortable rather than merely possible.
--
-- Harpoon ships a telescope extension. This config has no telescope, so the
-- list is browsed through a snacks picker instead, written below.

return {
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
      settings = {
        save_on_toggle = true,
        -- Jumping to a pinned file should not also move you inside it.
        sync_on_ui_close = true,
      },
    },
    keys = function()
      local keys = {
        {
          "<leader>ha",
          function()
            require("harpoon"):list():add()
            local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
            vim.notify(
              ("%s\npinned at %d"):format(name, #require("harpoon"):list().items),
              vim.log.levels.INFO,
              { title = "Harpoon" }
            )
          end,
          desc = "Pin this file",
        },
        {
          -- Not <leader>h on its own: that is the prefix these keys live
          -- under, so which-key waits there for the next key rather than
          -- running anything.
          "<leader>hh",
          function()
            require("util.harpoon").pick()
          end,
          desc = "Pinned files",
        },
        {
          "<leader>hd",
          function()
            require("harpoon"):list():remove()
            vim.notify("Unpinned this file", vim.log.levels.INFO, { title = "Harpoon" })
          end,
          desc = "Unpin this file",
        },
        {
          "<leader>hn",
          function()
            require("harpoon"):list():next({ ui_nav_wrap = true })
          end,
          desc = "Next pinned file",
        },
        {
          "<leader>hp",
          function()
            require("harpoon"):list():prev({ ui_nav_wrap = true })
          end,
          desc = "Previous pinned file",
        },
      }

      -- Position, not name: the third file stays <leader>3 when you rename it.
      for slot = 1, 5 do
        table.insert(keys, {
          "<leader>" .. slot,
          function()
            require("harpoon"):list():select(slot)
          end,
          desc = "Pinned file " .. slot,
        })
      end

      return keys
    end,
  },
}
