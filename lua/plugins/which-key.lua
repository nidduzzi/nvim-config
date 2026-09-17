-- which-key shows every mapping it can find, including the ones Vim and its
-- bundled plugins install without a description: matchit's [% and g%, the
-- window-command tag jumps, <SNR> internals. They render as a key with nothing
-- beside it, which makes the popup look broken and buries the keys that do say
-- what they do.
--
-- An entry that cannot describe itself is not a hint. This hides those, and
-- leaves everything that carries a description, ours and LazyVim's alike.

return {
  {
    "folke/which-key.nvim",
    opts = {
      filter = function(mapping)
        return mapping.desc ~= nil and mapping.desc ~= ""
      end,
    },
  },
}
