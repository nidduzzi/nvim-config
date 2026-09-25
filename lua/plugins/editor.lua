-- Editing plugins carried over from the kickstart config, minus everything
-- LazyVim already ships (gitsigns, which-key, todo-comments, mini.surround,
-- treesitter, autopairs, indent guides, neo-tree).

return {
  -- Yank history, so a yank three yanks ago is still reachable.
  --
  -- The picker is yanky's own. It registers itself as a snacks source when it
  -- loads after snacks, which this configuration spent 91 lines reimplementing
  -- on the belief that `Snacks.picker.yanky()` did not exist. It does not exist
  -- in snacks — snacks has no yank-ring source — but yanky adds it, and the
  -- pinned version shipped it the whole time.
  --
  -- One deliberate difference is kept: choosing an entry loads the register and
  -- stops there. yanky's own confirm pastes, and a picker that edits the buffer
  -- the moment you press enter is the thing that fails on an unwritable one.
  -- Loading the register leaves the paste in your hands, with p or P, at the
  -- position you meant. That is a two-line override of one action rather than a
  -- picker of our own.
  {
    "gbprod/yanky.nvim",
    dependencies = { "kkharji/sqlite.lua", "folke/snacks.nvim" },
    config = function(_, opts)
      require("yanky").setup(opts)

      local source = Snacks and Snacks.picker and Snacks.picker.sources and Snacks.picker.sources.yanky
      if source then
        source.actions = source.actions or {}
        source.actions.confirm = source.actions.set_default_register
      end
    end,
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
  --
  -- The fork rather than sindrets/diffview.nvim, for two reasons that are the
  -- same reason. Upstream has not been pushed since 2024-08 and its "is this
  -- repo active?" issue is unanswered; and the fork ships `:DiffviewToggle`,
  -- which is exactly the open-outside-close-inside behaviour this configuration
  -- git runs programs a repository names in its own .git/config, so gitsigns
  -- does not attach to a project that has not been trusted: no signs, no hunk
  -- preview, no blame, and one message saying why. See util/git.lua and
  -- DECISIONS 44.
  {
    "lewis6991/gitsigns.nvim",
    optional = true,
    opts = function(_, opts)
      local theirs = opts.on_attach

      opts.on_attach = function(bufnr)
        local git = require("util.git")
        local name = vim.api.nvim_buf_get_name(bufnr)
        local root = name ~= "" and vim.fs.dirname(name) or nil

        if not git.allowed(root) then
          git.say_refused(root)
          return false
        end

        if theirs then
          return theirs(bufnr)
        end
      end

      return opts
    end,
  },

  -- had written by hand. The module path is unchanged, so `require("diffview")`
  -- and every action name still resolve.
  {
    "dlyongemallo/diffview-plus.nvim",
    cmd = { "DiffviewOpen", "DiffviewToggle", "DiffviewFileHistory", "DiffviewClose" },
    keys = {
      {
        "<leader>gd",
        function()
          require("util.git").guard(function()
            vim.cmd("DiffviewToggle")
          end)
        end,
        desc = "Diff: working tree (toggle)",
      },
      {
        "<leader>gf",
        function()
          -- Not DiffviewToggle: that one is an alias for DiffviewOpen and
          -- takes its arguments, and there is no file-history toggle. The
          -- documented command list has DiffviewFileHistory and no toggling
          -- form of it.
          require("util.git").guard(function()
            require("util.diff").toggle("DiffviewFileHistory %")
          end)
        end,
        desc = "Diff: history of this file (toggle)",
      },
      {
        "<leader>gm",
        function()
          require("util.git").guard(function()
            require("util.diff").toggle_merge()
          end)
        end,
        desc = "Diff: merge conflicts (toggle)",
      },
      {
        "<leader>gw",
        function()
          local worktree = require("util.worktree")
          local root = worktree.root()
          require("util.git").guard(function()
            worktree.pick(root)
          end, root)
        end,
        desc = "Worktrees: switch, add, remove",
      },
      {
        "<leader>gW",
        function()
          local worktree = require("util.worktree")
          local root = worktree.root()
          require("util.git").guard(function()
            worktree.pick_branch(nil, root)
          end, root)
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
