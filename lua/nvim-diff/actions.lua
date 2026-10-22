-- Every user action, by name. Keymaps (config.keymaps) and options-bar clicks call M.run(name);
-- help.lua lists the descs.

local conflict = require("nvim-diff.conflict")
local git = require("nvim-diff.git")
local tree = require("nvim-diff.tree")

local M = {}

---@class NvimDiffActionCtx
---@field in_panel? boolean triggered from the panel window
---@field item? NvimDiffItem panel item under the cursor

---@class NvimDiffAction
---@field desc string
---@field fn fun(s: NvimDiffSession, ctx: NvimDiffActionCtx)

---@type table<string, NvimDiffAction>
local A = {}
M.actions = A

local ERROR, WARN = vim.log.levels.ERROR, vim.log.levels.WARN

local function view()
    return require("nvim-diff.view")
end

local function panel()
    return require("nvim-diff.panel")
end

local function diff()
    return require("nvim-diff.diff")
end

local function notify(msg, level)
    vim.notify("nvim-diff: " .. msg, level or vim.log.levels.INFO)
end

---@param s NvimDiffSession
---@return NvimDiffActionCtx
local function context(s)
    local win = vim.api.nvim_get_current_win()
    if win ~= s.panel_win then
        return {}
    end
    return { in_panel = true, item = s.items[vim.api.nvim_win_get_cursor(win)[1]] }
end

---Runs an action on the open session (no-op without one).
---@param name string
---@param ctx? NvimDiffActionCtx default: computed from the current window
function M.run(name, ctx)
    local s = view().session
    local action = A[name]
    if s and action then
        action.fn(s, ctx or context(s))
    end
end

---Entries an action applies to: the panel item (file, folder or section) or the shown file.
---@return NvimDiffEntry[] entries
---@return string? section
local function targets(s, ctx)
    if ctx.in_panel then
        local item = ctx.item
        if not item then
            return {}, nil
        elseif item.type == "file" then
            return { item.entry }, item.section
        elseif item.type == "dir" then
            return tree.entries(item.node.children), item.section
        end
        return vim.list_extend({}, s.status[item.section]), item.section
    end
    if s.current then
        return { s.current }, s.current.kind
    end
    return {}, nil
end

