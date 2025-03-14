local function print_color(color, ...)
    local old_color = term.getTextColor()
    term.setTextColor(color)
    print(...)
    term.setTextColor(old_color)
end

local response = http.get("https://raw.githubusercontent.com/MrVoustache/LuxOS/refs/heads/main/installer.lua")
local code = response.getResponseCode()

if code ~= 200 then
    print_color(colors.red, "Error response from github ("..code.."):")
    print(response.readAll())
    return
end

print_color(colors.lime, "Install script downloaded. Installing...")

local script = response.readAll()
local install_func, err = load(script, "LuxOS_install")

if install_func == nil then
    print_color(colors.red, "Error loading install script:")
    print_color(colors.orange, err)
    return
end

local ok, err = pcall(install_func)

if not ok then
    print_color(colors.red, "Error running install script:")
    print_color(colors.orange, err)
    return
end