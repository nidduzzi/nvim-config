-- yanky
-- https://github.com/gbprod/yanky.nvim

return {
  'gbprod/yanky.nvim',
  desc = 'Better Yank/Paste',
  dependencies = { 'kkharji/sqlite.lua', 'nvim-telescope/telescope.nvim' },
  opts = {
    ring = {
      history_length = 100,
      storage = 'sqlite',
    },
    system_clipboard = {
      sync_with_ring = not vim.env.SSH_CONNECTION,
    },
    highlight = { timer = 150 },
  },
  config = function(_, opts)
    -- Telescope extension
    require('yanky').setup(opts)
    require('telescope').load_extension 'yank_history'
  end,
  keys = {
    {
      '<leader>p',
      function()
        require('telescope').extensions.yank_history.yank_history {}
      end,
      mode = { 'n', 'x' },
      desc = 'Open Yank History',
    },
        -- stylua: ignore
    { "y", "<Plug>(YankyYank)", mode = { "n", "x" }, desc = "Yank Text" },
    { 'p', '<Plug>(YankyPutAfter)', mode = { 'n', 'x' }, desc = 'Put Text After Cursor' },
    { 'P', '<Plug>(YankyPutBefore)', mode = { 'n', 'x' }, desc = 'Put Text Before Cursor' },
    { 'gp', '<Plug>(YankyGPutAfter)', mode = { 'n', 'x' }, desc = 'Put Text After Selection' },
    { 'gP', '<Plug>(YankyGPutBefore)', mode = { 'n', 'x' }, desc = 'Put Text Before Selection' },
    { '[y', '<Plug>(YankyCycleForward)', desc = 'Cycle Forward Through Yank History' },
    { ']y', '<Plug>(YankyCycleBackward)', desc = 'Cycle Backward Through Yank History' },
    { ']p', '<Plug>(YankyPutIndentAfterLinewise)', desc = 'Put Indented After Cursor (Linewise)' },
    { '[p', '<Plug>(YankyPutIndentBeforeLinewise)', desc = 'Put Indented Before Cursor (Linewise)' },
    { ']P', '<Plug>(YankyPutIndentAfterLinewise)', desc = 'Put Indented After Cursor (Linewise)' },
    { '[P', '<Plug>(YankyPutIndentBeforeLinewise)', desc = 'Put Indented Before Cursor (Linewise)' },
    { '>p', '<Plug>(YankyPutIndentAfterShiftRight)', desc = 'Put and Indent Right' },
    { '<p', '<Plug>(YankyPutIndentAfterShiftLeft)', desc = 'Put and Indent Left' },
    { '>P', '<Plug>(YankyPutIndentBeforeShiftRight)', desc = 'Put Before and Indent Right' },
    { '<P', '<Plug>(YankyPutIndentBeforeShiftLeft)', desc = 'Put Before and Indent Left' },
    { '=p', '<Plug>(YankyPutAfterFilter)', desc = 'Put After Applying a Filter' },
    { '=P', '<Plug>(YankyPutBeforeFilter)', desc = 'Put Before Applying a Filter' },
  },
}
