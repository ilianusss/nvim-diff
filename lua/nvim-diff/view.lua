-- The review session: one tabpage with the file panel and the diff windows. All mutable state of
-- the plugin lives in M.session.

local align = require("nvim-diff.align")
local config = require("nvim-diff.config")
local diff = require("nvim-diff.diff")
local git = require("nvim-diff.git")
local hl = require("nvim-diff.hl")
local panel = require("nvim-diff.panel")
local whitespace = require("nvim-diff.whitespace")

local M = {}

---@class NvimDiffSession
---@field root string
---@field gitdir string
---@field tab integer
---@field prev_tab? integer tabpage `gf` opens files in
---@field panel_buf integer
---@field panel_win? integer nil while the panel is hidden
---@field wins integer[] diff windows, left to right (2, or 3 for conflicts)
---@field sides? NvimDiffSide[] what the diff windows show
---@field status NvimDiffStatus
---@field current? NvimDiffEntry entry shown in the diff windows
---@field items table<integer, NvimDiffItem> panel line -> item
---@field collapsed table<string, boolean> "<section>:<dir path>" -> folded
---@field listing_style "tree"|"list"
---@field flatten_dirs boolean
---@field ignore_ws boolean
---@field full_file boolean whole files, or only the changed parts (folds)
---@field quit_on_close boolean
---@field scratch table<string, integer> scratch buffer name -> bufnr
---@field scratch_spec table<integer, string> scratch bufnr -> blob spec it shows
---@field attached table<integer, table> bufnr -> { scopes, keys, saved, diagnostics }
---@field watcher? NvimDiffWatcher
---@field augroup integer
---@field dirty? boolean repo changed while the tab was not current
---@field refreshing? boolean
---@field refresh_queued? boolean
---@field generation? integer bumped by every refresh request
---@field loaded table<integer, boolean> file buffers the view loaded (unloaded again on close)

---@type NvimDiffSession?
M.session = nil

local EMPTY_STATUS = { has_head = false, conflicting = {}, working = {}, staged = {} }

--------------------------------------------------------------------------------
-- Buffer-local keymaps
--------------------------------------------------------------------------------

local function detach(s, buf)
    local a = s.attached[buf]
    if not a then
        return
    end
    s.attached[buf] = nil
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    for _, lhs in ipairs(a.keys) do
        pcall(vim.keymap.del, "n", lhs, { buffer = buf })
    end
    vim.api.nvim_buf_call(buf, function()
        for _, prev in pairs(a.saved) do
            pcall(vim.fn.mapset, "n", false, prev)
        end
    end)
    if a.diagnostics ~= nil then
        vim.diagnostic.enable(a.diagnostics, { bufnr = buf })
    end
end

