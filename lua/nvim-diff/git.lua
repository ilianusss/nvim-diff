-- Every git call of the plugin. Commands run as `git --no-optional-locks -C <root> ...` through
-- vim.system; --no-optional-locks keeps `git status` from rewriting the index, which would
-- wake the file watcher and loop.

local M = {}

---@class NvimDiffEntry
---@field kind "conflicting"|"working"|"staged"
---@field path string repo-relative path (new path for renames)
---@field old_path? string source path of a rename or copy
---@field status string letter shown in the panel: M A D R C T U ?
---@field xy string raw porcelain XY
---@field hashes table<string, string> blob hashes: head/index, or base/ours/theirs for conflicts
---@field stats? { additions: integer, deletions: integer }
---@field binary? boolean
---@field submodule? boolean
---@field conflicts? integer conflict regions left in the working file

---@class NvimDiffStatus
---@field has_head boolean false before the first commit
---@field conflicting NvimDiffEntry[]
---@field working NvimDiffEntry[]
---@field staged NvimDiffEntry[]

local function command(root, args)
    local cmd = { "git", "--no-optional-locks", "-C", root }
    vim.list_extend(cmd, args)
    return cmd
end

local function result(res)
    if res.code ~= 0 then
        return nil, vim.trim(res.stderr or "")
    end
    return res.stdout or ""
end

---Runs git synchronously.
---@param root string
---@param args string[]
---@return string? stdout
---@return string? err
function M.run(root, args)
    local ok, proc = pcall(vim.system, command(root, args), { text = false })
    if not ok then
        return nil, tostring(proc)
    end
    return result(proc:wait())
end

---@param path string any path inside the repo
---@return { root: string, gitdir: string }?
---@return string? err
function M.repo(path)
    local out, err = M.run(path, { "rev-parse", "--show-toplevel", "--absolute-git-dir" })
    if not out then
        return nil, err
    end
    local lines = vim.split(vim.trim(out), "\n", { plain = true })
    return { root = lines[1], gitdir = lines[2] }
end

---@param root string
---@return boolean
function M.has_head(root)
    return M.run(root, { "rev-parse", "--verify", "-q", "HEAD" }) ~= nil
end

---Version of the git on $PATH, e.g. "2.45.1" (build suffixes such as ".windows.1" dropped).
---@return string? version
---@return string? err
function M.version()
    local ok, proc = pcall(vim.system, { "git", "--version" }, { text = true })
    if not ok then
        return nil, "git not found: " .. tostring(proc)
    end
    local out, err = result(proc:wait())
    if not out then
        return nil, "`git --version` failed: " .. err
    end
    local version = out:match("^git version (%d+%.%d+%.?%d*)")
    if not version then
        return nil, "unexpected `git --version` output: " .. vim.trim(out)
    end
    return version
end

--------------------------------------------------------------------------------
-- Status
--------------------------------------------------------------------------------

local function add_entry(list, kind, status, xy, path, old_path, hashes, sub)
    list[#list + 1] = {
        kind = kind,
        path = path,
        old_path = (status == "R" or status == "C") and old_path or nil,
        status = status,
        xy = xy,
        hashes = hashes,
        submodule = sub:sub(1, 1) == "S" or nil,
    }
end

---Parses `git status --porcelain=v2 --branch -z --untracked-files=all`.
---@param out string
---@return NvimDiffStatus
function M.parse_status(out)
    local st = { has_head = true, conflicting = {}, working = {}, staged = {} }
    local tokens = vim.split(out, "\0", { plain = true })
    local i = 1
    while i <= #tokens do
        local t = tokens[i]
        local kind = t:sub(1, 1)
        local xy, sub, h1, h2, h3, path, old_path
        if t == "# branch.oid (initial)" then
            st.has_head = false
        elseif kind == "1" then
            xy, sub, h1, h2, path = t:match("^1 (..) (%S+) %S+ %S+ %S+ (%S+) (%S+) (.*)$")
        elseif kind == "2" then
            xy, sub, h1, h2, path = t:match("^2 (..) (%S+) %S+ %S+ %S+ (%S+) (%S+) %S+ (.*)$")
            i = i + 1
            old_path = tokens[i]
        elseif kind == "u" then
            xy, sub, h1, h2, h3, path = t:match("^u (..) (%S+) %S+ %S+ %S+ %S+ (%S+) (%S+) (%S+) (.*)$")
        elseif kind == "?" then
            add_entry(st.working, "working", "?", "??", t:sub(3), nil, {}, "N")
        end

        if kind == "u" and xy then
            add_entry(st.conflicting, "conflicting", "U", xy, path, nil, { base = h1, ours = h2, theirs = h3 }, sub)
        elseif xy then
            local x, y = xy:sub(1, 1), xy:sub(2, 2)
            if x ~= "." then
                add_entry(st.staged, "staged", x, xy, path, old_path, { head = h1, index = h2 }, sub)
            end
            if y ~= "." then
                add_entry(st.working, "working", y, xy, path, old_path, { index = h2 }, sub)
            end
        end
        i = i + 1
    end
    return st
