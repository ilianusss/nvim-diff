local ROOT = vim.fn.fnamemodify(vim.api.nvim_get_runtime_file("lua/nvim-diff/health.lua", false)[1], ":h:h:h")

---Runs `:checkhealth nvim-diff` in a child Neovim and returns the report. In-process, a second
---:checkhealth after a failed test crashed `nvim -l` (0.12.5).
---@param opts? { setup?: string, path?: string } setup: Lua run before the check; path: the child's $PATH
---@return string
local function checkhealth(opts)
    opts = opts or {}
    local out = vim.fn.tempname()
    local res = vim.system({
        vim.v.progpath,
        "--clean",
        "--headless",
        "-n",
        "--cmd",
        "set rtp^=" .. ROOT,
        "-c",
        "lua " .. (opts.setup or ""),
        "-c",
        "checkhealth nvim-diff",
        "-c",
        ("lua vim.fn.writefile(vim.api.nvim_buf_get_lines(0, 0, -1, false), %q)"):format(out),
        "-c",
        "qa!",
    }, { env = opts.path and { PATH = opts.path } or nil }):wait()
    assert(res.code == 0, res.stderr)
    return table.concat(vim.fn.readfile(out), "\n")
end

---A directory holding a `git` that only prints `version_line`.
local function fake_git_dir(version_line)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "#!/bin/sh", "echo '" .. version_line .. "'" }, dir .. "/git")
    vim.uv.fs_chmod(dir .. "/git", tonumber("755", 8))
    return dir
end

test("checkhealth: a supported setup is OK", function()
    local report = checkhealth()
    ok(report:find("OK Neovim " .. tostring(vim.version()), 1, true), report)
    ok(report:find("OK git %d+%.%d+"), report)
    ok(not report:find("ERROR", 1, true), report)
end)

test("checkhealth: git older than 2.23 is an error", function()
    local report = checkhealth({ path = fake_git_dir("git version 2.22.5") .. ":" .. vim.env.PATH })
    ok(report:find("ERROR git 2.22.5 is too old: 2.23 or newer is needed", 1, true), report)
end)

test("checkhealth: a git build suffix does not hide its version", function()
    local report = checkhealth({ path = fake_git_dir("git version 2.45.1.windows.1") .. ":" .. vim.env.PATH })
    ok(report:find("OK git 2.45.1", 1, true), report)
end)

test("checkhealth: no git on $PATH is an error", function()
    local empty = vim.fn.tempname()
    vim.fn.mkdir(empty, "p")
    local report = checkhealth({ path = empty })
    ok(report:find("ERROR git not found", 1, true), report)
end)

test("checkhealth: an unknown action in keymaps is a warning naming it", function()
    local report = checkhealth({
        setup = [[require("nvim-diff").setup({ keymaps = { view = { ["<C-x>"] = "stage_everything" } } })]],
    })
    ok(report:find('WARNING Unknown action names: keymaps.view["<C-x>"] = "stage_everything"', 1, true), report)
end)

test("checkhealth: reports the live refresh mode", function()
    local report = checkhealth()
    local mode = (vim.fn.has("mac") == 1 or vim.fn.has("win32") == 1) and "file system events" or "polling"
    ok(report:find("Live refresh: " .. mode, 1, true), report)
end)

test("checkhealth: a git that fails to run is an error saying so", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "#!/bin/sh", "echo 'broken install' >&2", "exit 1" }, dir .. "/git")
    vim.uv.fs_chmod(dir .. "/git", tonumber("755", 8))
    local report = checkhealth({ path = dir .. ":" .. vim.env.PATH })
    ok(report:find("ERROR `git --version` failed: broken install", 1, true), report)
end)
