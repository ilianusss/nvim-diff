-- "Ignore leading/trailing whitespace" (VS Code's ignoreTrimWhitespace). No 'diffopt' flag does
-- this (iwhite is `diff -b`), so a Lua 'diffexpr' diffs trimmed lines and writes the hunks as an
-- ed-style diff. 'diffexpr' is global: it is ours only while the nvim-diff tab is current.

local M = {}

M.EXPR = "v:lua.require'nvim-diff.whitespace'.diffexpr()"

-- vim.diff was renamed vim.text.diff in Neovim 0.12; 0.11 only has vim.diff
local text_diff = vim.text.diff or vim.diff

local saved ---@type string? the user's 'diffexpr' while ours is set

---@return table<string, string|boolean> 'diffopt' items: "iwhite" -> true, "algorithm" -> "histogram"
local function diffopt_flags()
    local flags = {}
    for _, item in ipairs(vim.split(vim.o.diffopt, ",", { plain = true })) do
        local key, value = item:match("^([^:]+):?(.*)$")
        if key then
            flags[key] = value ~= "" and value or true
        end
    end
    return flags
end

local function ed_range(start, count)
    if count <= 1 then
        return tostring(start)
    end
    return start .. "," .. (start + count - 1)
end

---Ed-style diff of `a` -> `b` that ignores leading and trailing whitespace. Trimming keeps line
---numbers, so the hunks apply to the untrimmed lines.
---@param a string[]
---@param b string[]
---@param flags? table<string, string|boolean> parsed 'diffopt' (default: the current one)
---@return string[]
function M.ed_diff(a, b, flags)
    flags = flags or diffopt_flags()
    local function text(lines)
        if #lines == 0 then
            return ""
        end
        local trimmed = {}
        for i, line in ipairs(lines) do
            line = vim.trim(line)
            trimmed[i] = flags.icase and line:lower() or line
        end
        return table.concat(trimmed, "\n") .. "\n"
    end

    local hunks = text_diff(text(a), text(b), {
        result_type = "indices",
        algorithm = type(flags.algorithm) == "string" and flags.algorithm or nil,
        indent_heuristic = flags["indent-heuristic"] == true,
        ignore_whitespace = flags.iwhiteall == true,
        ignore_whitespace_change = flags.iwhite == true,
        ignore_whitespace_change_at_eol = flags.iwhiteeol == true,
        ignore_blank_lines = flags.iblank == true,
    })

    local out = {}
    for _, h in ipairs(hunks) do
        local sa, ca, sb, cb = h[1], h[2], h[3], h[4]
        if ca == 0 then
            out[#out + 1] = ("%da%s"):format(sa, ed_range(sb, cb))
        elseif cb == 0 then
            out[#out + 1] = ("%sd%d"):format(ed_range(sa, ca), sb)
        else
            out[#out + 1] = ("%sc%s"):format(ed_range(sa, ca), ed_range(sb, cb))
        end
        for i = sa, sa + ca - 1 do
            out[#out + 1] = "< " .. a[i]
        end
        if ca > 0 and cb > 0 then
            out[#out + 1] = "---"
        end
        for i = sb, sb + cb - 1 do
            out[#out + 1] = "> " .. b[i]
        end
    end
    return out
end

---The 'diffexpr' entry point: Neovim sets v:fname_in / v:fname_new / v:fname_out.
function M.diffexpr()
    local a = vim.fn.readfile(vim.v.fname_in)
    local b = vim.fn.readfile(vim.v.fname_new)
    vim.fn.writefile(M.ed_diff(a, b), vim.v.fname_out)
end

---Sets (on) or restores (off) 'diffexpr'. Idempotent.
---@param on boolean
function M.apply(on)
    if on then
        if vim.o.diffexpr ~= M.EXPR then
            saved = vim.o.diffexpr
            vim.o.diffexpr = M.EXPR
        end
    elseif vim.o.diffexpr == M.EXPR then
        vim.o.diffexpr = saved or ""
        saved = nil
    end
end

return M