end

---Parses `git diff --numstat -z`: path -> stats (renames are keyed by their new path).
---@param out string
---@return table<string, { additions?: integer, deletions?: integer, binary?: boolean }>
function M.parse_numstat(out)
    local stats = {}
    local tokens = vim.split(out, "\0", { plain = true })
    local i = 1
    while i <= #tokens do
        local adds, dels, path = tokens[i]:match("^(%S+)\t(%S+)\t(.*)$")
        if adds then
            if path == "" then -- rename: "adds\tdels\t\0old\0new"
                path = tokens[i + 2]
                i = i + 2
            end
            if adds == "-" then
                stats[path] = { binary = true }
            else
                stats[path] = { additions = tonumber(adds), deletions = tonumber(dels) }
            end
        end
        i = i + 1
    end
    return stats
end

---Number of conflict regions in a file (lines starting with "<<<<<<< ").
---@param file string
---@return integer
function M.count_conflicts(file)
    local f = io.open(file, "rb")
    if not f then
        return 0
    end
    local n = 0
    for line in f:lines() do
        if line:sub(1, 8) == "<<<<<<< " then
            n = n + 1
        end
    end
    f:close()
    return n
end

local STATUS_JOBS = {
    status = { "status", "--porcelain=v2", "--branch", "--no-ahead-behind", "-z", "--untracked-files=all" },
    working = { "diff", "--numstat", "-z" },
    staged = { "diff", "--cached", "--numstat", "-z" },
}

