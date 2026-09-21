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

---

## 14. The extension list is read from git

**Decided:** `recall.extensions` asks `git ls-files` and falls back to walking
the tree when there is no repository.

**On:** the walk took 218.3ms on label-studio, blocking the main loop the
first time the extension filter is opened. git knows the answer already:
11.8ms, an eighteenfold difference. On a slower filesystem the walk is
seconds.

Both paths give the same answer, and the git path also stops counting files
nobody tracks.

    label-studio  13.5ms  md png py ts js svg tsx jsx
    crun           6.5ms  c h py sh md nix fmf yaml
    fixture        2.7ms  md lua js py
    nogit          4.2ms  py lua

---

## 15. Ties in a sort need a tiebreaker

**Decided:** extensions sort by count, then by name.

**On:** a spec failed one run in three. Two extensions with the same count
compared equal, and `table.sort` is not stable, so the list came back in a
different order each time — the filter would shuffle between sessions.

This is the same fault fixed earlier in `capabilities.lua`. Two occurrences is
a pattern: every comparator here should be a total order, and a spec that
fails intermittently is the cheapest way to find one that is not.

---

## 16. Every comparator audited for ties

**Decided:** after two unstable sorts were found by accident, all eight
`table.sort` comparators in `lua/` were read.

**Found:** two more that could tie.

`util/lsp_commands.lua` sorted server commands by name alone. Two language
servers attached to the same buffer can advertise the same command, and then
the menu order depended on hash order. Now command, then client name.

`lua/plugins/dap.lua` sorted built executables by modification time alone. A
build writes its outputs in the same second routinely: three binaries compiled
together all had mtime 1767200400, so which one the debugger offered first was
undefined. Now time, then path.

The other four were already total: window ids are unique integers, and command
and capability names are unique within their lists.

---

## 17. Grep ranking is checked on the screen, not in a spec

**Decided:** a screen test greps for a symbol and the committed frame shows
the declaration above the reference.

**Against:** a unit spec calling `rank_item` directly.

**On:** the spec needs treesitter's `locals` query, which Neovim does not ship
for Lua — nvim-treesitter provides it. Adding nvim-treesitter to the spec
bootstrap made it clone twenty-seven thousand objects and still not install a
parser in time. A spec that cannot see a parser tests an absence.

The screen test uses the real editor, where the parser is already there.

Two things it exposed:

Ranking is applied through `search.opts`, which sets `transform`. Calling
`Snacks.picker.grep()` directly skips it, and my first probe did exactly that
and reported every `score_mul` as nil — the feature looked inert when it was
the probe that was wrong.

The ranked item is stable; the unranked tail is not. Everything without a
declaration scores 1010, and snacks has no tiebreaker for equal scores, so two
such rows swap between runs. The test greps for a symbol whose hits cannot
tie rather than asserting an order the picker does not promise.

---

## 18. A prompt that asks for text is an input, not a picker

**Decided:** `recall.input` opens `vim.ui.input`, and offers what the project
remembered through `<Tab>` completion.

**Against:** the snacks picker it opened before, with the remembered values as
items and the query as the new value.

**On:** a picker's query is a match pattern, not text. Typing `!src/**` at the
glob prompt selected `docs/**`, because `!` inverts a snacks match: the prompt
answered with the opposite of what was typed, and the search that followed was
wrong in a way the title did not show. `'`, `^`, `$` and a space each claim a
meaning too, and globs, extension lists and questions all contain them.

An input takes the characters. Completion is prefix rather than fuzzy, which
is what completing a path wants.

---

## 19. The filters keep the picker they filter open

**Decided:** `search.keep_open` clears `auto_close` for as long as a filter's
prompt is up, and restores it afterwards.

**Against:** leaving it, and reopening the picker after the prompt.

**On:** a snacks picker closes itself when focus lands in a window that is not
part of it. The prompt is a float, so the picker survived while it was open —
and then answering it put focus back in the editor and took the picker with
it. Pressing `<a-G>`, typing a glob and pressing Enter landed on the dashboard.

The picker is the thing being filtered. Reopening it would lose the query, the
scroll position and the selection.

---

## 20. One definition per search toggle

**Decided:** `search.toggles` lists the key, the ripgrep flag, the title label
and what to say, and `lua/plugins/picker.lua` builds the keymap and the action
from it.

**Against:** a keymap entry, an action and a function per toggle.

**On:** the feature tour drove `<a-p>` for the preset list. `<a-p>` is snacks'
toggle-preview, and a comment in `picker.lua` says exactly that, three lines
above the key it was meant to be. The scenario captured a frame, the frame
showed a working picker, and the run passed for as long as the scenario has
existed.

Looking for the same mistake elsewhere produced one of my own: `<a-r>` is
snacks' regex toggle, I read our own `lua/` for it, found nothing, and added a
`--fixed-strings` toggle on the same key — replacing a working feature with a
second name for it. `check-picker-keys.sh` now resolves the picker's real key
table and fails on both: a key the tour presses that nothing answers to, and a
key taken from snacks that nobody wrote down.

The title is now built from the flags that are on, so a toggle and a glob
filter compose instead of overwriting each other's name.

---

## 21. `<Esc>` closes a picker, it does not cancel it

**Decided:** `<Esc>` in the picker's input and list runs `close`, the same
action `<c-c>` runs.

**Against:** snacks' own `cancel`.

**On:** searching, pressing `<Esc>`, then asking for the last search with
`<leader>sR` answered "No picker to resume" and offered a list of sources.
`<c-c>` on the same picker resumed it with the query intact. Two keys that
both mean "I am done here" left the editor in two different states, and the
one everybody presses was the one that threw the search away.

---

## 22. The fixture has to contain the thing being demonstrated

**Decided:** `make-fixture.sh` writes `src/login.js` after the commit that
adds it, and changes a line rather than only appending one.

**Against:** leaving it, since every scenario captured a frame.

**On:** the file was written twice before its commit, so the second write was
what got committed and the working tree was clean. `git-signs` had no sign to
show, `git-hunk` no hunk, `git-status` no change. The frames looked like a
file, which is what a file looks like when nothing is wrong, and the tour
called all three captured.

Appending only meant an inline hunk preview had nothing to draw either: a
deleted line is what it shows.

---

## 23. Windows is corrected for, not tested on

**Decided:** the places that could only work on a POSIX machine are fixed by
reading, and each carries a comment saying what Windows does instead.

**Against:** leaving them until someone runs this on Windows.

**On:** four of them were found by looking:

`shellcmdflag` was set to `-c` for any shell that was not literally `bash`.
cmd.exe takes `/c` and PowerShell takes `-Command`, so on Windows that setting
would have broken every `:!` command, every formatter and every language
server started through a shell. It is now guarded by the platform and by a
list of shells that take `-c`.

`git worktree list --porcelain` prints forward slashes on every platform,
while `vim.uv.cwd()` returns the platform's separator. Comparing them raw says
you are standing in none of your worktrees. Both sides are normalised now.

`vim.fn.systemlist("git diff ...")` was a string, which goes through `'shell'`
and quotes differently on Windows. It is a list now; nothing there needs a
shell.

Two paths were built with `..` and a literal slash.

**Closed by 29 and 42.** All three run on macOS and Windows now, and the
`shellcmdflag` guard is exercised by the boot job on both. The screens stay on
Linux, for the reason in 29.

---

## 24. A gate that cannot run has to say so

**Decided:** `run-probes.sh` clears its output directory before a run and
fails when a report is missing.

**Against:** the previous behaviour, which printed `did not run` and exited 0.

**On:** `stress-probe.lua` read `util.lsp.bin_dirs` as a table. It became a
function when the binary directories started being derived from the project,
so the probe died on that line and wrote nothing — and the gate printed
whatever `stress.txt` was left in `/tmp/nvim-probes` from the run before.
Against the nine-file fixture it reported label-studio's 5626 tracked files,
30.8% documentation, and no errors.

Compiling is not running: `check-syntax.sh` was happy with that file
throughout. The probes are now in CI against the fixture, because they are the
only gate that executes these modules rather than loading them.

---

## 25. The machine tier is verified in an editor, not only in a spec

