-- g?: a floating window listing the keymaps of the current context, from actions.lua descs.

local config = require("nvim-diff.config")

local M = {}

local ns = vim.api.nvim_create_namespace("nvim-diff-help")

local TITLES = { panel = "File panel", view = "Diff panes", conflict = "Conflicts" }

---@param scopes string[] keymap scopes, e.g. { "view", "conflict" }
---@return string[]
function M.lines(scopes)
    local actions = require("nvim-diff.actions").actions
    local lines = {}
    for _, scope in ipairs(scopes) do
        -- Group the keys of each action: "<CR>, l, o  Open the diff". By action, not by name, so
        -- that a key mapped to an old name shares the row of the new one.
        local keys_of, order = {}, {}
        for lhs, name in pairs(config.options.keymaps[scope] or {}) do
            local action = name and actions[name]
            if action then
                if not keys_of[action] then
                    keys_of[action] = {}
                    order[#order + 1] = action
                end
                table.insert(keys_of[action], lhs)
            end
        end
        table.sort(order, function(a, b)
            return a.desc < b.desc
        end)
        local rows, width = {}, 0
        for _, action in ipairs(order) do
            table.sort(keys_of[action])
            local keys = table.concat(keys_of[action], ", ")
            width = math.max(width, vim.fn.strdisplaywidth(keys))
            rows[#rows + 1] = { keys, action.desc }
        end
        if #lines > 0 then
            lines[#lines + 1] = ""
        end
        lines[#lines + 1] = TITLES[scope] or scope
        for _, row in ipairs(rows) do
            lines[#lines + 1] = ("  %s%s  %s"):format(
                row[1],
                string.rep(" ", width - vim.fn.strdisplaywidth(row[1])),
                row[2]
            )
        end
    end
    return lines
end

---@param scopes string[]
function M.open(scopes)
    local lines = M.lines(scopes)
    local width = 0
    for _, l in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(l))
    end
    width = math.min(width + 2, vim.o.columns - 4)
    local height = math.min(#lines, vim.o.lines - 6)

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2) - 1,
        col = math.floor((vim.o.columns - width) / 2),
        style = "minimal",
        border = "rounded",
        title = " nvim-diff ",
        title_pos = "center",
    })
    vim.wo[win].cursorline = true
    for i, l in ipairs(lines) do
        if l ~= "" and l:sub(1, 1) ~= " " then
            vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
                end_col = #l,
                hl_group = "NvimDiffTitle",
            })
        end
    end
    for _, key in ipairs({ "q", "<Esc>", "g?" }) do
        vim.keymap.set("n", key, function()
            pcall(vim.api.nvim_win_close, win, true)
        end, { buffer = buf, nowait = true })
    end
end

return M
