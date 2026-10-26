-- Commands and the `nvim diff` startup hook. Runs at every startup, so it stays cheap: the
-- plugin modules load when the view opens.

if vim.g.loaded_nvim_diff then
    return
end
vim.g.loaded_nvim_diff = true

local function is_diff_argv()
    return vim.fn.argc(-1) == 1 and vim.fn.argv(0, -1) == "diff" and vim.fn.getftype("diff") == ""
end

-- On an older Neovim the modules fail with Lua errors on missing APIs: say what is needed instead.
if vim.fn.has("nvim-0.11") == 0 then
    local function too_old()
        vim.notify("nvim-diff needs Neovim 0.11 or newer", vim.log.levels.ERROR)
    end
    vim.api.nvim_create_user_command("NvimDiff", too_old, { nargs = "?", desc = "nvim-diff needs Neovim 0.11+" })
    if is_diff_argv() then
        vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = too_old })
    end
    return
end

vim.api.nvim_create_user_command("NvimDiff", function(o)
    require("nvim-diff").open({ path = o.args ~= "" and vim.fn.expand(o.args) or nil })
end, { nargs = "?", complete = "dir", desc = "Review the changes of the repo (nvim-diff)" })

vim.api.nvim_create_user_command("NvimDiffClose", function()
    require("nvim-diff").close()
end, { desc = "Close the nvim-diff view" })

vim.api.nvim_create_user_command("NvimDiffRefresh", function()
    require("nvim-diff").refresh()
end, { desc = "Refresh the nvim-diff view" })

local function open_from_argv()
    local diff_buf = vim.api.nvim_get_current_buf()
    local session = require("nvim-diff").open({ current_tab = true, quit_on_close = true })
    if not session then
        vim.cmd("enew")
    end
    if vim.api.nvim_buf_is_valid(diff_buf) and vim.api.nvim_buf_get_name(diff_buf):match("diff$") then
        pcall(vim.api.nvim_buf_delete, diff_buf, { force = true })
    end
end

if is_diff_argv() then
    if vim.v.vim_did_enter == 1 then
        open_from_argv()
    else
        vim.api.nvim_create_autocmd("VimEnter", { once = true, nested = true, callback = open_from_argv })
    end
end
