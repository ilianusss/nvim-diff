-- Directory tree of one panel section, built from its entries.

local M = {}

---@class NvimDiffNode
---@field type "dir"|"file"
---@field name string display name ("a/b" once flattened)
---@field path string repo-relative path
---@field children? NvimDiffNode[]
---@field entry? NvimDiffEntry
---@field status? string folder status: the status shared by all its files, else "M"

local function sort(nodes)
    table.sort(nodes, function(a, b)
        if a.type ~= b.type then
            return a.type == "dir"
        end
        local la, lb = a.name:lower(), b.name:lower()
        if la ~= lb then
            return la < lb
        end
        return a.name < b.name
    end)
end

local function finalize(dir, flatten)
    dir.index = nil
    sort(dir.children)
    local status
    for _, child in ipairs(dir.children) do
        if child.type == "dir" then
            finalize(child, flatten)
            if flatten then
                -- Merge chains of single-child folders: a/ -> b/ -> c/ becomes "a/b/c"
                while #child.children == 1 and child.children[1].type == "dir" do
                    local only = child.children[1]
                    child.name = child.name .. "/" .. only.name
                    child.path = only.path
                    child.children = only.children
                    child.status = only.status
                end
            end
        else
            child.status = child.entry.status
        end
        if status == nil then
            status = child.status
        elseif status ~= child.status then
            status = "M"
        end
    end
    dir.status = status or " "
end

---@param entries NvimDiffEntry[]
---@param flatten boolean
---@return NvimDiffNode[] top-level nodes
function M.build(entries, flatten)
    local root = { type = "dir", name = "", path = "", children = {}, index = {} }
    for _, e in ipairs(entries) do
        local parts = vim.split(e.path, "/", { plain = true })
        local node = root
        for i = 1, #parts - 1 do
            local child = node.index[parts[i]]
            if not child then
                local path = node.path == "" and parts[i] or (node.path .. "/" .. parts[i])
                child = { type = "dir", name = parts[i], path = path, children = {}, index = {} }
                node.index[parts[i]] = child
                node.children[#node.children + 1] = child
            end
            node = child
        end
        node.children[#node.children + 1] = { type = "file", name = parts[#parts], path = e.path, entry = e }
    end
    finalize(root, flatten)
    return root.children
end

---Entries under `nodes`, in display order.
---@param nodes NvimDiffNode[]
---@param out? NvimDiffEntry[]
---@return NvimDiffEntry[]
function M.entries(nodes, out)
    out = out or {}
    for _, n in ipairs(nodes) do
        if n.type == "file" then
            out[#out + 1] = n.entry
        else
            M.entries(n.children, out)
        end
    end
    return out
end

---Every folder under `nodes` (for zR / zM).
---@param nodes NvimDiffNode[]
---@param out? NvimDiffNode[]
---@return NvimDiffNode[]
function M.dirs(nodes, out)
    out = out or {}
    for _, n in ipairs(nodes) do
        if n.type == "dir" then
            out[#out + 1] = n
            M.dirs(n.children, out)
        end
    end
    return out
end

return M
