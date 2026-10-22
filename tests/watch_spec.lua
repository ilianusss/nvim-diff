local H = require("tests.helpers")
local watch = require("nvim-diff.watch")

test("watcher calls back (debounced) when a file changes", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    local calls = 0
    local w = watch.start(repo.root, repo.root .. "/.git", { debounce_ms = 50, poll_ms = 100 }, function()
        calls = calls + 1
    end)
    vim.wait(100) -- let fs events start
    for i = 1, 5 do
        repo:write("a.txt", i .. "\n")
    end
    H.wait(function()
        return calls > 0
    end, 3000, "watcher callback")
    if w.kind == "fs_event" then
        vim.wait(200)
        eq(calls, 1, "five writes, one debounced call")
    end
    w.stop()
end)

test("the view refreshes by itself when an agent writes files", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    local s = H.open(repo)
    ok(H.find_line(s, "^Changes %(0%)$"))
    ok(s.watcher, "live refresh on by default")

    repo:write("a.txt", "2\n")
    repo:write("new.txt", "n\n")
    H.wait(function()
        return H.find_line(s, "^Changes %(2%)$") ~= nil
    end, 5000, "panel picks up the external writes")
    eq(s.current and s.current.path, "a.txt", "first file shown once it appears")

    -- The file shown is rewritten again: the real buffer reloads, the diff follows
    repo:write("a.txt", "3\n")
    H.wait(function()
        return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(s.wins[2]), 0, -1, false)[1] == "3"
    end, 5000, "real buffer reloaded")
end)

test("staging from another tool shows up without pressing R", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    local s = H.open(repo)
    repo:git("add", "a.txt")
    H.wait(function()
        return #s.status.staged == 1
    end, 5000, "index change picked up")
end)

test("live_refresh.enabled = false: no watcher, R still works", function()
    require("nvim-diff").setup({ live_refresh = { enabled = false } })
    local repo = H.repo({ ["a.txt"] = "1\n" })
    local s = H.open(repo)
    eq(s.watcher, nil)
    repo:write("a.txt", "2\n")
    H.run("refresh")
    eq(#s.status.working, 1)
end)
