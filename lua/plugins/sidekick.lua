-- The top rung: the agent's own terminal, run by someone else's plugin.
--
-- Everything in util/agent is headless. It sends one prompt, reads one answer,
-- and can say exactly which tools existed while that happened. That is what
-- makes the lower rungs worth anything, and it is also why they cannot be the
-- whole story: a real conversation with an agent that edits files is a
-- terminal, and writing a terminal integration here would be rewriting
-- sidekick.nvim badly.
--
-- So the ladder hands off. Rungs chat through edit are ours and carry a
-- guarantee checked by tools/nvim-harness/agent-canary.sh. The normal rung is
-- sidekick's terminal with the CLI's own defaults, and nothing here claims
-- anything about it — that is the honest meaning of the last step.
--
-- sidekick knows twelve CLIs (claude, codex, copilot, gemini, opencode, aider,
-- crush, cursor, grok, qwen, amazon q, pi) and each authenticates itself, so
-- this stays a subscription-driven setup with no API key anywhere.
--
-- <leader>an opens it, and a-q closes it, because a terminal must keep c-c for
-- the program inside it. See util/dismiss.lua.
return {
  {
    "folke/sidekick.nvim",
    opts = {
      -- Next Edit Suggestions are Copilot-only and are a different product
      -- from the ladder: inline completions you accept with Tab. Off, so that
      -- "what may the agent do" has one answer rather than two.
      nes = { enabled = false },
      cli = {
        mux = { backend = "tmux", enabled = false },
      },
    },
    keys = {
      {
        "<leader>an",
        function()
          require("sidekick.cli").toggle()
        end,
        mode = { "n", "v" },
        desc = "The agent's own terminal (the normal rung)",
      },
      {
        "<leader>aC",
        function()
          require("sidekick.cli").select()
        end,
        desc = "Pick which CLI the terminal runs",
      },
    },
  },
}
