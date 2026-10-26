-- The diff windows: which content each side shows for an entry (see ARCHITECTURE.md), the
-- buffers holding it, and putting them in diff mode.

local align = require("nvim-diff.align")
local config = require("nvim-diff.config")
local git = require("nvim-diff.git")

local M = {}

local BINARY = "Binary file: not shown"

---@class NvimDiffSide
---@field type "rev"|"file"|"empty"|"placeholder"
---@field path string
---@field label string winbar label
---@field spec? string blob spec for "rev": "HEAD:path", ":path", ":2:path"
---@field text? string line shown by a "placeholder"

local function rev(spec, path, label)
    return { type = "rev", spec = spec, path = path, label = label }
end

local function file(path, label)
    return { type = "file", path = path, label = label }
end

local function empty(path, label)
    return { type = "empty", path = path, label = label }
end

---Sides of an entry, left to right. A staged file without unstaged changes has the same content
---in the index and on disk: its right side is then the real (editable) file.
---@param entry NvimDiffEntry
---@param has_head boolean
---@param unstaged? table<string, boolean> paths with unstaged changes
---@return NvimDiffSide[]
function M.sides(entry, has_head, unstaged)
    local p, old = entry.path, entry.old_path or entry.path
    if entry.binary or entry.submodule then
        local text = entry.submodule and "Submodule: not shown" or BINARY
        return {
            { type = "placeholder", path = p, label = "OLD", text = text },
            { type = "placeholder", path = p, label = "NEW", text = text },
        }
    end
    if entry.kind == "conflicting" then
        return { rev(":2:" .. p, p, "OURS"), file(p, "LOCAL"), rev(":3:" .. p, p, "THEIRS") }
    elseif entry.kind == "working" then
        if entry.status == "?" then
            return { empty(p, "UNTRACKED"), file(p, "WORKING TREE") }
        elseif entry.status == "D" then
            return { rev(":" .. p, p, "INDEX"), empty(p, "DELETED") }
        end
        return { rev(":" .. old, old, "INDEX"), file(p, "WORKING TREE") }
    end
    if entry.status == "D" and has_head then
        return { rev("HEAD:" .. p, p, "HEAD"), empty(p, "DELETED") }
    end
    local right = (unstaged or {})[p] and rev(":" .. p, p, "INDEX") or file(p, "WORKING TREE")
    if entry.status == "A" or not has_head then
        return { empty(p, "NEW FILE"), right }
    end
    return { rev("HEAD:" .. old, old, "HEAD"), right }
end

local function looks_binary(path)
    local f = io.open(path, "rb")
    if not f then
        return false
    end
    local chunk = f:read(8000) or ""
    f:close()
    return chunk:find("\0", 1, true) ~= nil
end

local function set_lines(buf, lines)
    if vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), lines) then
        return
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
end

---Scratch buffer `nvim-diff://<label>/<path>`, reused while the session lives.
local function scratch(s, side, lines, filetype)
    local name = ("nvim-diff://%s/%s"):format(side.label, side.path)
    local buf = s.scratch[name]
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buf, name)
        vim.bo[buf].modifiable = false
        s.scratch[name] = buf
    end
    set_lines(buf, lines)
    if filetype and vim.bo[buf].filetype ~= filetype then
        vim.bo[buf].filetype = filetype
    end
    s.scratch_spec[buf] = side.spec
    return buf
end

local function rev_lines(s, spec)
    local lines, binary = git.show(s.root, spec)
    if binary then
        return { BINARY }, true
    end
    return lines or {}, false
end

---@param s NvimDiffSession
---@param side NvimDiffSide
---@return integer bufnr
function M.side_buf(s, side)
    local ft = vim.filetype.match({ filename = side.path }) or ""
    if side.type == "file" then
        local abs = s.root .. "/" .. side.path
        if not vim.uv.fs_stat(abs) then
            return scratch(s, { label = "MISSING", path = side.path }, {}, ft)
        end
        if looks_binary(abs) then
            return scratch(s, { label = side.label, path = side.path }, { BINARY })
        end
        -- bufadd() leaves new buffers unlisted, which keeps reviewed files out of the buffer
        -- list; `gf` (:edit) lists them.
        local buf = vim.fn.bufadd(abs)
        if not vim.api.nvim_buf_is_loaded(buf) then
            vim.fn.bufload(buf)
            s.loaded[buf] = true
        end
        return buf
    elseif side.type == "rev" then
        local lines, binary = rev_lines(s, side.spec)
        return scratch(s, side, lines, not binary and ft or nil)
    elseif side.type == "placeholder" then
        return scratch(s, side, { side.text })
    end
    return scratch(s, side, {}, ft)
end

