---
name: reference-code
description: How to use the upstream diffview.nvim and codediff.nvim clones in .reference/ when designing or debugging a nvim-diff feature — where each one implements the panel, staging, conflicts, whitespace and refresh, what may be copied (license rules) and how to re-clone them. Use when the user says "like diffview" or "like codediff", or when you need to know how they solved something.
---

# Reference code

`.reference/` is git-ignored. If it is missing:

```sh
mkdir -p .reference
git clone --depth 1 https://github.com/sindrets/diffview.nvim .reference/diffview.nvim
git clone --depth 1 https://github.com/esmuellert/codediff.nvim .reference/codediff.nvim
```

## License: what may be copied

| Project       | License | Rule |
|---------------|---------|------|
| diffview.nvim | GPL-3.0 | **Read only.** Copy behavior, look, key choices, never code. Write ours from scratch. |
| codediff.nvim | MIT     | Code may be copied/adapted. Add a line to README.md "Credits" naming the file. |

## Where things are

| Topic | diffview.nvim (`lua/diffview/...`) | codediff.nvim (`lua/codediff/...`) |
|-------|------------------------------------|------------------------------------|
| Panel look | `scene/views/diff/render.lua` (sections, tree, stats), `hl.lua` (groups, links) | `ui/explorer/render.lua`, `ui/explorer/nodes.lua` |
| Panel keymaps / defaults | `config.lua` (`keymaps.file_panel`, `keymaps.view`) | `config.lua` (`keymaps.explorer`, `keymaps.view`) |
| Stage / unstage / restore | `actions.lua` (`toggle_stage_entry`, `restore_entry`), `vcs/adapters/git/init.lua` | `ui/explorer/actions.lua`, `core/git/changes.lua` |
| Status parsing | `vcs/adapters/git/init.lua` (`--name-status` diffs, `show_untracked`, `add_files`, `reset_files`) | `core/git/` |
| Side-by-side windows | `scene/layouts/diff_2*.lua`, `scene/window.lua` | `ui/view/side_by_side/` |
| Conflict tool | `scene/layouts/diff_3*.lua`, `vcs/utils.lua` (`parse_conflicts`), `actions.lua` (`conflict_choose*`) | `ui/conflict/` (result-pane design, not the one we use) |
| Ignore trim whitespace | — (only 'diffopt' iwhite) | `config.lua` `diff.ignore_trim_whitespace`, done in its C library |
| Live refresh | `watch_index` (index file only) | `ui/refresh/` (controller), `core/watcher/` (external binary + polling) |

Our designs differ on purpose: native diff mode (not codediff's C engine), a Lua 'diffexpr' for
whitespace, libuv fs events instead of an external watcher. See `docs/architecture.md`.