**Decided:** the four tiers were driven end to end — a real `local.lua`, a
real `.nvim.lua`, a real `set()` — and `:checkhealth dotfiles` now prints what
each setting resolved to and where from.

**Against:** trusting the unit spec, which already covered the order.

**On:** the spec exercises `resolve` with tables it builds itself. It cannot
tell you that `local.lua` is looked for beside `init.lua` rather than in a
state directory, that it is gitignored, or that a project's `.nvim.lua` is
read at all — that one needs `exrc` and a trust decision, which is editor
behaviour, not module behaviour.

Driving it found that the module's own docstring was wrong: it said health
could say where a value came from, and health had no settings section.

Verified: built in → `local.lua` → the project's `.nvim.lua` → set for this
session, each overriding the one before.

---

## 26. The TypeScript debugger names a runtime this machine has

**Decided:** a `Run this file` configuration is prepended for TypeScript,
TSX, JavaScript and JSX, and it names a runtime only when one is needed.

**Against:** LazyVim's own, which sets `runtimeExecutable` to `tsx`, or
`ts-node` when `tsx` is absent.

**On:** neither is installed by anything in this configuration, and neither is
on this machine. A launch naming a runtime that does not exist fails with no
message at all: `<leader>db`, `<leader>dc`, Enter — the debugger UI opens, the
breakpoint is listed, and no session ever starts. That is what it did here
until this was found by asking `dap.session()` rather than by looking at it.

Node has stripped TypeScript types since 22.6, so on a current Node there is
no separate runtime to find; `tsx` and `ts-node` are used only when Node is
older, and only if one of them is there.

Verified stopping at a breakpoint: Python, C, C++, Rust and TypeScript.

**Closed by 41.** A component is debugged in a browser, and both
configurations for that are here.

Julia is verified too, through mise: session started, stopped at the
breakpoint, thread 1. See 27 for what that took.

---

## 27. A program that exists is not a program that runs

**Decided:** before an adapter is started, the command is asked for its
version, and a command that cannot answer is reported with what it said.

**Against:** `vim.fn.executable()`, which is what everything here used.

**On:** mise puts a shim on PATH. `executable("julia")` is true in any
directory, and outside a project that names a version the shim exits with
`mise ERROR No version is set for shim: julia`. The debugger started it, the
adapter died before it spoke, and nvim-dap sat at "Starting adapter julia"
forever. Nothing on the screen said why, and the session simply never existed.

Now:

    Julia debugger: julia is at ~/.local/share/mise/shims/julia,
    and does not run here: mise ERROR No version is set for shim: julia

The cost is one process at the moment a session starts, and every adapter here
reports its own version.

`make-debug-fixtures.sh` writes a `mise.toml` naming the version mise has, so
the Julia fixture is a project the shim resolves in. Julia debugging is
verified: stopped at the breakpoint, thread 1.

---

## 28. Neovim already says when a server quits

**Decided:** nothing is added for it, and pyrefly's own handler is removed.

**Against:** a shared `on_exit` on every server, which is what I wrote first.

**On:** driving a project whose `.venv/bin/ruff` exits 3 produced two warnings
where one was wanted:

    Language server: ruff stopped on its own, exit code 3. :LspLog has what it said.
    Client ruff quit with exit code 3 and signal 0. Check log for errors: …/lsp.log

The second is Neovim's, it carries the same facts and the path to the log, and
it fires for any client that quits. The comment on the pyrefly handler said
that server "exits quietly"; that was true of an older Neovim, and the handler
outlived the problem.

The debugger needed its own check (27) for the opposite reason: nvim-dap says
nothing at all when an adapter dies before speaking, and sits at "Starting
adapter" forever.

Also confirmed, since the test needed it: `bin_dirs` is evidence-based, so a
`.venv` without a `pyvenv.cfg` is not a virtualenv and its `bin` is not
searched. That is the intended answer, not a miss.

---

## 29. macOS is in CI; Windows is not

**Decided:** the specs and the boot-and-health job run on `macos-latest` as
well as `ubuntu-latest`, over both stable and nightly Neovim. The screens stay
on Linux only.

**Against:** a local VM, and against leaving both platforms unverified.

**On:** four portability defects were found by reading (23), and nothing had
ever run off Linux. A hosted macOS runner costs nothing and exercises the half
that is platform behaviour — paths, separators, shells, the standard
directories — which is exactly where those defects were.

The screens are excluded deliberately. A golden frame is a statement about one
terminal: a different platform draws its own box characters, its own widths
and its own idea of what a Nerd Font glyph occupies. Committing a second set
would be committing a second thing to keep in step.

**Superseded by 42.** Windows runs the specs and the boot check after all:
the runners carry Git Bash, so the scripts run unchanged and nothing had to be
rewritten in PowerShell. The screens are still Linux only.

---

## 30. A panel is not a file, and buftype says so later than filetype

**Decided:** the language-server warning reads `buftype` again after its
two-second wait, and `M.unserved` keeps only the real-file types no server
serves: gitcommit, gitrebase, text.

**Against:** the list of fourteen filetypes it had, which named lazy, mason,
trouble, the quickfix list, help, man, checkhealth and every picker panel.

**On:** opening a merge conflict warned that nothing serves `DiffviewFiles`.
The autocmd already skipped buffers with a buftype — but a plugin sets its
filetype first and its buftype after, so at `FileType` the panel still looks
like an ordinary file. The warning then fired from the deferred callback,
where nobody looked again.

Reading it at the moment the decision is made covers every panel, including
the ones nobody thought to name. Verified by opening Lazy, checkhealth,
Trouble, the quickfix list and help in one session: no warnings. A Rust file
with no server still warns.

---

## 31. The dismiss key closes the diff view too

**Decided:** a rung between the floats and the panels closes a Diffview tab
with `:DiffviewClose`.

**Against:** leaving it, since every other overlay was covered.

**On:** `<c-c>` is documented here as the key that closes whatever is open,
and the configuration's own merge-conflict view was the exception: pressing it
in a Diffview tab did nothing at all. The panel rung could not do it either —
Diffview owns the whole tab, and closing one of its windows leaves the tab,
the panel and the files exactly where they were.

Found by driving combinations rather than features: open a thing, open
another thing over it, press the key, and see what is left. The same pass
confirmed the ladder is right for a picker over Trouble — picker, then
Trouble, then nothing, and the file underneath is never closed.

---

## 32. An overlay is a buffer with a buftype, and some views are several windows

**Decided:** `dismiss` asks the buffer whether it is a file instead of
matching a filetype against a list, and closes a debugger UI or a diff view
through the command that owns it.

**Against:** the list of nine filetypes it had.

**On:** driving combinations rather than features. With the debugger UI open,
`<c-c>` did nothing at all: six panels, none of them named in the list. With a
terminal in a split, nothing. With a diff view, nothing — and that one could
not be fixed by naming it either, because closing one of its windows leaves
the tab, the panel and the diff.

Every panel is a buffer with a buftype and a file has none, so the rule covers
the plugins nobody has installed yet. The two composite views are named, with
the command each ships, because "close this window" is not what ending them
means.

Driven after the change: explorer closes, terminal closes, the debugger UI
closes in one press rather than six, the diff view closes and gives the tab
back, and a picker over Trouble still closes in that order without touching
the file underneath.

Two specs had to change with it. They opened scratch buffers and called them
files, which is exactly the distinction the new rule turns on.

---

## 33. Which root a feature asks about depends on the feature

**Decided:** `recall` asks for the root of the working directory; the agent
asks for the root of the buffer.

**Against:** recall delegating to the agent, which it did.

**On:** a conversation belongs to the code being discussed, so the agent is
right to follow the buffer. A glob or a set of extensions belongs to the
project being searched, and a search reads the directory. While the agent's
marker list was shorter than the language servers' the two rarely disagreed;
making them agree (32) made the delegation visible, as three specs that had
been reading one project while standing in another.

---

## 34. Trust is recorded against the directory, not against its name

**Decided:** the trust store keeps `path<TAB>dev:inode:birthtime`, and trust
holds only while all three still match. Lines from the old store, which held
paths alone, are dropped rather than honoured.

