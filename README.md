# nvim-diff

Review your changes in Neovim like VS Code's Source Control view: the changed files on the left
(Conflicts / Changes / Staged changes), a side-by-side diff on the right. Built for reviewing
what a coding agent just wrote: the view refreshes by itself while the agent works.

- Stage / unstage a file, a folder or everything; restore (discard) with a confirmation
- Side-by-side diff on Neovim's diff mode: `]c` `[c` `do` `dp` work, the right side is the real
  file (also for fully staged files), so you can fix things in place
- "Ignore leading/trailing whitespace" toggle (VS Code semantics), on by default
- Whole files by default, or only the changed parts (folded unchanged lines)
- Live refresh, clickable options bar, 3-way conflict tool (OURS ∣ file ∣ THEIRS)
- `nvim diff` from anywhere in a repo opens the view; closing it quits Neovim

Neovim 0.11+ and git. No dependencies (file icons from nvim-web-devicons or mini.icons if installed).

## Install

lazy.nvim. Don't lazy-load it: `nvim diff` needs the startup hook, and the plugin only loads its
modules when you open the view.

```lua
{ "ilianusss/nvim-diff", lazy = false, opts = {} }
-- or a local clone:
{ dir = "~/Desktop/nvim-diff", name = "nvim-diff", lazy = false, opts = {} }
```

## Use

```sh
nvim diff          # in a git repo (any subfolder)
```

or `:NvimDiff` (new tab), `:NvimDiffClose`, `:NvimDiffRefresh`.

| Where       | Keys | Action |
|-------------|------|--------|
| panel       | `<CR>` `o` `l` click | open the diff (on a folder: fold/unfold) |
| panel       | `-` `s` | stage / unstage file, folder or section |
| panel       | `S` / `U` | stage all / unstage all |
| panel       | `X` | restore (discard) file, folder or section — asks first |
| panel       | `i` / `f` | tree ↔ list / flatten folders |
| panel       | `za` `zo` `zc` `h` `zR` `zM` | folds |
| panel       | `R` | refresh |
| panel, diff | `<Tab>` `<S-Tab>` `[F` `]F` | next / previous / first / last file |
| panel, diff | `W` | toggle "ignore leading/trailing whitespace" |
| panel, diff | `zF` | toggle full file / only the changed parts (folds) |
| panel, diff | `gf` | open the file itself |
| panel, diff | `<leader>e` / `<leader>b` | focus / toggle the panel |
| panel, diff | `g?` / `q` | help / close |
| diff        | `-` | stage / unstage the current file |
| conflict    | `]x` `[x` | next / previous conflict |
| conflict    | `<leader>co` `ct` `cb` `ca`, `dx` | take ours / theirs / base / all / none |
| conflict    | `<leader>cO` `cT` `cB` `cA`, `dX` | same, for the whole file |
| conflict    | `2do` / `3do` | get the hunk from ours / theirs |

To resolve a conflict: pick versions, `:w`, then `-` to stage the file.

## Options (defaults)

```lua
require("nvim-diff").setup({
    ignore_trim_whitespace = true, -- start with whitespace-only changes hidden (W toggles)
    full_file = true, -- whole files; false folds unchanged lines like plain diff mode (zF toggles)
    panel = { width = 35, listing_style = "tree", flatten_dirs = true },
    live_refresh = { enabled = true, debounce_ms = 150, poll_ms = 2000 }, -- poll_ms: Linux only
    use_icons = true,
    keymaps = { panel = {}, view = {}, conflict = {} }, -- { ["X"] = false } disables, { ["<C-s>"] = "toggle_stage" } adds
})
```

Full docs: `:help nvim-diff`.

## Credits

The UI and keymaps follow [diffview.nvim](https://github.com/sindrets/diffview.nvim) (no code
reused). The trimmed-whitespace option and live refresh come from ideas in
[codediff.nvim](https://github.com/esmuellert/codediff.nvim).
