---
name: add-action
description: How to add, change or remove a user action in nvim-diff (a keymap in the file panel, the diff panes or the conflict panes, or a click in the options bar) — which files to touch, how keymaps are declared and attached, and what docs and tests to update. Use when adding a feature the user triggers, rebinding a default key, or removing an action.
---

# Adding a user action

An action is a named function the user triggers by a key or a click. Four places, always all four:

| Step | File | What |
|------|------|------|
| 1 | `lua/nvim-diff/actions.lua` | `A.<name> = { desc = "...", fn = function(s, ctx) ... end }` |
| 2 | `lua/nvim-diff/config.lua`  | default key in `keymaps.panel`, `keymaps.view` or `keymaps.conflict` |
| 3 | `README.md` + `doc/nvim-diff.txt` | the keys table / `nvim-diff-keymaps` section |
| 4 | `tests/<area>_spec.lua`     | a test calling the action through `H.run(name)` |

## 1. The action

```lua
-- lua/nvim-diff/actions.lua
A.stage_all = {
    desc = "Stage all changes",
    fn = function(s)
        local ok, err = git.stage_all(s.root)
        if not ok then
            notify(err or "git failed", ERROR)
        end
        view().refresh({ sync = true })
    end,
}
```

- `A` is the local action table (`M.actions`). `fn(s, ctx)`: `s` is the live session (see
  `view.lua`); `ctx.in_panel` is true from the panel and `ctx.item` is the panel item under the
  cursor (may be nil). Use `targets(s, ctx)` to get the entries a file/folder/section item covers.
- Git work goes through `git.lua` only. After anything that changes the repo, call
  `view().refresh({ sync = true })` so the panel is right before the key handler returns.
- Destructive work asks first (`confirm()`) and backs up content (`git.backup()`).
- Add the action name to the list in `doc/nvim-diff.txt` (`nvim-diff-config`).
- The `desc` is shown by `g?` (help.lua) and must say what happens, in a few words.

## 2. The key

```lua
-- lua/nvim-diff/config.lua, inside defaults.keymaps
panel = {
    ["S"] = "stage_all",
},
```

- Map lhs -> action name. Users disable a key with `["S"] = false` in `setup()`.
- `panel` keys live in the panel buffer, `view` keys in every diff pane, `conflict` keys only in
  the conflict layout (on top of `view` keys).
- Check the key against the other maps of the same scope and against Vim keys that matter in diff
  mode (`]c`, `[c`, `do`, `dp`). Use `nowait`-friendly keys: no key may be a prefix of another
  key in the same scope.
- Keymaps are attached by `view.lua` when a buffer enters the view and removed when it leaves;
  never call `vim.keymap.set` anywhere else.

## Options-bar items (clicks)

The panel winbar is built in `panel.lua` (`options_bar()`). Each item is
`%<id>@v:lua.__nvim_diff_click@<label>%X`; `__nvim_diff_click(id)` maps `id` to an action name.
Add the id to the `CLICK` table in `panel.lua` and keep the bar under the panel width (35).

## Removing an action

Delete the entry in `actions.lua`, its keys in `config.lua`, its doc lines and its tests.
Then `make check`.
