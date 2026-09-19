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

---

## 4. Debug adapters taken from LazyVim's extras, the rest left

**Decided:** `lua/plugins/dap.lua` defines codelldb for Rust, C and C++, and
Julia's adapter, rather than importing `lang.rust` and `lang.clangd`.

**Against:** importing those extras.

**On:** they also bring rustaceanvim, crates.nvim and clangd_extensions, each
of which starts a language server on its own terms. This configuration attaches
only what a project provides. One adapter serves all three languages, because
codelldb is LLDB with a DAP front end.

---

## 5. Python debugs through the project's own interpreter

**Decided:** `dap.adapters.python` resolves the project's virtualenv python and
runs `-m debugpy.adapter`, falling back to Mason's `debugpy-adapter`.

**Against:** LazyVim's `require("dap-python").setup("debugpy-adapter")`, which
names Mason's binary and nothing else.

**On:** Mason's debugpy installer runs `python3 -m venv` with pip, and this
machine's python has no ensurepip — `spawn: python3 failed with exit code 1`.
Python debugging was therefore impossible, silently. Worse, Mason reported
`is_installed() == true` for a package whose directory does not exist.

Debugging a project with the project's interpreter is also the correct
behaviour: that is the environment the code runs in.

**Consequence:** running the project's python is running a program from the
repository, exactly what the LSP trust gate refuses. It goes through the same
gate. An untrusted project says so:

    This project has a Python environment, but it is not trusted.
    :DotfilesTrustProject to debug with it, or install debugpy with
    :MasonInstall debugpy.

---

## 6. mise provides the Python that Mason needs

**Decided:** `mise install python@3.13` rather than `sudo apt install
python3-venv python3-pip`.

**On:** no sudo needed, and it is reversible. Recorded because the machine now
has a python that other tools may pick up.

**Blocked, for the person whose machine this is:** the system python still
cannot create a venv with pip, so `:MasonInstall debugpy` fails there too.
Either install `python3-venv` and `python3-pip`, or accept that Python
debugging needs a project virtualenv. The configuration works either way.
