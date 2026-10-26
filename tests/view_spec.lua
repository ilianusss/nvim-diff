local H = require("tests.helpers")

test("open builds panel + two diff windows on the first file", function()
    local repo = H.repo({ ["a.txt"] = "1\n", ["b.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    repo:write("b.txt", "2\n")
    local s = H.open(repo)
    eq(#vim.api.nvim_tabpage_list_wins(s.tab), 3)
    eq(vim.api.nvim_get_current_win(), s.panel_win, "focus starts in the panel")
    eq(vim.api.nvim_win_get_width(s.panel_win), 35)
    eq(H.diff_names(s), { "nvim-diff://INDEX/a.txt", repo.root .. "/a.txt" })
    for _, w in ipairs(s.wins) do
        ok(vim.wo[w].diff, "diff mode in every diff window")
    end
    eq(vim.bo[vim.api.nvim_win_get_buf(s.wins[1])].modifiable, false, "left side is read-only")
    eq(vim.bo[vim.api.nvim_win_get_buf(s.wins[2])].buftype, "", "right side is the real file")
    ok(vim.wo[s.wins[2]].winbar:find("WORKING TREE", 1, true))
end)

test("selecting files: <CR>, next/prev with wrap-around, first/last", function()
    local repo = H.repo({ ["a.txt"] = "1\n", ["b.txt"] = "1\n", ["c.txt"] = "1\n" })
    for _, f in ipairs({ "a.txt", "b.txt", "c.txt" }) do
        repo:write(f, "2\n")
    end
    local s = H.open(repo)
    H.panel_cursor(s, "b%.txt")
    H.run("select")
    eq(s.current.path, "b.txt")
    H.run("next_file")
    eq(s.current.path, "c.txt")
    H.run("next_file")
    eq(s.current.path, "a.txt", "wraps around")
    H.run("prev_file")
    eq(s.current.path, "c.txt")
    H.run("first_file")
    eq(s.current.path, "a.txt")
    H.run("last_file")
    eq(s.current.path, "c.txt")
    ok(H.panel_lines(s)[vim.api.nvim_win_get_cursor(s.panel_win)[1]]:find("c%.txt"), "panel cursor follows")
end)

test("what each side shows: untracked, deleted, staged, staged new file", function()
    local repo = H.repo({ ["mod.txt"] = "1\n", ["del.txt"] = "x\n" })
    repo:write("u.txt", "u\n")
    os.remove(repo.root .. "/del.txt")
    repo:write("mod.txt", "2\n")
    repo:git("add", "mod.txt")
    repo:write("added.txt", "a\n")
    repo:git("add", "added.txt")
    local s = H.open(repo)
    local function show(kind, path)
        for _, e in ipairs(s.status[kind]) do
            if e.path == path then
                require("nvim-diff.view").select(e)
                return H.diff_names(s)
            end
        end
        error("no entry " .. kind .. ":" .. path)
    end
    eq(show("working", "u.txt"), { "nvim-diff://UNTRACKED/u.txt", repo.root .. "/u.txt" })
    eq(show("working", "del.txt"), { "nvim-diff://INDEX/del.txt", "nvim-diff://DELETED/del.txt" })
    -- Fully staged: index == disk, so the right side is the real, editable file
    eq(show("staged", "mod.txt"), { "nvim-diff://HEAD/mod.txt", repo.root .. "/mod.txt" })
    eq(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(s.wins[1]), 0, -1, false), { "1" })
    eq(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(s.wins[2]), 0, -1, false), { "2" })
    eq(vim.bo[vim.api.nvim_win_get_buf(s.wins[2])].modifiable, true)
    eq(show("staged", "added.txt"), { "nvim-diff://NEW FILE/added.txt", repo.root .. "/added.txt" })
end)

test("staged file with unstaged edits on top: the right side is the index", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    repo:git("add", "a.txt")
    repo:write("a.txt", "3\n")
    local s = H.open(repo)
    require("nvim-diff.view").select(s.status.staged[1])
    eq(H.diff_names(s), { "nvim-diff://HEAD/a.txt", "nvim-diff://INDEX/a.txt" })
    eq(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(s.wins[2]), 0, -1, false), { "2" })
end)

test("staging from the panel moves the file and the diff follows it", function()
    local repo = H.repo({ ["a.txt"] = "1\n", ["b.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    repo:write("b.txt", "2\n")
    local s = H.open(repo)
    H.panel_cursor(s, "a%.txt")
    H.run("toggle_stage")
    eq(#s.status.staged, 1)
    eq(s.current.kind, "staged")
    eq(s.current.path, "a.txt")
    ok(H.find_line(s, "^Staged changes %(1%)$"))
    H.panel_cursor(s, "^Staged changes")
    H.run("toggle_stage") -- on the section header: the whole section
    eq(#s.status.staged, 0)
    H.run("stage_all")
    eq(#s.status.staged, 2)
    H.run("unstage_all")
    eq(#s.status.working, 2)
end)

test("stage from a diff pane stages the shown file", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    local s = H.open(repo)
    vim.api.nvim_set_current_win(s.wins[2])
    H.run("toggle_stage")
    eq(s.current.kind, "staged")
end)

test("staging a folder stages every file in it", function()
    local repo = H.repo({ ["src/a.lua"] = "1\n", ["src/b.lua"] = "1\n", ["c.txt"] = "1\n" })
    for _, f in ipairs({ "src/a.lua", "src/b.lua", "c.txt" }) do
        repo:write(f, "2\n")
    end
    local s = H.open(repo)
    H.panel_cursor(s, "src$")
    H.run("toggle_stage")
    eq(#s.status.staged, 2)
    eq(s.status.working[1].path, "c.txt")
end)

test("staging asks first when the buffer has unsaved changes", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    local s = H.open(repo)
    local buf = vim.api.nvim_win_get_buf(s.wins[2])
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited" })
    H.stub_confirm(2) -- Cancel
    H.panel_cursor(s, "a%.txt")
    H.run("toggle_stage")
    eq(#H.confirms, 1)
    eq(#s.status.staged, 0, "cancel keeps the file unstaged")
    vim.bo[buf].modified = false
end)

test("restore asks, discards, backs up and refreshes", function()
    local repo = H.repo({ ["a.txt"] = "1\n", ["b.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    repo:write("b.txt", "2\n")
    repo:write("u.txt", "u\n")
    local s = H.open(repo)

    H.stub_confirm(2) -- Cancel
    H.panel_cursor(s, "a%.txt")
    H.run("restore")
    eq(repo:read("a.txt"), "2\n", "cancel keeps the change")

    H.stub_confirm(1) -- Discard
    H.run("restore")
    ok(H.confirms[1]:find("Discard changes to a.txt", 1, true), H.confirms[1])
    eq(repo:read("a.txt"), "1\n")
    eq(#s.status.working, 2)
    eq(vim.api.nvim_buf_get_lines(vim.fn.bufnr(repo.root .. "/a.txt"), 0, -1, false), { "1" }, "buffer reloaded")

    H.panel_cursor(s, "u%.txt")
    H.run("restore")
    ok(H.confirms[2]:find("Delete untracked file u.txt", 1, true), H.confirms[2])
    eq(repo:exists("u.txt"), false)
end)

test("keymaps are buffer-local, and a user's own mapping comes back after close", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    local file_buf = vim.fn.bufadd(repo.root .. "/a.txt")
    vim.fn.bufload(file_buf)
    vim.keymap.set("n", "q", "<cmd>echo 'mine'<CR>", { buffer = file_buf, desc = "user q" })

    local s = H.open(repo)
    eq(vim.api.nvim_win_get_buf(s.wins[2]), file_buf)
    local q = vim.api.nvim_buf_call(file_buf, function()
        return vim.fn.maparg("q", "n", false, true)
    end)
    ok(q.desc:find("nvim%-diff"), "view key while in the view")
    ok(vim.api
        .nvim_buf_call(s.panel_buf, function()
            return vim.fn.maparg("S", "n", false, true).desc
        end)
        :find("Stage all"))

    s.quit_on_close = false
    require("nvim-diff").close()
    q = vim.api.nvim_buf_call(file_buf, function()
        return vim.fn.maparg("q", "n", false, true)
    end)
    eq(q.desc, "user q", "user mapping restored")
    eq(vim.fn.maparg("<Tab>", "n", false, true).buffer, nil, "no view key left")
end)

test("close removes the tab and the scratch buffers; :NvimDiff reuses an open view", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    local s = H.open(repo)
    local first_tab = vim.api.nvim_list_tabpages()[1]
    vim.api.nvim_set_current_tabpage(first_tab)
    eq(H.open(repo), s, "focuses the existing session")
    eq(vim.api.nvim_get_current_tabpage(), s.tab)
    local scratch = vim.api.nvim_win_get_buf(s.wins[1])
    s.quit_on_close = false
    vim.cmd("NvimDiffClose")
    eq(require("nvim-diff.view").session, nil)
    eq(#vim.api.nvim_list_tabpages(), 1)
    eq(vim.api.nvim_buf_is_valid(scratch), false)
end)

test("closing the tab by hand cleans the session up", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    H.open(repo)
    vim.cmd("tabclose")
    H.wait(function()
        return require("nvim-diff.view").session == nil
    end, 1000, "session torn down")
    eq(vim.o.diffexpr, "")
end)

test("toggle_panel hides and shows the panel; diff windows keep working", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    local s = H.open(repo)
    H.run("toggle_panel")
    eq(s.panel_win, nil)
    eq(#vim.api.nvim_tabpage_list_wins(s.tab), 2)
    H.run("focus_panel")
    ok(s.panel_win and vim.api.nvim_win_is_valid(s.panel_win))
    eq(vim.api.nvim_get_current_win(), s.panel_win)
end)

test("gf opens the file in the previous tab", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    local before = vim.api.nvim_get_current_tabpage()
    local s = H.open(repo)
    H.panel_cursor(s, "a%.txt")
    H.run("goto_file")
    eq(vim.api.nvim_get_current_tabpage(), before)
    eq(vim.api.nvim_buf_get_name(0), repo.root .. "/a.txt")
end)

test("help lists the keys of the context", function()
    local lines = require("nvim-diff.help").lines({ "panel" })
    eq(lines[1], "File panel")
    local joined = table.concat(lines, "\n")
    ok(joined:find("<CR>, l, o", 1, true), joined)
    ok(joined:find("Stage all changes", 1, true))
end)

test("not a repo: open returns nil with an error", function()
    local msgs = {}
    local orig = vim.notify
    vim.notify = function(m)
        msgs[#msgs + 1] = m
    end
    local s = require("nvim-diff").open({ path = vim.fn.tempname() })
    vim.notify = orig
    eq(s, nil)
    ok(msgs[1]:find("not in a git repository", 1, true))
end)

test("discarding the shown file moves to the nearest file, not the first", function()
    local repo = H.repo({ ["a.txt"] = "1\n", ["b.txt"] = "1\n", ["c.txt"] = "1\n" })
    for _, f in ipairs({ "a.txt", "b.txt", "c.txt" }) do
        repo:write(f, "2\n")
    end
    local s = H.open(repo)
    H.panel_cursor(s, "b%.txt")
    H.run("select")
    H.stub_confirm(1)
    H.run("restore")
    eq(s.current.path, "c.txt")
end)

test("an async refresh that started before a newer one is dropped", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    require("nvim-diff").setup({ live_refresh = { enabled = false } })
    local s = H.open(repo)
    local view = require("nvim-diff.view")
    local git = require("nvim-diff.git")
    -- Hold the async status result until after the sync refresh that follows staging
    local orig, pending = git.status, nil
    git.status = function(root, cb)
        if not cb then
            return orig(root)
        end
        local stale = orig(root)
        pending = function()
            cb(stale)
        end
    end
    view.refresh()
    git.status = orig
    H.run("toggle_stage")
    eq(#s.status.staged, 1)
    pending()
    eq(#s.status.staged, 1, "stale result ignored")
end)

test("reviewed files stay out of the buffer list and are unloaded on close", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    local s = H.open(repo)
    local buf = vim.api.nvim_win_get_buf(s.wins[2])
    eq(vim.bo[buf].buflisted, false)
    s.quit_on_close = false
    require("nvim-diff").close()
    eq(vim.api.nvim_buf_is_loaded(buf), false)
end)

test(":NvimDiff on another repo replaces the view", function()
    local one = H.repo({ ["a.txt"] = "1\n" })
    local two = H.repo({ ["b.txt"] = "1\n" })
    local s1 = H.open(one)
    local s2 = H.open(two)
    ok(s1 ~= s2)
    eq(s2.root, two.root)
    eq(#vim.api.nvim_list_tabpages(), 2)
end)

test("full file by default; zF folds the unchanged lines, and back", function()
    local lines = {}
    for i = 1, 40 do
        lines[i] = "line " .. i
    end
    local repo = H.repo({ ["long.txt"] = table.concat(lines, "\n") .. "\n" })
    lines[20] = "changed"
    repo:write("long.txt", table.concat(lines, "\n") .. "\n")
    local s = H.open(repo)
    local function folded_line1()
        return vim.api.nvim_win_call(s.wins[2], function()
            return vim.fn.foldclosed(1)
        end)
    end
    eq(vim.wo[s.wins[2]].foldenable, false)
    eq(folded_line1(), -1, "line 1 visible")
    H.run("toggle_full_file")
    eq(s.full_file, false)
    eq(folded_line1(), 1, "unchanged lines folded")
    ok(vim.wo[s.panel_win].winbar:find("Folded", 1, true))
    H.run("next_file") -- the setting sticks across files
    eq(vim.wo[s.wins[2]].foldenable, true)
    H.run("toggle_full_file")
    eq(folded_line1(), -1)
end)

test(":tabclose | NvimDiff reopens the view at once and stops the old watcher", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    local old = H.open(repo)
    local stopped = false
    local stop = old.watcher.stop
    old.watcher.stop = function()
        stopped = true
        stop()
    end
    local reopened, err = pcall(vim.cmd, "tabclose | NvimDiff " .. vim.fn.fnameescape(repo.root))
    ok(reopened, err)
    local s = require("nvim-diff.view").session
    ok(s and s ~= old, "a new session")
    eq(vim.api.nvim_buf_get_name(s.panel_buf), "nvim-diff://panel")
    ok(stopped, "the old session's watcher is stopped")
end)

test("restore discards nothing when the backup fails", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "2\n")
    local s = H.open(repo)
    vim.uv.fs_chmod(repo.root .. "/a.txt", 0) -- git cannot read it, so cannot back it up
    local errors = {}
    H.stub_notify(errors, vim.log.levels.ERROR)
    H.stub_confirm(1)
    H.panel_cursor(s, "a%.txt")
    H.run("restore")
    vim.uv.fs_chmod(repo.root .. "/a.txt", tonumber("644", 8))
    eq(repo:read("a.txt"), "2\n")
    ok(errors[1] and errors[1]:find("backup failed, nothing discarded", 1, true), vim.inspect(errors))
end)

test("discarding a staged file with unstaged edits on top lists its staged version for recovery", function()
    local repo = H.repo({ ["a.txt"] = "1\n" })
    repo:write("a.txt", "staged\n")
    repo:git("add", "a.txt")
    repo:write("a.txt", "unstaged\n")
    local s = H.open(repo)
    local infos = {}
    H.stub_notify(infos, vim.log.levels.INFO)
    H.stub_confirm(1)
    H.panel_cursor(s, "^Staged changes")
    H.run("restore")
    eq(repo:read("a.txt"), "1\n")
    local message = table.concat(infos, "\n")
    local hashes = {}
    for hash in message:gmatch("git cat%-file %-p (%x+)") do
        hashes[#hashes + 1] = vim.trim(repo:git("cat-file", "-p", hash))
    end
    table.sort(hashes)
    eq(hashes, { "staged", "unstaged" }, message)
end)
