-- persistence
-- https://github.com/folke/persistence.nvim

return {
  'folke/persistence.nvim',
  event = 'BufReadPre',
  opts = {},
  keys = {
    {
      '<leader>Ps',
      function()
        require('persistence').load()
      end,
      desc = 'Restore Session',
    },
    {
      '<leader>PS',
      function()
        require('persistence').select()
      end,
      desc = 'Select Session',
    },
    {
      '<leader>Pl',
      function()
        require('persistence').load { last = true }
      end,
      desc = 'Restore Last Session',
    },
    {
      '<leader>Pd',
      function()
        require('persistence').stop()
      end,
      desc = "Don't Save Current Session",
    },
  },
}
