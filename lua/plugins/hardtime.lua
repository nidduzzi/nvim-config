-- Hints toward the motion that does in one key what you just did in four:
-- jjjj, then "use 4j" or a jump. Hint mode only; nothing is ever blocked.
--
-- hardtime works by remapping keys with its own expression handlers, then
-- replaying whatever mapping it found there when it started. That replay only
-- knows normal-mode maps, and a remap replaces the key outright, so the keys
-- other plugins here own are left alone:
--   - y, p, P, gp, gP belong to yanky; a replayed <Plug> map with noremap does
--     not reach yanky at all.
--   - <, >, = would turn yanky's >p, <p, =p into a wait on timeoutlen.
--   - <C-N>/<C-P> cycle the yank ring.
-- Everything is restricted in normal mode only, for the same reason: LazyVim's
-- visual-mode j/k (gj/gk on wrapped lines) would be replaced by a bare j/k.
--
-- Terminals (lazygit, the agent CLIs) are skipped by hardtime itself. The
-- agent panel is a markdown scratch buffer and gets hints like any other.
--
-- The hint log is local: stdpath("log")/hardtime.nvim.log. Nothing else is
-- recorded, and nothing leaves the machine.
local n = { "n" }

return {
  {
    "m4xshen/hardtime.nvim",
    event = "VeryLazy",
    dependencies = { "MunifTanjim/nui.nvim" },
    opts = {
      restriction_mode = "hint",
      disable_mouse = false,
      disabled_keys = {
        ["<Up>"] = false,
        ["<Down>"] = false,
        ["<Left>"] = false,
        ["<Right>"] = false,
      },
      restricted_keys = {
        ["h"] = n,
        ["j"] = n,
        ["k"] = n,
        ["l"] = n,
        ["+"] = n,
        ["gj"] = n,
        ["gk"] = n,
        ["<C-M>"] = n,
        ["<C-N>"] = false,
        ["<C-P>"] = false,
      },
      resetting_keys = {
        ["y"] = false,
        ["Y"] = false,
        ["p"] = false,
        ["P"] = false,
        ["gp"] = false,
        ["gP"] = false,
        ["<"] = false,
        [">"] = false,
        ["="] = false,
      },
      disabled_filetypes = {
        ["snacks_picker.*"] = true,
        ["snacks_input"] = true,
        ["snacks_terminal"] = true,
        ["snacks_layout_box"] = true,
        ["snacks_notif"] = true,
        ["harpoon"] = true,
        ["grug%-far.*"] = true,
        ["DiffviewFiles"] = true,
        ["gitcommit"] = true,
      },
    },
    config = function(_, opts)
      -- After LazyVim's own VeryLazy keymaps, so the snapshot hardtime takes
      -- of the existing normal-mode maps includes them (j/k's gj/gk).
      vim.schedule(function()
        require("hardtime").setup(opts)
      end)
    end,
  },
}