**Against:** the path on its own, which is what it held.

**On:** trusting a project here means running programs out of it — a language
server or a debug adapter from `.venv/bin`. A path is not a directory: delete
`/tmp/work` and let something else create it, and a store keyed on the name
hands the new one everything the old one was given. Nobody is asked again,
because as far as the store is concerned nothing changed.

The inode alone was not enough, and the spec that proved it is why this is
written down: a directory deleted and immediately recreated is routinely
handed the same inode back, and the first version of this read as trusted
through exactly that. Creation time separates them.

You will be asked once more for projects trusted before this, which is the
price of the store being checkable at all.

---

## 35. A formatter from a project is a program from a project

**Decided:** every formatter named here resolves through
`util.lsp.project_bin`, the same trust gate the language servers use.

**Against:** conform's default, which looks in `node_modules/.bin` first.

**On:** that default is right for a repository you wrote and an execution
path for one you cloned. Demonstrated rather than argued: a repository with
`node_modules/.bin/prettierd` as a shell script, a `package.json`, and an
`app.js`. Opening the file and formatting it ran the script. Nothing was
asked, nothing was said, and format-on-save means saving is enough.

    formatters: prettierd@<the cloned repository>/node_modules/.bin/prettierd
    ran: true

Afterwards, in the same repository: no formatters offered, nothing executed.
Trusting it with `:DotfilesTrustProject` brings its prettierd back. A
formatter on PATH is unaffected --- stylua still formats a file in an
untrusted project, because it is not the project's program.

This is the third program-from-a-project path: language servers (guarded
already), debug adapters (guarded already), and formatters. `<leader>cf` and
format-on-save were the only one of the three that ran without asking.

---

## 36. "From PATH" can still mean "from the project"

**Decided:** `util.lsp.safe_exepath` replaces `vim.fn.exepath` wherever this
configuration decides which program to run. It refuses a result that lies
inside an untrusted project.

**Against:** treating PATH as the safe fallback, which is what 35 had just
made it.

**On:** venv-selector activates a project's virtualenv, and activating one
puts its `bin` on PATH. direnv does the same, and so does a shell started
inside the project. After that, `exepath("prettierd")` answers with the
project's program without anything having looked in the project --- so the
gate added an hour earlier could be walked around by a repository shipping a
`.envrc`, and the editor would have called it a program from PATH.

Demonstrated in the same repository as 35, with its `node_modules/.bin` put on
PATH before the file was opened:

    exepath says:       <repo>/node_modules/.bin/prettierd
    safe_exepath says:
    formatters:
    ran: false

stylua from Mason still formats, and codelldb still starts a debug session,
because neither is inside the project being judged.

---

## 37. A repository's own git config runs commands, and that is git's model

**Decided:** nothing is changed in the configuration. Written down instead,
with the demonstration, because it is the one execution path found today that
this editor cannot close.

**Against:** refusing git features in untrusted projects, which would mean
refusing them nearly everywhere: almost no project is in the trust store, and
the trust store exists for running the project's *programs*, not for reading
its history.

**On:** git honours `diff.<name>.textconv` from the repository's own
`.git/config`, and `.gitattributes` chooses which files it applies to. A
directory carrying both runs that command whenever anything diffs a matching
file:

    [diff "evil"]
        textconv = sh -c 'touch /tmp/PWNED; cat'

Opening the file is not enough --- gitsigns did not trigger it here. A git
feature is: `<leader>ghp`, `<leader>gd` and `<leader>gs` between them ran it.

What limits this is delivery. `git clone` does not copy the remote's config,
so a cloned repository cannot carry one; an archive, a shared directory or a
container volume can. Git's own protections here are about ownership
(`safe.directory`), not about what the config may do.

The editor's own git calls pass no user-controlled diff drivers, but gitsigns
and diffview issue their own, and neither takes `--no-textconv` from us.

**Decided by you, against my recommendation, and implemented in 44:** git
features run only in trusted projects.

Also verified while looking: `exrc` is safe. A `.nvim.lua` in an untrusted
project does not run. Neovim asks, and the editor does not finish starting
until it is answered --- the harness reports "Neovim did not become ready",
which is the prompt waiting.

---

## 38. The agent asks before it is shown a credential

**Decided:** everything the agent is shown goes through `util.agent.context`,
and that file now asks first when the buffer looks like it holds a
credential. The answer is not remembered.

**Against:** relying on the rung ladder, which decides *whether* code is sent
but not *which* code.

**On:** the ladder's second rung and above put the buffer in the prompt. If
the buffer is a `.env`, the prompt is the `.env`. Nothing said so, and the
question that sends it is the ordinary one --- `<leader>aa` on the file you
happen to be looking at.

Two kinds of recognition, because neither is enough alone: the filename, for
a `.env` that is empty today and full tomorrow, and the contents, for a key
pasted into a scratch buffer with no telling name. The token patterns are the
prefixes the issuers document --- `AKIA`, `ghp_`, `sk-ant-`, `xoxb-`, `AIza`
--- so a match says something about the token's format rather than guessing at
the word before it.

`.env.example` and `secrets.sample.yaml` are left alone. A template is the
shape of a configuration, which is a reasonable thing to ask about, and it
holds nothing.

Only the first 400 lines are read. A credential at the bottom of a ten
thousand line file is not what this is for, and reading all of one on every
question is.

---

## 39. What the editor writes about you is yours to read

**Decided:** the state this configuration writes — the trust store, the
recall lists, the agent's session files — is created 0600, in directories
created 0700, and files already there are narrowed when the directory is next
used.

**Against:** the process umask, which is what it used and which is usually
0022.

**On:** none of it is a key. All of it is about you: what you asked the agent,
which projects you have trusted, which conversation belongs to which project.
On a shared machine, world-readable means the next account along can read your
questions. This was 0664 and 0755 on this machine, and the migration matters
because a state directory that predates the change keeps the old modes until
something writes to it.

Neovim's `writefile` takes no mode, so these are written and then narrowed.
The gap between the two is a race nobody can win from another account without
already watching the directory, and closing it properly would mean writing
through `vim.uv` by hand for a state file holding a question.

---

## 40. Mason gets a Python that can make a virtualenv

**Decided:** when the `python3` on PATH cannot create a virtualenv, one that
can is put in front of it, taken from whatever version manager this machine
already has: mise, uv, pyenv or asdf.

**Against:** leaving `:MasonInstall debugpy` broken and documenting the
project-venv workaround, which is what entries 6 and 11 said to do.

**On:** Mason installs a Python package by making a virtualenv with the
`python3` it finds. Debian and its descendants ship `ensurepip` separately, so
that python3 cannot, and the failure is `spawn: python3 failed with exit code
1` --- which does not mention ensurepip, virtualenvs or the package that is
missing.

This machine had a working interpreter the whole time: mise's 3.13.15, twelve
candidates in all. `:MasonInstall debugpy` now succeeds and `debugpy-adapter`
is on PATH, and a Python file in a project with no virtualenv stops at a
breakpoint --- which is what entry 11 said could not be done here.

The interpreter is asked whether it can, rather than judged by its version:
what is missing is a package the distribution split out, not a feature of the
language.

This is a side effect on PATH, and the only one in this configuration. It
changes what `python3` means for every process the editor starts, which is the
point --- Mason is not the only thing that wants a virtualenv --- and it
happens only when the one on PATH cannot do the job.

---

## 41. A component is debugged in a browser

**Decided:** TypeScript, TSX, JavaScript and JSX get two more configurations:
open a browser on this project's dev server, and attach to one already
running with `--remote-debugging-port=9222`.

**Against:** leaving TSX with only "Run this file", which cannot work: Node
strips types but does not understand JSX, so a component never runs as a
file.

**On:** a `.tsx` is compiled by the dev server into JavaScript with a source
map, the browser runs that, and the debugger attaches to the browser and maps
the stop back through the map. That is what VS Code does with `pwa-chrome`,
and the adapter is already here --- what was missing were the configurations
and the two things that make a breakpoint land in your file rather than in
something the bundler invented: `webRoot` and `sourceMapPathOverrides`.

