-- :checkhealth nvim-diff

local config = require("nvim-diff.config")
local git = require("nvim-diff.git")
local watch = require("nvim-diff.watch")

local M = {}

-- `git restore` is the newest command the plugin runs
local MIN_GIT = "2.23"

local function check_versions()
    if vim.fn.has("nvim-0.11") == 1 then
        vim.health.ok("Neovim " .. tostring(vim.version()))
    else
        vim.health.error("Neovim " .. tostring(vim.version()) .. " is too old: 0.11 or newer is needed")
    end

    local version, err = git.version()
    if not version then
        vim.health.error(err or "git not found")
    elseif vim.version.lt(version, MIN_GIT) then
        vim.health.error(("git %s is too old: %s or newer is needed (git restore)"):format(version, MIN_GIT))
    else
        vim.health.ok("git " .. version)
    end
end

local function check_keymaps()
    local actions = require("nvim-diff.actions").actions
    local unknown = {}
    for scope, maps in pairs(config.options.keymaps) do
        for lhs, name in pairs(maps) do
            if name and not actions[name] then
                unknown[#unknown + 1] = ("keymaps.%s[%q] = %q"):format(scope, lhs, name)
            end
        end
    end
    if #unknown == 0 then
        vim.health.ok("Keymaps: every action name exists")
        return
    end
    table.sort(unknown)
    vim.health.warn(
        "Unknown action names: " .. table.concat(unknown, ", "),
        "See `:help nvim-diff-config` for the action names"
    )
end

local function report_options()
    local o = config.options
    if not o.use_icons then
        vim.health.info("File icons: off (use_icons = false)")
    elseif pcall(require, "nvim-web-devicons") then
        vim.health.info("File icons: nvim-web-devicons")
    elseif _G.MiniIcons then
        vim.health.info("File icons: mini.icons")
    else
        vim.health.info("File icons: none (install nvim-web-devicons or mini.icons to get them)")
    end

    if not o.live_refresh.enabled then
        vim.health.info("Live refresh: off (live_refresh.enabled = false)")
    elseif watch.has_recursive_events() then
        vim.health.info("Live refresh: file system events")
    else
        vim.health.info(("Live refresh: polling `git status` every %d ms"):format(o.live_refresh.poll_ms))
    end
end

function M.check()
    vim.health.start("nvim-diff")
    check_versions()
    check_keymaps()
    report_options()
end

return M