local function build_status(root, results)
    local out, err = result(results.status)
    if not out then
        return nil, err
    end
    local st = M.parse_status(out)
    for _, section in ipairs({ "working", "staged" }) do
        local numstat = result(results[section])
        local stats = M.parse_numstat(numstat or "")
        local kept = {}
        for _, e in ipairs(st[section]) do
            local s = stats[e.path]
            if s and s.binary then
                e.binary = true
            elseif s then
                e.stats = s
            end
            -- `git status` flags a file whose size changed even when its clean filter (.gitattributes)
            -- gives back the index content; `git diff` then has nothing to show, and neither do we.
            local filtered_out = numstat and not s and e.status == "M" and not e.submodule
            if not filtered_out then
                kept[#kept + 1] = e
            end
        end
        st[section] = kept
    end
    for _, e in ipairs(st.conflicting) do
        e.conflicts = M.count_conflicts(root .. "/" .. e.path)
    end
    return st
end

---Status of the repo: three git processes run in parallel. Synchronous without `cb`; with
---`cb`, it is called on the main loop.
---@param root string
---@param cb? fun(status: NvimDiffStatus?, err: string?)
---@return NvimDiffStatus? status
---@return string? err
function M.status(root, cb)
    local procs, results, pending = {}, {}, 0
    for name, args in pairs(STATUS_JOBS) do
        pending = pending + 1
        local ok, proc = pcall(vim.system, command(root, args), { text = false }, cb and function(res)
            results[name] = res
            pending = pending - 1
            if pending == 0 then
                vim.schedule(function()
                    cb(build_status(root, results))
                end)
            end
        end or nil)
        if not ok then
            if cb then
                vim.schedule(function()
                    cb(nil, tostring(proc))
                end)
            end
            return nil, tostring(proc)
        end
        procs[name] = proc
    end
    if cb then
        return
    end
    for name, proc in pairs(procs) do
        results[name] = proc:wait()
    end
    return build_status(root, results)
end

--------------------------------------------------------------------------------
-- Content
--------------------------------------------------------------------------------

---Splits blob content into buffer lines. A file whose lines all end in CR is shown without
---them, like a 'fileformat' dos buffer.
---@param text string
---@return string[]
function M.split_lines(text)
    if text == "" then
        return {}
    end
    local lines = vim.split(text, "\n", { plain = true })
    if lines[#lines] == "" then
        lines[#lines] = nil
    end
    local crlf = #lines > 0
    for _, l in ipairs(lines) do
        if l:sub(-1) ~= "\r" then
            crlf = false
            break
        end
    end
    if crlf then
        for i, l in ipairs(lines) do
            lines[i] = l:sub(1, -2)
        end
    end
    return lines
end

---Content of a blob: "HEAD:path", ":path" (index), ":2:path" (ours), ...
---@param root string
---@param spec string
---@return string[]? lines nil when the blob does not exist
---@return boolean? binary
function M.show(root, spec)
    local out = M.run(root, { "cat-file", "blob", spec })
    if not out then
        return nil
    end
    if out:sub(1, 8000):find("\0", 1, true) then
        return {}, true
    end
    return M.split_lines(out)
end

---Filter driver .gitattributes gives `path` (`filter=<driver>`), if any.
---@param root string
---@param path string
---@return string? driver
---@return string? err
function M.filter_driver(root, path)
    local out, err = M.run(root, { "check-attr", "-z", "filter", "--", path })
    if not out then
        return nil, err
    end
    local value = vim.split(out, "\0", { plain = true })[3] -- "<path>\0filter\0<value>\0"
    if value ~= "unspecified" and value ~= "unset" and value ~= "set" then
        return value
    end
end

---Working-tree content of `path` after its clean filter, as `git add` stores it (the result is
---written to the object database to be read back). nil when the result is binary.
---@param root string
---@param path string
---@return string[]? lines
---@return string? err
function M.clean(root, path)
    local oid, err = M.run(root, { "hash-object", "-w", "--", path })
    if not oid then
        return nil, err
    end
    local lines, binary = M.show(root, vim.trim(oid))
    if binary then
        return nil
    end
    return lines
end

--------------------------------------------------------------------------------
-- Stage / unstage / restore
--------------------------------------------------------------------------------

local function with_paths(args, paths)
    args = vim.list_extend(args, { "--" })
    return vim.list_extend(args, paths)
end

---@param root string
---@param paths string[]
---@return string? stdout
---@return string? err
function M.stage(root, paths)
    return M.run(root, with_paths({ "add", "-A" }, paths))
end

---@param root string
---@param paths string[] include both sides of a rename
---@return string? stdout
---@return string? err
function M.unstage(root, paths)
    if M.has_head(root) then
        return M.run(root, with_paths({ "restore", "--staged" }, paths))
    end
    return M.run(root, with_paths({ "rm", "--cached", "-r", "-q" }, paths))
end

---@param root string
---@return string? stdout
---@return string? err
function M.stage_all(root)
    return M.run(root, { "add", "-A" })
end

---@param root string
---@return string? stdout
---@return string? err
function M.unstage_all(root)
    if M.has_head(root) then
        return M.run(root, { "reset", "-q" })
    end
    return M.run(root, { "rm", "--cached", "-r", "-q", "--", "." })
end

---Writes the working-tree content of `paths` to the object database, so discarded changes can be
---recovered with `git cat-file -p <hash>`. Only regular files are backed up: hash-object fails on a
---directory (a nested repo, a submodule) and on a missing path.
---@param root string
---@param paths string[]
---@return table<string, string>? hashes path -> blob hash
---@return string? err
function M.backup(root, paths)
    local existing = vim.tbl_filter(function(path)
        local stat = vim.uv.fs_stat(root .. "/" .. path)
        return stat ~= nil and stat.type == "file"
    end, paths)
    if #existing == 0 then
        return {}
    end
    local out, err = M.run(root, with_paths({ "hash-object", "-w" }, existing))
    if not out then
        return nil, err
    end
    local hashes = {}
    for i, hash in ipairs(vim.split(vim.trim(out), "\n", { plain = true })) do
        hashes[existing[i]] = hash
    end
    return hashes
end

---Discards entries: each goes back to the left side of its diff. One git call per kind of entry, so a
---path git rejects (gone since the last status) leaves the other entries of its kind untouched.
---working: the index version (untracked files are deleted).
---staged: the HEAD version, in the index and the working tree.
---@param root string
---@param entries NvimDiffEntry[]
---@return boolean? ok
---@return string? err
function M.restore(root, entries)
    local tracked, untracked, staged = {}, {}, {}
    for _, e in ipairs(entries) do
        if e.kind == "conflicting" then
            return nil, "conflicts are resolved with the conflict actions, not restored"
        elseif e.kind == "staged" then
            staged[#staged + 1] = e.path
            staged[#staged + 1] = e.old_path
        elseif e.status == "?" then
            untracked[#untracked + 1] = e.path
        else
            tracked[#tracked + 1] = e.path
        end
    end

    local errors = {}
    local function run(args, paths)
        if #paths > 0 then
            local out, err = M.run(root, with_paths(args, paths))
            if not out then
                errors[#errors + 1] = err
            end
        end
    end
    run({ "restore" }, tracked)
    if #staged > 0 then
        local args = M.has_head(root) and { "restore", "--source=HEAD", "--staged", "--worktree" }
            or { "rm", "-f", "-q" }
        run(args, staged)
    end
    for _, path in ipairs(untracked) do
        local removed, err = os.remove(root .. "/" .. path)
        if not removed then
            errors[#errors + 1] = err
        end
    end
    if #errors > 0 then
        return nil, table.concat(errors, "\n")
    end
    return true
end

return M