The URL is derived. A port written into a `package.json` script wins, because
somebody wrote it down on purpose; otherwise the framework's own default,
keyed on the config file that says which framework it is --- 5173 for Vite and
SvelteKit, 3000 for Next and Remix, 4200 for Angular, 4321 for Astro.

Verified end to end, not by reading: a page served on 4321, an `app.js` with a
source map naming `app.tsx`, headless Chrome from the playwright cache, a
breakpoint set on line 2 of the `.tsx`. The session started and stopped there,
in `app.tsx`.

Worth recording how the first attempt failed. The new function was defined
below the one that called it, which Lua only notices when the call runs:
`check-syntax.sh` passed, and the editor reported `Failed to run 'config' for
nvim-dap`. The configurations silently fell back to LazyVim's two. Driving it
is what found that; compiling it never would have.

---

## 42. Windows runs the specs, through Git Bash

**Decided:** `specs` and `boot` run on `windows-latest` as well, every step
under `shell: bash`.

**Against:** 29's conclusion, which was that Windows meant rewriting the
harness in PowerShell and was therefore a day of work.

**On:** that was wrong, and cheaply so: the Windows runners ship Git Bash, so
`./scripts/test` runs as written. The only change the workflow needed was the
boot job putting the configuration where Neovim looks for it --- a symlink
needs developer mode on Windows, so it falls back to a copy, and the XDG
directories moved to `runner.temp` because a directory cannot be copied into
itself.

The screens are still Linux only, for 29's reason.

It found four things in the first run and three in the second, and only one of
the seven was Windows-specific in a way that could be dismissed as
platform noise:

- a virtualenv there is `Scripts\ruff.exe`, which `util.lsp` knew and the spec
  did not
- NTFS has no mode bits, so the 0600 work in 39 cannot be enforced there
- switching worktrees reopened a picker without checking one exists, which was
  latent everywhere and surfaced there as a scheduled callback failing after
  its test had passed
- the worktree list marked nothing as current, because git says
  `C:/Users/runneradmin/...` and the editor says `C:\Users\RUNNER~1\...`

macOS found the fourth of the same family, and the worst: `/var` is a symlink
to `/private/var`, so `safe_exepath` --- which decides whether a program lies
inside an untrusted project --- was comparing two spellings of one directory.
`util.lsp.root` resolves now, so the comparison is made once, in one place.

All fourteen jobs pass: lint, the debug-call check, and the specs and boot
check on Linux, macOS and Windows against stable and nightly.

---

## 43. The rung ladder, re-proved against the CLI that shipped today

**Decided:** nothing changes. Recorded because the guarantee is a claim about
somebody else's program, and that program updates itself.

**On:** all four rungs were run against `claude` 2.1.278 and each held:

    chat      tools=[] mcp_servers=[]              canary untouched
    context   tools=[] mcp_servers=[]              canary untouched
    explore   tools=[Glob, Grep, Read]             canary untouched
    edit      tools=[Edit, Glob, Grep, Read, Write] canary changed, as permitted

`rung-flags-match.py` confirms the flags proved here are the flags the editor
sends.

The two findings in `agent-canary.sh`'s own header are why this is re-run
rather than trusted: `--tools ""` once left every MCP server registered, and
Hermes' `-t ""` was ignored as falsy and left `file` and `terminal` enabled,
which overwrote the canary on the first attempt. Neither would have been found
by reading the documentation, and neither stays fixed by itself.

Also driven in the same pass, and correct: session save and restore through
persistence.nvim (two buffers and the working directory came back), grug-far's
search-and-replace window, and `<c-c>` closing it --- it is a `nofile` buffer,
so the rule from 32 covers a plugin nobody had tested against.

---

## 44. git runs only where the project is trusted

**Decided:** every git-backed feature this configuration wires up is refused
in a project that has not been trusted. Your call, against my recommendation
in 37.

**What it covers:** gitsigns does not attach --- no signs, no hunk preview, no
blame; `<leader>gd`, `<leader>gf`, `<leader>gm`, `<leader>gw` and `<leader>gW`
report the refusal; the git pickers on `<leader>gs`, `<leader>gl`,
`<leader>gL`, `<leader>gb` and `<leader>gf` are rebound through the same
guard; `util.worktree` and `util.diff` go through it; and `recall` stops
asking `git ls-files`, falling back to ripgrep, which reads the same ignore
files and runs nothing the repository named.

**Why any git command and not only the diffs:** `textconv` is the one that is
easy to demonstrate, but `core.fsmonitor` names a program that almost every
git command runs, `status` included. Gating only the diffs would leave that.

**The cost, stated plainly:** one `:DotfilesTrustProject` per repository, and
until then a visibly emptier editor --- no gutter signs is the one you will
notice. The command now reloads the buffer, so gitsigns attaches immediately
rather than on the next open.

**The way out:** `git_project` is a setting like every other, so a machine
that only ever holds your own repositories can put `git_project = true` in its
`local.lua` and never see the prompt; `false` refuses everywhere. The default
is `"ask"`, which means trusted projects only.

**What changed for search:** in an untrusted project the extension and glob
filters come from ripgrep rather than git, so they include untracked files.
Same ignore rules, slightly different answer, and the specs say which is
which.

**Verified:** the repository from 37, with its `textconv` still in place ---
`<leader>ghp`, `<leader>gd` and `<leader>gs` run nothing. After
`:DotfilesTrustProject` the same keys run it, which is what trusting a project
means.

---

## 45. The git decision asks, rather than waiting to be asked

**Decided:** opening a repository nobody has answered for shows the menu, and
`<leader>gt` reaches the same menu at any time. A trusted project shows
nothing.

**Against:** the command alone, which is what 44 shipped.

**On:** the first sign of an untrusted project was a feature quietly missing
--- no gutter signs, and nothing on screen to say why or what to do. A gate
whose refusal has to be discovered is a gate that reads as a bug.

Three choices, because two of them are the ones people actually want:

    Trust this project: run its programs and its git
    Not now: ask again next time this project is opened
    Trust every project on this machine (writes local.lua)

The third writes `git_project = true` into the machine-local settings file,
which is the answer for a laptop that only ever holds your own repositories.
It edits one line and leaves the rest of that file alone.

**When it asks:** on the first file read from a project, not at startup.

`VimEnter` and `User VeryLazy` both fire before `lua/config/autocmds.lua` is
loaded, because LazyVim loads that file *on* VeryLazy, so a handler
registered there waits for something that has already happened and never runs
--- which is what the first version did, silently. `BufReadPost` is also the
better moment on its own terms: the question is about this project's code, so
opening some of it is when it means anything, and starting the editor and
closing it again asks nothing.

**One explanation, not two.** Opening a file in an untrusted project fired
gitsigns' refusal notification *and* the menu, side by side, saying the same
thing. The menu says it better, so it marks the project as explained and the
notification stays quiet. The committed screen is what caught this --- both
were in the frame.

**The delay was the bug.** The first version waited 1.5 seconds so that snacks
would own `vim.ui.select`, then guessed whether you looked busy and fell back
to a notification. Both of those were working around the delay. By the time a
file has been read snacks is already loaded, so the question can arrive with
the file --- before there is anything to interrupt. Driven frame by frame: the
picker closes, the file appears with the menu over it, `<Esc>` dismisses it,
and what you type next lands in the file.

---

## 46. What the git gate costs a large project

**Measured, on label-studio: 5626 tracked files, 60000 on disk.**

    trusted    5.7ms   15 extensions   (git ls-files)
    untrusted  34.9ms  15 extensions   (ripgrep)

Six times slower and the same answer, once per project per session, because
the list is cached per root. The walk both of them replaced was 218ms.

Worth knowing rather than worth fixing: the untrusted path is the one a
cloned repository gets, and 35ms on the first search of a project nobody has
vouched for is not a cost anyone can feel.

---

## 47. The debuggers were never driven to a breakpoint

**Every language stopped. One of them never had.**

