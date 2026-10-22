-- Headless test runner: `nvim --clean -l tests/run.lua [filter]` (see `make test`).
-- Spec files call the globals test(name, fn), eq(actual, expected, msg?) and ok(value, msg?).

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
package.path = root .. "/?.lua;" .. package.path

-- The user's git config must not change the results (conflict style, rename detection, signing...)
vim.env.GIT_CONFIG_GLOBAL = "/dev/null"
vim.env.GIT_CONFIG_NOSYSTEM = "1"
vim.o.swapfile = false
vim.o.columns, vim.o.lines = 200, 50

vim.cmd("runtime! plugin/nvim-diff.lua")

local filter = arg[1]
local tests, current_file = {}, nil

function _G.test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn, file = current_file }
end

function _G.eq(actual, expected, msg)
    if not vim.deep_equal(actual, expected) then
        error(
            ("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", vim.inspect(expected), vim.inspect(actual)),
            2
        )
    end
end

function _G.ok(value, msg)
    if not value then
        error(msg or "expected a truthy value", 2)
    end
    return value
end

local files = vim.fn.glob(root .. "/tests/*_spec.lua", false, true)
table.sort(files)
for _, file in ipairs(files) do
    if not filter or filter == "" or file:find(filter, 1, true) then
        current_file = vim.fn.fnamemodify(file, ":t")
        dofile(file)
    end
end

local H = require("tests.helpers")
local failed = 0
for _, t in ipairs(tests) do
    local passed, err = xpcall(t.fn, debug.traceback)
    local reset_ok, reset_err = pcall(H.reset)
    if passed and not reset_ok then
        passed, err = false, "reset failed: " .. tostring(reset_err)
    end
    if passed then
        print(("ok    %s: %s"):format(t.file, t.name))
    else
        failed = failed + 1
        print(("FAIL  %s: %s\n%s\n"):format(t.file, t.name, err))
    end
end
H.cleanup()
print(("\n%d tests, %d failed"):format(#tests, failed))
os.exit(failed > 0 and 1 or 0)
