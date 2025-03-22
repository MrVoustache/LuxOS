--[[
This is the main script of LuxOS. It has multiple steps:
- It makes the "lux" and "kernel" APIs available.
- It enumerates all the Lux packages APIs and all the routines of the Lux packages.
- It makes all the Lux packages APIs available.
- It runs all of the Lux packages routines in parallel and watches for "Lux_panic" events.
- It shuts down the computer.

Note that no routine should ever stop! This would cause a kernel panic.
]]

if _G.lux then       -- LuxOS is already running. Do not start it again!
    -- local function override_shell()
    --     local w, h = term.getSize()
    --     local rshift = 1
    --     term.clear()
    --     term.setCursorPos(1, 1)
    --     term.setBackgroundColor(colors.black)
    --     term.setTextColor(colors.purple)
    --     term.write("Lux")
    --     term.setTextColor(colors.blue)
    --     term.write("OS")
    --     term.setTextColor(colors.gray)
    --     term.write(" 1.0")
    --     term.setTextColor(colors.white)
    --     term.setCursorPos(1, 2)
    --     term.setBackgroundColor(colors.magenta)
    --     term.setCursorPos(w - rshift - 2, 1)
    --     term.write(" ")
    --     term.setBackgroundColor(colors.purple)
    --     term.setCursorPos(w - rshift - 1, 1)
    --     term.write(" ")
    --     term.setBackgroundColor(colors.blue)
    --     term.setCursorPos(w - rshift, 1)
    --     term.write(" ")
    --     term.setBackgroundColor(colors.black)
    --     term.setCursorPos(1, 2)
    -- end
    -- local ok, err = pcall(override_shell)
    -- if not ok then
    --     error("Error setting up shell:\n"..err, 1)
    -- end
    return
end

local old_shutdown = os.shutdown
local old_reboot = os.reboot

function os.version()
    return "LuxOS 1.0"
end

