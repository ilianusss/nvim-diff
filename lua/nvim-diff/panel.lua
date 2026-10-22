-- The file panel: renders the session status (Conflicts / Changes / Staged changes) into the
-- panel buffer, keeps a line -> item map for actions, and draws the options bar (winbar).

local config = require("nvim-diff.config")
local hl = require("nvim-diff.hl")
local tree = require("nvim-diff.tree")

local M = {}

local ns = vim.api.nvim_create_namespace("nvim-diff-panel")

M.SECTIONS = {
    { kind = "conflicting", title = "Conflicts" },
    { kind = "working", title = "Changes" },
    { kind = "staged", title = "Staged changes" },
}

---@class NvimDiffItem
---@field type "file"|"dir"|"section"
---@field section "conflicting"|"working"|"staged"
---@field key string stable across renders, to keep the cursor on the same item
---@field entry? NvimDiffEntry
---@field node? NvimDiffNode

---@param kind string
---@param path string
---@return string
function M.entry_key(kind, path)
    return kind .. ":" .. path
end

---@return integer bufnr
function M.create_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "nvim-diff://panel")
    vim.bo[buf].filetype = "NvimDiffPanel"
    vim.bo[buf].modifiable = false
    return buf
end

---@param win integer
function M.setup_win(win)
    local wo = vim.wo[win]
    wo.number = false
    wo.relativenumber = false
    wo.list = false
    wo.wrap = false
    wo.spell = false
    wo.signcolumn = "no"
    wo.foldcolumn = "0"
    wo.statuscolumn = ""
    wo.colorcolumn = ""
    wo.cursorline = true
    wo.winfixwidth = true
end

local function file_icon(name)
    if not config.options.use_icons then
        return "", nil
    end
    local ok, devicons = pcall(require, "nvim-web-devicons")
    if ok then
        local icon, icon_hl = devicons.get_icon(name, vim.fn.fnamemodify(name, ":e"), { default = true })
        return icon and (icon .. " ") or "", icon_hl
    end
    if _G.MiniIcons then
        local icon, icon_hl = _G.MiniIcons.get("file", name)
        return icon .. " ", icon_hl
    end
    return "", nil
end

