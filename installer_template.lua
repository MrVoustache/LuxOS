local DIRECTORY = 1
local FILE = 2
local ENTRY_POINT = "LuxOS/main.lua"

local function print_color(color, ...)
    local old_color = term.getTextColor()
    term.setTextColor(color)
    print(...)
    term.setTextColor(old_color)
end

local package = {package_dump}              -- This is actually a Python format variable.

local raw_package = {raw_package_content}   -- This too

local function install(node, parent_path)
    if node.type == DIRECTORY then
        if not fs.exists(parent_path..node.name) then
            fs.makeDir(parent_path..node.name)
        end
        for _, child in ipairs(node.children) do
            install(child, parent_path..node.name.."/")
        end
    elseif node.type == FILE then
        local path = parent_path..node.name
        if not fs.exists(path) then
            local content = raw_package[node.code]
            print_color(colors.yellow, "Installing file '"..path.."'...")
            local file = fs.open(path, "w")
            file.write(content)
            file.close()
        end
    end
end

install(package, "")

print_color(colors.cyan, "Installation is finished. Press any key to boot LuxOS.")
while true do
    local event = coroutine.yield()
    if event == "key" then
        break
    end
end

dofile(ENTRY_POINT)