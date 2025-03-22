--[[
This is LuxOS Object-Oriented standart library.
]]





kernel.panic_pcall("dofile", dofile, "LuxOS/standart_library/path.lua")
kernel.panic_pcall("dofile", dofile, "LuxOS/standart_library/app.lua")





local base_type = type

---Returns the type of the given object as a string.
---@param obj any The object for which the type should be evaluated.
---@return type string The object type.
function _G.type(obj)
    if base_type(obj) == "table" and base_type(obj.__name) == "string" then
        return obj.__name
    end
    return base_type(obj)
end





---Returns a copy of the table.
---@return table The copy of the table.
function table:copy()
    local cp = {}
    for k, v in pairs(self) do
        cp[k] = v
    end
    return cp
end





return {
    Path = Path,
    Application = Application
}