The tour asserted a breakpoint sign in the margin, which the editor draws
whether or not an adapter ever answers. `check-debuggers.sh` now opens the
file, sets the breakpoint, starts the session, picks the first configuration
and matches on the argument values in the variables pane --- `b int = 1` ---
which only a live adapter can put on the screen.

    python      main.py:3     debugpy
    typescript  main.ts:2     pwa-node, types stripped by node
    c           main.c:4      codelldb
    cpp         main.cpp:5    codelldb
    rust        src/main.rs:2 codelldb
    julia       main.jl:2     DebugAdapter.DebugSession

Julia failed on the first run: `exepath("julia")` follows the symlink, and a
mise shim points at mise itself, so the adapter was started as `/usr/bin/mise`
with Julia's arguments and exited 2 before speaking. `runs()` had checked
`--version`, which mise answers happily. The trust decision is still made on
the resolved path; only the spelling handed to the adapter changed.

Adapters are looked for in mason as well as on PATH --- looking only at PATH
reported codelldb missing on a machine where three languages debugged fine ---
and a run that checked nothing fails rather than passing quietly.

---

## 48. TSX in a browser: what works, and what is still open

**Needs your call: whether a browser belongs in the harness.**

The real way TSX is debugged is the browser one: the page runs compiled
JavaScript and the source map puts the breakpoint back on the line you wrote.
`make-debug-fixtures.sh` now builds that fixture --- `index.tsx` compiled by
the TypeScript the language server already ships, a source map beside it, a
`package.json` whose dev script names port 5599.

Verified: the configuration list the editor offers in a `.tsx` file is right,
and the port is read out of the project rather than guessed ---

    1. Run this file
    2. Open a browser on http://localhost:5599
    3. Attach to a browser started with --remote-debugging-port=9222
    4. Launch file
    5. Attach

Not verified: either browser configuration actually stopping. `launch` needs a
Chrome this machine does not have --- the only browser here is the one
Playwright downloaded. `attach` against that browser, started with
`--remote-debugging-port=9222` and answering on `/json/version`, sat at
`Starting adapter pwa-chrome` and never connected; the same `js-debug-adapter`
serves `pwa-node`, which stops fine, so this is the chrome side of it.

**Settled, and no longer yours to decide.** Both halves are fixed:

    browser        the configuration finds one, Playwright's included
    breakpoint     bound, and hit, at index.tsx:9 through the source map

js-debug looks for an installed Chrome and stops when it finds none. This
machine has no Chrome and a browser all the same --- Playwright downloads one
per build into its own cache --- so `browser_executable()` looks along PATH
first and falls back to the newest Playwright build, on each platform's own
cache directory. The gate drives the browser configuration for real: it serves
the fixture on the port the project's own dev script names, opens the page,
and stops inside `add()` on the line the .tsx file has, not the line the
compiled .js has.

Three things had to be true, and each one had failed silently:

    the page ran too early     document.body was null; the script needs defer
    the picker took a letter   j typed into its filter, selecting nothing
    the ex command was dropped single quotes ended the Vimscript string

All seven stop in CI as well --- python, typescript, tsx, c, cpp, rust,
julia --- once the runner was given a TypeScript compiler to build the fixture
with. Before that the TSX case skipped itself and the run went green having
debugged no browser at all, which is the failure this harness exists to
prevent: the fixture step fails now if the compiled file is not there.

---

## 49. The agent answers, checked in the editor rather than at the CLI

`agent-canary.sh` proved the agent cannot write. Nothing proved it answers:
review, explain and lookup each open a window, and a request that failed left
that window empty --- which is what a slow answer looks like too.

`check-agent.sh` drives the three flows against the configured backend and
matches on what only an answer produces:

    review     a finding carrying its line number
    explain    a panel with a title and a body
    lookup     the same, for a signature asked by name

All three answer on Claude at the context rung. It stays out of CI because it
spends real requests; it belongs beside the canary, run after touching
lua/util/agent.

The first version of the review check matched `Findings — <number>`, which is
not what the window draws --- the title carries the scope, and the number is
in the row. It failed against a review that had worked, which is the same
mistake as a gate that passes on a frame nobody looked at.

---

## 50. Startup does not depend on how big the project is

    fixture (9 files)          66.0ms  68.1ms  59.1ms
    label-studio (60000 files) 66.9ms  75.0ms

`nvim --startuptime`, headless, five runs. Nothing in this configuration walks
the project at startup: the file list is built when a picker first asks for it
and cached per root, the language servers attach on a buffer, and the git gate
is a question about one directory. A large repository costs on the first
search, which entry 46 measured, and nothing before that.

Five of fifty plugins load before the dashboard is drawn, which is what
`check-startup-plugins.sh` holds still.

---

## 51. Six debuggers stop on a runner that had none of them

The debugger gate went green in CI only after two things that both looked like
a broken debugger:

    MasonInstall … +qa      the install is asynchronous; the editor quit first
    :MasonInstall           E492, because nothing had loaded mason yet

Both left the runner without `js-debug-adapter`, so the TypeScript session
never started --- and a session that never starts draws the same frame as one
that started and did not stop. The install goes through `mason-registry` now,
waits for the binaries, and fails in its own step rather than in the gate.

What the gate prints on a failure was built for exactly this: the tail of
nvim-dap's log, and, when that log is empty, the configurations the editor
offers for the file. An empty log is a missing adapter; a short list is a
missing configuration.

---

## 52. The browser debugger, and the one machine it will not start on

**Settled. The cause was the harness, not the browser.**

Six languages stop on macOS in CI: python, typescript, c, cpp, rust, and julia
where julia is installed. The seventh, TSX in a browser, does not --- and the
reason is Chrome rather than the configuration.

What is known: the runner has Google Chrome, the configuration finds it, the
fixture is served and answers, the session starts, and js-debug logs
`js-debug/launch`. Then nothing. No CDP traffic, no bound breakpoint, and no
trace file even when one is asked for. The same commit, the same fixture and
the same keys stop at `index.tsx:9` on Linux, in CI and here.

Tried, in order: a longer wait; pinning the address to 127.0.0.1, since macOS
resolves localhost to ::1 first and nothing answered there; a profile of the
browser's own rather than the default one; serving with node after python's
http.server bound nothing at all on that runner. The first, second and fourth
were real defects and are fixed. The third changed nothing.

None of those was the reason, and the first three were fixed on the way past.
The reason was that **every Ex command the harness sent on macOS was dropped**:
the driver delivers them over RPC, that call failed on every macOS run, and the
failure went to /dev/null. So the configuration was never made headless. Chrome
opened a window on a machine with no screen, and waited.

The driver types the command at the editor when the RPC call fails --- which is
how the keys get there in the first place --- and macOS now stops in all six,
the browser case included.

The step that found it was making the harness prove it had changed anything:
the Ex command leaves a marker, and its absence is reported as what it is
rather than as a debugger that did not stop.

---

## 53. Windows: the adapters are there, and the sessions die silently

**Settled. Nothing needed from you.**

Windows has no tmux, so the driven check cannot run there at all. A headless
one now can --- `check-debuggers-headless.sh` asks nvim-dap directly, start
this configuration and stop on this line --- and it runs on Linux, macOS and
Windows alike. Six languages stop through it here.

On the Windows runner both cases fail the same way:

    python       never stopped: Run this file, session gone -- the adapter logged nothing
    typescript   never stopped: Run this file, session gone -- the adapter logged nothing

What is known: mason installs into `C:\Users\…\AppData\Local\nvim-lazyvim-data`,
the gate finds the adapters there, the configurations are offered, the session
starts and is gone by the time anything asks. nvim-dap's log has nothing in it
at all, which is what a command that never ran looks like. The likely reason
is that mason's Windows shims are `.CMD` files, and a `.CMD` is not a program
libuv can spawn without a shell --- but that is a hypothesis, not a finding.

Three things got fixed on the way to this being reportable rather than a hang:
a Git Bash path Neovim could not open (`luafile /d/a/…` is E484, which is a
hit-enter prompt, which is a headless editor that never exits), an answer that
was never flushed before the quit threw it away, and a mason directory looked
for where Windows does not keep it.

The Windows job reports rather than enforces until this is understood. The
alternative --- a red tick on every push saying the same thing --- is a tick
nobody reads.

