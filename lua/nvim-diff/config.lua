-- Defaults and setup() merge. Keymaps map a key to an action name from actions.lua; a key set
-- to false in setup() is disabled.

local M = {}

---@class NvimDiffConfig
M.defaults = {
    -- Start with leading/trailing whitespace changes ignored (VS Code's default); `W` toggles.
    ignore_trim_whitespace = true,
    -- Show whole files. false: fold the unchanged lines, like plain diff mode; `zF` toggles.
    full_file = true,
    -- Wrap long lines in the diff windows, padding the shorter side so both stay aligned.
    wrap = true,
    panel = {
        width = 35,
        listing_style = "tree", -- "tree" | "list"
        flatten_dirs = true, -- show "a/b/c" instead of nested single-child folders
    },
    live_refresh = {
        enabled = true,
        debounce_ms = 150,
        poll_ms = 2000, -- Linux has no recursive file watching: poll `git status` instead
    },
    use_icons = true, -- file icons from nvim-web-devicons or mini.icons, when installed
    icons = {
        folder_closed = "\u{e5ff}",
        folder_open = "\u{e5fe}",
        fold_closed = "\u{f460}",
        fold_open = "\u{f47c}",
        done = "\u{2713}",
    },
    keymaps = {
        -- File panel buffer
        panel = {
            ["<CR>"] = "select",
            ["o"] = "select",
            ["l"] = "select",
            ["<LeftRelease>"] = "click",
            ["-"] = "toggle_stage",
            ["s"] = "toggle_stage",
            ["S"] = "stage_all",
            ["U"] = "unstage_all",
            ["X"] = "restore",
            ["R"] = "refresh",
            ["i"] = "toggle_listing_style",
            ["f"] = "toggle_flatten_dirs",
            ["za"] = "toggle_fold",
            ["zo"] = "open_fold",
            ["zc"] = "close_fold",
            ["h"] = "close_fold",
            ["zR"] = "open_all_folds",
            ["zM"] = "close_all_folds",
            ["<Tab>"] = "next_file",
            ["<S-Tab>"] = "prev_file",
            ["[F"] = "first_file",
            ["]F"] = "last_file",
            ["W"] = "toggle_whitespace",
            ["zF"] = "toggle_full_file",
            ["gf"] = "goto_file",
            ["<leader>e"] = "focus_panel",
            ["<leader>b"] = "toggle_panel",
            ["g?"] = "help",
            ["q"] = "close",
        },
        -- Every diff pane
        view = {
            ["<Tab>"] = "next_file",
            ["<S-Tab>"] = "prev_file",
            ["[F"] = "first_file",
            ["]F"] = "last_file",
            ["-"] = "toggle_stage",
            ["W"] = "toggle_whitespace",
            ["zF"] = "toggle_full_file",
            ["gf"] = "goto_file",
            ["<leader>e"] = "focus_panel",
            ["<leader>b"] = "toggle_panel",
            ["g?"] = "help",
            ["q"] = "close",
        },
        -- Diff panes of the conflict layout (added to the view keys)
        conflict = {
            ["]x"] = "next_conflict",
            ["[x"] = "prev_conflict",
            ["<leader>co"] = "choose_ours",
            ["<leader>ct"] = "choose_theirs",
            ["<leader>cb"] = "choose_base",
            ["<leader>ca"] = "choose_all",
            ["dx"] = "choose_none",
            ["<leader>cO"] = "choose_all_ours",
            ["<leader>cT"] = "choose_all_theirs",
            ["<leader>cB"] = "choose_all_base",
            ["<leader>cA"] = "choose_all_all",
            ["dX"] = "choose_all_none",
            ["2do"] = "diffget_ours",
            ["3do"] = "diffget_theirs",
        },
    },
}

---@type NvimDiffConfig
M.options = vim.deepcopy(M.defaults)

---@param opts? table
function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
