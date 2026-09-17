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

  -- Side-by-side diffs, file history, and the three-way view used to resolve
  -- merge conflicts.
  --
  -- Each key toggles: press it to open the view, press the same key again to
  -- close it. Diffview opens in a tab of its own, so without that you end up
  -- hunting for :DiffviewClose or leaving stray tabs behind.
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
    keys = {
      {
        "<leader>gd",
        function()
          require("util.diff").toggle("DiffviewOpen")
        end,
        desc = "Diff: working tree (toggle)",
      },
      {
        "<leader>gf",
        function()
          require("util.diff").toggle("DiffviewFileHistory %")
        end,
        desc = "Diff: history of this file (toggle)",
      },
      {
        "<leader>gm",
        function()
          require("util.diff").toggle_merge()
        end,
        desc = "Diff: merge conflicts (toggle)",
      },
      {
        "<leader>gw",
        function()
          require("util.worktree").pick()
        end,
        desc = "Worktrees: switch",
      },
      {
        "<leader>gW",
        function()
          require("util.worktree").pick_branch()
        end,
        desc = "Worktrees: check out a branch beside this one",
      },
    },
    opts = {
      enhanced_diff_hl = true,
      view = {
        -- The three-way layout is what makes a conflict readable: your side,
        -- the base it diverged from, and theirs, with the working copy below.
        merge_tool = {
          layout = "diff3_mixed",
          disable_diagnostics = true,
          winbar_info = true,
        },
      },
      keymaps = {
        view = {
          { "n", "<leader>gd", "<cmd>DiffviewClose<cr>", { desc = "Close the diff" } },
          { "n", "<leader>gm", "<cmd>DiffviewClose<cr>", { desc = "Close the diff" } },
          { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close the diff" } },
        },
        file_panel = {
          { "n", "<leader>gd", "<cmd>DiffviewClose<cr>", { desc = "Close the diff" } },
          { "n", "<leader>gm", "<cmd>DiffviewClose<cr>", { desc = "Close the diff" } },
          { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close the diff" } },
        },
        file_history_panel = {
          { "n", "<leader>gf", "<cmd>DiffviewClose<cr>", { desc = "Close the diff" } },
          { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close the diff" } },
        },
      },
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
