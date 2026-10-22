-- Conflict markers in the working file: parsing and the "choose a version" edits.

local M = {}

---@class NvimDiffConflict
---@field first integer line of "<<<<<<<"
---@field last integer line of ">>>>>>>"
---@field ours string[]
---@field base? string[] only with merge.conflictStyle=diff3 / zdiff3
---@field theirs string[]

local function marker(line, m)
    return line:sub(1, 7) == m and (#line == 7 or line:sub(8, 8) == " ")
end

---@param lines string[]
---@return NvimDiffConflict[]
function M.parse(lines)
    local regions, cur, part = {}, nil, nil
    for i, line in ipairs(lines) do
        if marker(line, "<<<<<<<") then
            cur, part = { first = i, ours = {}, theirs = {} }, "ours"
        elseif cur and part == "ours" and marker(line, "|||||||") then
            cur.base, part = {}, "base"
        elseif cur and (part == "ours" or part == "base") and line == "=======" then
            part = "theirs"
        elseif cur and part == "theirs" and marker(line, ">>>>>>>") then
            cur.last = i
            regions[#regions + 1] = cur
            cur, part = nil, nil
        elseif cur then
            table.insert(cur[part], line)
        end
    end
    return regions
end

---@param region NvimDiffConflict
---@param which "ours"|"theirs"|"base"|"all"|"none"
---@return string[]
local function content(region, which)
    if which == "all" then
        return vim.list_extend(vim.list_extend(vim.list_extend({}, region.ours), region.base or {}), region.theirs)
    elseif which == "none" then
        return {}
    end
    return region[which] or {}
end

local NO_BASE = "no base version in the markers (git config merge.conflictStyle diff3 adds it)"

---Replaces the conflict around `lnum` with the chosen version.
---@param buf integer
---@param lnum integer
---@param which "ours"|"theirs"|"base"|"all"|"none"
---@return integer? first line of the replaced region
---@return string? err when `lnum` is not in a conflict, or "base" without a base section
function M.choose(buf, lnum, which)
    for _, r in ipairs(M.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))) do
        if lnum >= r.first and lnum <= r.last then
            if which == "base" and not r.base then
                return nil, NO_BASE
            end
            vim.api.nvim_buf_set_lines(buf, r.first - 1, r.last, false, content(r, which))
            return r.first
        end
    end
    return nil, "no conflict under the cursor"
end

---Replaces every conflict of the buffer with the chosen version.
---@param buf integer
---@param which "ours"|"theirs"|"base"|"all"|"none"
---@return integer count regions replaced
---@return string? err
function M.choose_all(buf, which)
    local regions = M.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    if which == "base" then
        for _, r in ipairs(regions) do
            if not r.base then
                return 0, NO_BASE
            end
        end
    end
    for i = #regions, 1, -1 do
        local r = regions[i]
        vim.api.nvim_buf_set_lines(buf, r.first - 1, r.last, false, content(r, which))
    end
    return #regions
end

---Start line of the next (dir = 1) or previous (dir = -1) conflict from `lnum`, wrapping around.
---@param buf integer
---@param lnum integer
---@param dir 1|-1
---@return integer?
function M.jump_target(buf, lnum, dir)
    local regions = M.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    if #regions == 0 then
        return nil
    end
    if dir > 0 then
        for _, r in ipairs(regions) do
            if r.first > lnum then
                return r.first
            end
        end
        return regions[1].first
    end
    for i = #regions, 1, -1 do
        if regions[i].first < lnum then
            return regions[i].first
        end
    end
    return regions[#regions].first
end

return M
