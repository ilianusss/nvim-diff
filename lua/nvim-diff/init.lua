-- nvim-diff: review changes like VS Code's Source Control view. See :help nvim-diff.

local M = {}

---@param opts? table see :help nvim-diff-config
function M.setup(opts)
    require("nvim-diff.config").setup(opts)
end

---Opens the view on the repo containing `opts.path` (default: cwd), or focuses it.
---@param opts? NvimDiffOpenOpts
---@return NvimDiffSession?
function M.open(opts)
    return require("nvim-diff.view").open(opts)
end

function M.close()
    require("nvim-diff.view").close()
end

function M.refresh()
    require("nvim-diff.view").refresh({ sync = true })
end

---@return boolean
function M.is_open()
    return require("nvim-diff.view").session ~= nil
end

return M
