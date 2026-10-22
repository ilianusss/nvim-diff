local H = require("tests.helpers")
local panel = require("nvim-diff.panel")
local tree = require("nvim-diff.tree")

local function entry(path, status, kind)
    return { path = path, status = status or "M", kind = kind or "working", hashes = {} }
end

local function names(nodes)
    return vim.tbl_map(function(n)
        return n.type == "dir" and (n.name .. "/") or n.name
    end, nodes)
end

test("tree: folders first, sorted, single-child chains flattened", function()
    local nodes = tree.build({
        entry("z.txt"),
        entry("a/b/c/deep.lua"),
        entry("lib/x.lua"),
        entry("lib/sub/y.lua"),
        entry("B.txt"),
    }, true)
    eq(names(nodes), { "a/b/c/", "lib/", "B.txt", "z.txt" })
    eq(nodes[1].path, "a/b/c")
    eq(names(nodes[2].children), { "sub/", "x.lua" })
end)

test("tree: no flattening keeps every level", function()
    local nodes = tree.build({ entry("a/b/c.lua") }, false)
    eq(names(nodes), { "a/" })
    eq(names(nodes[1].children), { "b/" })
end)

test("tree: folder status is the shared status, else M", function()
    local nodes = tree.build({ entry("d/a", "A"), entry("d/b", "A"), entry("e/a", "A"), entry("e/b", "D") }, true)
    eq(nodes[1].status, "A")
    eq(nodes[2].status, "M")
end)

test("panel shows the root, the sections with counts and stats", function()
    local repo = H.repo({ ["lua/a.lua"] = "1\n", ["b.txt"] = "1\n" })
    repo:write("lua/a.lua", "1\n2\n")
    repo:write("b.txt", "2\n")
    repo:git("add", "b.txt")
    repo:write("new.md", "n\n")
    local s = H.open(repo)
    local lines = H.panel_lines(s)
    ok(lines[1]:find(vim.fs.basename(repo.root), 1, true), "root path on the first line")
    eq(lines[2], "Help: g?")
    ok(H.find_line(s, "^Changes %(2%)$"), "Changes (2)")
    ok(H.find_line(s, "^Staged changes %(1%)$"), "Staged changes (1)")
    ok(H.find_line(s, "a%.lua 1, 0"), "stats after the file name")
    ok(H.find_line(s, "^%?   .*new%.md"), "untracked status letter")
    eq(H.find_line(s, "^Conflicts"), nil)
end)

test("panel: empty repo still shows Changes (0)", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    local s = H.open(repo)
    ok(H.find_line(s, "^Changes %(0%)$"))
end)

test("panel: list mode shows parent paths, i toggles back to tree", function()
    local repo = H.repo({ ["src/deep/a.lua"] = "1\n" })
    repo:write("src/deep/a.lua", "2\n")
    local s = H.open(repo)
    ok(H.find_line(s, "src/deep$"), "flattened folder in tree mode")
    H.run("listing_style")
    eq(s.listing_style, "list")
    ok(H.find_line(s, "a%.lua 1, 1 src/deep$"), "parent path after the stats")
    H.run("listing_style")
    eq(s.listing_style, "tree")
end)

test("panel: folders fold and unfold, the cursor stays on the folder", function()
    local repo = H.repo({ ["src/a.lua"] = "1\n", ["src/b.lua"] = "1\n" })
    repo:write("src/a.lua", "2\n")
    repo:write("src/b.lua", "2\n")
    local s = H.open(repo)
    H.panel_cursor(s, "src$")
    H.run("select") -- <CR> on a folder folds it
    eq(H.find_line(s, "a%.lua"), nil)
    ok(H.panel_lines(s)[vim.api.nvim_win_get_cursor(s.panel_win)[1]]:find("src$"))
    H.run("open_fold")
    ok(H.find_line(s, "a%.lua"))
    H.panel_cursor(s, "b%.lua")
    H.run("close_fold") -- `h` on a file folds its folder
    eq(H.find_line(s, "b%.lua"), nil)
    H.run("open_all_folds")
    ok(H.find_line(s, "b%.lua"))
    H.run("close_all_folds")
    eq(H.find_line(s, "b%.lua"), nil)
end)

test("options bar shows the whitespace and listing state", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    local s = H.open(repo)
    local bar = vim.wo[s.panel_win].winbar
    ok(bar:find("WS ignored", 1, true), bar)
    ok(bar:find(" Full ", 1, true), bar)
    ok(bar:find(" Tree ", 1, true), bar)
    ok(bar:find("v:lua.__nvim_diff_click", 1, true), bar)
    _G.__nvim_diff_click(1, 1, "l", "    ")
    ok(vim.wo[s.panel_win].winbar:find("WS shown", 1, true))
    _G.__nvim_diff_click(2, 1, "l", "    ")
    eq(s.listing_style, "list")
end)

test("ordered entries follow the panel: conflicts, changes, staged", function()
    local repo = H.repo({ ["z.txt"] = "1\n", ["a.txt"] = "1\n" })
    repo:write("z.txt", "2\n")
    repo:write("a.txt", "2\n")
    repo:git("add", "z.txt")
    local s = H.open(repo)
    eq(
        vim.tbl_map(function(e)
            return e.kind .. ":" .. e.path
        end, panel.ordered_entries(s)),
        { "working:a.txt", "staged:z.txt" }
    )
end)
