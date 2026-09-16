-- Editing plugins carried over from the kickstart config, minus everything
-- LazyVim already ships (gitsigns, which-key, todo-comments, mini.surround,
-- treesitter, autopairs, indent guides, neo-tree).

return {
  -- Yank history, so a yank three yanks ago is still reachable.
  {
    "gbprod/yanky.nvim",
    dependencies = { "kkharji/sqlite.lua" },
    opts = {
      ring = {
        history_length = 100,
        storage = "sqlite",
        sync_with_numbered_registers = true,
        cancel_event = "update",
      },
      highlight = { on_put = true, on_yank = true, timer = 300 },
    },
    keys = {
      { "y", "<Plug>(YankyYank)", mode = { "n", "x" }, desc = "Yank" },
      { "p", "<Plug>(YankyPutAfter)", mode = { "n", "x" }, desc = "Put after" },
      { "P", "<Plug>(YankyPutBefore)", mode = { "n", "x" }, desc = "Put before" },
      { "<c-n>", "<Plug>(YankyNextEntry)", desc = "Next yank entry" },
      { "<c-p>", "<Plug>(YankyPreviousEntry)", desc = "Previous yank entry" },
      {
        "<leader>sy",
        function()
          Snacks.picker.yanky()
        end,
        desc = "Yank history",
      },
    },
  },

  -- Restore the session for the directory Neovim was opened in.
  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {},
    keys = {
      {
        "<leader>P",
        function()
          require("persistence").load()
        end,
        desc = "Restore session for this directory",
      },
      {
        "<leader>qS",
        function()
          require("persistence").select()
        end,
        desc = "Select a session to restore",
      },
      {
        "<leader>ql",
        function()
          require("persistence").load({ last = true })
        end,
        desc = "Restore the last session",
      },
    },
  },

  -- Folds that open on the keys you already press, instead of needing zo/zc.
  {
    "chrisgrieser/nvim-origami",
    event = "VeryLazy",
    opts = {},
  },

  -- Side-by-side diffs and a readable file history.
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview: open" },
      { "<leader>gf", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history" },
    },
  },

  -- Match the indentation a file already uses rather than imposing ours.
  {
    "NMAC427/guess-indent.nvim",
    event = "BufReadPre",
    opts = {
      filetype_exclude = { "netrw", "tutor" },
    },
  },
}
