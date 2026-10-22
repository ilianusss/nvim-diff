local H = require("tests.helpers")
local whitespace = require("nvim-diff.whitespace")

local DEFAULT = { internal = true, filler = true }

test("ed_diff ignores leading and trailing whitespace only", function()
    local a = { "x", "  indented", "trail", "a b" }
    local b = { "x", "indented", "trail   ", "a  b" }
    eq(whitespace.ed_diff(a, b, DEFAULT), { "4c4", "< a b", "---", "> a  b" })
end)

test("ed_diff writes add / delete / change hunks", function()
    eq(whitespace.ed_diff({ "a" }, { "a", "b", "c" }, DEFAULT), { "1a2,3", "> b", "> c" })
    eq(whitespace.ed_diff({ "a", "b", "c" }, { "a" }, DEFAULT), { "2,3d1", "< b", "< c" })
    eq(whitespace.ed_diff({}, { "a" }, DEFAULT), { "0a1", "> a" })
    eq(whitespace.ed_diff({ "a", "b" }, { "A", "B" }, DEFAULT), { "1,2c1,2", "< a", "< b", "---", "> A", "> B" })
end)

test("ed_diff honors icase and iwhite from 'diffopt'", function()
    eq(whitespace.ed_diff({ "Hello" }, { "hello" }, { icase = true }), {})
    eq(whitespace.ed_diff({ "a b" }, { "a   b" }, { iwhite = true }), {})
end)

local function open_ws_repo()
    local repo = H.repo({ ["f.lua"] = "local a = 1\nif a then\n  print(a)\nend\n" })
    -- line 2: trailing spaces, line 3: re-indented, line 4: real change
    repo:write("f.lua", "local a = 1\nif a then   \n    print(a)\nend -- done\n")
    return H.open(repo)
end

test("diff windows hide whitespace-only lines while ignoring, show them when toggled", function()
    local s = open_ws_repo()
    eq(vim.o.diffexpr, whitespace.EXPR)
    local right = s.wins[2]
    eq(H.changed_lines(right), { 4 })
    H.run("toggle_whitespace")
    eq(s.ignore_ws, false)
    eq(vim.o.diffexpr, "")
    eq(H.changed_lines(right), { 2, 3, 4 })
end)

test("'diffexpr' is only ours while the view's tab is current, and restored on close", function()
    vim.o.diffexpr = ""
    local s = open_ws_repo()
    eq(vim.o.diffexpr, whitespace.EXPR)
    vim.cmd("tabprevious")
    eq(vim.o.diffexpr, "", "restored when leaving the tab")
    vim.api.nvim_set_current_tabpage(s.tab)
    eq(vim.o.diffexpr, whitespace.EXPR, "set again on TabEnter")
    s.quit_on_close = false
    require("nvim-diff").close()
    eq(vim.o.diffexpr, "")
end)

test("ignore_trim_whitespace = false starts with whitespace shown", function()
    require("nvim-diff").setup({ ignore_trim_whitespace = false })
    local s = open_ws_repo()
    eq(s.ignore_ws, false)
    eq(H.changed_lines(s.wins[2]), { 2, 3, 4 })
end)

test("linematch alignment is the same with our 'diffexpr' as with the internal diff", function()
    local a = { "start", "alpha one", "beta two", "gamma three", "end" }
    local b = { "start", "inserted line", "alpha one!", "beta two!", "gamma three!", "end" }
    local function fillers()
        vim.cmd("tabnew")
        local ba = vim.api.nvim_create_buf(false, true)
        local bb = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(ba, 0, -1, false, a)
        vim.api.nvim_buf_set_lines(bb, 0, -1, false, b)
        local wa = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(wa, ba)
        vim.cmd("diffthis | vsplit")
        vim.api.nvim_win_set_buf(0, bb)
        vim.cmd("diffthis")
        local out = vim.api.nvim_win_call(wa, function()
            local r = {}
            for l = 1, #a do
                r[l] = vim.fn.diff_filler(l)
            end
            return r
        end)
        vim.cmd("diffoff! | tabclose")
        return out
    end
    ok(vim.o.diffopt:find("linematch", 1, true), "default 'diffopt' has linematch")
    vim.o.diffexpr = ""
    local internal = fillers()
    vim.o.diffexpr = whitespace.EXPR
    local ours = fillers()
    vim.o.diffexpr = ""
    eq(ours, internal)
    eq(internal[2], 1, "the inserted line is a filler above 'alpha one', not a changed pair")
end)
