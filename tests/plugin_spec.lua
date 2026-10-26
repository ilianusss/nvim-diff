local H = require("tests.helpers")

local PLUGIN = vim.api.nvim_get_runtime_file("plugin/nvim-diff.lua", false)[1]

---Sources plugin/nvim-diff.lua again as if Neovim had version `version`, then puts back the real one.
local function source_plugin_as(version)
    local has = vim.fn.has
    vim.fn.has = function(feature)
        if feature:match("^nvim%-") then
            return vim.version.ge(version, feature:sub(6)) and 1 or 0
        end
        return has(feature)
    end
    vim.g.loaded_nvim_diff = nil
    for _, cmd in ipairs({ "NvimDiff", "NvimDiffClose", "NvimDiffRefresh" }) do
        pcall(vim.api.nvim_del_user_command, cmd)
    end
    local ok, err = pcall(dofile, PLUGIN)
    vim.fn.has = has
    assert(ok, err)
end

test("on Neovim older than 0.11, :NvimDiff says which version it needs and loads nothing", function()
    local errors = {}
    H.stub_notify(errors, vim.log.levels.ERROR)
    local loaded = {}
    for name, module in pairs(package.loaded) do
        if name:match("^nvim%-diff") then
            loaded[name] = module
            package.loaded[name] = nil
        end
    end
    source_plugin_as("0.10.4")
    vim.cmd("NvimDiff " .. vim.fn.tempname())
    local loaded_after = vim.tbl_filter(function(name)
        return name:match("^nvim%-diff") ~= nil
    end, vim.tbl_keys(package.loaded))
    source_plugin_as(tostring(vim.version()))
    for name, module in pairs(loaded) do
        package.loaded[name] = module
    end

    eq(errors, { "nvim-diff needs Neovim 0.11 or newer" })
    eq(loaded_after, {}, "no module loaded")
end)
