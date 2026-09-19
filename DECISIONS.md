# Decisions

One entry per decision, newest last. A decision that turned out wrong keeps
its entry and gains a correction, because the reasoning is the useful part.

Format: what was decided, what it was decided against, and what the decision
rested on. "Blocked" means it needs an answer from the person whose editor
this is.

---

## 1. The decision log lives in the config repository

**Decided:** here, rather than in dotfiles.

**Against:** dotfiles, which is the umbrella repository holding the harness.

**On:** almost every decision so far is about the editor's behaviour. The
harness exists to test it. A reader chasing "why does this key do that" starts
here.

---

## 2. Branches are stacked, not merged first

**Decided:** `debuggers` branches from `claude-manual`, which is still open as
PR #2.

**Against:** merging #2 first and branching from main.

**On:** #2 is 30 commits and unreviewed. Waiting blocks the work; branching
from main would make the debugger work conflict with everything in #2.

---

## 3. Trust gate does not touch debugging

**Decided:** no change needed.

**On:** `project_bin` is called only from `util/lsp.lua`. Debug adapters are
installed by Mason under the data directory, outside any project, so the gate
that refuses a repository's own binaries never sees them. Checked by grep, to
be confirmed against a real venv project when the debuggers are tested.
