-- Options. LazyVim sets most of what the old config set by hand, so only the
-- differences are here. LazyVim loads this file before plugins start.

local opt = vim.opt

-- Mouse in normal and visual mode only: dragging in insert mode moved the
-- cursor mid-typing more often than it helped.
opt.mouse = "nv"

-- Ten lines of context rather than LazyVim's four, which is enough to read a
-- function signature while standing at its last line.
opt.scrolloff = 10

opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- Ask about unsaved changes instead of refusing to quit.
opt.confirm = true

-- Neovim picks 'shellcmdflag' from the shell it finds, and gets it right for
-- the shells it knows. The one it cannot know is a POSIX shell reached by an
-- absolute path, where the name it compares against is "/usr/bin/zsh" rather
-- than "zsh", so the flag stays at the default. Only that case is corrected,
-- and only on a system whose shells take -c at all: cmd.exe takes /c and
-- PowerShell takes -Command, and the old unconditional "-c" would have handed
-- either of them a flag it does not have.
if vim.fn.has("win32") == 0 then
  local shell = vim.fs.basename(vim.o.shell)
  if shell ~= "bash" and vim.tbl_contains({ "sh", "dash", "zsh", "ksh", "fish", "ash" }, shell) then
    opt.shellcmdflag = "-c"
  end
end

-- Copy through OSC 52, which reaches the clipboard of whatever terminal is
-- attached. This is what makes yanking work over SSH, where there is no local
-- display to talk to. Deferred because resolving the provider at startup costs
-- measurable time.
vim.schedule(function()
  local function paste()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end

  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
      ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end)

-- Per-project configuration.
--
-- With exrc on, Neovim reads a `.nvim.lua` from the directory it starts in,
-- after asking once whether that file is trusted and remembering the answer.
-- That is the hook for per-project settings: which globs count as
-- documentation, which formatter to use, which LSP settings apply.
--
-- Trust is per file content, so editing a `.nvim.lua` prompts again. Answer
-- `v` at the prompt to view the file before deciding.
opt.exrc = true

-- A modeline is configuration in a file you opened, applied by opening it.
-- Nothing here needs it, and a repository should not get to set options.
opt.modeline = false

-- A project file can set these. Defaults live next to the code that reads
-- them, so a project only has to state what differs:
--
--   vim.g.search_filters = { docs = { "adr/**", "*.rst" } }
