# Architecture

## Data flow

```
git.status(root)                    porcelain v2 + numstat (3 git processes, run in parallel)
  -> Status { conflicting, working, staged }   lists of Entry
  -> view.session.status
       -> panel.render(session)     tree.build() per section -> lines + extmarks + line->item map
       -> view.select(entry)        diff.sides(entry) -> buffers -> diff windows (diffthis)
watch (fs events / poll / autocmds) -> debounce -> view.refresh() -> git.status() -> same path
actions.lua (keymaps, clicks)       -> git.stage/unstage/restore -> view.refresh()
```

`view.refresh()` re-renders only when the new `Status` differs from the old one. It keeps the
panel cursor on the same item, reloads scratch sides whose blob hash changed, runs `:checktime`
on the real file buffer, then `:diffupdate`.

## Entry

```lua
---@class NvimDiffEntry
---@field kind "conflicting"|"working"|"staged"   panel section
---@field path string          repo-relative, "/" separated (new path for renames)
---@field old_path? string     source path of a rename/copy
---@field status string        letter shown in the panel: M A D R C T U ?
---@field xy string            raw porcelain XY (conflicts: "UU", "AA", "DU", ...)
---@field hashes table         blob hashes from porcelain v2 (head/index or base/ours/theirs)
---@field stats? { additions: integer, deletions: integer }   nil for binary/untracked
---@field binary? boolean
---@field submodule? boolean
---@field conflicts? integer   number of conflict regions in the working file
```

A file that is both staged and modified appears twice, once in `staged` and once in `working`.

## What each side shows

| Entry                     | Left                | Right                      |
|---------------------------|---------------------|----------------------------|
| working: modified         | index `:path`       | working-tree file (real)   |
| working: untracked `?`    | empty               | working-tree file (real)   |
| working: deleted          | index `:path`       | empty                      |
| staged: modified/type     | `HEAD:path`         | index `:path`              |
| staged: added             | empty               | index `:path`              |
| staged: deleted           | `HEAD:path`         | empty                      |
| staged: renamed/copied    | `HEAD:old_path`     | index `:path`              |
| conflicting (3 panes)     | OURS `:2:path`  ∣  working-tree file (real, with markers)  ∣  THEIRS `:3:path` |

- No HEAD yet (fresh repo): the left side of staged entries is empty.
- Binary files and submodules get a one-line placeholder on both sides.
- A missing conflict stage (modify/delete conflicts) is an empty pane.

Scratch sides are `nvim-diff://<label>/<path>` buffers (`buftype=nofile`, not modifiable,
filetype from the path). The real file side is `bufadd(path)`, so edits, `:w` and LSP work.

## Whitespace ("ignore leading/trailing whitespace")

`diffopt` has no flag for this: `iwhite` is `diff -b`, which ignores changes in the amount of
whitespace but still flags added indentation. So when the toggle is on, `whitespace.lua` sets
'diffexpr' to a Lua function that:

1. reads `v:fname_in` / `v:fname_new`,
2. trims every line (and lowercases it with `icase`),
3. runs `vim.text.diff(a, b, { result_type = "indices", ... })` with `iwhite`, `iwhiteall`,
   `iwhiteeol`, `iblank`, `algorithm:` and `indent-heuristic` mapped from 'diffopt',
4. writes the hunks as an ed-style diff (`1a2`, `3,4c3`, `5d4` + `<`/`---`/`>` lines) to `v:fname_out`.

Line numbers are unchanged by trimming, so the hunks apply to the untrimmed buffers. `inline:char`
and `linematch` still work with a 'diffexpr' (tested in `tests/whitespace_spec.lua`).

'diffexpr' is global: it is set on `TabEnter` of the nvim-diff tab and the previous value is put
back on `TabLeave` and `close()`.

## Live refresh

- macOS and Windows: one recursive `uv.fs_event` on the repo root, plus a non-recursive one on
  the git dir when it lives outside the root (worktrees).
- Linux (no recursive fs events in libuv): a `git status` poll every `live_refresh.poll_ms`.
- Always: `FocusGained`, `BufWritePost`, `TabEnter` of the view, and after every action.
- Events are debounced (`live_refresh.debounce_ms`) and paths under `.git/objects`, `.git/logs`
  and `*.lock` files are ignored. While the view's tab is not current, events only mark it dirty;
  it refreshes on `TabEnter`. Only one refresh runs at a time; a request during a run queues
  exactly one more.

## Conflicts

The conflict layout has three diff windows: OURS ∣ LOCAL ∣ THEIRS. `conflict.parse(lines)` finds
regions (`<<<<<<<`, optional `|||||||` base, `=======`, `>>>>>>>`). The choose actions replace the
region under the cursor in the LOCAL buffer (or every region with the "whole file" variants).
The user writes the file and stages it with `-`, which runs `git add` and resolves the conflict.
Staging asks first while conflict markers remain.

## `nvim diff`

`plugin/nvim-diff.lua` checks at startup whether the only argument is `diff` and no file named
`diff` exists. On `VimEnter` it wipes the `diff` buffer and opens the view in the current tab
with `quit_on_close = true`: closing the view runs `confirm qa`.