**Since then: Python debugs on Windows.** Five defects came out of chasing it,
every one of them real and none of them visible without asking the editor what
it had been told:

    the venv had no debugpy      python -m debugpy.adapter exits 1, silently
    mason had not loaded         its bin directory is only on PATH once it has
    the shim is a .CMD           a script, not something libuv can spawn
    the adapters were overwritten LazyVim's extra writes them after this runs
    ${port} was never substituted the editor dialled a port called ${port}

The adapters are started from the programs inside mason's packages now ---
debugpy's own interpreter, and the server js-debug ships run by node --- which
is a real program on every platform.

TypeScript debugs on Windows too, after a sixth: the server was told which
port to listen on and not which address, so it took whatever `localhost`
resolves to --- ::1 first on Windows --- while the editor dialled 127.0.0.1.
A refused connection against a server that had started perfectly well.

Rust debugs there as well --- the runner's toolchain and codelldb's Windows
build agree about a program built on that machine --- so the job checks
python, typescript and rust and enforces rather than reports.

What found each of these was the same thing every time: making the check say
what the editor had been told, rather than reasoning about what it should have
been. The decisive step was starting the debug server by hand in CI, with no
editor in the picture, which ruled out node and the package in one run.

Where each platform stands:

    Linux    seven, driven through the keys and the frame, browser included
    macOS    six, driven, browser included; julia is not installed there
    Windows  four, headless, browser included; there is no tmux to drive

The headless path serves the page and starts the browser itself, which is a
few lines rather than a terminal --- so the case Windows had no way to check
at all is checked there, in a real Chrome, stopping at `index.tsx:9` through
the source map.

---

## 54. The nightly tour will not run until the stack merges

**Yours, and it resolves itself the moment the branches land.**

`harness.yml` now runs the whole feature tour on a schedule --- sixty editors
started one after another, too slow for a push and the thing most worth
knowing about a configuration that moves only when someone edits it. The
contact sheet is kept either way, so a failure can be looked at rather than
guessed at.

GitHub runs scheduled workflows from the default branch only. This one lives
on `audit-single-keys` until the stack is merged, so the schedule fires
nothing until then. Nothing to fix; it is written down so that a tour nobody
has seen running is not mistaken for a tour that passed.

---

## 55. The same frames hold on macOS

Every committed screen that needs no language server --- eleven of the
fourteen --- now draws identically on macOS and on Linux, and CI holds both to
the same files. A terminal grid turns out to be the portable thing this
harness hoped it was.

Getting there found four defects, every one of them in the harness and none in
the configuration:

    mapfile                 a bash 4 builtin; macOS ships bash 3.2
    \b \| \{n,\}            GNU sed extensions; macOS ships BSD sed
    an empty batch list     unbound under set -u on bash 3.2
    an escaped tilde        survives as a backslash on bash 3.2

The normaliser is Python now rather than sed. Porting it caught a rule that
had been read as a space and is a Nerd Font glyph: as a space it stripped
every line number on every screen, which no committed frame would have
noticed because they were all generated by the same wrong rule.

Windows draws no screens: there is no tmux to drive an editor with, which is
why the debuggers are checked there by asking nvim-dap directly instead.

---

## 56. Codex is one credential away from being verified

**Closed. You have no OpenAI subscription, so this stays proven = false.**

`M.codex` in `lua/util/agent/backends.lua` is `proven = false` --- written from
the documentation, run against nothing, because codex was never installed on
this machine. That much is still true, but the rest of the reason has moved:

    npx --yes @openai/codex@0.155.1 --help    works, no install left behind
    codex exec --sandbox read-only "say hi"    401 Unauthorized

Codex runs fine through npx, pinned to a version, with nothing persisted
afterward. What stops the canary is exactly one thing: no `OPENAI_API_KEY` and
no `codex login` session on this machine, and getting either of those is not
something to do without you --- it is your account.

You said plainly: no OpenAI subscription. That ends this one -- not a
credential to gather later, a backend nobody here can pay to verify. `codex`
stays in `backends.lua` as documentation-only, `proven = false`, and the
canary is not run against it. If that changes, the path back is exactly what
is written above: `codex login` or `OPENAI_API_KEY`, nothing else.

---

## 57. Two real bugs in the diagnostic itself, and one real flake left under it

**Not yours. Written down so the next investigation starts past this point
instead of at it.**

`lsp-parity.lua` had never asked a language server anything, on any run,
against any project, this whole session: `run-probes.sh` drove it with no
file open, so `vim.lsp.get_clients()` on the dashboard buffer was always
empty and the report was one line, `cursor: {...}`. Fixing that exposed a
second bug behind it --- `--include` placed after `--` in the `grep` that
finds a file containing the symbol, read as eight literal filenames instead
of eight flags, failing with exit 2 and no output. Both fixed; verified
against the fixture (20 real requests answered by lua_ls) and against a
5417-file real project (correctly reports no python server installed here).
Wired into CI, where it had never run either.

Chasing a Windows CI flake on the browser debugger found the same shape of
bug in `debug-headless.lua`: it read `dap.log` from `stdpath("cache")`, and
nvim-dap writes it through `stdpath("log")` (an alias for `stdpath("state")`
on current Neovim). Every "the adapter logged nothing" this script ever
printed, on every platform, was reading an empty directory --- not reporting
an empty log.

With that fixed, the real trace showed two genuine timeouts under it:
`initialize_timeout_sec` (default 4s) firing before a cold node + a real
browser launch on Windows finished the DAP handshake, and 40s of settle
being too little for the same reason. Both raised. The browser case now gets
through further each time --- `configurationDone` succeeds, telemetry sends
--- and still occasionally disconnects before the breakpoint, on Windows
only, intermittently: three of the last four Windows runs passed.

What is not fixed, and may not be fixable from here: whatever makes a real
Chrome under CI load occasionally drop the DAP connection after a correct
handshake. Nothing left to read blind for it --- the log is real now, the
timeouts are generous, and the remaining failure is a live browser under
contended CI hardware being a live browser under contended CI hardware.

**Update:** it was closer to one run in three across the next few pushes,
not one in four, which is too often to keep gating a job on. python,
typescript and rust --- the three that do not depend on a second live
process --- keep enforcing; tsx now reports without failing the job. Still
worth seeing when it fails, so it still prints.

**Update:** not Windows-only after all. The identical signature (breakpoint
verified, then the browser process exits with nothing further) showed up on
`debuggers-macos`, which runs `check-debuggers.sh` --- a different script
from the one this entry was written against, driven over real tmux keys
rather than headless, and one that had never received the flaky/failures
split above at all: every tsx mismatch there was an unconditional failure,
gating the job every time it happened to land on this. Given the same
treatment now, in `check-debuggers.sh` alongside `check-debuggers-headless.sh`.

---

## 58. The stack is ready to merge. Yours to say go.

**Needs you: an explicit go-ahead. This session's own permissions require it
for a merge, separately from anything about readiness.**

All three PRs are clean and mergeable, checked directly against GitHub right
now:

    nvim-config #3  debuggers → claude-manual       CLEAN, MERGEABLE
    nvim-config #2  claude-manual → master          CLEAN, MERGEABLE
    dotfiles    #2  audit-single-keys → main        CLEAN, MERGEABLE

CI is green on every job on every one of them. Attempting the first merge
just now was refused by this session's own permission layer, not by GitHub
and not by a defect in the branches: merging is gated for your decision
regardless of readiness, and correctly so.

The order that keeps history honest: nvim-config #3 into claude-manual,
then claude-manual into master, both as merge commits, never squashed or
rebased, exactly as asked. Then dotfiles' submodule at `neovim/.config/nvim`
--- currently pinned to `21e126b`, the commit master was at before any of
this started --- needs bumping to the new master tip, as its own commit on
`audit-single-keys` before that PR merges, so the submodule pointer and the
harness's own `CONFIG_REF: debuggers` default in `harness.yml` both move
together rather than one trailing the other.

Say go and this finishes in the order above. Nothing about it is still being
worked out.

---

## 59. What "the ladder resets when you move" actually resets on

**Not a decision. Worth knowing, found while writing the first spec for
`hint.lua`.**

