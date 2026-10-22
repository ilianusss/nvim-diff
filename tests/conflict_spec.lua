local H = require("tests.helpers")
local conflict = require("nvim-diff.conflict")

local TWO_WAY = { "a", "<<<<<<< HEAD", "ours", "=======", "theirs", ">>>>>>> other", "b" }
local DIFF3 = { "<<<<<<< HEAD", "ours", "||||||| base", "base", "=======", "theirs", ">>>>>>> other" }

local function buf_with(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
end

local function lines(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

test("parse finds regions, with and without a base", function()
    local r = conflict.parse(TWO_WAY)
    eq(#r, 1)
    eq({ r[1].first, r[1].last }, { 2, 6 })
    eq(r[1].ours, { "ours" })
    eq(r[1].theirs, { "theirs" })
    eq(r[1].base, nil)
    eq(conflict.parse(DIFF3)[1].base, { "base" })
    eq(#conflict.parse({ "<<<<<<<< not a marker", "=======" }), 0)
end)

test("choose replaces the region under the cursor", function()
    for which, expected in pairs({
        ours = { "a", "ours", "b" },
        theirs = { "a", "theirs", "b" },
        all = { "a", "ours", "theirs", "b" },
        none = { "a", "b" },
    }) do
        local buf = buf_with(TWO_WAY)
        eq(conflict.choose(buf, 3, which), 2)
        eq(lines(buf), expected, which)
    end
    local buf = buf_with(TWO_WAY)
    eq(select(2, conflict.choose(buf, 1, "ours")), "no conflict under the cursor")
    local first, err = conflict.choose(buf, 3, "base")
    eq(first, nil)
    ok(err:find("no base"), "base without diff3 markers is refused")
    eq(lines(buf), TWO_WAY, "untouched")
end)

test("choose_all handles every region; base works with diff3 markers", function()
    local buf = buf_with(vim.list_extend(vim.deepcopy(TWO_WAY), TWO_WAY))
    eq(conflict.choose_all(buf, "theirs"), 2)
    eq(lines(buf), { "a", "theirs", "b", "a", "theirs", "b" })
    buf = buf_with(DIFF3)
    conflict.choose_all(buf, "base")
    eq(lines(buf), { "base" })
end)

test("jump_target wraps around", function()
    local buf = buf_with(vim.list_extend(vim.deepcopy(TWO_WAY), TWO_WAY))
    eq(conflict.jump_target(buf, 1, 1), 2)
    eq(conflict.jump_target(buf, 2, 1), 9)
    eq(conflict.jump_target(buf, 9, 1), 2)
    eq(conflict.jump_target(buf, 2, -1), 9)
end)

test("a conflicted file opens 3 panes: OURS | LOCAL | THEIRS", function()
    local repo = H.repo({ ["keep.txt"] = "k\n" })
    repo:conflict("c.txt")
    local s = H.open(repo)
    ok(H.find_line(s, "^Conflicts %(1%)$"))
    ok(H.find_line(s, "c%.txt 1$"), "conflict count")
    eq(s.current.kind, "conflicting")
    eq(H.diff_names(s), { "nvim-diff://OURS/c.txt", repo.root .. "/c.txt", "nvim-diff://THEIRS/c.txt" })
    eq(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(s.wins[1]), 0, -1, false), { "start", "ours", "end" })
    eq(vim.api.nvim_win_get_cursor(s.wins[2])[1], 2, "cursor on the first conflict")
end)

test("resolve: take theirs, save, stage -> the file moves to Staged", function()
    local repo = H.repo({ ["keep.txt"] = "k\n" })
    repo:conflict("c.txt")
    local s = H.open(repo)
    vim.api.nvim_set_current_win(s.wins[2])
    vim.api.nvim_win_set_cursor(s.wins[2], { 3, 0 })
    H.run("choose_theirs")
    local buf = vim.api.nvim_win_get_buf(s.wins[2])
    eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "start", "theirs", "end" })
    vim.api.nvim_buf_call(buf, function()
        vim.cmd("silent write")
    end)
    H.run("toggle_stage")
    eq(#s.status.conflicting, 0)
    eq(s.current.kind, "staged")
    eq(#s.wins, 2, "back to two panes")
end)

test("staging with markers left asks first", function()
    local repo = H.repo({ ["keep.txt"] = "k\n" })
    repo:conflict("c.txt")
    local s = H.open(repo)
    H.stub_confirm(2)
    H.panel_cursor(s, "c%.txt")
    H.run("toggle_stage")
    ok(H.confirms[1]:find("not resolved", 1, true))
    eq(#s.status.conflicting, 1)
end)

test("conflict keys only exist in the conflict layout", function()
    local repo = H.repo({ ["keep.txt"] = "k\n" })
    repo:conflict("c.txt")
    -- Already open before the view (else close unloads it): its keys must be cleaned up
    local buf = vim.fn.bufadd(repo.root .. "/c.txt")
    vim.fn.bufload(buf)
    local s = H.open(repo)
    eq(vim.api.nvim_win_get_buf(s.wins[2]), buf)
    local function has(lhs)
        return vim.api.nvim_buf_call(buf, function()
            return vim.fn.maparg(lhs, "n", false, true).buffer == 1
        end)
    end
    ok(has("]x"))
    ok(has("2do"))
    eq(vim.diagnostic.is_enabled({ bufnr = buf }), false, "diagnostics off in LOCAL")
    s.quit_on_close = false
    require("nvim-diff").close()
    eq(has("]x"), false)
    eq(vim.diagnostic.is_enabled({ bufnr = buf }), true)
end)