local function paths(entries, with_old)
    local out = {}
    for _, e in ipairs(entries) do
        out[#out + 1] = e.path
        if with_old and e.old_path then
            out[#out + 1] = e.old_path
        end
    end
    return out
end

---Loaded buffer of a repo file, if any.
local function file_buf(s, path)
    local abs = s.root .. "/" .. path
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buf) == abs then
            return buf
        end
    end
end

local function confirm(msg, choice)
    return vim.fn.confirm(msg, "&" .. choice .. "\n&Cancel", 2) == 1
end

--------------------------------------------------------------------------------
-- Panel / selection
--------------------------------------------------------------------------------

local function fold_key(item)
    return item.section .. ":" .. item.node.path
end

local function open_item(s, item)
    if not item then
        return
    end
    if item.type == "file" then
        view().select(item.entry)
    elseif item.type == "dir" then
        s.collapsed[fold_key(item)] = not s.collapsed[fold_key(item)] or nil
        panel().render(s)
    end
end

A.select = {
    desc = "Open the diff (folder: fold / unfold)",
    fn = function(s, ctx)
        if ctx.in_panel then
            open_item(s, ctx.item)
        end
    end,
}

A.click = {
    desc = "Open the diff under the mouse (folder: fold / unfold)",
    fn = function(s)
        local m = vim.fn.getmousepos()
        if m.winid == s.panel_win and m.line > 0 then
            open_item(s, s.items[m.line])
        end
    end,
}

---@param s NvimDiffSession
---@param ctx NvimDiffActionCtx
---@param collapse boolean|"toggle"
local function set_fold(s, ctx, collapse)
    local item = ctx.item
    if not (ctx.in_panel and item) then
        return
    end
    local key
    if item.type == "dir" then
        key = fold_key(item)
    elseif item.type == "file" and collapse == true then
        -- On a file, "close fold" folds its folder (diffview's `h`)
        local parent = vim.fs.dirname(item.entry.path)
        if parent == "." or s.listing_style == "list" then
            return
        end
        key = item.section .. ":" .. parent
    else
        return
    end
    if collapse == "toggle" then
        collapse = not s.collapsed[key]
    end
    s.collapsed[key] = collapse or nil
    panel().render(s)
    if item.type == "file" then
        local lnum = panel().find(s, "dir:" .. key)
        if lnum then
            vim.api.nvim_win_set_cursor(s.panel_win, { lnum, 0 })
        end
    end
end

A.toggle_fold = {
    desc = "Fold / unfold the folder",
    fn = function(s, ctx)
        set_fold(s, ctx, "toggle")
    end,
}

A.open_fold = {
    desc = "Unfold the folder",
    fn = function(s, ctx)
        set_fold(s, ctx, false)
    end,
}

A.close_fold = {
    desc = "Fold the folder (on a file: its folder)",
    fn = function(s, ctx)
        set_fold(s, ctx, true)
    end,
}

A.open_all_folds = {
    desc = "Unfold all folders",
    fn = function(s)
        s.collapsed = {}
        panel().render(s)
    end,
}

A.close_all_folds = {
    desc = "Fold all folders",
    fn = function(s)
        for _, sec in ipairs(panel().SECTIONS) do
            for _, dir in ipairs(tree.dirs(panel().nodes(s, sec.kind))) do
                s.collapsed[sec.kind .. ":" .. dir.path] = true
            end
        end
        panel().render(s)
    end,
}

A.listing_style = {
    desc = "Toggle tree / list",
    fn = function(s)
        s.listing_style = s.listing_style == "tree" and "list" or "tree"
        panel().render(s)
    end,
}

A.toggle_flatten_dirs = {
    desc = "Toggle flattening single-child folders",
    fn = function(s)
        s.flatten_dirs = not s.flatten_dirs
        panel().render(s)
    end,
}

A.refresh = {
    desc = "Refresh",
    fn = function()
        view().refresh({ sync = true })
    end,
}

A.next_file = {
    desc = "Next file",
    fn = function(s)
        view().select_relative(s, 1)
    end,
}

A.prev_file = {
    desc = "Previous file",
    fn = function(s)
        view().select_relative(s, -1)
    end,
}

A.first_file = {
    desc = "First file",
    fn = function(s)
        view().select_relative(s, "first")
    end,
}

A.last_file = {
    desc = "Last file",
    fn = function(s)
        view().select_relative(s, "last")
    end,
}

--------------------------------------------------------------------------------
-- Git
--------------------------------------------------------------------------------

A.toggle_stage = {
    desc = "Stage / unstage (file, folder or section)",
    fn = function(s, ctx)
        local entries, section = targets(s, ctx)
        if #entries == 0 then
            return
        end
        local unsaved = {}
        for _, e in ipairs(entries) do
            local buf = file_buf(s, e.path)
            if buf and vim.bo[buf].modified then
                unsaved[#unsaved + 1] = e.path
            end
        end
        if
            #unsaved > 0
            and not confirm(("Unsaved changes in %s. Stage the saved version?"):format(unsaved[1]), "Stage")
        then
            return
        end

        local ok, err
        if section == "staged" then
            ok, err = git.unstage(s.root, paths(entries, true))
        else
            if section == "conflicting" then
                local left = 0
                for _, e in ipairs(entries) do
                    left = left + git.count_conflicts(s.root .. "/" .. e.path)
                end
                if left > 0 and not confirm(("%d conflict(s) not resolved. Stage anyway?"):format(left), "Stage") then
                    return
                end
            end
            ok, err = git.stage(s.root, paths(entries))
        end
        if not ok then
            notify(err or "git failed", ERROR)
        end
        view().refresh({ sync = true })
    end,
}

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

A.unstage_all = {
    desc = "Unstage all changes",
    fn = function(s)
        local ok, err = git.unstage_all(s.root)
        if not ok then
            notify(err or "git failed", ERROR)
        end
        view().refresh({ sync = true })
    end,
}

A.restore = {
    desc = "Restore: discard the changes (file, folder or section; asks first)",
    fn = function(s, ctx)
        local entries, section = targets(s, ctx)
        entries = vim.tbl_filter(function(e)
            return e.kind ~= "conflicting"
        end, entries)
        if #entries == 0 then
            return
        end
        local untracked = #vim.tbl_filter(function(e)
            return e.status == "?"
        end, entries)
        local what = #entries == 1 and entries[1].path or (#entries .. " files")
        local msg
        if section == "staged" then
            msg = ("Discard staged and unstaged changes to %s?"):format(what)
        elseif #entries == 1 and untracked == 1 then
            msg = ("Delete untracked file %s?"):format(what)
        else
            msg = ("Discard changes to %s?"):format(what)
            if untracked > 0 then
                msg = msg .. (" %d untracked file(s) will be deleted."):format(untracked)
            end
        end
        if not confirm(msg, "Discard") then
            return
        end

        local backups, gone = {}, {}
        for _, e in ipairs(entries) do
            local hash = git.backup(s.root, e.path)
            local ok, err = git.restore(s.root, e)
            if not ok then
                notify(("%s: %s"):format(e.path, err or "failed"), ERROR)
            else
                if hash then
                    backups[#backups + 1] = ("  %s: git cat-file -p %s"):format(e.path, hash:sub(1, 12))
                end
                local buf = file_buf(s, e.path)
                if buf and vim.api.nvim_buf_is_loaded(buf) then
                    if vim.uv.fs_stat(s.root .. "/" .. e.path) then
                        vim.cmd("checktime " .. buf)
                    else
                        gone[#gone + 1] = buf
                    end
                end
            end
        end
        view().refresh({ sync = true })
        -- Buffers of deleted files: drop them unless they are edited or still on screen
        for _, buf in ipairs(gone) do
            if vim.api.nvim_buf_is_valid(buf) and not vim.bo[buf].modified and #vim.fn.win_findbuf(buf) == 0 then
                pcall(vim.api.nvim_buf_delete, buf, { force = true })
            end
        end
        if #backups > 0 then
            notify("discarded. To recover:\n" .. table.concat(backups, "\n"))
        end
    end,
}

--------------------------------------------------------------------------------
-- View
--------------------------------------------------------------------------------

A.toggle_whitespace = {
    desc = "Toggle ignoring leading/trailing whitespace changes",
    fn = function(s)
        view().set_ignore_whitespace(s, not s.ignore_ws)
    end,
}

A.goto_file = {
    desc = "Open the file itself",
    fn = function(s, ctx)
        local entry
        if ctx.in_panel then
            entry = ctx.item and ctx.item.type == "file" and ctx.item.entry
        else
            entry = s.current
        end
        if not entry then
            return
        end
        local abs = s.root .. "/" .. entry.path
        if not vim.uv.fs_stat(abs) then
            notify(entry.path .. " does not exist in the working tree", WARN)
            return
        end
        local lnum
        if not ctx.in_panel and vim.api.nvim_buf_get_name(0) == abs then
            lnum = vim.api.nvim_win_get_cursor(0)[1]
        end
        if s.prev_tab and vim.api.nvim_tabpage_is_valid(s.prev_tab) then
            vim.api.nvim_set_current_tabpage(s.prev_tab)
            vim.cmd.edit(vim.fn.fnameescape(abs))
        else
            vim.cmd.tabedit(vim.fn.fnameescape(abs))
        end
        if lnum then
            pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
        end
    end,
}

A.focus_panel = {
    desc = "Focus the file panel",
    fn = function(s)
        view().open_panel(s, true)
    end,
}

A.toggle_panel = {
    desc = "Show / hide the file panel",
    fn = function(s)
        if s.panel_win and vim.api.nvim_win_is_valid(s.panel_win) then
            local main = diff().main_win(s)
            if vim.api.nvim_get_current_win() == s.panel_win and main and vim.api.nvim_win_is_valid(main) then
                vim.api.nvim_set_current_win(main)
            end
            view().close_panel(s)
        else
            view().open_panel(s, false)
        end
    end,
}

A.help = {
    desc = "Show the keymaps",
    fn = function(s, ctx)
        local scopes
        if ctx.in_panel then
            scopes = { "panel" }
        elseif s.current and s.current.kind == "conflicting" then
            scopes = { "view", "conflict" }
        else
            scopes = { "view" }
        end
        require("nvim-diff.help").open(scopes)
    end,
}

A.close = {
    desc = "Close the view",
    fn = function()
        view().close()
    end,
}

--------------------------------------------------------------------------------
-- Conflicts (3-way layout: OURS | LOCAL | THEIRS)
--------------------------------------------------------------------------------

---LOCAL window and its cursor line. cursorbind keeps it aligned with the pane the user is in.
local function local_side(s)
    local win = #s.wins == 3 and s.wins[2]
    if win and vim.api.nvim_win_is_valid(win) then
        return win, vim.api.nvim_win_get_buf(win), vim.api.nvim_win_get_cursor(win)[1]
    end
end

local LABELS = { ours = "OURS", theirs = "THEIRS", base = "BASE", all = "all the versions", none = "none" }

for which, label in pairs(LABELS) do
    A["choose_" .. which] = {
        desc = ("Conflict under the cursor: take %s"):format(label),
        fn = function(s)
            local win, buf, lnum = local_side(s)
            if not win then
                return
            end
            local first, err = conflict.choose(buf, lnum, which)
            if not first then
                notify(err, WARN)
                return
            end
            vim.api.nvim_win_set_cursor(win, { math.min(first, vim.api.nvim_buf_line_count(buf)), 0 })
            diff().update(s)
        end,
    }
    A["choose_all_" .. which] = {
        desc = ("Every conflict of the file: take %s"):format(label),
        fn = function(s)
            local win, buf = local_side(s)
            if not win then
                return
            end
            local _, err = conflict.choose_all(buf, which)
            if err then
                notify(err, WARN)
            end
            diff().update(s)
        end,
    }
end

local function jump_conflict(s, dir)
    local win, buf, lnum = local_side(s)
    if not win then
        return
    end
    local target = conflict.jump_target(buf, lnum, dir)
    if not target then
        notify("no conflict markers left", WARN)
        return
    end
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_cursor(win, { target, 0 })
    vim.cmd("normal! zz")
end

A.next_conflict = {
    desc = "Next conflict",
    fn = function(s)
        jump_conflict(s, 1)
    end,
}

A.prev_conflict = {
    desc = "Previous conflict",
    fn = function(s)
        jump_conflict(s, -1)
    end,
}

local function diffget(s, from)
    local win = local_side(s)
    local src = s.wins[from]
    if not (win and src and vim.api.nvim_win_is_valid(src)) then
        return
    end
    vim.api.nvim_win_call(win, function()
        vim.cmd("diffget " .. vim.api.nvim_win_get_buf(src))
    end)
end

A.diffget_ours = {
    desc = "Get the hunk from OURS",
    fn = function(s)
        diffget(s, 1)
    end,
}

A.diffget_theirs = {
    desc = "Get the hunk from THEIRS",
    fn = function(s)
        diffget(s, 3)
    end,
}

return M