The doc comment says the hint ladder "resets when you move somewhere else."
What it actually tracks is `context.here()`'s start line --- a treesitter
node's range when a parser is attached, or a plain +/-20 line window around
the cursor when there is none. Inside that window the start does not move,
so on an untyped buffer or one with no parser installed, moving the cursor a
few lines does not reset anything: the ladder only resets once the window
itself shifts, which on the fallback path is roughly a 20-line move, or on
crossing into a different function when a parser is attached.

A person using this day to day is almost always inside a real, parsed
buffer, where the reset is per-function and matches the doc comment closely.
The fallback's coarser granularity only shows up in a language with no
treesitter parser installed, or, as here, in a test harness that loads none
on purpose. Nothing to fix --- the design is "resets on a real move," and a
20-line window is a reasonable answer to "was that a real move" when there
is no syntax tree to ask instead.

---

## 60. All three CI runners already have a real browser

**Not a decision. Worth knowing, found writing browser_spec.lua.**

    ubuntu-latest    /usr/bin/google-chrome, on PATH
    macos-latest     /Applications/Google Chrome.app, an installed application
    windows-latest    an installed application under Program Files

Every runner this repository's own CI matrix uses already has a real Chrome,
each found through a different one of `util/browser.lua`'s three lookups. A
test that means to prove "nothing is found" or "the Playwright fallback is
what answers" has to neutralise PATH, `M.installed.mac`/`.win32`, and point
`PLAYWRIGHT_BROWSERS_PATH` somewhere empty, all three at once --- clearing
only PATH passed locally and failed on macOS and Windows for two entirely
different reasons before that was clear.

Consequence for `check-debuggers.sh`'s own TSX case: the browser it finds in
CI is never Playwright's --- it is the runner's own installed one, every
time. That gate has been proving something slightly different from what its
comments say since the runner images changed under it, not from anything in
this session. Worth a look, not urgent: the case still stops at a real
breakpoint through a real browser, which is the thing that actually matters.

## 61. The set -e/pipefail bare-assignment audit is closed

**Not a decision. Closing out the sweep entries 57 and 60's tail referred to.**

Two more real instances of the same bug found and fixed, both in
`dotfiles/tools/nvim-harness`:

- `check-debuggers-headless.sh:183` --- the failure-reporting branch's own
  `said=$(grep -oE '...' "$answered" | head -1)` died on pipefail exactly
  when the editor's answer matched none of the four expected phrasings ---
  inside the branch that exists to explain a failure.
