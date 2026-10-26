---
name: testing
description: How to write and run nvim-diff's headless tests — the tests/run.lua runner, temp git repos from tests/helpers.lua, waiting for async refreshes, testing diff highlighting and the `nvim diff` startup smoke test. Use when adding or fixing a test, when a spec fails or hangs, or before claiming a change works.
---

# Testing nvim-diff

```sh
make test                  # every tests/*_spec.lua
make test FILTER=conflict  # only spec files whose name contains "conflict"
make smoke                 # tests/smoke.sh: real `nvim diff` startup in a temp repo
make check                 # lint + test + smoke
```

The runner is `nvim --clean -l tests/run.lua`: no user config, this repo on 'runtimepath',
`plugin/nvim-diff.lua` sourced. It exits 1 if any test fails.

## Writing a spec

`tests/<area>_spec.lua` is a plain script; the runner provides `test`, `eq`, `ok` as globals and
resets the editor between tests (closes the session, `tabonly`, `only`, wipes buffers):

```lua
local H = require("tests.helpers")
local git = require("nvim-diff.git")

test("modified file is listed in Changes", function()
    local repo = H.repo({ ["a.txt"] = "one\n" }) -- temp repo with an initial commit
    repo:write("a.txt", "two\n")
    local status = git.status(repo.root) -- sync when no callback
    eq(#status.working, 1)
    eq(status.working[1].status, "M")
end)
```

- `H.repo(files?)`: new temp repo (user/email set, gpg signing off). With `files` it commits them.
  Methods: `repo:write(path, text)`, `repo:read(path)`, `repo:exists(path)`,
  `repo:git(args...)` (asserts success, returns stdout), `repo:try_git(args...)` (stdout, exit
  code, no assert), `repo:commit(msg)`, `repo:conflict(path, { diff3? })` (a real merge conflict).
- `H.open(repo)`: opens the view on that repo and returns the session.
- `H.wait(cond, ms)`: `vim.wait` with a failure message; use it for anything async (refresh after
  an fs event, `git.status` with a callback).
- `H.panel_lines(session)` returns the panel text; `H.find_line(session, pattern)` its line number;
  `H.panel_cursor(session, pattern)` focuses the panel on that line.
- `H.run(name)` runs an action as if its key was pressed in the current window.
- `H.diff_names(session)` buffer names of the diff windows, left to right (`nvim-diff://INDEX/a.txt`,
  or the absolute path of a real file); `H.changed_lines(win)` the lines diff mode highlights.
- Diff highlighting: check `vim.fn.diff_hlID(lnum, 1) ~= 0` inside `nvim_win_call(win, ...)`;
  `vim.fn.diff_filler(lnum)` for filler lines.

## Rules

- Every test makes its own repo; never depend on test order.
- Do not test through `vim.fn.feedkeys` when an action can be called with
  `require("nvim-diff.actions").run(name, ctx)`: feedkeys needs the typeahead to be processed and
  makes tests flaky.
- Never leave a process running: a spec that opens windows must not prompt. Stub `vim.fn.confirm`
  in tests that trigger confirmations: `H.stub_confirm(1)` (1 = first button). To assert on
  messages, `H.stub_notify(list, vim.log.levels.WARN)` collects them. Both are undone between tests.
- `:checkhealth` runs in a child Neovim (`tests/health_spec.lua`): in-process, a second
  `:checkhealth` after a failed test crashed `nvim -l` 0.12.5.
- What only happens in a real startup (VimEnter, swap files: `bufload()` raises E325 there but
  not under `nvim -l`) goes in `tests/smoke.sh`, which uses its own swap directory.
- Run the suite on the oldest supported Neovim too: `make test NVIM=/path/to/nvim-0.11.0` (CI
  does it on every pull request).
- A hanging test usually means a missing `H.wait` or a prompt; run `make test FILTER=<file>`
  and add prints, which `nvim -l` writes to stdout.
