-- NvimDiff* highlight groups. All are `default`, so a colorscheme or the user can override them;
-- they are set again on ColorScheme.

local M = {}

M.status = {
    A = "NvimDiffStatusAdded",
    ["?"] = "NvimDiffStatusUntracked",
    M = "NvimDiffStatusModified",
    R = "NvimDiffStatusRenamed",
    C = "NvimDiffStatusCopied",
    T = "NvimDiffStatusTypeChange",
    U = "NvimDiffStatusUnmerged",
    D = "NvimDiffStatusDeleted",
}

local LINKS = {
    NvimDiffRootPath = "NvimDiffTitle",
    NvimDiffFileName = "Normal",
    NvimDiffSelected = "Type",
    NvimDiffPath = "Comment",
    NvimDiffInsertions = "Added",
    NvimDiffDeletions = "Removed",
    NvimDiffConflicts = "DiagnosticWarn",
    NvimDiffFolderName = "Directory",
    NvimDiffFolderSign = "PreProc",
    NvimDiffNonText = "NonText",
    NvimDiffStatusAdded = "Added",
    NvimDiffStatusUntracked = "Added",
    NvimDiffStatusModified = "Changed",
    NvimDiffStatusRenamed = "Changed",
    NvimDiffStatusCopied = "Changed",
    NvimDiffStatusTypeChange = "Changed",
    NvimDiffStatusUnmerged = "Changed",
    NvimDiffStatusDeleted = "Removed",
    NvimDiffOption = "Pmenu", -- options bar items
    NvimDiffOptionActive = "PmenuSel", -- an option that hides something (whitespace ignored)
    NvimDiffLive = "Added",
    NvimDiffLiveOff = "Comment",
    NvimDiffWinbarLabel = "Title", -- "INDEX", "WORKING TREE", ... above the diff panes
    NvimDiffWinbarPath = "Comment",
}

local function fg(name)
    return vim.api.nvim_get_hl(0, { name = name, link = false }).fg
end

function M.setup()
    vim.api.nvim_set_hl(0, "NvimDiffTitle", { fg = fg("Label"), bold = true, default = true })
    vim.api.nvim_set_hl(0, "NvimDiffCounter", { fg = fg("Identifier"), bold = true, default = true })
    for name, link in pairs(LINKS) do
        vim.api.nvim_set_hl(0, name, { link = link, default = true })
    end
end

return M