---@param s NvimDiffSession
---@param buf integer
---@param scopes string[] keymap scopes from config.keymaps, applied in order
local function attach(s, buf, scopes)
    local id = table.concat(scopes, ",")
    if s.attached[buf] and s.attached[buf].scopes == id then
        return
    end
    detach(s, buf)
    local actions = require("nvim-diff.actions")
    local maps = {}
    for _, scope in ipairs(scopes) do
        for lhs, name in pairs(config.options.keymaps[scope] or {}) do
            maps[lhs] = name
        end
    end
    local a = { scopes = id, keys = {}, saved = {} }
    vim.api.nvim_buf_call(buf, function()
        for lhs, name in pairs(maps) do
            local action = name and actions.actions[name]
            if action then
                local prev = vim.fn.maparg(lhs, "n", false, true)
                if prev.buffer == 1 then
                    a.saved[lhs] = prev
                end
                vim.keymap.set("n", lhs, function()
                    actions.run(name)
                end, { buffer = buf, nowait = true, silent = true, desc = "nvim-diff: " .. action.desc })
                a.keys[#a.keys + 1] = lhs
            elseif name then
                vim.notify(("nvim-diff: unknown action %q for %s"):format(name, lhs), vim.log.levels.WARN)
            end
        end
    end)
    if vim.tbl_contains(scopes, "conflict") and vim.bo[buf].buftype == "" then
        a.diagnostics = vim.diagnostic.is_enabled({ bufnr = buf })
        vim.diagnostic.enable(false, { bufnr = buf })
    end
    s.attached[buf] = a
end

--------------------------------------------------------------------------------
-- Panel window
--------------------------------------------------------------------------------

---@param s NvimDiffSession
---@param enter? boolean
function M.open_panel(s, enter)
    if s.panel_win and vim.api.nvim_win_is_valid(s.panel_win) then
        if enter then
            vim.api.nvim_set_current_win(s.panel_win)
        end
        return
    end
    s.panel_win = vim.api.nvim_open_win(s.panel_buf, enter or false, {
        split = "left",
        win = -1,
        width = config.options.panel.width,
    })
    panel.setup_win(s.panel_win)
    panel.render(s)
    diff.equalize(s)
end

---@param s NvimDiffSession
function M.close_panel(s)
    if s.panel_win and vim.api.nvim_win_is_valid(s.panel_win) and #s.wins > 0 then
        vim.api.nvim_win_close(s.panel_win, false)
    end
    s.panel_win = nil
    diff.equalize(s)
end

--------------------------------------------------------------------------------
-- Selection
--------------------------------------------------------------------------------

---@param st NvimDiffStatus
---@param kind string
---@param path string
---@return NvimDiffEntry?
local function find_entry(st, kind, path)
    for _, e in ipairs(st[kind] or {}) do
        if e.path == path then
            return e
        end
    end
end

---Shows `entry` in the diff windows.
---@param entry NvimDiffEntry
function M.select(entry)
    local s = M.session
    if not s then
        return
    end
    s.current = entry
    local old = vim.tbl_keys(s.attached)
    local bufs = diff.show(s, entry)
    local scopes = entry.kind == "conflicting" and { "view", "conflict" } or { "view" }
    local keep = { [s.panel_buf] = true }
    for _, buf in ipairs(bufs) do
        attach(s, buf, scopes)
        keep[buf] = true
    end
    for _, buf in ipairs(old) do
        if not keep[buf] then
            detach(s, buf)
        end
    end
    panel.render(s)
end

---Selects the next / previous / first / last entry in panel order (wraps around).
---@param s NvimDiffSession
---@param dir 1|-1|"first"|"last"
function M.select_relative(s, dir)
    local list = panel.ordered_entries(s)
    if #list == 0 then
        return
    end
    local idx
    if dir == "first" then
        idx = 1
    elseif dir == "last" then
        idx = #list
    else
        local cur = 0
        for i, e in ipairs(list) do
            if s.current and e.kind == s.current.kind and e.path == s.current.path then
                cur = i
                break
            end
        end
        if cur == 0 then
            idx = dir > 0 and 1 or #list
        else
            idx = (cur - 1 + dir) % #list + 1
        end
    end
    M.select(list[idx])
    panel.focus_entry(s, list[idx])
end

local function first_entry(st)
    return st.conflicting[1] or st.working[1] or st.staged[1]
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

---Applies a new status: re-renders the panel when something changed and keeps the diff on the
---same file (following it to another section when it moved, e.g. after staging).
---@param s NvimDiffSession
---@param st NvimDiffStatus
local function apply_status(s, st)
    local changed = not vim.deep_equal(s.status, st)
    -- Position of the shown file in the old panel order, to land nearby if it disappears
    local old_index
    if s.current then
        for i, e in ipairs(panel.ordered_entries(s)) do
            if e.kind == s.current.kind and e.path == s.current.path then
                old_index = i
                break
            end
        end
    end
    s.status = st
    local cur = s.current
    if not cur then
        local first = first_entry(st)
        if first then
            M.select(first)
        elseif changed then
            panel.render(s)
        end
        return
    end

    local same = find_entry(st, cur.kind, cur.path)
    if same then
        s.current = same
        if same.status ~= cur.status or same.binary ~= cur.binary then
            M.select(same)
            return
        end
        -- The real file is reloaded every time (an agent may rewrite it without changing the
        -- status); git blobs only when their hash changed.
        diff.reload(s, not vim.deep_equal(same.hashes, cur.hashes))
        if changed then
            panel.render(s)
        end
        return
    end

    -- The file moved section (staged, unstaged, resolved) or disappeared (restored)
    for _, kind in ipairs({ "staged", "working", "conflicting" }) do
        local moved = find_entry(st, kind, cur.path)
        if moved then
            M.select(moved)
            return
        end
    end
    local list = panel.ordered_entries(s)
    if #list > 0 then
        local nearest = list[math.min(old_index or 1, #list)]
        M.select(nearest)
        panel.focus_entry(s, nearest)
    else
        s.current = nil
        panel.render(s)
    end
end

---Re-reads the git status. Async by default; `{ sync = true }` after actions so the UI is
---updated before the key handler returns.
---@param opts? { sync?: boolean }
function M.refresh(opts)
    local s = M.session
    if not s then
        return
    end
    -- Every request bumps the generation: an async result that started before a newer request
    -- (e.g. a sync refresh after staging) is stale and dropped.
    s.generation = (s.generation or 0) + 1
    local generation = s.generation
    if opts and opts.sync then
        local st = git.status(s.root)
        if st then
            apply_status(s, st)
        end
        return
    end
    if s.refreshing then
        s.refresh_queued = true
        return
    end
    s.refreshing = true
    git.status(s.root, function(st)
        s.refreshing = false
        if M.session ~= s then
            return
        end
        if st and s.generation == generation then
            apply_status(s, st)
        end
        if s.refresh_queued then
            s.refresh_queued = false
            M.refresh()
        end
    end)
end

local function on_repo_change()
    local s = M.session
    if not s then
        return
    end
    if vim.api.nvim_get_current_tabpage() ~= s.tab then
        s.dirty = true
        return
    end
    M.refresh()
end

--------------------------------------------------------------------------------
-- Whitespace
--------------------------------------------------------------------------------

---@param s NvimDiffSession
---@param ignore boolean
function M.set_ignore_whitespace(s, ignore)
    s.ignore_ws = ignore
    if vim.api.nvim_get_current_tabpage() == s.tab then
        whitespace.apply(ignore)
    end
    diff.update(s)
    panel.render(s)
end

---@param s NvimDiffSession
---@param full boolean
function M.set_full_file(s, full)
    s.full_file = full
    diff.apply_folds(s)
    align.apply(s)
    panel.render(s)
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------

local function teardown(s)
    if M.session ~= s then
        return
    end
    M.session = nil
    pcall(vim.api.nvim_del_augroup_by_id, s.augroup)
    if s.watcher then
        s.watcher.stop()
    end
    whitespace.apply(false)
    align.clear()
    for buf in pairs(s.attached) do
        detach(s, buf)
    end
end

local function wipe_buffers(s)
    for _, buf in pairs(s.scratch) do
        if vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
    if vim.api.nvim_buf_is_valid(s.panel_buf) then
        pcall(vim.api.nvim_buf_delete, s.panel_buf, { force = true })
    end
    -- Files the view loaded go away again, unless edited or on screen elsewhere
    for buf in pairs(s.loaded) do
        if
            vim.api.nvim_buf_is_valid(buf)
            and not vim.bo[buf].modified
            and not vim.bo[buf].buflisted
            and #vim.fn.win_findbuf(buf) == 0
        then
            pcall(vim.api.nvim_buf_delete, buf, {})
        end
    end
end

local function setup_autocmds(s)
    local group = s.augroup
    vim.api.nvim_create_autocmd("TabEnter", {
        group = group,
        callback = function()
            if vim.api.nvim_get_current_tabpage() ~= s.tab then
                return
            end
            whitespace.apply(s.ignore_ws)
            diff.update(s)
            if s.dirty then
                s.dirty = false
                M.refresh()
            end
        end,
    })
    vim.api.nvim_create_autocmd("TabLeave", {
        group = group,
        callback = function()
            if vim.api.nvim_get_current_tabpage() == s.tab then
                whitespace.apply(false)
            end
        end,
    })
    vim.api.nvim_create_autocmd("TabClosed", {
        group = group,
        callback = function()
            -- Neovim 0.11 runs TabClosed while the closed tabpage is still valid: check on the next tick
            vim.schedule(function()
                if M.session == s and not vim.api.nvim_tabpage_is_valid(s.tab) then
                    teardown(s)
                    wipe_buffers(s)
                end
            end)
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(ev)
            if tonumber(ev.match) == s.panel_win then
                s.panel_win = nil
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "FocusGained", "BufWritePost" }, {
        group = group,
        callback = function()
            if s.watcher then
                s.watcher.trigger()
            else
                on_repo_change()
            end
        end,
    })
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = hl.setup })
    -- Wrapped lines change height with the text and the window width. Deferred: computing the
    -- padding reads the diff, which can update it and fire DiffUpdated again.
    vim.api.nvim_create_autocmd({ "DiffUpdated", "WinResized" }, {
        group = group,
        callback = function()
            if vim.api.nvim_get_current_tabpage() ~= s.tab then
                return
            end
            vim.schedule(function()
                if M.session == s then
                    align.apply(s)
                end
            end)
        end,
    })
end

---@class NvimDiffOpenOpts
---@field path? string a path inside the repo (default: cwd)
---@field current_tab? boolean build the layout in the current tab instead of a new one
---@field quit_on_close? boolean closing the view quits Neovim (`nvim diff`)

---@param opts? NvimDiffOpenOpts
---@return NvimDiffSession?
function M.open(opts)
    opts = opts or {}
    local repo, err = git.repo(opts.path or vim.fn.getcwd())
    if not repo then
        vim.notify(
            "nvim-diff: not in a git repository" .. (err and err ~= "" and (" (" .. err .. ")") or ""),
            vim.log.levels.ERROR
        )
        return nil
    end

    local s = M.session
    if s and not vim.api.nvim_tabpage_is_valid(s.tab) then
        -- Its tab was just closed (`:tabclose | NvimDiff`): TabClosed cleans up on the next tick, too
        -- late for this open, whose panel buffer would clash with the old one's name.
        teardown(s)
        wipe_buffers(s)
    elseif s then
        if s.root == repo.root or s.quit_on_close then
            vim.api.nvim_set_current_tabpage(s.tab)
            M.refresh()
            return s
        end
        M.close() -- another repo: replace the view
    end
    hl.setup()

    local prev_tab = vim.api.nvim_get_current_tabpage()
    if opts.current_tab then
        vim.cmd("silent! only")
    else
        vim.cmd("tabnew")
    end
    local o = config.options
    s = {
        root = repo.root,
        gitdir = repo.gitdir,
        tab = vim.api.nvim_get_current_tabpage(),
        prev_tab = not opts.current_tab and prev_tab or nil,
        panel_buf = panel.create_buf(),
        wins = { vim.api.nvim_get_current_win() },
        status = git.status(repo.root) or EMPTY_STATUS,
        items = {},
        collapsed = {},
        listing_style = o.panel.listing_style,
        flatten_dirs = o.panel.flatten_dirs,
        ignore_ws = o.ignore_trim_whitespace,
        full_file = o.full_file,
        quit_on_close = opts.quit_on_close or false,
        scratch = {},
        scratch_spec = {},
        attached = {},
        loaded = {},
        augroup = vim.api.nvim_create_augroup("NvimDiffSession", { clear = true }),
    }
    M.session = s

    attach(s, s.panel_buf, { "panel" })
    whitespace.apply(s.ignore_ws)
    if o.live_refresh.enabled then
        s.watcher = require("nvim-diff.watch").start(s.root, s.gitdir, o.live_refresh, on_repo_change)
    end
    setup_autocmds(s)

    local entry = first_entry(s.status)
    if entry then
        M.select(entry)
    else
        local placeholder = diff.side_buf(s, { type = "placeholder", path = "", label = "", text = "No changes" })
        vim.api.nvim_win_set_buf(s.wins[1], placeholder)
    end
    M.open_panel(s, true)
    if entry then
        panel.focus_entry(s, entry)
    end
    return s
end

---Closes the view (quits Neovim when it was opened by `nvim diff`).
function M.close()
    local s = M.session
    if not s then
        return
    end
    if s.quit_on_close then
        vim.cmd("confirm qall")
        return
    end
    teardown(s)
    if vim.api.nvim_tabpage_is_valid(s.tab) then
        if #vim.api.nvim_list_tabpages() == 1 then
            vim.cmd("tabnew")
        end
        vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(s.tab))
    end
    wipe_buffers(s)
    if s.prev_tab and vim.api.nvim_tabpage_is_valid(s.prev_tab) then
        vim.api.nvim_set_current_tabpage(s.prev_tab)
    end
end

return M
