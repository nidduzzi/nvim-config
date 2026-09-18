-- Keymaps. LazyVim already provides window navigation with <C-h/j/k/l>,
-- buffer and search keys, so only what it does not cover is here.
--
-- LazyVim applies this file after the plugins have set their own keys, which
-- is what makes it the right place for a mapping that has to win an argument
-- with one of them.

local map = vim.keymap.set

-- One key that closes whatever is open, because the set of close keys is not
-- learnable: q in Trouble and Lazy, <Esc> in a picker's list but not its
-- input, the opening key in some places, :q in others. See util/dismiss.lua.
require("util.dismiss").setup()

-- Clear the search highlight without typing a command.
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Diagnostics for this buffer, in a plain location list, which is what the
-- old configuration had on <leader>q. Not <leader>xq: that is LazyVim's
-- Quickfix List, and taking it was an accident, found by the collision
-- check rather than by noticing the feature had gone.
map("n", "<leader>xD", vim.diagnostic.setloclist, { desc = "Diagnostics to location list" })

-- Watch the keys this config depends on. Something taking one of these means a
-- feature quietly stopped existing, which is worth hearing about when it
-- happens rather than when it is next needed.
local keyguard = require("config.keyguard")
for _, lhs in ipairs({
  "<leader><leader>",
  "<leader>/",
  "<leader>?",
  "<leader>sg",
  "<leader>sw",
  "<leader>e",
  "<leader>gd",
  "<leader>gm",
  "<leader>gw",
  "<leader>hh",
}) do
  keyguard.watch("n", lhs)
end

-- Neovim's own LSP keys describe themselves with the function they call, and
-- fire in buffers with no language server. See lua/config/lsp-keys.lua.
require("config.lsp-keys").setup()

-- The parts of a language server that nothing binds a key to: the commands it
-- advertises, and code actions of a particular kind. See lua/util/lsp_commands.lua.
map("n", "<leader>cx", function()
  require("util.lsp_commands").pick()
end, { desc = "Run a server command" })

map("n", "<leader>cX", function()
  require("util.lsp_commands").report()
end, { desc = "What the servers here offer" })

map("n", "<leader>cI", function()
  require("util.lsp_commands").apply_kind("source.organizeImports", "Organize imports")
end, { desc = "Organize imports" })

-- Not <leader>cA: LazyVim binds that, buffer-locally, to its Source Action
-- menu, which already offers every source.* action a server has. A global
-- mapping there loses the argument silently and takes a working feature with
-- it, which is the same mistake as taking which-key's key.
map("n", "<leader>cq", function()
  require("util.lsp_commands").apply_kind("source.fixAll", "Fix everything fixable")
end, { desc = "Fix everything fixable" })

-- Refactors, on their own rather than mixed into the code action menu. Which
-- servers answer these varies: ruff and pyright offer source actions, while
-- pyrefly advertises refactor.extract and friends and currently returns none,
-- so this says who was asked and what came back.
map({ "n", "x" }, "<leader>cw", function()
  require("util.lsp_commands").refactor()
end, { desc = "Refactor here" })

-- Call and type hierarchy: answered by pyrefly, rust-analyzer, clangd and
-- others, with no default key in Neovim.
map("n", "<leader>ci", vim.lsp.buf.incoming_calls, { desc = "Incoming calls" })
map("n", "<leader>co", vim.lsp.buf.outgoing_calls, { desc = "Outgoing calls" })

-- Search the editor itself: "what can I do here". Every capability this config
-- adds, with the key that runs it, matched on name, description and key alike,
-- so "conflict" finds the merge view without knowing it is <leader>gm.
--
-- This has to be set here rather than in the picker's own spec. LazyVim binds
-- <leader>? to which-key's buffer-local keymap list, which <leader>sk already
-- covers, and which-key loads after snacks, so a mapping declared alongside
-- the picker loses.
map("n", "<leader>?", function()
  require("util.capabilities").open()
end, { desc = "What this editor can do" })

-- A coding agent, as a consultant rather than an author.
--
-- Every one of these runs a CLI headless with no tools at all, so it cannot
-- write to a file even if asked. What comes back is a finding, a hint or an
-- explanation; turning any of it into code is typing you do. There is
-- deliberately no key here that edits a buffer — when agentic work is actually
-- wanted, that is a decision worth making in a terminal, not one keystroke away
-- from reading.
--
-- Which agent answers is a setting. Claude Code is the default because it is
-- the one whose lockdown has been proven here; see util/agent/backends.lua.
map({ "n", "x" }, "<leader>ar", function()
  require("util.agent.review").run()
end, { desc = "Review this code, as diagnostics" })

map("n", "<leader>af", function()
  require("util.agent.review").open()
end, { desc = "List the review findings" })

map("n", "<leader>as", function()
  require("util.agent.review").choose_scope()
end, { desc = "Review something wider or narrower" })

map("n", "<leader>ac", function()
  require("util.agent.review").clear()
end, { desc = "Clear the review findings" })

-- The hint ladder: press again for the next rung, never for the answer.
map({ "n", "x" }, "<leader>ah", function()
  require("util.agent.hint").next()
end, { desc = "Hint, one rung further each press" })

map("n", "<leader>aH", function()
  require("util.agent.hint").reset()
end, { desc = "Start the hint ladder over" })

map("n", "<leader>al", function()
  require("util.agent.ask").lookup()
end, { desc = "Look up a signature or argument order" })

map({ "n", "x" }, "<leader>ax", function()
  require("util.agent.ask").explain()
end, { desc = "Explain this code, or this error" })

map({ "n", "x" }, "<leader>aa", function()
  require("util.agent.ask").ask()
end, { desc = "Ask about this code" })

map("n", "<leader>a$", function()
  require("util.agent").report()
end, { desc = "What the agent has cost this session" })

map("n", "<leader>au", function()
  require("util.agent").use()
end, { desc = "Switch which agent answers" })

map("n", "<leader>aq", function()
  require("util.agent").cancel()
end, { desc = "Stop the request in flight" })

map("n", "<leader>aN", function()
  require("util.agent").reset()
end, { desc = "Start a new conversation here" })
