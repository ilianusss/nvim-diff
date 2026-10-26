-- Clean filters (.gitattributes `filter=`): git compares the working-tree file after its clean
-- filter, while the diff shows the real, editable file. The lines the filter removes or rewrites
-- are copied onto the git side, at the same place, so they show as unchanged and only the changes
-- `git diff` reports are highlighted.

local M = {}

local text_diff = vim.text and vim.text.diff or vim.diff

local function text(lines)
    return #lines == 0 and "" or table.concat(lines, "\n") .. "\n"
end

---@class NvimDiffHunk
---@field first integer `clean` lines first+1..last are replaced; first == last inserts after line first
---@field last integer
---@field lines string[]
---@field from_filter boolean

---@return NvimDiffHunk[]
local function hunks(clean, to, from_filter)
    local out = {}
    for _, h in ipairs(text_diff(text(clean), text(to), { result_type = "indices" })) do
        local start, count = h[1], h[2]
        local first = count == 0 and start or start - 1
        out[#out + 1] = {
            first = first,
            last = first + count,
            lines = vim.list_slice(to, h[3], h[3] + h[4] - 1),
            from_filter = from_filter,
        }
    end
    return out
end

---Insertions at the same place, or at either end of a replaced range, do not overlap: both apply.
local function overlap(a, b)
    if a.first == a.last then
        return b.first < a.first and a.first < b.last
    elseif b.first == b.last then
        return a.first < b.first and b.first < a.last
    end
    return a.first < b.last and b.first < a.last
end

local function before(a, b)
    if a.first ~= b.first then
        return a.first < b.first
    elseif a.last ~= b.last then
        return a.last < b.last
    end
    return a.from_filter and not b.from_filter
end

---The git side with the filter's changes (`clean` -> `raw`) applied where they do not overlap the
---real changes (`clean` -> `blob`), so that diffed against `raw` it shows only the real changes. A
---filter change that overlaps a real one is left out: its lines show as part of that change.
---@param blob string[] git side
---@param clean string[] working-tree file after its clean filter
---@param raw string[] working-tree file
---@return string[] lines
---@return boolean spliced some filtered lines were added
function M.splice(blob, clean, raw)
    local changes = hunks(clean, blob, false)
    local kept = vim.list_extend({}, changes)
    for _, f in ipairs(hunks(clean, raw, true)) do
        local free = true
        for _, c in ipairs(changes) do
            if overlap(f, c) then
                free = false
                break
            end
        end
        if free then
            kept[#kept + 1] = f
        end
    end
    if #kept == #changes then
        return blob, false
    end
    table.sort(kept, before)
    local out, pos = {}, 0
    for _, h in ipairs(kept) do
        vim.list_extend(out, clean, pos + 1, h.first)
        vim.list_extend(out, h.lines)
        pos = h.last
    end
    vim.list_extend(out, clean, pos + 1, #clean)
    return out, true
end

return M