---Makes the session have exactly `n` diff windows, right of the panel.
---@param s NvimDiffSession
---@param n integer
---@param filler integer buffer for new windows
local function ensure_wins(s, n, filler)
    local wins = {}
    for _, w in ipairs(s.wins) do
        if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_tabpage(w) == s.tab then
            wins[#wins + 1] = w
        end
    end
    if #wins == 0 then
        local anchor = s.panel_win and vim.api.nvim_win_is_valid(s.panel_win) and s.panel_win or -1
        wins[1] = vim.api.nvim_open_win(filler, false, { split = "right", win = anchor })
    end
    while #wins < n do
        wins[#wins + 1] = vim.api.nvim_open_win(filler, false, { split = "right", win = wins[#wins] })
    end
    while #wins > n do
        vim.api.nvim_win_close(table.remove(wins), true)
    end
    s.wins = wins
end

local function winbar(side)
    local path = side.path:gsub("%%", "%%%%")
    return ("%%#NvimDiffWinbarLabel# %s %%#NvimDiffWinbarPath#%s"):format(side.label, path)
end

---Shows an entry in the diff windows.
---@param s NvimDiffSession
---@param entry NvimDiffEntry
---@return integer[] bufs one per window
function M.show(s, entry)
    local unstaged = {}
    for _, e in ipairs(s.status.working) do
        unstaged[e.path] = true
    end
    local sides = M.sides(entry, s.has_head, unstaged)
    local bufs = {}
    for i, side in ipairs(sides) do
        bufs[i] = M.side_buf(s, side)
    end
    ensure_wins(s, #sides, bufs[1])

    for _, w in ipairs(s.wins) do
        vim.api.nvim_win_call(w, function()
            vim.cmd("diffoff")
        end)
    end
    for i, w in ipairs(s.wins) do
        vim.api.nvim_win_set_buf(w, bufs[i])
        vim.wo[w].winbar = winbar(sides[i])
        vim.api.nvim_win_call(w, function()
            vim.opt_local.fillchars:append({ diff = "\u{2571}" })
            vim.cmd("diffthis")
        end)
        -- :diffthis turns 'wrap' off
        if config.options.wrap then
            vim.wo[w].wrap = true
            vim.wo[w].linebreak = true
        end
    end
    M.apply_folds(s)
    s.sides = sides
    M.equalize(s)
    M.jump_first_change(s)
    return bufs
end

---Full file (folds off) or only the changed parts (diff mode's folds of unchanged lines).
---@param s NvimDiffSession
function M.apply_folds(s)
    for _, w in ipairs(s.wins) do
        if vim.api.nvim_win_is_valid(w) then
            vim.wo[w].foldenable = not s.full_file
        end
    end
end

---Equal widths for the diff windows; the panel keeps its width (winfixwidth). Wrapped lines
---take other heights at the new widths, so the padding is redone.
---@param s NvimDiffSession
function M.equalize(s)
    if s.wins[1] and vim.api.nvim_win_is_valid(s.wins[1]) then
        vim.api.nvim_win_call(s.wins[1], function()
            vim.cmd("wincmd =")
        end)
    end
    align.apply(s)
end

---Window holding the "new" side: the right one, or LOCAL in the 3-way layout.
---@param s NvimDiffSession
---@return integer? win
function M.main_win(s)
    return #s.wins == 3 and s.wins[2] or s.wins[#s.wins]
end

---Cursor on the first change (or the first conflict marker) of the main window.
---@param s NvimDiffSession
function M.jump_first_change(s)
    local win = M.main_win(s)
    if not (win and vim.api.nvim_win_is_valid(win)) then
        return
    end
    vim.api.nvim_win_call(win, function()
        vim.api.nvim_win_set_cursor(win, { 1, 0 })
        if #s.wins == 3 then
            local target = require("nvim-diff.conflict").jump_target(vim.api.nvim_win_get_buf(win), 0, 1)
            if target then
                vim.api.nvim_win_set_cursor(win, { target, 0 })
            end
        elseif vim.fn.diff_hlID(1, 1) == 0 and vim.fn.diff_filler(1) == 0 then
            pcall(vim.cmd, "normal! ]c")
        end
    end)
end

---Live refresh of the shown entry: reloads real files from disk and, with `blobs`, scratch sides
---from git, then recomputes the diff. Cursors stay where they are.
---@param s NvimDiffSession
---@param blobs boolean
function M.reload(s, blobs)
    for i, w in ipairs(s.wins) do
        if vim.api.nvim_win_is_valid(w) then
            local buf = vim.api.nvim_win_get_buf(w)
            local spec = s.scratch_spec[buf]
            if spec then
                if blobs then
                    set_lines(buf, (rev_lines(s, spec)))
                end
            elseif s.sides and s.sides[i] and s.sides[i].type == "file" and vim.bo[buf].buftype == "" then
                vim.cmd("checktime " .. buf)
            end
        end
    end
    M.update(s)
end

---:diffupdate for the session windows (it only acts on the current tabpage).
---@param s NvimDiffSession
function M.update(s)
    if vim.api.nvim_get_current_tabpage() == s.tab and s.wins[1] and vim.api.nvim_win_is_valid(s.wins[1]) then
        vim.api.nvim_win_call(s.wins[1], function()
            vim.cmd("diffupdate")
        end)
    end
end

return M
