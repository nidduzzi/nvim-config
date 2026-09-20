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