- `record-stress-tour.sh:47` --- `film_in()`'s `tracked=$(git -C "$project"
  ls-files | wc -l)` died on pipefail whenever `$project` existed but was
  not a git repository, true of at least two real directories this harness
  has pointed at (`forgejo`, `keycloak`), before the SKIPPED message a few
  lines up ever got the chance to run.

Both fixed with the same `|| true` pattern as `run-probes.sh`'s two earlier
fixes, both sabotage-verified against a real non-matching answer and a real
non-git directory, both re-run against the full local gate suite
(`check-syntax.sh`, `check-debuggers-headless.sh`, `scripts/test`) before
push.

Two remaining candidates from the same grep swept and ruled safe, not this
bug class:

- `check-key-names.sh:37` --- `seen=$(tmux ... capture-pane -p | tr -d
  '\n')`. A pane always has content; `tr` never fails; a nonzero status here
  means tmux itself broke, which is a real harness fault worth aborting
  loudly on, not a normal "nothing found" outcome.
- `agent-canary.sh:203` --- `WANT=$(expected_registry)`, a shell function
  whose body is a `case`/`printf` over three fixed strings with no default
  arm. An unmatched `$RUNG` yields an empty `WANT`, not a nonzero exit ---
  nothing in the function can fail the pipefail check at all.

All 23 `pipefail`-using scripts in `tools/nvim-harness` have now been swept
for this pattern. Four real instances found and fixed across this session
(`run-probes.sh` x2, plus the two above); none outstanding.

## 62. Harpoon and yanky write real state outside anything this harness isolates

**Not blocking, handled at the point it actually mattered. Worth knowing.**

`nvim-drive.sh` and `film.sh` isolate `XDG_CONFIG_HOME` (which config loads)
and, with `-I`, shada (cursor history, marks). Neither isolates
`XDG_DATA_HOME`, and two plugins persist real, meaningful state there:
harpoon's pinned-file list and yanky's yank-ring sqlite database. The first
draft of `harpoon-list.keys`/`yank-ring.keys` proved it directly — the
captured frame showed 45 yank-history entries and a fourth pinned file
neither `.keys` file ever touched, real state left over from unrelated
earlier runs on this machine.

Fixed at the two call sites that render it on screen: both `.keys` files now
open with `ex:lua require("harpoon"):list():clear()` /
`ex:lua require("yanky.history").clear()` before acting, so the frame shows
only what the test itself did. Checked every other committed `.expected`
file for the same risk — `dashboard.expected` is the one that could plausibly
show a real recent-files list, and it does not; the dashboard menu here is
static labels, not a live list. Nothing else screen-tested touches a
plugin whose whole feature is "remember something across runs."

Left as a real, general gap rather than fixed at the driver level:
`nvim-drive.sh`/`film.sh` isolating `XDG_DATA_HOME` wholesale would also
isolate the installed `lazy`/`mason` directories, forcing every driven run to
reinstall plugins and language servers rather than reusing what is already
there — real cost for a problem that, checked directly above, does not
currently reach any committed frame. Worth a proper fix (redirect the
directory, symlink `lazy`/`mason` back in for speed) if a third
persistent-state plugin becomes a screen test; not before.

Also worth noting: this closes the plan's surface B. All twelve rendered
flows it enumerated (dashboard, find-file, grep-ranking, capabilities,
explorer, settings, the rung picker, hover, both dismiss paths, harpoon,
yank-ring, diagnostics) now have a committed golden frame.

## 63. The stress tour is recorded and published

**Not a decision. Closes the plan's last open item.**

`record-stress-tour.sh` against `label-studio` (5,611 tracked files),
`crun` (277) and `migml` (736): six real flows (grep ranking, file finding,
the capability picker in a large project, the same grep in a C project, a
docs-heavy project's filter cycling, `:checkhealth dotfiles`), plus probe
timings on all three projects. Every probe stayed under `run-probes.sh`'s
500ms budget; nothing reported a startup error.

A recording existed from two days earlier but predated today's fixes to
`record-stress-tour.sh` itself (entry 61) and was never built into a page,
so it was replaced rather than reused. Built with `build-tour.py` and
published: https://claude.ai/artifact/PMMjt3WddNQp1ymEwboToq

Together with entry 62, the plan in `vectorized-popping-summit.md` is now
complete end to end: the shell gates, the unit specs, the golden frames, and
the recorded, published tour.

---

## 64. Orphaned Neovim processes, found while the stress tour recorded

**Not a decision. Real resource leak, fixed.**

Three real Neovim processes were found alive at a process listing, hours
after the harness runs that started them: reparented to init, each still
holding the RPC socket (`--listen /tmp/nvim-drive-*.sock -i NONE`) of a run
whose tmux server and socket file were both long gone. `nvim-drive.sh`'s and
`film.sh`'s cleanup only ever asked tmux to kill its server -- which sends
SIGHUP to the pane, and Neovim does not reliably go down with it, headless
or not.

Fixed in both scripts: right after the tmux server is killed, a process
match against this run's own RPC socket path takes down anything left
listening on it. The path is unique per process
(`nvim-drive-$$.sock` / `nvim-film-$$.sock`), so the match can only ever
land on the one Neovim this run itself started -- guarded against an unset
`$RPC` matching everything, the same shape as the existing socket-file
removal's guard. Verified: killed the three real orphans by hand, confirmed
a single driven run leaves nothing behind, then ran the full local screen
suite (13 real driven runs) and confirmed a process listing shows nothing
afterward.

Worth a line for the record given this session's security scope (arbitrary
execution / secrets that may leak): every orphan found was inert, holding
only its own RPC socket with nothing connected to it, not attached to a
terminal, not running anything -- a resource leak, not an execution or data
exposure. Logged here because "careful with memory/storage, cleanup
enforced" is explicit standing instruction, not because anything was found
running that should not have been.

---

## 65. hover.keys flaked once, on content rather than on timing

**Not a decision. Worth watching, not yet worth acting on.**

The same commit ran through `gates` (ubuntu) twice in parallel -- once as a
push-triggered run, once as the paired pull-request run. The push run
matched all 14 screens; the pull-request run reported `1 of 14 screens
differ`, and it was `hover`: expected
`function M.add(a: number, b: number)` / `-> number`, drawn
`function M.add(a, b)` with no return type. Real content, not an empty pane
--- lua_ls answered, just with less resolved than usual.

`hover.keys` already carries the fix from the entry this session's summary
calls "the hover screen's longer wait": ten attempts, each a fresh editor
and a fresh lua_ls, fifteen seconds settle on the last one. A partial-type
hover surviving all ten attempts on one of two identical parallel runs
suggests the ten attempts are not independent draws the way that fix assumed
--- if whatever slows lua_ls down on a loaded runner is a property of the
runner for the whole job rather than of one attempt, ten retries buy nothing.

Not decoupled from the gate the way tsx was (entry 57): this is one
occurrence, not the one-in-three rate that justified that for a
browser-dependent case, and hover is core editor behaviour with no second
live process to blame. If it recurs, the fix is probably watching for a
resolved signature specifically (retry until the type annotations appear, not
just until any hover appears) rather than more attempts of the same kind.

---

## 66. Julia verified working, for the first time this session

**Not a decision. Closes a gap in the original requirement.**

"Debuggers for Python, Rust, TypeScript, TSX, C, C++, Julia" is the standing
requirement, and Julia had been "skipped, no julia on PATH or in mason"
every single run this whole session -- never once actually verified,
despite the config carrying a full `dap.adapters.julia` (fixture, mise.toml
pinning 1.11.9, `DebugAdapter.jl` already installed into it).

The gap was environmental, not a config bug: mise here is activate-based
(`mise activate` in shell rc, `shims_on_path: no`), and this Bash tool's own
environment does not source that rc, so `julia` was never actually on its
PATH regardless of what a real interactive shell -- or CI with mise properly
set up -- would see. Confirmed by putting mise's shim directory on PATH by
hand: `check-debuggers.sh -f julia` stops at `main.jl:2` like every other
language. All seven required languages are now confirmed working on this
machine, at least once, for real.

CI does not install Julia and is not expected to (`harness.yml` has no
mise/Julia setup step) -- matches the harness's existing "skip languages the
machine does not have" design, same as codelldb or js-debug would skip on a
runner missing them. Not proposing to add it; a full Julia toolchain per CI
run is a real cost for a language nothing else here depends on, and the
config's own behaviour (skip cleanly, say why) is already the point.

---

## 67. The Julia leak was the small version of a much bigger one

**Not a decision. A second real resource leak, found chasing the first.**

Verifying Julia (entry 66) left three real `julia ... DebugAdapter.DebugSession`
processes running after their test runs ended. Chasing why turned up
something much larger: `nvim-dap` starts a **server**-type adapter's
executable detached, in its own process group, deliberately, so the adapter
can survive a Neovim that crashes -- which also means the harness's own
`tmux kill-server` (entry 64's fix) never reaches it either. Julia is one
example. `js-debug`'s `pwa-chrome` adapter is a much bigger one: every tsx
debugger run left an entire headless Chrome tree behind -- the adapter's own
node server plus Chrome's zygote, gpu-process, network and storage
utilities, and every renderer, eight to ten processes per run. Five full
trees were found still running, one from the previous day, all rooted at
init. **Over 4GB combined**, cleaned up by hand before the fix below went in.

Fixed generally in both `nvim-drive.sh` and `film.sh` rather than as another
per-adapter special case: `cleanup()` now asks tmux for the pane's PID
before killing the server, walks its full descendant tree (`ps -A -o
pid=,ppid=` piped through an awk that builds the parent-to-children map and
walks it -- not `--ppid`, which is GNU-only and would not run on
`debuggers-macos`), and after `kill-server` runs, signals anything from that
snapshot still alive. Covers Julia and js-debug today without knowing either
by name, and whatever server-type adapter comes next.

Writing the fix reproduced the exact bug this session has now found and
fixed four times: `kill -0 "$pid" 2>/dev/null && kill -KILL "$pid"
2>/dev/null` as a bare statement, under `set -Eeuo pipefail`, ends the whole
`cleanup()` function the moment `kill -0` reports the process already
gone -- which is the good outcome, the one this code exists to handle.
Caught by the same symptom as every previous instance: `nvim-drive.sh`
started reporting "the driver gave up" on a plain, working find-file case,
in a script the change never should have touched the exit code of.
Rewritten as a proper `if`. Verified: all seven debuggers still stop where
told, the full local screen suite (13 driven runs) still passes, and a
process listing shows nothing left over after either.

---

## 68. The same leak, in the other debugger script

**Not a decision. Closes entry 67 out properly -- it only covered half the
harness.**

`check-debuggers.sh` (tmux-driven) got the fix in entry 67. Its counterpart,
`check-debuggers-headless.sh`, spawns Neovim directly, with no tmux pane to
walk -- and has the identical leak for the identical reason: a graceful
`qa!`/`cq!` never runs nvim-dap's session-close cleanup, since that hook is
scoped to the DAP session closing, not to Neovim quitting. This is the
script Windows and the ubuntu `gates` job actually run, so both were
accumulating a julia process or a full Chrome tree per tsx/julia case,
inside the one CI run that ran them -- not visible the way the dev-machine
leak was (each job is a fresh runner, thrown away after), but real
resource pressure on whatever ran later in that same job.

Fixed with a single sweep in the script's own EXIT trap, run once after all
cases finish: find anything now parented to init whose command line names
`DebugAdapter.DebugSession` or `dapDebugServer.js`, walk its descendant tree
the same way entry 67's fix does, kill what is found. Verified against the
real leak, filtered to tsx+julia specifically and then the full seven-
language run: both stop where told, exit 0, nothing left over either time.

---

## 69. python flaked once, on debuggers-macos, unrelated to anything in flight

**Not a decision. Worth watching, not yet worth acting on -- same call as
entry 65.**

The push-triggered run right after entry 68's fix failed `debuggers-macos`
on python: debugpy answered ("Telemetry" for both ptvsd and debugpy), the
editor listed real launch configurations for the file, and the session
never stopped at the breakpoint. The pull-request run on the identical
commit passed every debugger, python included. That fix only touched
`check-debuggers-headless.sh`, which `debuggers-macos` does not run at all
(it runs `check-debuggers.sh`, the tmux-driven one), so this is not a
regression from it.

python is one of the three languages this session has deliberately kept
enforcing rather than given tsx's flaky treatment (entry 57), on the
reasoning that it does not depend on a second live process the way a real
browser does. One occurrence, contradicted by the parallel run on the same
commit, is not the recurring rate that justified that treatment for tsx --
so left enforcing, logged rather than acted on, same call as entry 65's
hover flake. Worth a look if it recurs.

---

## 70. Not every named directory under ~/Documents/projects is a clone

**Not a decision. A caution for whoever runs a probe against a new project
next.**

Went looking for a fourth real project to stress-probe, beyond the three
this session's tour already used (`label-studio`, `crun`, `migml`).
`~/Documents/projects/forgejo` reported `tracked_files 0`, `files_on_disk
18` -- nothing like the real forgejo. `ls` showed why: it holds candidate
onboarding CSVs and a message log, not a forgejo checkout, just a directory
that happens to share the name. `keycloak` (1 tracked file), `wordpress` (0)
and `temporal` (15) are the same shape -- near-empty, not the real project.

Stopped there rather than probing further names blind: this session's
security scope is explicitly about secrets and untrusted execution, and a
directory that turns out to hold someone's personal data is exactly the
kind of thing worth not running an unfamiliar tool against without knowing
that first. The probe output itself was harmless (file counts and keymap
timings, nothing from the files' content), and was deleted rather than
kept. `jupyter` (87 tracked files) is real but small; nothing else checked
turned out to be a substantial clone. The three already in the stress tour
remain the right set for this kind of test on this machine.
