local H = require("tests.helpers")
local filter = require("nvim-diff.filter")
local git = require("nvim-diff.git")

local SETTINGS = '{\n  "a": 1,\n  "b": 2\n}\n'

---Repo whose settings.json goes through a clean filter that drops the "model" lines, like a
---settings file keeping a local-only key out of git.
local function filtered_repo()
    local repo = H.repo({ [".gitattributes"] = "settings.json filter=strip\n", ["settings.json"] = SETTINGS })
    repo:git("config", "filter.strip.clean", "sed /model/d")
    repo:git("config", "filter.strip.smudge", "cat")
    return repo
end

test("a file whose only change is dropped by its clean filter is not listed", function()
    local repo = filtered_repo()
    repo:write("settings.json", '{\n  "model": "opus",\n  "a": 1,\n  "b": 2\n}\n')
    eq(assert(git.status(repo.root)).working, {})
end)

test("clean reads the working-tree file through its clean filter", function()
    local repo = filtered_repo()
    repo:write("settings.json", '{\n  "model": "opus",\n  "a": 1,\n  "b": 3\n}\n')
    eq(git.clean(repo.root, "settings.json"), { "{", '  "a": 1,', '  "b": 3', "}" })
end)

test("filter_driver names the driver of a path's filter attribute, nil without one", function()
    local repo = filtered_repo()
    eq(git.filter_driver(repo.root, "settings.json"), "strip")
    eq(git.filter_driver(repo.root, "other.json"), nil)
end)

test("clean reports a required filter that fails", function()
    local repo = filtered_repo()
    repo:git("config", "filter.strip.clean", "false")
    repo:git("config", "filter.strip.required", "true")
    local lines, err = git.clean(repo.root, "settings.json")
    eq(lines, nil)
    ok(err and err:find("clean filter", 1, true), "error from git: " .. tostring(err))
end)

test("splice puts a line the filter removed back at its place on the git side", function()
    local blob = { "{", '  "a": 1,', '  "b": 2', "}" }
    local clean = { "{", '  "a": 1,', '  "b": 3', "}" }
    local raw = { "{", '  "model": "opus",', '  "a": 1,', '  "b": 3', "}" }
    eq(filter.splice(blob, clean, raw), { "{", '  "model": "opus",', '  "a": 1,', '  "b": 2', "}" })
end)

test("splice takes a line the filter rewrote from the working-tree file", function()
    -- Dropping the last key takes the comma off the line above it
    local blob = { "{", '  "x": 1,', '  "a": 1', "}" }
    local clean = { "{", '  "x": 2,', '  "a": 1', "}" }
    local raw = { "{", '  "x": 2,', '  "a": 1,', '  "model": "opus"', "}" }
    eq(filter.splice(blob, clean, raw), { "{", '  "x": 1,', '  "a": 1,', '  "model": "opus"', "}" })
end)

test("splice leaves the git side as is where a real change overlaps the filtered lines", function()
    local blob = { "{", '  "a": 1', "}" }
    local clean = { "{", '  "a": 2', "}" }
    local raw = { "{", '  "a": 2,', '  "model": "opus"', "}" }
    eq({ filter.splice(blob, clean, raw) }, { blob, false })
end)

test("splice keeps a filtered line and a deleted line at the same place", function()
    local blob = { "{", '  "a": 1', "}" }
    local clean = { "{", "}" }
    local raw = { "{", '  "model": "opus"', "}" }
    eq(filter.splice(blob, clean, raw), { "{", '  "model": "opus"', '  "a": 1', "}" })
end)

test("splice returns the git side as is when the filter changes nothing", function()
    local blob = { "x", "y" }
    eq({ filter.splice(blob, { "x", "y2" }, { "x", "y2" }) }, { blob, false })
end)

local WITH_MODEL = '{\n  "model": "opus",\n  "a": 1,\n  "b": 3\n}\n'

test("Changes: the filtered line is not highlighted and the real file stays editable", function()
    local repo = filtered_repo()
    repo:write("settings.json", WITH_MODEL)
    local s = H.open(repo)
    eq(H.diff_names(s), { "nvim-diff://INDEX/settings.json", repo.root .. "/settings.json" })
    eq(H.changed_lines(s.wins[2]), { 4 })
    eq(vim.bo[vim.api.nvim_win_get_buf(s.wins[2])].modifiable, true)
    ok(vim.wo[s.wins[1]].winbar:find("INDEX (FILTERED)", 1, true), vim.wo[s.wins[1]].winbar)
end)

test("Staged changes: HEAD gets the filtered line of the real file", function()
    local repo = filtered_repo()
    repo:write("settings.json", WITH_MODEL)
    repo:git("add", "settings.json")
    local s = H.open(repo)
    eq(s.current.kind, "staged")
    eq(H.diff_names(s), { "nvim-diff://HEAD/settings.json", repo.root .. "/settings.json" })
    eq(H.changed_lines(s.wins[2]), { 4 })
    ok(vim.wo[s.wins[1]].winbar:find("HEAD (FILTERED)", 1, true), vim.wo[s.wins[1]].winbar)
end)

test("a filtered line typed in the buffer is highlighted until the file is written", function()
    local repo = filtered_repo()
    repo:write("settings.json", WITH_MODEL)
    local s = H.open(repo)
    local win = s.wins[2]
    local buf = vim.api.nvim_win_get_buf(win)
    vim.api.nvim_buf_set_lines(buf, 1, 1, false, { '  "model": "sonnet",' })
    vim.api.nvim_win_call(win, function()
        vim.cmd("diffupdate")
    end)
    eq(H.changed_lines(win), { 2, 5 })

    vim.api.nvim_buf_call(buf, function()
        vim.cmd("silent write")
    end)
    H.wait(function()
        return vim.deep_equal(H.changed_lines(win), { 5 })
    end, 5000, "typed line no longer highlighted after :w")
end)

test("a filtered line written by another process is not highlighted after the live refresh", function()
    local repo = filtered_repo()
    repo:write("settings.json", '{\n  "a": 1,\n  "b": 3\n}\n')
    local s = H.open(repo)
    local win = s.wins[2]
    eq(H.changed_lines(win), { 3 })
    ok(not vim.wo[s.wins[1]].winbar:find("FILTERED", 1, true), "nothing filtered yet")

    repo:write("settings.json", WITH_MODEL)
    H.wait(function()
        return vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)) == 5
            and vim.deep_equal(H.changed_lines(win), { 4 })
    end, 5000, "file reloaded, model line not highlighted")
    ok(vim.wo[s.wins[1]].winbar:find("INDEX (FILTERED)", 1, true), vim.wo[s.wins[1]].winbar)
end)

test("a filter whose driver is not configured in the clone changes nothing, like in git diff", function()
    local repo = filtered_repo()
    repo:git("config", "--unset", "filter.strip.clean")
    repo:write("settings.json", WITH_MODEL)
    local s = H.open(repo)
    eq(H.changed_lines(s.wins[2]), { 2, 4 })
    ok(not vim.wo[s.wins[1]].winbar:find("FILTERED", 1, true), vim.wo[s.wins[1]].winbar)
end)

test("a mode-only change has no changed lines and is still listed", function()
    local repo = H.repo({ ["run.sh"] = "echo\n" })
    vim.uv.fs_chmod(repo.root .. "/run.sh", tonumber("755", 8))
    local working = assert(git.status(repo.root)).working
    eq(#working, 1)
    eq(working[1].stats, { additions = 0, deletions = 0 })
end)
