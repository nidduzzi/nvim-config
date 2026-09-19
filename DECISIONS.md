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

---

## 7. Julia's debugger is a server, not a program on a pipe

**Decided:** the Julia adapter is `type = "server"`. Julia opens a socket and
nvim-dap connects to it.

**Against:** `type = "executable"` over stdin and stdout, which is how the
other adapters work and what the first version did.

**On:** `DebugAdapter.run_debugger(stdin, stdout)` does not exist. The package
exports `DebugSession(conn)` and `run(session)`, and its README says `conn`
should be "a named pipe or socket connection" — one duplex stream, which
Julia's separate stdin and stdout are not. The adapter started, answered
`initialize`, and exited 1.

---

## 8. TypeScript needed nothing

**Decided:** no configuration added for TypeScript or TSX.

**On:** Node 22.22 strips types natively, so LazyVim's `Launch file`, which
runs `${file}` with node, already stops on a breakpoint in a `.ts` file:
`global.add at line 2 in main.ts`.

Breakpoints in a `.ts` compiled to `dist/` do **not** bind through the source
map, even with `outFiles` and `resolveSourceMapLocations`. Running the
TypeScript directly works and is simpler, so that is the documented path. A
project that must debug built output can set `outFiles` in its own
configuration.

---

## 9. Our debug configurations are prepended, not assigned

**Decided:** the FileType handler puts this configuration's entries in front of
whatever is already registered, and keeps the rest.

**Against:** returning early when something was registered (the first version),
or replacing the list outright.

**On:** mason-nvim-dap registers an "LLDB: Launch" for every adapter it
installs, and that one asks for the executable with `vim.fn.input`. Returning
early left ours unreachable — pressing the debug key opened a prompt that
blocks the editor until you type an absolute path. Replacing the list would
discard configurations a project set in its own `.nvim.lua`.

Found by driving the keys rather than the API: `dap.run({ type = "codelldb" })`
worked in every test, because it bypasses the configuration list entirely.
The thing a person actually presses did not.

---

## 10. The executable is derived from the build system

**Decided:** `program` looks for built output using the marker that proves the
build system is in use — `Cargo.toml` means `target/debug`, `CMakeLists.txt`
means `build`, and so on — and falls back to executables sitting in the root
for a project compiled by hand.

**Against:** asking for the path every time, which is what both LazyVim's
clangd extra and mason-nvim-dap do.

**On:** the answer is almost always one file and the editor can see it. One
candidate is used without asking, several offer a list, none falls back to the
prompt.

Resolved in 0.1ms against the three test projects: `hello`, `hello`, and
`target/debug/rust-hello`.

---

## 11. Where a virtualenv keeps its programs is looked up, not assumed

**Decided:** `bin_evidence` entries may be a function, and the virtualenv ones
check which of `bin` or `Scripts` exists.

**On:** a Windows virtualenv uses `Scripts`, and every path here said `bin`.
The derivation that replaced the hardcoded list was itself hardcoded to one
platform.

Executables are matched by name **and** name-with-any-extension, because a
Windows executable is `python.exe`. `glob(".../python")` finds nothing there.

Verified both shapes on Linux, the Windows one by building a project with
`.venv/pyvenv.cfg` and `.venv/Scripts/python.exe` and no `bin`:

    bin_dirs: .venv/Scripts
    python in .venv/Scripts -> .../Scripts/python.exe

**Blocked, for the person whose machine this is:** none of this has run on
Windows or macOS. It is reasoned from Neovim's documented behaviour and tested
against a directory laid out the way Windows lays one out. A real check needs
one of those machines.

---

## 12. The update checker is off

**Decided:** `checker = { enabled = false }`.

**Against:** leaving it on with `notify = false`, which is what it was.

**On:** measured, not guessed. With the checker's last-check timestamp reset,
one startup spawned **53 git invocations** — `git fetch --recurse-submodules
--tags --force --progress` and a `git remote-https` to github.com for every
plugin in the lockfile. With it off, zero.

It costs nothing visible here: startup is 68.8ms either way, because the work
happens after the editor is usable and Linux process spawning is cheap. On
Windows, where a process spawn is expensive and an antivirus scanner reads
every file each git touches, fifty of them is seconds. That is the shape of
the five-second start reported there.

It also contradicts how this configuration treats plugins: they are pinned by
lazy-lock.json and updating them is a deliberate act. `:Lazy check` asks the
same question at a moment of your choosing.

**Not verified on Windows.** This is a measured cause with a plausible
mechanism, not a confirmed fix. It needs one start on that machine to say.

---

## 13. c-c closes an overlay it is not standing in

**Decided:** `dismiss` looks for an overlay window anywhere in the tabpage,
preferring the one the cursor is in.

**Against:** reading `vim.bo.filetype`, which is what it did.

**On:** a combination matrix over ten overlay types found Trouble was never
closed. Trouble and the quickfix list open without taking focus, so the
current buffer is the file, not the list, and the key did nothing while a list
sat in plain sight.

This is the third time the same mistake has been found here — the hover float,
the keyguard shadow, and now this. Each one read the state of the window the
cursor happened to be in and called it the state of the editor.

After: all ten close.

    picker (files)  picker (grep)  lazy  help  checkhealth
    quickfix  trouble  notification history  explorer  agent panel
