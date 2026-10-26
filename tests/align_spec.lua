local H = require("tests.helpers")

local LONG = vim.trim(string.rep("word ", 80)) -- wraps in a diff window of the 200-column test screen

---Screen rows above line `lnum` of the window, from the top of the buffer. Not screenpos(): it needs
---a redraw, and a headless redraw of the tabline after run.lua's `columns = 200` writes past the
---screen grid (Neovim 0.12.5).
local function row(win, lnum)
    return vim.api.nvim_win_text_height(win, { end_row = lnum - 1, end_vcol = 0 }).all
end

test("diff windows wrap long lines", function()
    local repo = H.repo({ ["a.txt"] = "short\n" })
    repo:write("a.txt", LONG .. "\n")
    local s = H.open(repo)
    for _, w in ipairs(s.wins) do
        ok(vim.wo[w].wrap, "wrap")
        ok(vim.wo[w].linebreak, "linebreak")
    end
end)

test("a line wrapping longer on one side is padded on the other: the lines below stay aligned", function()
    local repo = H.repo({ ["a.txt"] = "first\nshort\nthird\nlast\n" })
    repo:write("a.txt", "first\n" .. LONG .. "\nthird\nlast\n")
    local s = H.open(repo)
    local left, right = s.wins[1], s.wins[2]
    ok(row(right, 3) - row(right, 2) > 1, "the long line wraps")
    eq(row(left, 3), row(right, 3))
    eq(row(left, 4), row(right, 4))
end)

test("a deleted line that wraps is padded beyond the one filler row on the other side", function()
    local repo = H.repo({ ["a.txt"] = "first\n" .. LONG .. "\nthird\n" })
    repo:write("a.txt", "first\nthird\n")
    local s = H.open(repo)
    local left, right = s.wins[1], s.wins[2]
    ok(row(left, 3) - row(left, 2) > 1, "the deleted line wraps")
    eq(row(right, 2), row(left, 3))
end)

test("padding follows edits of the real file", function()
    local repo = H.repo({ ["a.txt"] = "first\nshort\nthird\n" })
    repo:write("a.txt", "first\n" .. LONG .. "\nthird\n")
    local s = H.open(repo)
    local left, right = s.wins[1], s.wins[2]
    vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(right), 1, 2, false, { "short too" })
    H.wait(function()
        return row(left, 3) == row(right, 3)
    end, 1000, "the padding is redone")
    eq(row(left, 3), row(left, 2) + 1, "no padding left")
end)

test("padding follows the window width", function()
    local repo = H.repo({ ["a.txt"] = "first\nshort\nthird\n" })
    repo:write("a.txt", "first\n" .. LONG .. "\nthird\n")
    local s = H.open(repo)
    local left, right = s.wins[1], s.wins[2]
    local before = row(right, 3) - row(right, 2)
    H.run("toggle_panel")
    ok(row(right, 3) - row(right, 2) < before, "wider windows, fewer wrapped rows")
    eq(row(left, 3), row(right, 3))
end)

local function padding_marks(buf)
    local ns = vim.api.nvim_get_namespaces()["nvim-diff-align"]
    return ns and vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) or {}
end

test("wrap = false keeps diff mode's nowrap and adds no padding", function()
    require("nvim-diff.config").setup({ wrap = false })
    local repo = H.repo({ ["a.txt"] = "first\nshort\nthird\n" })
    repo:write("a.txt", "first\n" .. LONG .. "\nthird\n")
    local s = H.open(repo)
    for _, w in ipairs(s.wins) do
        eq(vim.wo[w].wrap, false)
        eq(padding_marks(vim.api.nvim_win_get_buf(w)), {})
    end
end)

---Repo where the real file is the shorter side, so the padding goes in its buffer, which is also
---open in a window of the first tab.
local function real_file_padded()
    local repo = H.repo({ ["a.txt"] = "first\n" .. LONG .. "\nthird\n" })
    repo:write("a.txt", "first\nshort\nthird\n")
    vim.cmd("edit " .. vim.fn.fnameescape(repo.root .. "/a.txt"))
    local other = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_get_current_buf()
    local s = H.open(repo)
    ok(#padding_marks(buf) > 0, "the real file is padded")
    return s, other, buf
end

test("the padding only shows in the review windows", function()
    local s, other = real_file_padded()
    eq(row(s.wins[1], 3), row(s.wins[2], 3))
    vim.api.nvim_set_current_win(other)
    eq(row(other, 3), row(other, 2) + 1)
end)

test("closing the view removes the padding", function()
    local _, _, buf = real_file_padded()
    require("nvim-diff").close()
    eq(padding_marks(buf), {})
end)

test("closing the review tab by hand removes the padding", function()
    local s, _, buf = real_file_padded()
    vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(s.tab))
    H.wait(function()
        return #padding_marks(buf) == 0
    end, 1000, "padding removed")
end)

test("lines added at the end next to a wrapped line keep the sides aligned", function()
    local repo = H.repo({ ["a.txt"] = "first\n" })
    repo:write("a.txt", "first\n" .. LONG .. "\nthird\n")
    local s = H.open(repo)
    local function height(win)
        return vim.api.nvim_win_text_height(win, {}).all
    end
    eq(height(s.wins[1]), height(s.wins[2]), "padding below the last line included")
end)

test("an untracked file is padded against the empty side", function()
    local repo = H.repo({ ["keep.txt"] = "x\n" })
    repo:write("new.txt", "first\n" .. LONG .. "\nthird\n")
    local s = H.open(repo)
    eq(H.diff_names(s)[1], "nvim-diff://UNTRACKED/new.txt")
    -- The empty side shows its one empty line under the filler and padding
    eq(row(s.wins[1], 1), vim.api.nvim_win_text_height(s.wins[2], {}).all)
end)

test("the three conflict windows stay aligned", function()
    local repo = H.repo()
    repo:conflict("c.txt")
    local s = H.open(repo)
    eq(#s.wins, 3)
    local local_buf = vim.api.nvim_win_get_buf(s.wins[2])
    vim.api.nvim_buf_set_lines(local_buf, 0, 1, false, { "start " .. LONG })
    ok(row(s.wins[2], 2) > 1, "the edited line wraps")
    -- "end": line 3 of OURS and THEIRS, line 7 of LOCAL (under the conflict markers)
    H.wait(function()
        return row(s.wins[1], 3) == row(s.wins[2], 7) and row(s.wins[3], 3) == row(s.wins[2], 7)
    end, 1000, "OURS and THEIRS padded like LOCAL")
end)

test("folded mode (zF) keeps the sides aligned", function()
    local context = string.rep("same\n", 20)
    local repo = H.repo({ ["a.txt"] = context .. "short\n" .. context })
    repo:write("a.txt", context .. LONG .. "\n" .. context)
    local s = H.open(repo)
    local left, right = s.wins[1], s.wins[2]
    H.run("toggle_full_file")
    ok(vim.wo[left].foldenable)
    eq(row(left, 22), row(right, 22))
    eq(row(left, 41), row(right, 41))
end)
