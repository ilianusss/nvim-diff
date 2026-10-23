-- Wrapped lines in the diff windows. Diff mode aligns buffer lines, not screen rows: a line that
-- wraps to more rows on one side pushes every line below it out of step with the other side.
-- Padding under the shorter side (virtual lines drawn like diff filler, as VS Code does) puts the
-- rows back in step. Scrollbind still works in whole lines, so the sides only drift while the top
-- of a window is inside a wrapped line or its padding.

local config = require("nvim-diff.config")

local M = {}

local ns = vim.api.nvim_create_namespace("nvim-diff-align")

---@class NvimDiffSlot
---@field rows integer screen rows it takes
---@field row integer 0-based buffer line padding is attached to
---@field above boolean padding goes above `row` (diff filler) instead of below it

---Slots of a diff window, top to bottom: one per diff filler line and one per buffer line (a
---closed fold is one slot). The windows of one diff have the same slots, in the same order.
---@param win integer
---@return NvimDiffSlot[]
local function slots(win)
    return vim.api.nvim_win_call(win, function()
        local out = {}
        local last = vim.api.nvim_buf_line_count(0)
        local lnum = 1
        while lnum <= last + 1 do
            local filler = vim.fn.diff_filler(lnum)
            for _ = 1, filler do
                if lnum > last then
                    out[#out + 1] = { rows = 1, row = last - 1, above = false }
                else
                    out[#out + 1] = { rows = 1, row = lnum - 1, above = true }
                end
            end
            if lnum > last then
                break
            end
            -- Virtual lines of other plugins above the line count with it
            local height = vim.api.nvim_win_text_height(win, { start_row = lnum - 1, end_row = lnum - 1 })
            local fold_end = vim.fn.foldclosedend(lnum)
            lnum = fold_end > 0 and fold_end or lnum
            out[#out + 1] = { rows = height.all - filler, row = lnum - 1, above = false }
            lnum = lnum + 1
        end
        return out
    end)
end

---@param win integer
---@param count integer
local function padding(win, count)
    local char = vim.wo[win].fillchars:match("diff:([^,]+)") or "-"
    local info = vim.fn.getwininfo(win)[1]
    local line = { { char:rep(info.width - info.textoff), "NvimDiffPadding" } }
    local lines = {}
    for i = 1, count do
        lines[i] = line
    end
    return lines
end

---Removes the padding from every buffer.
function M.clear()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
            vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        end
    end
end

---Pads the diff windows of the session so that their slots start on the same screen row.
---@param s NvimDiffSession
function M.apply(s)
    M.clear()
    if not config.options.wrap or vim.api.nvim_get_current_tabpage() ~= s.tab then
        return
    end
    local wins = vim.tbl_filter(function(w)
        return vim.api.nvim_win_is_valid(w) and vim.wo[w].diff
    end, s.wins)
    if #wins < 2 then
        return
    end
    -- The real file can be open in other windows too: the padding only belongs in these ones
    vim.api.nvim__ns_set(ns, { wins = wins })

    local all = vim.tbl_map(slots, wins)
    local count = 0
    for _, list in ipairs(all) do
        count = math.max(count, #list)
    end
    for k = 1, count do
        local most = 0
        for _, list in ipairs(all) do
            most = math.max(most, list[k] and list[k].rows or 0)
        end
        for i, list in ipairs(all) do
            local slot = list[k]
            if slot and slot.rows < most then
                vim.api.nvim_buf_set_extmark(vim.api.nvim_win_get_buf(wins[i]), ns, slot.row, 0, {
                    virt_lines = padding(wins[i], most - slot.rows),
                    virt_lines_above = slot.above,
                })
            end
        end
    end
end

return M
