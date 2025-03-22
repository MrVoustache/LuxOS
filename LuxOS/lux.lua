--[[
This is the standart library of LuxOS
]]

_G.lux = {} --- The lux API. It contains simple functions to interact with LuxOS.
libraries.lux = lux





local CURRENT_TICK = 0
local NEXT_TICK = 0

---This function creates an immediate "tick" event and waits (instantly) for it.
---This is used for heavy computations.
---@param terminable? boolean If set to false, a terminate event will not be caught by this function.
function lux.tick(terminable)
    if CURRENT_TICK == NEXT_TICK then
        NEXT_TICK = NEXT_TICK + 1
        os.queueEvent("tick")
    end
    local expected_tick = NEXT_TICK
    if terminable == false then
        local event = {coroutine.yield()}
        while #event ~= 1 or event[1] ~= "tick" do
            event = {coroutine.yield()}
        end
    else
        local event = {os.pullEvent()}
        while #event ~= 1 or event[1] ~= "tick" do
            event = {os.pullEvent()}
        end
    end
    if CURRENT_TICK < expected_tick then
        CURRENT_TICK = expected_tick
    end
end

---This function creates a "tick" event without waiting for it to happen.
function lux.make_tick()
    NEXT_TICK = NEXT_TICK + 1
    os.queueEvent("tick")
end

lux.INSTALLER_CODE = "68i8QBxE"





---Turns off the computer.
---Actually throws a {"shutdown", "s"} event for the kernel to handle then blocks undefinitely.
---Note that in kernel space, this function also marks the current routine offline.
function os.shutdown()
    os.queueEvent("shutdown", "s")
    if kernel.kernel_space() then
        local event = {}
        while event[1] ~= "shutdown" do
            event = {coroutine.yield()}
        end
        kernel.mark_routine_offline()
    else
        while true do
            coroutine.yield()
        end
    end
end

---Reboots the computer.
---Actually throws a {"shutdown", "r"} event for the kernel to handle then blocks undefinitely.
---Note that in kernel space, this function also marks the current routine offline.
function os.reboot()
    os.queueEvent("shutdown", "r")
    if kernel.kernel_space() then
        local event = {}
        while event[1] ~= "shutdown" do
            event = {coroutine.yield()}
        end
        kernel.mark_routine_offline()
    else
        while true do
            coroutine.yield()
        end
    end
end

---Creates a new user namespace.
function os.create_user_environment()
    local env = {
        ["print"] = print,
        ["error"] = error,
        ["assert"] = assert,
        ["pcall"] = pcall,
        ["tostring"] = tostring,
        ["tonumber"] = tonumber,
        ["type"] = type,
        ["pairs"] = pairs,
        ["ipairs"] = ipairs,
        ["next"] = next,
        ["unpack"] = table.unpack,
        ["loadfile"] = loadfile,
        ["dofile"] = dofile,
        ["setmetatable"] = setmetatable,
        ["getmetatable"] = getmetatable,
        ["write"] = write,
        ["read"] = read,
        ["sleep"] = sleep
    }
    for name, lib in pairs(libraries) do
        env[name] = lib
    end
    return env
end

--- Uninstalls LuxOS and restarts the computer.
function os.uninstall()
    local script_path = "uninstall.lua"
    local i = 0
    while fs.exists(script_path) do
        script_path = "uninstall-"..i..".lua"
    end
    local f = fs.open(script_path, "w")
    f.write([[
        print("Uninstalling LuxOS...")

        local function remove_files(file)
            if not fs.exists(file) then
                print("Skipping "..file)
                return
            end
            if fs.isDir(file) then
                for index, f in ipairs(fs.list(file)) do
                    remove_files(file.."/"..f)
                end
                fs.delete(file)
            else
                print("Removing "..file)
                fs.delete(file)
            end
        end

        remove_files("LuxOS")
        remove_files("startup")
        remove_files(".settings")
        remove_files("]]..script_path..[[")

        print("LuxOS has been removed. You can use the following command to install it again:")
        print("pastebin run ]]..lux.INSTALLER_CODE..[[")
    ]])
    f.close()
    boot.set_boot_sequence(script_path)
    os.reboot()
end

--- Uninstalls LuxOS and reinstalls a fresh updated version.
function os.reinstall()
    local script_path = "reinstall.lua"
    local i = 0
    while fs.exists(script_path) do
        script_path = "reinstall-"..i..".lua"
    end
    local f = fs.open(script_path, "w")
    f.write([[
        print("Uninstalling LuxOS...")

        local function remove_files(file)
            if not fs.exists(file) then
                print("Skipping "..file)
                return
            end
            if fs.isDir(file) then
                for index, f in ipairs(fs.list(file)) do
                    remove_files(file.."/"..f)
                end
                fs.delete(file)
            else
                print("Removing "..file)
                fs.delete(file)
            end
        end

        remove_files("LuxOS")
        remove_files("startup")
        remove_files(".settings")
        remove_files("]]..script_path..[[")

        print("LuxOS has been removed. Re-installing it...")
        local pastebin_func, err = loadfile("rom/programs/http/pastebin.lua")
        if not pastebin_func then
            error("error while loading pastebin: "..err)
        end
        pastebin_func("run", "]]..lux.INSTALLER_CODE..[[")
    ]])
    f.close()
    boot.set_boot_sequence(script_path)
    os.reboot()
end