local panic_recovery_coroutine = coroutine.create(function()

    -- Copy the references to all the original functions: in case of panic, we need to have working code, no matter what the user did to the APIs.

    local getSize = term.getSize
    local setBackgroundColor = term.setBackgroundColor
    local clear = term.clear
    local setCursorPos = term.setCursorPos
    local setTextColor = term.setTextColor
    local native_term = term.native()
    local redirect = term.redirect

    local purple = colors.purple
    local blue = colors.blue
    local black = colors.black

    local create_window = window.create

    -- This yield only returns if a panic occurs. It will return the panic message.

    local panic_message = coroutine.yield()

    redirect(native_term)
    local w, h = getSize()
    setBackgroundColor(purple)
    clear()
    setCursorPos(1, 1)
    setTextColor(black)
    print()
    local panic_header = "LUX KERNEL PANIC"
    panic_header = string.rep(" ", math.floor((w - #panic_header) / 2))..panic_header
    print(panic_header)
    setCursorPos(1, h - 1)
    print(panic_header)
    local error_message_zone = create_window(native_term, 1, 4, w, h - 6, true)
    local virtual_error_screen = create_window(error_message_zone, 1, 1, w, 1024, true)
    virtual_error_screen.setBackgroundColor(black)
    virtual_error_screen.setTextColor(blue)
    redirect(virtual_error_screen)

    local message = "\nYour computer ran into a big problem. Here is the issue:\n\n" .. panic_message .. "\n\nPress any key to reboot"
    local pos = 1
    print(message)
    local h_visible = h - 6
    local _, h_text = virtual_error_screen.getCursorPos()
    virtual_error_screen.reposition(1, pos, w, 1024)

    while true do
        local event = {coroutine.yield()}
        if event[1] == "key" then
            break
        elseif event[1] == "mouse_scroll" then
            pos = math.min(1, math.max(h_visible - h_text + 1, pos - event[2]))
            virtual_error_screen.reposition(1, pos, w, 1024)
        end
    end
    old_reboot()

end)
coroutine.resume(panic_recovery_coroutine)
-- print("Loading kernel...")

_G.libraries = {       -- Contains all the APIs that the user will have access to (making it its environment).
    term = term,
    colors = colors,
    colours = colours,
    fs = fs,
    os = os,
    table = table,
    string = string,
    coroutine = coroutine,
    math = math,
    peripheral = peripheral,
    http = http,
    textutils = textutils,
    turtle = turtle,
    commands = commands,
    settings = settings,
    paintutils = paintutils,
    parallel = parallel,
    window = window,
    event = event,
    disk = disk,
    help = help,
}

libraries.libraries = libraries

dofile("LuxOS/kernel.lua")
dofile("LuxOS/syscall.lua")
dofile("LuxOS/lux.lua")

-- print("Kernel loaded!")
kernel.promote_coroutine(panic_recovery_coroutine)

local PANIC = false
local PANIC_MESSAGE = ""

---System hook for Lux kernel panic
local function catch_panic()
    while true do
        local event = {coroutine.yield()}
        if #event == 2 and event[1] == "Lux_panic" then
            PANIC_MESSAGE = event[2]
            PANIC = true
            return
        end
    end
end

---As the name says, it runs all of LuxOS
local function run_everything()
    local packages = {}
    local routines = {}

    if not kernel.panic_pcall("fs.exists", fs.exists, "LuxOS") then
        lux.panic("'LuxOS' folder does not exists: your Lux installation might have been partially erased.")
        return
    end

    if not kernel.panic_pcall("fs.isDir", fs.isDir, "LuxOS") then
        lux.panic("'LuxOS' folder is actually a file: your Lux installation has been broken.")
        return
    end

    for index, package_name in pairs(kernel.panic_pcall("fs.list", fs.list, "LuxOS")) do
        local package_path = "LuxOS/"..package_name
        if kernel.panic_pcall("fs.isDir", fs.isDir, package_path) then
            if kernel.panic_pcall("fs.exists", fs.exists, package_path.."/lib.lua") then
                packages[package_name] = package_path.."/lib.lua"
            end
            if kernel.panic_pcall("fs.exists", fs.exists, package_path.."/routine.lua") then
                routines[package_name] = package_path.."/routine.lua"
            end
        end
    end

    for package_name, package_path in pairs(packages) do
        local libs = kernel.panic_pcall("dofile", dofile, package_path)
        for name, lib in pairs(libs) do
            libraries[name] = lib
        end
    end
    for package_name, routine_path in pairs(routines) do
        local routine_main, routine_priority = kernel.panic_pcall("dofile", dofile, routine_path)
        if type(routine_main) ~= "function" then
            kernel.panic("Routine loader of package '"..package_name.."' did not return a function.'")
        end
        if routine_priority == nil then
            routine_priority = 0
        end
        if type(routine_priority) ~= "number" then
            kernel.panic("Routine loader of package '"..package_name.."' returned a non-number priority.")
        end
        local coro = coroutine.create(routine_main)
        kernel.register_routine(package_name, coro, routine_priority)
    end

    -- Start runtime : wait for all routines to be ready.

    local event = {}
    while true do
        for i, coro_data in ipairs(kernel.starting_routines("")) do
            local name, coro = coro_data[1], coro_data[2]
            -- print("Resuming starting routine '"..name.."' with '"..tostring(event[1]).."' event.")
            kernel.set_current_routine(name)
            local ok, err = coroutine.resume(coro, table.unpack(event))
            kernel.set_current_routine()
            if not ok then
                kernel.panic("Kernel routine '"..name.."' had an exception during startup:\n"..err)
            elseif coroutine.status(coro) == "dead" then
                kernel.panic("Kernel routine '"..name.."' stopped unexpectedly during startup.")
            end
        end
        if kernel.is_system_ready() then
            event = {}
            break
        end
        event = {coroutine.yield()}
    end
    syscall.validate_syscall_table()

    -- Normal runtime : everyone runs as if the world had no end

    while event[1] ~= "shutdown" do
        for i, coro_data in ipairs(kernel.get_routines_for_event(event[1])) do
            local name, coro = coro_data[1], coro_data[2]
            -- print("Resuming routine '"..name.."' with '"..tostring(event[1]).."' event.")
            kernel.set_current_routine(name)
            local ok, err = coroutine.resume(coro, table.unpack(event))
            kernel.set_current_routine()
            if not ok then
                kernel.panic("Kernel routine '"..name.."' had an exception:\n"..err)
            elseif coroutine.status(coro) == "dead" then
                kernel.panic("Kernel routine '"..name.."' stopped unexpectedly.")
            end
        end
        event = {coroutine.yield()}
    end

    -- Shutdown runtime : wait for all routines to return true before shutting down.

    kernel.initialize_shutdown()
    local shutdown_info = {table.unpack(event, 2)}

    while true do
        for i, coro_data in ipairs(kernel.disconnecting_routines(event[1])) do
            local name, coro = coro_data[1], coro_data[2]
            -- print("Resuming disconnecting routine '"..name.."' with '"..tostring(event[1]).."' event.")
            kernel.set_current_routine(name)
            local ok, err = coroutine.resume(coro, table.unpack(event))
            kernel.set_current_routine()
            if not ok then
                kernel.panic("Kernel routine '"..name.."' had an exception during shutdown:\n"..err)
            elseif coroutine.status(coro) == "dead" then
                kernel.panic("Kernel routine '"..name.."' stopped unexpectedly during shutdown.")
            end
        end
        if kernel.is_system_offline() then
            break
        end
        event = {coroutine.yield()}
    end

    -- Time to shutdown.

    if shutdown_info[1] == "s" then
        old_shutdown()
    elseif shutdown_info[1] == "r" then
        old_reboot()
    else
        kernel.panic("Shutdown event has incoherent arguments: "..kernel.tostring(shutdown_info))
    end

end

local catch_panic_coro, run_everything_coro = coroutine.create(catch_panic), coroutine.create(run_everything)
kernel.promote_coroutine(catch_panic_coro)
kernel.promote_coroutine(run_everything_coro)
local event = {}
while coroutine.status(catch_panic_coro) ~= "dead" do
    coroutine.resume(run_everything_coro, table.unpack(event))
    coroutine.resume(catch_panic_coro, table.unpack(event))
    event = {coroutine.yield()}
end

if PANIC then

    coroutine.resume(panic_recovery_coroutine, PANIC_MESSAGE)
    while true do
        local event = {coroutine.yield()}
        local ok, err = coroutine.resume(panic_recovery_coroutine, table.unpack(event))
        if not ok then
            print(err)
            return
        end
    end

end