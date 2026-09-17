# Neovim configuration

Built on [LazyVim](https://lazyvim.org). This replaced a fork of
kickstart.nvim, whose single 1138-line `init.lua` had to be hand-merged with
upstream every time either side changed.

```
init.lua                 entry point, nothing else
lua/config/lazy.lua      bootstrap, LazyVim, which extras are enabled
lua/config/options.lua   options that differ from LazyVim's defaults
lua/config/keymaps.lua   keymaps LazyVim does not already provide
lua/plugins/picker.lua   snacks.picker, search filters, tree view
lua/plugins/lsp.lua      language server settings
lua/plugins/format.lua   formatter choices
lua/plugins/editor.lua   yanky, persistence, origami, diffview, guess-indent
lua/util/search.lua      the search filter presets
```

## Searching without drowning in documentation

In an openspec repository most text is prose, so a grep for a symbol returns
far more specification than code. The filter is therefore a mode you change
while the picker is open, not a decision made before opening it.

| Key          | Effect                                              |
| ------------ | --------------------------------------------------- |
| `<leader>sg` | Grep, documentation excluded. The usual case.       |
| `<leader>/`  | The same thing, on a key that needs no prefix.      |
| `<leader>sw` | Grep the word under the cursor, documentation excluded. |
| `<a-d>`      | Cycle: code → all → docs → any project presets.     |
| `<a-p>`      | Choose a preset from a list.                        |
| `<a-e>`      | Restrict to file extensions, e.g. `lua,ts`.         |
| `<a-G>`      | Restrict to a path glob. Prefix with `!` to exclude. |
| `<c-g>`      | Switch between live ripgrep and fuzzy matching.     |
| `<a-r>`      | Switch between regex and fixed-string matching.     |

The active preset is shown in the picker title, so there is never a doubt
about what is being searched.

There is deliberately one grep key rather than one per filter. Which files to
search is a decision made while reading results, not before opening the picker,
and `<leader>s` already carries thirty-five bindings without three more that
`<a-d>` covers between them.

`<leader>?` searches the editor itself: every capability this config adds, with
the key that runs it, matched on name, description and key alike. Searching
"conflict" finds the merge view without knowing it is `<leader>gm`.

### Flat list or tree

The picker list is the flat view. `<c-t>` sends the same results to Trouble,
which groups them by file, giving a tree with a count per file. Nothing is
re-run; it is the same result set shown differently.

## Language servers

Nothing is installed automatically. A server attaches when the project can
already provide it, and is disabled quietly when nothing can:

1. an executable inside the project, which wins, because it is the version the
   project pins. Searched for in `.venv/bin`, `venv/bin`, `.direnv/*/bin`,
   `node_modules/.bin`, `.yarn/bin`, `vendor/bin`, `.bundle/bin`, `bin`,
   `.tools/bin` and `result/bin`.
2. an executable on `PATH`.

How it got there is not this configuration's business. apt, uv, npm, mise,
Mason, or built by hand, all look the same from here and all work. Installing
the tools is your job; the editor's job is to use what it finds and to say what
it could not find.

So a project selects its own servers by what it installs, and the same
configuration behaves differently in each checkout without being edited. In a
Python project with a virtualenv the servers come out of `.venv/bin` whether or
not the environment is activated.

A filetype whose server is configured but unavailable warns once, because an
editor with no language server looks exactly like one with a working server
until a feature turns out to be missing. `:checkhealth dotfiles` lists every
server, whether it resolved, and where from.

`:Mason` still works for installing by hand. It is simply never invoked on your
behalf.

## Per-project settings

`exrc` is on, so Neovim reads a `.nvim.lua` from the directory it starts in.
Neovim asks once whether to trust that file and remembers the answer; editing
the file asks again.

```lua
-- .nvim.lua
vim.g.search_filters = {
  -- What counts as documentation in this project.
  docs = { "adr/**", "*.rst" },

  -- Extra presets, appended to the cycle.
  presets = {
    { name = "api only", desc = "the public API surface", globs = { "src/api/**" } },
  },
}
```

For language server and formatter settings per project, the `util.project`
extra also reads `.neoconf.json` and `.vscode/settings.json`, so a project
already tuned for VS Code needs no second copy of its settings.

## Verifying a change

Changes here are checked by driving a real Neovim and looking at what it drew,
rather than by reading the config and hoping. See
`dotfiles/tools/nvim-harness/README.md`.
