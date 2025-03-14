--[[
This is the Path library. It declares the Path object.
Use it to work with paths and make system calls.
]]





---@class Path A path to a file.
---@field name string The final part of the path
---@field parts string[] The different parts of the path from root to name.
---@field stem string The name without the suffix
---@field suffix string The suffix of the path (ex: ".txt") if it has any.
---@field parent Path The parent path or itself if it is a root path.
local Path = {}
_G.Path = Path

Path.__index = Path
Path.__name = "Path"


---Creates a new Path object
---@param path string? The path as a string to create. If left nil, returns the root path.
---@return Path path_object the new Path object.
function Path:new(path)
    local p = {}
    setmetatable(p, self)
    if path == nil then
        path = ""
    end
    local parts = {}
    for part in string.gmatch(path, "([^/]+)") do
        table.insert(parts, part)
    end
    p.parts = parts
    p.name = parts[#parts] or ""
    local find = 0
    for i = 1, #p.name do
        if string.sub(p.name, i, i + 1) == "." then
            find = i
        end
    end
    if find == 0 then
        p.stem = p.name
        p.suffix = ""
    else
        p.stem = string.sub(p.name, 1, find - 1)
        p.suffix = string.sub(p.name, find)
    end
    if #parts == 0 then
        p.parent = p
    else
        local parent = ""
        for i = 1, #parts - 1 do
            parent = parent.."/"..parts[i]
        end
        p.parent = Path:new(parent)
    end
    return p
end




function Path:__tostring()
    local s = ""
    for index, part in ipairs(self.parts) do
        s = s..part
        if index < #self.parts then
            s = s.."/"
        end
    end
    return s
end





function Path:exists()
    
end





function Path:is_file()
    
end





function Path:is_dir()
    
end





function Path:mkdir(exists_ok, parents)
    
end





function Path:touch(exists_ok)
    
end





function Path:open(mode)
    
end