-- The agent's own terminal, run by someone else's plugin — but still on the
-- ladder.
--
-- Everything in util/agent is headless: one prompt out, one answer back, and
-- the CLI's own registry available to say exactly which tools existed while
-- that happened. That is what makes the lower rungs worth anything. It is also
-- why they cannot be the whole story, because a real back-and-forth with an
-- agent is a terminal, and writing one here would be rewriting sidekick.nvim
-- badly.
--
-- The obvious way to hand off is to let the terminal be "the unconstrained
-- one" and leave it there. That was the first version of this file and it was
-- wrong: it made the terminal the one place where "how much may it do" had no
-- answer, so the easiest way to use the agent was the way that walked around
-- the ladder.
--
-- sidekick's tool config is a `cmd` list, so the rung flags go straight into
-- it. Each backend appears once per rung — claude_chat, claude_explore,
-- claude_edit, hermes_edit — generated from backends.lua so the two cannot
-- drift, and <leader>an opens the one matching the rung you are actually on.
-- `normal` is the plain command with no flags, and that absence is the promise
-- being withdrawn rather than an oversight.
--
-- a-q closes it, because a terminal has to keep c-c for the program inside it.
-- See util/dismiss.lua.
return {
  {
    "folke/sidekick.nvim",
    opts = function(_, opts)
      local backends = require("util.agent.backends")

      opts.cli = opts.cli or {}
      -- Merged rather than replaced: sidekick ships twelve tools and this adds
      -- the rung-constrained ones beside them.
      opts.cli.tools = vim.tbl_deep_extend("force", opts.cli.tools or {}, backends.terminal_tools())

      -- Next Edit Suggestions are Copilot-only and are a different product
      -- from the ladder: inline completions accepted with Tab. Off, so "how
      -- much may the agent do" has one answer rather than two.
      opts.nes = { enabled = false }
      return opts
    end,
    keys = {
      {
        "<leader>an",
        function()
          local agent = require("util.agent")
          local backends = require("util.agent.backends")

          local name = agent.config.backend
          local rung = agent.config.trust

          -- A rung this backend cannot express has no terminal either. Saying
          -- so is better than opening an unconstrained one that looks like it
          -- honoured the setting.
          local backend = backends[name]
          if backend and not backends.terminal_cmd(backend, rung) then
            local _, why_not = backends.supports(backend, rung)
            vim.notify(why_not or "No terminal for that rung.", vim.log.levels.ERROR, { title = "Agent" })
            return
          end

          if rung == "normal" then
            vim.notify(
              "Opening the CLI with its own defaults. Nothing here limits what it can do.",
              vim.log.levels.WARN,
              { title = "Agent" }
            )
          end
          require("sidekick.cli").toggle(backends.terminal_name(name, rung))
        end,
        mode = { "n", "v" },
        desc = "Talk to the agent in a terminal, at this rung",
      },
      {
        "<leader>aC",
        function()
          require("sidekick.cli").select()
        end,
        desc = "Pick any CLI and rung to talk to",
      },
    },
  },
}
