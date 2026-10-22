-- Live refresh: tells the view when the repo may have changed. Recursive fs events where libuv
-- supports them (macOS, Windows), a `git status` poll elsewhere. Debounced; the callback runs on
-- the main loop.

local M = {}

local uv = vim.uv or vim.loop

local IGNORED = { "%.git/objects/", "%.git/logs/", "^objects/", "^logs/", "%.lock$" }

local function ignored(fname)
    if not fname then
        return false
    end
    for _, pat in ipairs(IGNORED) do
        if fname:find(pat) then
            return true
        end
    end
    return false
end

---@class NvimDiffWatcher
---@field kind "fs_event"|"poll"
---@field trigger fun() request a refresh (debounced)
---@field stop fun()

---@param root string
---@param gitdir string
---@param opts { debounce_ms: integer, poll_ms: integer }
---@param on_change fun()
---@return NvimDiffWatcher
function M.start(root, gitdir, opts, on_change)
    local closed = false
    local debounce = assert(uv.new_timer())
    local handles = {}

    local function fire()
        if not closed then
            on_change()
        end
    end

    local function trigger()
        if closed then
            return
        end
        debounce:stop()
        debounce:start(opts.debounce_ms, 0, vim.schedule_wrap(fire))
    end

    local function watch(path, recursive)
        local h = uv.new_fs_event()
        if not h then
            return false
        end
        local ok = h:start(path, { recursive = recursive }, function(err, fname)
            if not err and not ignored(fname) then
                trigger()
            end
        end)
        if ok ~= 0 and ok ~= true then
            h:close()
            return false
        end
        handles[#handles + 1] = h
        return true
    end

    local kind = "poll"
    if vim.fn.has("mac") == 1 or vim.fn.has("win32") == 1 then
        if watch(root, true) then
            kind = "fs_event"
            -- A linked worktree keeps its git dir outside the root
            if not vim.startswith(gitdir, root .. "/") then
                watch(gitdir, false)
            end
        end
    end

    local poll
    if kind == "poll" then
        poll = assert(uv.new_timer())
        poll:start(opts.poll_ms, opts.poll_ms, vim.schedule_wrap(fire))
    end

    return {
        kind = kind,
        trigger = trigger,
        stop = function()
            if closed then
                return
            end
            closed = true
            for _, h in ipairs(handles) do
                h:stop()
                h:close()
            end
            debounce:stop()
            debounce:close()
            if poll then
                poll:stop()
                poll:close()
            end
        end,
    }
end

return M