-- Line builder: each line is a list of { text, hl } segments.
local function builder()
    local b = { lines = {}, marks = {}, items = {} }
    function b.add(segments, item)
        local parts, col = {}, 0
        for _, seg in ipairs(segments) do
            if seg[2] and #seg[1] > 0 then
                b.marks[#b.marks + 1] = { #b.lines, col, col + #seg[1], seg[2] }
            end
            parts[#parts + 1] = seg[1]
            col = col + #seg[1]
        end
        b.lines[#b.lines + 1] = table.concat(parts)
        b.items[#b.lines] = item
    end
    return b
end

local function file_segments(s, entry, depth)
    local icons = config.options.icons
    local icon, icon_hl = file_icon(vim.fs.basename(entry.path))
    local active = s.current and s.current.kind == entry.kind and s.current.path == entry.path
    local segs = {
        { entry.status .. " ", hl.status[entry.status] },
        { depth and string.rep(" ", depth * 2 + 2) or "" },
        { icon, icon_hl },
        { vim.fs.basename(entry.path), active and "NvimDiffSelected" or "NvimDiffFileName" },
    }
    if entry.kind == "conflicting" then
        local n = entry.conflicts or 0
        segs[#segs + 1] = { " " }
        segs[#segs + 1] = n > 0 and { tostring(n), "NvimDiffConflicts" } or { icons.done, "NvimDiffInsertions" }
    elseif entry.stats then
        segs[#segs + 1] = { " " }
        segs[#segs + 1] = { tostring(entry.stats.additions), "NvimDiffInsertions" }
        segs[#segs + 1] = { ", " }
        segs[#segs + 1] = { tostring(entry.stats.deletions), "NvimDiffDeletions" }
    end
    if not depth then
        local parent = vim.fs.dirname(entry.path)
        if parent ~= "." then
            segs[#segs + 1] = { " " .. parent, "NvimDiffPath" }
        end
    end
    return segs
end

local function render_nodes(s, b, nodes, section, depth)
    local icons = config.options.icons
    for _, node in ipairs(nodes) do
        if node.type == "file" then
            b.add(file_segments(s, node.entry, depth), {
                type = "file",
                section = section,
                entry = node.entry,
                key = M.entry_key(section, node.path),
            })
        else
            local fold_key = section .. ":" .. node.path
            local collapsed = s.collapsed[fold_key]
            local segs = {
                { (collapsed and node.status or " ") .. " ", hl.status[node.status] },
                { string.rep(" ", depth * 2) },
                { collapsed and icons.fold_closed or icons.fold_open, "NvimDiffNonText" },
            }
            if config.options.use_icons then
                segs[#segs + 1] = {
                    " " .. (collapsed and icons.folder_closed or icons.folder_open) .. " ",
                    "NvimDiffFolderSign",
                }
            else
                segs[#segs + 1] = { " " }
            end
            segs[#segs + 1] = { node.name, "NvimDiffFolderName" }
            b.add(segs, { type = "dir", section = section, node = node, key = "dir:" .. fold_key })
            if not collapsed then
                render_nodes(s, b, node.children, section, depth + 1)
            end
        end
    end
end

---Nodes of each section, as displayed (tree or flat list).
---@param s NvimDiffSession
---@param section string
---@return NvimDiffNode[]
function M.nodes(s, section)
    local entries = s.status[section]
    if s.listing_style == "list" then
        local nodes = {}
        for i, e in ipairs(entries) do
            nodes[i] = { type = "file", name = e.path, path = e.path, entry = e }
        end
        return nodes
    end
    return tree.build(entries, s.flatten_dirs)
end

---Every entry in panel order (conflicts, changes, staged), for next/previous file.
---@param s NvimDiffSession
---@return NvimDiffEntry[]
function M.ordered_entries(s)
    local out = {}
    for _, sec in ipairs(M.SECTIONS) do
        tree.entries(M.nodes(s, sec.kind), out)
    end
    return out
end

local function truncate(path, width)
    if vim.fn.strdisplaywidth(path) <= width then
        return path
    end
    return "\u{2026}" .. vim.fn.strcharpart(path, vim.fn.strchars(path) - width + 1)
end

---@param s NvimDiffSession
---@return string[] lines
---@return table marks
---@return table<integer, NvimDiffItem> items
function M.build(s)
    local b = builder()
    local width = config.options.panel.width
    b.add({ { truncate(vim.fn.fnamemodify(s.root, ":~"), width - 2), "NvimDiffRootPath" } })
    b.add({ { "Help: ", "NvimDiffPath" }, { "g?", "NvimDiffCounter" } })
    b.add({ { "" } })

    local st = s.status
    local others = #st.conflicting > 0 or #st.staged > 0
    for _, sec in ipairs(M.SECTIONS) do
        local entries = st[sec.kind]
        -- "Changes" stays visible when everything is empty, like diffview
        if #entries > 0 or (sec.kind == "working" and not others) then
            b.add({
                { sec.title .. " ", "NvimDiffTitle" },
                { "(" .. #entries .. ")", "NvimDiffCounter" },
            }, { type = "section", section = sec.kind, key = "section:" .. sec.kind })
            if s.listing_style == "list" then
                for _, e in ipairs(entries) do
                    b.add(file_segments(s, e, nil), {
                        type = "file",
                        section = sec.kind,
                        entry = e,
                        key = M.entry_key(sec.kind, e.path),
                    })
                end
            else
                render_nodes(s, b, M.nodes(s, sec.kind), sec.kind, 0)
            end
            b.add({ { "" } })
        end
    end
    return b.lines, b.marks, b.items
end

---Re-renders the panel, keeping the cursor on the same item.
---@param s NvimDiffSession
function M.render(s)
    local buf = s.panel_buf
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    local win = s.panel_win and vim.api.nvim_win_is_valid(s.panel_win) and s.panel_win or nil
    local cursor_key, cursor_line
    if win then
        cursor_line = vim.api.nvim_win_get_cursor(win)[1]
        local item = s.items[cursor_line]
        cursor_key = item and item.key
    end

    local lines, marks, items = M.build(s)
    s.items = items
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, m in ipairs(marks) do
        vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
    end

    if win then
        local target = cursor_key and M.find(s, cursor_key) or math.min(cursor_line, #lines)
        vim.api.nvim_win_set_cursor(win, { target, 0 })
        vim.wo[win].winbar = M.options_bar(s)
    end
end

---@param s NvimDiffSession
---@param key string
---@return integer? lnum
function M.find(s, key)
    for lnum, item in pairs(s.items) do
        if item.key == key then
            return lnum
        end
    end
end

---Moves the panel cursor to an entry (no-op when the panel is hidden).
---@param s NvimDiffSession
---@param entry NvimDiffEntry
function M.focus_entry(s, entry)
    local lnum = M.find(s, M.entry_key(entry.kind, entry.path))
    if lnum and s.panel_win and vim.api.nvim_win_is_valid(s.panel_win) then
        vim.api.nvim_win_set_cursor(s.panel_win, { lnum, 0 })
    end
end

--------------------------------------------------------------------------------
-- Options bar (panel winbar). Items are click labels: %<id>@v:lua.__nvim_diff_click@...%X
--------------------------------------------------------------------------------

local CLICK = {
    [1] = "toggle_whitespace",
    [2] = "listing_style",
    [3] = "refresh",
    [4] = "toggle_full_file",
}

---Click handler of the options bar (called by Neovim with the item id as `minwid`).
---@diagnostic disable-next-line: unused-local
function _G.__nvim_diff_click(id, clicks, button, mods)
    if button == "l" and CLICK[id] then
        require("nvim-diff.actions").run(CLICK[id], {})
    end
end

local function click_item(id, label, group)
    return ("%%%d@v:lua.__nvim_diff_click@%%#%s#%s%%*%%X"):format(id, group, label)
end

---@param s NvimDiffSession
---@return string
function M.options_bar(s)
    -- Keep it under the panel width (35)
    local ws = s.ignore_ws and click_item(1, " WS ignored ", "NvimDiffOptionActive")
        or click_item(1, " WS shown ", "NvimDiffOption")
    local listing = click_item(2, s.listing_style == "tree" and " Tree " or " List ", "NvimDiffOption")
    local folds = s.full_file and click_item(4, " Full ", "NvimDiffOption")
        or click_item(4, " Folded ", "NvimDiffOptionActive")
    local live = click_item(3, "\u{25cf} ", s.watcher and "NvimDiffLive" or "NvimDiffLiveOff")
    return " " .. ws .. " " .. listing .. " " .. folds .. "%=" .. live
end

return M
