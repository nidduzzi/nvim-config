return {
  {
    "snacks.nvim",
    opts = {
      terminal = {
        win = {
          position = "float",
          keys = {
            term_normal_after_both_escapes_arrive_together = {
              "<M-Esc>",
              function()
                vim.cmd.stopinsert()
              end,
              mode = "t",
              desc = "Double escape to normal mode",
            },
          },
        },
      },
    },
  },
}
