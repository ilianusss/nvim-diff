-- Test helpers: temporary git repos, opening the view, waiting, stubbing prompts.

local M = {}

local dirs = {}
local restores = {}

---@class TestRepo
---@field root string
local Repo = {}
Repo.__index = Repo

local function git(root, args, allow_fail)
    local cmd = { "git", "-C", root }
    vim.list_extend(cmd, args)
    local res = vim.system(cmd, { text = true }):wait()
    if res.code ~= 0 and not allow_fail then
        error(("git %s failed: %s"):format(table.concat(args, " "), res.stderr), 3)
    end
    return res.stdout, res.code
end

---Runs git in the repo; errors unless it succeeds. Returns stdout.
function Repo:git(...)
    return (git(self.root, { ... }))
end

---Runs git in the repo and returns stdout, exit code (no error on failure).
function Repo:try_git(...)
    return git(self.root, { ... }, true)
end

function Repo:write(path, text)
    local file = self.root .. "/" .. path
    vim.fn.mkdir(vim.fs.dirname(file), "p")
    local f = assert(io.open(file, "wb"))
    f:write(text)
    f:close()
end

function Repo:read(path)
    local f = io.open(self.root .. "/" .. path, "rb")
    if not f then
        return nil
    end
    local text = f:read("*a")
    f:close()
    return text
end

function Repo:exists(path)
    return vim.uv.fs_stat(self.root .. "/" .. path) ~= nil
end

function Repo:commit(msg)
    self:git("add", "-A")
    self:git("commit", "-q", "-m", msg or "commit")
end

---Creates a real merge conflict on `path` (main: "ours", branch other: "theirs").
function Repo:conflict(path, opts)
    opts = opts or {}
    if opts.diff3 then
        self:git("config", "merge.conflictStyle", "diff3")
    end
    self:write(path, "start\nbase\nend\n")
    self:commit("base")
    self:git("checkout", "-q", "-b", "other")
    self:write(path, "start\ntheirs\nend\n")
    self:commit("theirs")
    self:git("checkout", "-q", "main")
    self:write(path, "start\nours\nend\n")
    self:commit("ours")
    local _, code = self:try_git("merge", "-q", "other")
    assert(code ~= 0, "expected a merge conflict")
end

---New temp repo. With `files` (path -> content), they are committed.
---@param files? table<string, string>
---@return TestRepo
function M.repo(files)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    dir = vim.uv.fs_realpath(dir) -- macOS: /var -> /private/var, as git reports it
    dirs[#dirs + 1] = dir
    local r = setmetatable({ root = dir }, Repo)
    r:git("init", "-q", "-b", "main")
    r:git("config", "user.email", "test@example.com")
    r:git("config", "user.name", "Test")
    r:git("config", "commit.gpgsign", "false")
    if files then
        for path, text in pairs(files) do
            r:write(path, text)
        end
        r:commit("init")
    end
    return r
end

---Opens the view on the repo (new tab) and returns the session.
---@param repo TestRepo
---@param opts? table
---@return NvimDiffSession
function M.open(repo, opts)
    return assert(require("nvim-diff").open(vim.tbl_extend("force", { path = repo.root }, opts or {})))
end

---vim.wait that fails the test on timeout.
function M.wait(cond, ms, msg)
    if not vim.wait(ms or 3000, cond, 10) then
        error("timed out: " .. (msg or "condition"), 2)
    end
end

function M.panel_lines(s)
    return vim.api.nvim_buf_get_lines(s.panel_buf, 0, -1, false)
end

---Line number of the first panel line matching the Lua pattern.
function M.find_line(s, pattern)
    for i, l in ipairs(M.panel_lines(s)) do
        if l:find(pattern) then
            return i
        end
    end
end

---Puts the cursor on a panel line (by pattern) with the panel focused.
function M.panel_cursor(s, pattern)
    local lnum = assert(M.find_line(s, pattern), "no panel line matches " .. pattern)
    vim.api.nvim_set_current_win(s.panel_win)
    vim.api.nvim_win_set_cursor(s.panel_win, { lnum, 0 })
end

---Runs an action as if its key was pressed in the current window.
function M.run(name)
    require("nvim-diff.actions").run(name)
end

---Buffer names shown in the diff windows, left to right.
function M.diff_names(s)
    return vim.tbl_map(function(w)
        return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
    end, s.wins)
end

---Lines of the window (lnum) that diff mode highlights as changed/added.
function M.changed_lines(win)
    return vim.api.nvim_win_call(win, function()
        local out = {}
        for l = 1, vim.api.nvim_buf_line_count(0) do
            if vim.fn.diff_hlID(l, 1) ~= 0 then
                out[#out + 1] = l
            end
        end
        return out
    end)
end

---vim.fn.confirm returns `answer` (1 = first button) until the test ends; calls are recorded.
function M.stub_confirm(answer)
    local orig = vim.fn.confirm
    M.confirms = {}
    vim.fn.confirm = function(msg)
        M.confirms[#M.confirms + 1] = msg
        return answer
    end
    restores[#restores + 1] = function()
        vim.fn.confirm = orig
    end
end

---Back to a single empty window between tests.
function M.reset()
    local view = require("nvim-diff.view")
    if view.session then
        view.session.quit_on_close = false
        view.close()
    end
    for _, restore in ipairs(restores) do
        restore()
    end
    restores = {}
    require("nvim-diff.config").setup({})
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! only!")
    vim.cmd("enew!")
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if buf ~= vim.api.nvim_get_current_buf() then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
end

function M.cleanup()
    for _, dir in ipairs(dirs) do
        vim.fn.delete(dir, "rf")
    end
end

return M
