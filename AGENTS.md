# nvim-diff

A light Neovim plugin to review changes like VS Code's Source Control view: a file panel on the
left (Conflicts / Changes / Staged changes), a side-by-side diff on the right, staging from the
panel, a VS Code-style "ignore leading/trailing whitespace" toggle, live refresh while an agent
writes files, and a 3-way conflict tool. `nvim diff` in a repo opens it.

The look and keymaps follow diffview.nvim; some ideas (whitespace trimming, live refresh) come
from codediff.nvim. Neovim 0.11+ and git, no plugin dependencies. Keep it light: features beyond
the list in README.md need a reason.

- `README.md`: user-facing summary (install, keys, options). Keep in sync with `doc/nvim-diff.txt`.
- `ARCHITECTURE.md`: how data flows, what each diff side shows, the whitespace design.
- `doc/` holds only the vimdoc (Neovim reads `doc/*.txt` for `:help`); developer docs live at the root.

## Layout

```
plugin/nvim-diff.lua    :NvimDiff* commands + the `nvim diff` startup hook. Must stay cheap
lua/nvim-diff/
  init.lua              public API: setup(), open(), close(), refresh()
  config.lua            defaults + setup() merge; keymaps map a key to an action name
  actions.lua           every user action: name -> { fn, desc }. Keymaps and help read it
  view.lua              the session (one tabpage): layout, selection, keymap attach/detach, close
  diff.lua              buffers for each diff side (real file or nvim-diff:// scratch), diff windows
  panel.lua             panel buffer: render, line -> item map, options bar (winbar) clicks
  tree.lua              entries -> directory tree (flatten, sort, folder status)
  git.lua               EVERY git call: status parsing, show, stage/unstage/restore
  whitespace.lua        trim-aware 'diffexpr' and its install/restore
  watch.lua             live refresh: fs events / polling / autocmds, debounced
  align.lua             padding under the shorter side of wrapped lines, so both sides stay aligned
  conflict.lua          conflict-marker parser and the choose ours/theirs/base/all/none edits
  hl.lua                NvimDiff* highlight groups (default = true, relinked on ColorScheme)
  help.lua              g? floating help built from actions.lua descs
doc/nvim-diff.txt       vimdoc
tests/                  headless specs (tests/run.lua runner, tests/helpers.lua temp repos)
.github/                CI (lint + tests on Linux and macOS, Neovim v0.11.0 and stable), templates, CODEOWNERS
.reference/             upstream diffview.nvim + codediff.nvim, git-ignored, read-only
```

## Conventions

- Lua 5.1/LuaJIT, formatted with stylua (`.stylua.toml`: 4 spaces, 120 columns, double quotes).
  `---@class`/`---@param` annotations on public functions and data shapes.
- **Only `git.lua` runs git** (through `vim.system`, `git -C <root>`). Other modules get parsed data.
- **Session state lives in `view.lua`** (one session at a time). Other modules are stateless or
  take the session as an argument.
- **Keymaps are buffer-local** and only exist while a buffer is shown in the view. A key that the
  buffer already had (an LSP `<leader>ca`) is saved on attach and restored on detach.
- **New user action** = an entry in `actions.lua` + a default key in `config.lua` + a line in
  README.md and `doc/nvim-diff.txt` + a test. See `.claude/skills/add-action/SKILL.md`.
- **Global options we touch are restored**: 'diffexpr' is ours only while the nvim-diff tab is
  current (`whitespace.lua`). Never leave other global state behind after `close()`.
- Scratch buffers are named `nvim-diff://<label>/<path>`, `buftype=nofile`, not modifiable.
  The working-tree side is always the real file buffer, so editing and LSP work there.
- Destructive actions (restore/discard) ask for confirmation and back up the file content with
  `git hash-object -w` first. If the backup fails, they discard nothing.
- No plugin dependencies. Optional integrations (nvim-web-devicons, mini.icons) go through `pcall`.

## License rule

The repo is MIT. `.reference/diffview.nvim` is **GPL-3.0: read it for behavior, never copy its
code** (not even "small" functions). `.reference/codediff.nvim` is MIT: copying is allowed with a
credit line in README.md's Credits section. See `.claude/skills/reference-code/SKILL.md`.

## Verify a change

```sh
make test                 # all specs (headless, temp git repos); make test FILTER=git for one file
make smoke                # real `nvim diff` startup in a temp repo
make lint                 # stylua --check (stylua from PATH or Mason)
```

The oldest supported Neovim (0.11.0) differs in places (see the comments that name 0.11): CI runs
both it and the latest release. Run another build locally with `make test NVIM=/path/to/nvim`.

## Releasing

Users install with `version = "*"` (lazy.nvim follows the latest semver tag), so a change reaches
them only with a new tag. `main` is protected: every change lands through a pull request,
squash-merged once CI is green. After the merge, tag `main`:

```sh
git tag -a vX.Y.Z -m "nvim-diff vX.Y.Z" && git push origin vX.Y.Z
gh release create vX.Y.Z --title vX.Y.Z --generate-notes
```

Patch for fixes and docs, minor for new features or options, major for breaking keymaps/options.

How to write specs: `.claude/skills/testing/SKILL.md`. Headless gotchas:
- A headless script that opens windows must always end with `qa!` (wrap the work in `pcall`),
  or Neovim keeps running.
- Async work (`vim.system` callbacks, timers, fs events) only progresses inside `vim.wait()`.
- `nvim -l` never fires `VimEnter`: the `nvim diff` hook is covered by `make smoke` instead.
