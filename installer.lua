local DIRECTORY = 1
local FILE = 2
local ENTRY_POINT = "LuxOS/main.lua"

local function print_color(color, ...)
    local old_color = term.getTextColor()
    term.setTextColor(color)
    print(...)
    term.setTextColor(old_color)
end

local package = {
	name = "LuxOS",
	type = DIRECTORY,
	children = {
		{
			name = "autorun",
			type = DIRECTORY,
			children = {
				{
					name = "lib.lua",
					type = FILE,
					code = 1
				},
				{
					name = "registered",
					type = DIRECTORY,
					children = {

					}
				},
				{
					name = "routine.lua",
					type = FILE,
					code = 2
				}
			}
		},
		{
			name = "boot",
			type = DIRECTORY,
			children = {
				{
					name = "lib.lua",
					type = FILE,
					code = 3
				},
				{
					name = "routine.lua",
					type = FILE,
					code = 4
				}
			}
		},
		{
			name = "kernel.lua",
			type = FILE,
			code = 5
		},
		{
			name = "lux.lua",
			type = FILE,
			code = 6
		},
		{
			name = "luxnet",
			type = DIRECTORY,
			children = {
				{
					name = "lib.lua",
					type = FILE,
					code = 7
				},
				{
					name = "routine.lua",
					type = FILE,
					code = 8
				}
			}
		},
		{
			name = "luxUI",
			type = DIRECTORY,
			children = {
				{
					name = "routine.lua",
					type = FILE,
					code = 9
				},
				{
					name = "shell.lua",
					type = FILE,
					code = 10
				}
			}
		},
		{
			name = "main.lua",
			type = FILE,
			code = 11
		},
		{
			name = "processes",
			type = DIRECTORY,
			children = {
				{
					name = "lib.lua",
					type = FILE,
					code = 12
				}
			}
		},
		{
			name = "services",
			type = DIRECTORY,
			children = {
				{
					name = "lib.lua",
					type = FILE,
					code = 13
				},
				{
					name = "routine.lua",
					type = FILE,
					code = 14
				}
			}
		},
		{
			name = "standart_library",
			type = DIRECTORY,
			children = {
				{
					name = "app.lua",
					type = FILE,
					code = 15
				},
				{
					name = "lib.lua",
					type = FILE,
					code = 16
				},
				{
					name = "path.lua",
					type = FILE,
					code = 17
				}
			}
		},
		{
			name = "syscall.lua",
			type = FILE,
			code = 18
		}
	}
}              -- This is actually a Python format variable.

local raw_package = {
[[--]].."[["..[[
This the standart autorun Lux API. Use it to register/unregister scripts that should be run at startup.
]].."]]"..[[

_G.autorun = {}     -- The autorun Lux API. Allows you to add and manage Lua script files to be run at system startup.





autorun.register = syscall.new(
    "autorun.register",
    ---Registers a script file to be run at system startup.
    ---@param script_path string The path to the script file to register.
    ---@param ... string The arguments for the script.
    ---@return integer identifier The identifier under which the script with these arguments will be referenced.
    function (script_path, ...)
        local ok, identifier_or_err = syscall.trampoline(script_path, ...)
        if ok then
            return identifier_or_err
        else
            error(identifier_or_err, 2)
        end
    end
)


autorun.unregister = syscall.new(
    "autorun.unregister",
    ---Unregisters an autorun script that has been run at system startup.
    ---@param identifier integer The identifier under which the script with these arguments will be referenced.
    function (identifier)
        local ok, err = syscall.trampoline(identifier)
        if not ok then
            error(err, 2)
        end
    end
)


autorun.enumerate = syscall.new(
    "autorun.enumerate",
    ---Returns the array of the names of the currently registered autorun scripts.
    ---@return {[integer] : string[]} tasks The table of tasks to be run at autorun. Indexes are identifiers and values are the commands.
    function ()
        local ok, tasks_or_err = syscall.trampoline()
        if not ok then
            error(tasks_or_err, 2)
        else
            return tasks_or_err
        end
    end
)


autorun.running_startup_scripts = syscall.new(
    "autorun.running_startup_scripts",
    ---Returns the list of currently running startup scripts.
    ---@return integer[] running The running script identifiers.
    function ()
        local ok, running_or_err = syscall.trampoline()
        if not ok then
            error(running_or_err, 2)
        else
            return running_or_err
        end
    end
)


---Returns true if all the startup scripts have returned.
---@return boolean finished Is startup finished?
function autorun.is_startup_finished()
    return #(autorun.running_startup_scripts()) == 0
end





return {autorun = autorun}]],
[[--]].."[["..[[
Routine for the autorun Lux package. Runs all the scripts registered for startup then halts.
]].."]]"..[[





local AUTORUN_FS_STRUCTURE = kernel.filesystem_structure{

    kernel.filesystem_node{
        name = "LuxOS",
        type = kernel.DIRECTORY,
        children = {

            kernel.filesystem_node{
                name = "autorun",
                type = kernel.DIRECTORY,
                children = {

                    kernel.filesystem_node{
                        name = "registered",
                        type = kernel.DIRECTORY,
                        mode = kernel.DIRECTORY.ENSURE_EXISTS
                    },

                    kernel.filesystem_node{
                        name = "commands.table",
                        type = kernel.FILE,
                        mode = kernel.FILE.ENSURE_EXISTS
                    },

                    kernel.filesystem_node{
                        name = "routine.lua",
                        type = kernel.FILE
                    },

                    kernel.filesystem_node{
                        name = "lib.lua",
                        type = kernel.FILE
                    }

                }
            }

        }
    }

}

local REGISTERED_SCRIPTS_DIR = "LuxOS/autorun/registered/"
local REGISTERED_SCRIPT_FILE = "LuxOS/autorun/commands.table"
local command_table = {}            ---@type {[integer] : string[]}     The scripts to run at startup, indexed by identifiers
local script_coroutines = {}       ---@type {[integer] : thread}

local function save_command_table()
    local f = kernel.panic_pcall("fs.open", fs.open, REGISTERED_SCRIPT_FILE, "w")
    f.write(textutils.serialise(command_table))
    f.close()
end

local function load_command_table()
    if not kernel.panic_pcall("fs.exists", fs.exists, REGISTERED_SCRIPT_FILE) then
        return
    end
    local f = kernel.panic_pcall("fs.open", fs.open, REGISTERED_SCRIPT_FILE, "r")
    local cmd_tab = textutils.unserialise(f.readAll())
    f.close()
    if type(cmd_tab) == "table" then
        command_table = cmd_tab
    end
end

--- Adds a script file with its arguments to the autorun system.
---@param script_path string The path to the script file to add
---@param args string[] The arguments for the script file.
---@return integer identifier The generated identifier for the script.
local function register_command(script_path, args)
    local max_identifier = 0
    for i, command in pairs(command_table) do
        if max_identifier < i then
            max_identifier = i
        end
    end
    local chosen_identifier = 0
    for identifier = 1, max_identifier + 1 do
        if command_table[identifier] == nil then
            chosen_identifier = identifier
            break
        end
    end
    kernel.panic_pcall("fs.copy", fs.copy, script_path, REGISTERED_SCRIPTS_DIR..chosen_identifier)
    command_table[chosen_identifier] = {script_path, table.unpack(args)}
    save_command_table()
    return chosen_identifier
end

--- Removes a script file and its arguments from autorun.
---@param identifier integer The identifier of the command.
local function unregister_command(identifier)
    kernel.panic_pcall("fs.delete", fs.delete, REGISTERED_SCRIPTS_DIR..identifier)
    command_table[identifier] = nil
    save_command_table()
end

---Answers the system calls to autorun.register.
local function answer_calls_to_register(...)
    local args = table.pack(...)
    if #args < 1 then
        return false, "syscall got "..tostring(#args).." parameters, expected at least 1"
    else
        for index, arg in ipairs(args) do
            if type(arg) ~= "string" then
                return false, "bad argument #"..index..": expected string, got "..type(arg)
            end
        end
        local script_path = table.remove(args, 1)
        if not kernel.panic_pcall("fs.exists", fs.exists, script_path) then
            return false, "given script file does not exist: '"..script_path.."'"
        elseif kernel.panic_pcall("fs.isDir", fs.isDir, script_path) then
            return false, "given script file is not a file: '"..script_path.."'"
        else
            return true, register_command(script_path, args)
        end
    end
end

---Answers the system calls to autorun.unregister.
local function answer_calls_to_unregister(...)
    local args = table.pack(...)
    if #args ~= 1 then
        return false, "syscall got "..tostring(#args).." parameters, expected 1"
    else
        local identifier = args[1]
        if type(identifier) ~= "number" then
            return false, "expected number, got '"..type(args[1]).."'"
        elseif identifier <= 0 then
            return false, "expected positive nonzero integer, got "..identifier
        elseif command_table[identifier] == nil then
            return false, "unknown autorun task: "..identifier
        else
            unregister_command(identifier)
            return true
        end
    end
end

---Answers the system calls to autorun.enumerate.
local function answer_calls_to_enumerate(...)
    local args = table.pack(...)
    if #args > 0 then
        return false, "syscall got "..tostring(#args).." parameters, expected 0"
    else
        local tab = {}
        for identifier, command in pairs(command_table) do
            tab[identifier] = command
        end
        return true, tab
    end
end

local function answer_calls_to_running_startup_scripts(...)
    local args = table.pack(...)
    if #args > 0 then
        return false, "syscall got "..tostring(#args).." parameters, expected 0"
    else
        local running = {}      ---@type integer[]
        for identifier, coro in pairs(script_coroutines) do
            if coroutine.status(coro) ~= "dead" then
                table.insert(running, identifier)
            end
        end
        return true, running
    end
end

---Internal function that runs the given program in user space.
---@param script_path string The path to the Lua script file to run.
---@param args string[] The arguments to call the script with.
local function execute_program(script_path, args)
    coroutine.yield()
    local func, err = loadfile(script_path, os.create_user_environment())
    if not func then
        term.setTextColor(colors.red)
        print("Error while executing autorun script '"..script_path.."':\n"..err)
    end
    local ok, err = kernel.run_function_in_user_space(pcall, func, table.unpack(args))
    if not ok then
        term.setTextColor(colors.red)
        print("Error while executing autorun script '"..script_path.."':\n"..err)
    end
end

---Runs all the autorun-registered script files in parallel and returns.
local function execute_autorun()

    load_command_table()

    for identifier, command in pairs(command_table) do
        local script_path = REGISTERED_SCRIPTS_DIR..identifier
        local args = {}
        for index, arg in ipairs(command) do
            if index > 1 then
                table.insert(args, arg)
            end
        end
        if not kernel.panic_pcall("fs.exists", fs.exists, script_path) then
            kernel.panic("Lost script file '"..identifier.."'.")
        end
        if kernel.panic_pcall("fs.isDir", fs.isDir, script_path) then
            kernel.panic("A folder '"..identifier.."' found its way in the '"..REGISTERED_SCRIPTS_DIR.."' script directory.")
        end
        local coro = coroutine.create(kernel.panic_pcall)
        kernel.promote_coroutine(coro)
        local ok, err = coroutine.resume(coro, "execute_program", execute_program, script_path, args)
        if not ok then
            kernel.panic("Error while creating autorun script coroutine #'"..identifier.."':\n"..err)
        end
        script_coroutines[identifier] = coro
    end

    syscall.affect_routine(autorun.register, answer_calls_to_register)
    syscall.affect_routine(autorun.unregister, answer_calls_to_unregister)
    syscall.affect_routine(autorun.enumerate, answer_calls_to_enumerate)
    syscall.affect_routine(autorun.running_startup_scripts, answer_calls_to_running_startup_scripts)

    kernel.mark_routine_ready()
    local running = true
    local event = {}
    while true do
        running = false
        for identifier, coro in pairs(script_coroutines) do
            if coroutine.status(coro) ~= "dead" then
                coroutine.resume(coro, table.unpack(event))
            end
            if coroutine.status(coro) ~= "dead" then
                running = true
            end
        end
        if kernel.is_system_shutting_down() then
            kernel.mark_routine_offline(false)
        end
        if running then
            event = {coroutine.yield()}
        else
            return
        end
    end
end


local function main()

    kernel.validate_filesystem_structure(AUTORUN_FS_STRUCTURE)
    execute_autorun()
    kernel.mark_routine_offline()

end

return main, 1]],
[[--]].."[["..[[
This is the library to handle the boot sequence of LuxOS. By default, this directly lauches the operating system but it can be changed.
]].."]]"..[[

_G.boot = {}            -- The LuxOS boot API. Allows the user the manage the boot sequence.





boot.set_boot_sequence = syscall.new(
    "boot.set_boot_sequence",
    --- Sets the boot sequence of LuxOS.
    ---@param ... string The files to execute in the given order.
    function (...)
        local ok, err = syscall.trampoline(...)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)





boot.get_boot_sequence = syscall.new(
    "boot.get_boot_sequence",
    --- Returns the boot sequence of LuxOS.
    ---@return string[] boot_sequence The files to execute at boot in the given order.
    function ()
        local ok, err_or_boot = syscall.trampoline()
        if ok then
            return err_or_boot
        else
            error(err_or_boot, 2)
        end
    end
)





--- Resets the boot to its original state.
function boot.reset()
    boot.set_boot_sequence("LuxOS/main.lua")
end





--- Disables LuxOS boot.
function boot.disable()
    boot.set_boot_sequence()
end





return {boot = boot}]],
[[--]].."[["..[[
This routine ensures that LuxOS will boot successfully.
]].."]]"..[[

-- while true do print(textutils.serialize({os.pullEvent()})) end





local WATCH_KEYS = {keys.s, keys.r}
local CTRL_LEFT = keys.leftCtrl
local CTRL_RIGHT = keys.rightCtrl
local BOOT_SEQUENCE = {"LuxOS/main.lua"}
local BOOT_FOLDER = "LuxOS/boot/boot_files"
local BOOT_FILE = "LuxOS/boot/boot.txt"
local BOOT_FS_STRUCTURE = kernel.filesystem_structure{

    kernel.filesystem_node{
        name = "LuxOS",
        type = kernel.DIRECTORY,
        children = {

            kernel.filesystem_node{
                name = "boot",
                type = kernel.DIRECTORY,
                children = {

                    kernel.filesystem_node{
                        name = "routine.lua",
                        type = kernel.FILE
                    },

                    kernel.filesystem_node{
                        name = "lib.lua",
                        type = kernel.FILE
                    },

                    kernel.filesystem_node{
                        name = "boot_files",
                        type = kernel.DIRECTORY,
                        mode = kernel.DIRECTORY.ENSURE_EXISTS
                    }
                    
                }
            }
        }
    }

}
local settings_set = settings.set
local settings_save = settings.save
local open = fs.open
local last_save = -math.huge





local function save_boot_file()
    local f = kernel.panic_pcall("fs.open", fs.open, BOOT_FILE, "w")
    for _, file in ipairs(BOOT_SEQUENCE) do
        f.write(file.."\n")
    end
    f.close()
end

local function load_boot_sequence()
    if not kernel.panic_pcall("fs.exists", fs.exists, BOOT_FILE) then
        boot.set_boot_sequence("LuxOS/main.lua")
    else
        local f = kernel.panic_pcall("fs.open", fs.open, BOOT_FILE, "r")
        BOOT_SEQUENCE = {}
        local line = " "
        while line do
            line = f.readLine()
            if line then
                line = string.gsub(line, "\n", "")
                table.insert(BOOT_SEQUENCE, line)
            end
        end
        f.close()
    end
end

local function ensure_boot(force)
    if force or os.time() - last_save > 0.01 then
        settings_set("shell.allow_startup", true)
        settings_set("shell.allow_disk_startup", false)
        settings_save(".settings")
        local f = open("startup", "w")
        for _, file in ipairs(BOOT_SEQUENCE) do
            kernel.panic_pcall("file.write", f.write, "dofile('"..BOOT_FOLDER.."/"..kernel.panic_pcall("fs.getName", fs.getName, file).."')\n")
        end
        f.close()
        last_save = os.time()
    end
end

local function answer_calls_to_get_boot_sequence(...)
    local args = table.pack(...)
    if #args > 0 then
        return false, "syscall got "..tostring(#args).." parameters, expected 0"
    else
        local res = {}
        for _, file in ipairs(BOOT_SEQUENCE) do
            table.insert(res, file)
        end
        return true, res
    end
end

local function answer_calls_to_set_boot_sequence(...)
    local args = table.pack(...)
    for index, file in ipairs(args) do
        if type(file) ~= "string" then
            return false, "bad argument #"..tostring(index)..": expected string, got '"..type(file).."'"
        end
    end
    for index, file in ipairs(args) do
        if not kernel.panic_pcall("fs.exists", fs.exists, file) then
            return false, "given file does not exist: '"..file.."'"
        end
    end
    for index, file in ipairs(args) do
        if kernel.panic_pcall("fs.isDir", fs.isDir, file) then
            return false, "given file is a directory: '"..file.."'"
        end
    end
    for index, file in ipairs(args) do
        local ok, err = loadfile(file, os.create_user_environment())
        if not ok then
            return false, "given file '"..file.."' could be loaded: "..err
        end
    end
    for index, file in ipairs(kernel.panic_pcall("fs.list", fs.list, BOOT_FOLDER)) do
        kernel.panic_pcall("fs.delete", fs.delete, BOOT_FOLDER.."/"..file)
    end
    for index, file in ipairs(args) do
        kernel.panic_pcall("fs.copy", fs.copy, file, BOOT_FOLDER.."/"..kernel.panic_pcall("fs.getName", fs.getName, file))
    end
    BOOT_SEQUENCE = args
    save_boot_file()
    ensure_boot(true)
    return true
end





local function main()

    kernel.validate_filesystem_structure(BOOT_FS_STRUCTURE)

    syscall.affect_routine(boot.get_boot_sequence, answer_calls_to_get_boot_sequence)
    syscall.affect_routine(boot.set_boot_sequence, answer_calls_to_set_boot_sequence)

    kernel.panic_pcall("load_boot_sequence", load_boot_sequence)

    local ctrl_left = false
    local ctrl_right = false

    kernel.panic_pcall("ensure_boot", ensure_boot)

    kernel.mark_routine_ready()

    while true do
        local event = {coroutine.yield()}
        if kernel.is_system_shutting_down() then
            break
        end
        if event[1] == "key" then
            local key = event[2]
            if key == CTRL_LEFT then
                ctrl_left = true
            elseif key == CTRL_RIGHT then
                ctrl_right = true
            elseif ctrl_left or ctrl_right then
                for _, k in ipairs(WATCH_KEYS) do
                    if k == key then
                        kernel.panic_pcall("ensure_boot", ensure_boot)
                    end
                end
            end
        elseif event[1] == "key_up" then
            local key = event[2]
            if key == CTRL_LEFT then
                ctrl_left = false
            elseif key == CTRL_RIGHT then
                ctrl_right = false
            end
        end
    end

    kernel.panic_pcall("ensure_boot", ensure_boot, true)

    kernel.mark_routine_offline()

end

return main]],
[[--]].."[["..[[
The Lux kernel API. Used only by Lux code!
]].."]]"..[[

_G.kernel = {} --- The kernel API. Used mostly by the Lux kernel. Most of its functions are not available in user space.
libraries.kernel = kernel





local main_coro = coroutine.running()
local kernel_coroutines = {[main_coro] = main_coro}    ---@type {[thread] : thread} Stores the kernel coroutines. The Key is the allowed coroutine and the value is the coroutine that added it.

---Checks that the caller runs in kernel space. Throws an error above ther caller otherwise.
function kernel.check_kernel_space_before_running()
    if not kernel.kernel_space() then
        error("Kernel-space-only function.", 3)
    end
end

local check_kernel_space_before_running = kernel.check_kernel_space_before_running


local current_coroutine = coroutine.running

---Returns whether or not this code is running in kernel space.
---@return boolean in_kernel_space If true, you are currently in kernel space. false otherwise.
function kernel.kernel_space()
    local coro, is_main = current_coroutine()
    return kernel_coroutines[coro] ~= nil
end


---Makes a coroutine a kernel coroutine.
---@param coro thread
function kernel.promote_coroutine(coro)
    check_kernel_space_before_running()
    local current_coroutine = current_coroutine()
    kernel_coroutines[coro] = current_coroutine
end





---Lux Kernel panic. Stops everything and prints the error.
---@param message string The message to print on the purple screen.
---@param level integer? The stacktrace level to trace the error back to. Default (0) is the the line where panic was called, 1 is where the function that called panic was called, etc.
function kernel.panic(message, level)
    check_kernel_space_before_running()
    if level == nil then
        level = 0
    end
    if type(message) ~= "string" then
        local ok, res = pcall(textutils.serialise, message)
        if ok then
            message = "Panic error: panic() received a non-string object:\n"..res
        else      
            message = "Panic error: panic() received a non-string object:\n"..tostring(message)
        end
    end
    local ok, res = pcall(error, "", 3 + level)
    os.queueEvent("Lux_panic", res..message)
    while true do
        coroutine.yield()
    end
end





---Calls the function in kernel protected mode: if an error is raised by this function, causes kernel panic.
---Returns what the function had returned on success.
---@generic R
---@generic P
---@param func_name string The name of the function to call. Used when panicking for better traceback.
---@param func fun(... : P) : R The function to call.
---@param ... any The arguments to call the function with.
---@return R func_return The return value(s) of the function.
function kernel.panic_pcall(func_name, func, ...)
    check_kernel_space_before_running()
    local res = {pcall(func, ...)}
    if not res[1] then
        kernel.panic("Error while calling the function '"..tostring(func_name).."':\n"..tostring(res[2]), 1)
    end
    table.remove(res, 1)
    return table.unpack(res)
end


---Runs the given function in user space (re-entering and leaving kernel space around each yield).
---Note that if this function raises an error, it will still cause a kernel panic.
---@generic P
---@generic R
---@param func fun(... : P) : R The function to run in user space.
---@param ... P The arguments to pass to the function.
---@return R func_return The return value(s) of the function
function kernel.run_function_in_user_space(func, ...)
    check_kernel_space_before_running()
    local coro = coroutine.create(func)
    local res = {coroutine.resume(coro, ...)}
    local ok, err = res[1], res[2]
    table.remove(res, 1)
    while true do
        if not ok then
            kernel.panic("An error occured while running a function in user space:\n"..err)
        end
        if coroutine.status(coro) == "dead" then
            return table.unpack(res)
        end
        local event = {coroutine.yield()}
        res = {coroutine.resume(coro, table.unpack(event))}
        ok, err = res[1], res[2]
        table.remove(res, 1)
    end
end





local routine_coroutines = {}   ---@type [string, thread][]
local routine_names = {}        ---@type {[string] : thread}
local routines_priority = {}    ---@type {[string] : integer}
local current_routine = nil     ---@type string?
local routines_ready = {}       ---@type {[string] : boolean}
local routines_offline = {}     ---@type {[string] : boolean}
local private_event = {}        ---@type {[string] : string}

---Register a new system routine. Only called by the main scheduler.
---@param name string The name of the coroutine.
---@param coro thread The coroutine object itself.
---@param priority integer The execution priority of the routine. The lower the number, the higher the priority. 0 is the highest priority.
function kernel.register_routine(name, coro, priority)
    check_kernel_space_before_running()
    kernel.promote_coroutine(coro)
    for iname, icoro in pairs(routine_coroutines) do
        if name == iname then
            kernel.panic("Routine '"..name.."' has already been registered.")
        end
    end
    routines_ready[name] = false
    routines_offline[name] = false
    routines_priority[name] = priority
    routine_names[name] = coro
    local ok = false
    for i, coro_data in ipairs(routine_coroutines) do
        if routines_priority[coro_data[1]].."]]"..[[ > priority then
            table.insert(routine_coroutines, i, {name, coro})
            ok = true
            break
        end
    end
    if not ok then
        table.insert(routine_coroutines, {name, coro})
    end
end

---Sets the name of the currently running routine.
---@param name string? The name of the current routine.
function kernel.set_current_routine(name)
    check_kernel_space_before_running()
    current_routine = name
end

---Returns the name of the currently running system routine.
---@return string name The name of the current system routine.
function kernel.current_routine()
    if current_routine == nil then
        kernel.panic("Calling function 'kernel.current_routine' outside of a routine.")
    else
        return current_routine
    end
    return "nil"
end

---Returns a dictionnary of all the existing routines.
---@return [string, thread][] routines The existing routines, indexed by priority.
function kernel.routines()
    check_kernel_space_before_running()
    return routine_coroutines
end

---Registers an event as private to the currently running routine.
---@param event_name string The name of the event to make private.
function kernel.make_event_private(event_name)
    check_kernel_space_before_running()
    if private_event[event_name] ~= nil then
        kernel.panic("Event '"..event_name.."' is already private to routine '"..private_event[event_name].."'.")
    end
    private_event[event_name] = kernel.current_routine()
end

---Returns a table of the routines to run for a given event.
---@param event_name string The name of the event to get the routines for.
---@return [string, thread][] routines The routines to run for the event.
function kernel.get_routines_for_event(event_name)
    check_kernel_space_before_running()
    if private_event[event_name] ~= nil then
        return {{private_event[event_name], routine_names[private_event[event_name]].."]]"..[[}}
    else
        return kernel.routines()
    end
end

---Marks the currently running routine as ready to start LuxOS.
---@param halt boolean? If true (default), waits until all the other routines are ready to start.
function kernel.mark_routine_ready(halt)
    check_kernel_space_before_running()
    if halt == nil then
        halt = true
    end
    local name = kernel.current_routine()
    if routines_ready[name] == nil then
        kernel.panic("Unknown routine '"..name.."' tried to mark itself ready.", 1)
    end
    routines_ready[name] = true
    while not kernel.is_system_ready() do
        coroutine.yield()
    end
end

---Returns true when the system is ready to run (i.e. when all routines haved marked themselves ready).
---@return boolean ready Is LuxOS ready to run?
function kernel.is_system_ready()
    for name, ready in pairs(routines_ready) do
        if not ready then
            return false
        end
    end
    return true
end

---Returns an array of the routines that have yet to finish startup.
---@param event_name string The name of the event to get the routines for.
---@return [string, thread][] not_ready The routines' coroutines to run to finish startup.
function kernel.starting_routines(event_name)
    check_kernel_space_before_running()
    if private_event[event_name] ~= nil and not routines_ready[private_event[event_name]].."]]"..[[ then
        return {{private_event[event_name], routine_names[private_event[event_name]].."]]"..[[}}
    end
    local not_ready = {}
    for i, coro_data in ipairs(routine_coroutines) do
        if not routines_ready[coro_data[1]].."]]"..[[ then
            table.insert(not_ready, {coro_data[1], coro_data[2]})
        end
    end
    return not_ready
end

---Marks the currently running routine as offline and ready for shutdown.
---@param halt boolean? If true (default), this function will halt forever, awaiting shutdown.
function kernel.mark_routine_offline(halt)
    check_kernel_space_before_running()
    if halt == nil then
        halt = true
    end
    local name = kernel.current_routine()
    if routines_offline[name] == nil then
        kernel.panic("Unknown routine '"..name.."' tried to mark itself offline.", 1)
    end
    routines_offline[name] = true
    if halt then
        while true do
            coroutine.yield()
        end
    end
end

---Returns true when the system is ready for shutdown (i.e. when all routines haved marked themselves offline).
---@return boolean offline Is LuxOS ready to shutdown?
function kernel.is_system_offline()
    for name, offline in pairs(routines_offline) do
        if not offline then
            return false
        end
    end
    return true
end

---Returns an array of the routines that have yet to finish shutting down.
---@param event_name string The name of the event to get the routines for.
---@return [string, thread][] not_ready The routines' coroutines to run to finish shutdown.
function kernel.disconnecting_routines(event_name)
    check_kernel_space_before_running()
    if private_event[event_name] ~= nil and not routines_offline[private_event[event_name]].."]]"..[[ then
        return {{private_event[event_name], routine_names[private_event[event_name]].."]]"..[[}}
    end
    local not_offline = {}
    for i, coro_data in ipairs(routine_coroutines) do
        if not routines_offline[coro_data[1]].."]]"..[[ then
            table.insert(not_offline, {coro_data[1], coro_data[2]})
        end
    end
    return not_offline
end





local SHUTTING_DOWN = false

---Returns true if the kernel has initialized shutdown.
---@return boolean shutting_down
function kernel.is_system_shutting_down()
    return SHUTTING_DOWN
end

---Initializes kernel shutdown. Should only be called once.
function kernel.initialize_shutdown()
    check_kernel_space_before_running()
    if SHUTTING_DOWN then
        kernel.panic("Shutdown has already been initialized.", 1)
    end
    SHUTTING_DOWN = true
end





--- A class to represent a filesystem node for kernel runtime checks. See function 'kernel.chec'
---@class FS_Node
---@field name string
---@field type FS_Node_type
---@field mode FileModes | DirectoryModes
---@field children FS_Node[]
local FS_Node = {}
FS_Node.__index = FS_Node
FS_Node.__name = "FS_Node"

local i = 1
---Internal function used to create enums.
---@return integer
local function enum()
    local res = i
    i = i * 2
    return res
end

---@enum FileModes
kernel.FILE = {
    EXISTS = enum(),                    -- Checks that the file exists and is not a directory. Panics otherwise.
    ENSURE_EXISTS = enum(),               -- Ensures that the file does exist, creating an empty file if not and deleting recursively directories with the same name.
    DOES_NOT_EXIST = enum(),            -- Checks that the file does not exist nor a that a directory with the same name exists. Panics otherwise.
    ENSURE_DOES_NOT_EXISTS = enum(),    -- Ensures that the file does not exist, deleting it or deleting recursively directories with the same name.
}
---@enum DirectoryModes
kernel.DIRECTORY = {
    EXISTS = enum(),                    -- Checks that the directory exists and is not a file. Panics otherwise.
    ENSURE_EXISTS = enum(),             -- Ensures that the directory does exist, creating an empty directory if not and deleting files with the same name.
    DOES_NOT_EXIST = enum(),            -- Checks that the directory does not exist nor a that a file with the same name exists. Panics otherwise.
    ENSURE_DOES_NOT_EXISTS = enum(),    -- Ensures that the directory does not exist, deleting it recursively or deleting files with the same name.
}

---@alias FS_Node_type `kernel.FILE` | `kernel.DIRECTORY`

---Creates a new node for a file system structure tree.
---@param obj {name : string, type : FS_Node_type, mode : FileModes | DirectoryModes ?, children : FS_Node[]?}
function FS_Node:new(obj)
    check_kernel_space_before_running()
    local fs_struct = obj or {}
    setmetatable(fs_struct, self)
    if type(fs_struct.name) ~= "string" then
        kernel.panic("FS_Node's 'name' field should be a string, not '"..type(fs_struct.name).."'", 1)
    end
    if fs_struct.type ~= kernel.FILE and fs_struct.type ~= kernel.DIRECTORY then
        kernel.panic("FS_Node's 'type' field should be either 'FS_Node.FILE' or 'FS_Node.DIRECTORY', not '"..tostring(fs_struct.type).."'", 1)
    end
    if not fs_struct.mode then
        if fs_struct.type == kernel.FILE then
            fs_struct.mode = kernel.FILE.EXISTS
        else
            fs_struct.mode = kernel.DIRECTORY.EXISTS
        end
    else
        local ok = false
        for mode_name, mode_value in pairs(fs_struct.type) do
            if fs_struct.mode == mode_value then
                ok = true
                break
            end
        end
        if not ok then
            kernel.panic("Unrecognized "..((fs_struct.type == kernel.FILE) and "file" or "directory").." mode: "..tostring(fs_struct.mode), 1)
        end
    end
    if type(fs_struct.children) ~= "table" and fs_struct.children ~= nil then
        kernel.panic("FS_Node's 'children' field should be a table, not '"..type(fs_struct.children).."'", 1)
    end
    local children = fs_struct.children or {}
    fs_struct.children = {}
    for index, child in ipairs(children) do
        if type(child) ~= type(fs_struct) then
            kernel.panic("FS_Node children should also be '"..type(child).."', not '"..type(fs_struct).."'", 1)
        end
        if not rawequal(getmetatable(child), self) then
            kernel.panic("FS_Node children should also be '"..type(child).."', not '"..type(fs_struct).."' (different metatables)", 1)
        end
        table.insert(fs_struct.children, child)
    end
    if #fs_struct.children > 0 and fs_struct.type == kernel.FILE then
        kernel.panic("FS_Node of type FILE has "..tostring(#fs_struct.children).." children.")
    end
    if #fs_struct.children > 0 and (fs_struct.mode == kernel.DIRECTORY.DOES_NOT_EXIST or fs_struct.mode == kernel.DIRECTORY.ENSURE_DOES_NOT_EXISTS) then
        kernel.panic("FS_Node of type DIRECTORY has "..tostring(#fs_struct.children).." children with mode '"..((fs_struct.mode == kernel.DIRECTORY.DOES_NOT_EXIST) and "DOES_NOT_EXIST" or "ENSURE_DOES_NOT_EXISTS").."'.")
    end
    return fs_struct
end

---Creates a new filesystem structure tree, starting from the root.
---@param root_items {children : FS_Node[]}
function kernel.filesystem_structure(root_items)
    check_kernel_space_before_running()
    return FS_Node:new{
        name = "",
        type = kernel.DIRECTORY,
        children = root_items
    }
end

---Creates a new node for a file system structure tree.
---@param node {name : string, type : FS_Node_type, mode : FileModes | DirectoryModes ?, children : FS_Node[]?} A table hodling the required information about the node.
---@return FS_Node node The new filesystem node.
function kernel.filesystem_node(node)
    check_kernel_space_before_running()
    return FS_Node:new(node)
end





--]].."[["..[[Ensures that the given filesystem structure exists. Panics if not. Here is an example of such a structure:

    local filesystem = kernel.filesystem_structure{       -- Implicitely creates the root directory.

        kernel.filesystem_node{
            name = "startup.lua",       -- A startup file at the root.
            type = kernel.FILE
        },

        kernel.filesystem_node{
            name = "tmp",               -- A possible tmp directory...
            type = kernel.DIRECTORY,
            mode = kernel.DIRECTORY.IS_NOT_FILE  -- ...as long as it does not exist as a file.
        },

        kernel.filesystem_node{
            name = "LuxOS",             -- The LuxOS directory at the root.
            type = kernel.DIRECTORY,
            children = {

                kernel.filesystem_node{
                    name = "kernel.lua",
                    type = kernel.FILE  -- A kernel file inside LuxOS.
                }

            }
        }

    }
    
    kernel.validate_filesystem_structure(filesystem)      -- Panics if the described filesystem structure does not exist.

]].."]]"..[[
---@param structure FS_Node The structure. A FS_Node object.
function kernel.validate_filesystem_structure(structure)
    check_kernel_space_before_running()

    ---Inner recursive structure checker
    ---@param sub_structure FS_Node Directory to check.
    ---@param root string The path of the parent directory.
    ---@param level integer The depth in the filesystem + 1.
    local function recursive_structure_validation(sub_structure, root, level)
        for index, child_node in ipairs(sub_structure.children) do
            local path = root..child_node.name
            if child_node.type == kernel.FILE then
                if child_node.mode == kernel.FILE.EXISTS then
                    if not kernel.panic_pcall("fs.exists", fs.exists, path) then
                        kernel.panic("Required file node '"..path.."' does not exist.", level)
                    end
                    if kernel.panic_pcall("fs.isDir", fs.isDir, path) then
                        kernel.panic("Required file node '"..path.."' exists but is a directory.", level)
                    end
                elseif child_node.mode == kernel.FILE.ENSURE_EXISTS then
                    if kernel.panic_pcall("fs.exists", fs.exists, path) and kernel.panic_pcall("fs.isDir", fs.isDir, path) then
                        kernel.panic_pcall("fs.delete", fs.delete, path)
                    end
                    if not kernel.panic_pcall("fs.exists", fs.exists, path) then
                        local h = kernel.panic_pcall("fs.open", fs.open, path, "w")
                        kernel.panic_pcall("h.close", h.close)
                    end
                elseif child_node.mode == kernel.FILE.DOES_NOT_EXIST then
                    if kernel.panic_pcall("fs.exists", fs.exists, path) then
                        if kernel.panic_pcall("fs.isDir", fs.isDir, path) then
                            kernel.panic("Forbidden file node '"..path.."' exists as a directory.", level)
                        end
                        kernel.panic("Forbidden file node '"..path.."' exists.", level)
                    end
                elseif child_node.mode == kernel.FILE.ENSURE_DOES_NOT_EXISTS then
                    if kernel.panic_pcall("fs.exists", fs.exists, path) then
                        kernel.panic_pcall("fs.delete", fs.delete, path)
                    end
                end
            else
                if child_node.mode == kernel.DIRECTORY.EXISTS then
                    if not kernel.panic_pcall("fs.exists", fs.exists, path) then
                        kernel.panic("Required directory node '"..path.."' does not exist.", level)
                    end
                    if not kernel.panic_pcall("fs.isDir", fs.isDir, path) then
                        kernel.panic("Required directory node '"..path.."' exists but is a file.", level)
                    end
                    recursive_structure_validation(child_node, path.."/", level + 1)
                elseif child_node.mode == kernel.DIRECTORY.ENSURE_EXISTS then
                    if kernel.panic_pcall("fs.exists", fs.exists, path) and not kernel.panic_pcall("fs.isDir", fs.isDir, path) then
                        kernel.panic_pcall("fs.delete", fs.delete, path)
                    end
                    if not kernel.panic_pcall("fs.exists", fs.exists, path) then
                        kernel.panic_pcall("fs.makeDir", fs.makeDir, path)
                    end
                    recursive_structure_validation(child_node, path.."/", level + 1)
                elseif child_node.mode == kernel.DIRECTORY.DOES_NOT_EXIST then
                    if kernel.panic_pcall("fs.exists", fs.exists, path) then
                        if not kernel.panic_pcall("fs.isDir", fs.isDir, path) then
                            kernel.panic("Forbidden directory node '"..path.."' exists as a file.", level)
                        end
                        kernel.panic("Forbidden directory node '"..path.."' exists.", level)
                    end
                elseif child_node.mode == kernel.DIRECTORY.ENSURE_DOES_NOT_EXISTS then
                    if kernel.panic_pcall("fs.exists", fs.exists, path) then
                        kernel.panic_pcall("fs.delete", fs.delete, path)
                    end
                end
            end
        end
    end

    if getmetatable(structure) ~= FS_Node then
        kernel.panic("'kernel.validate_fs_structure' expected a FS_Node object, got a '"..type(structure).."' (wrong metatable).")
    end
    if structure.name ~= "" or structure.type ~= kernel.DIRECTORY then
        kernel.panic("Invalid root node in structure given to 'kernel.validate_fs_structure', got a "..((structure.type == kernel.FILE) and "file" or "directory").." node named '"..tostring(structure.name).."'")
    end
    recursive_structure_validation(structure, structure.name, 1)
end]],
[[--]].."[["..[[
This is the standart library of LuxOS
]].."]]"..[[

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
    f.write(]].."[["..[[
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
        remove_files("]].."]]"..[[..script_path..]].."[["..[[")

        print("LuxOS has been removed. You can use the following command to install it again:")
        print("pastebin run ]].."]]"..[[..lux.INSTALLER_CODE..]].."[["..[[")
    ]].."]]"..[[)
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
    f.write(]].."[["..[[
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
        remove_files("]].."]]"..[[..script_path..]].."[["..[[")

        print("LuxOS has been removed. Re-installing it...")
        local pastebin_func, err = loadfile("rom/programs/http/pastebin.lua")
        if not pastebin_func then
            error("error while loading pastebin: "..err)
        end
        pastebin_func("run", "]].."]]"..[[..lux.INSTALLER_CODE..]].."[["..[[")
    ]].."]]"..[[)
    f.close()
    boot.set_boot_sequence(script_path)
    os.reboot()
end]],
[[--]].."[["..[[
This is the standart LuxNet service API. It contains all the functions to communicate with other machines running on LuxOS.

Use luxnet() to create a new LuxNet context.
]].."]]"..[[

_G.luxnet = {}      -- The LuxNet API. Allows you to communicate with other machines running LuxOS.





luxnet.LUXNET_PORT = 42      -- The port that LuxNet uses to communicate with other machines.
luxnet.BROADCAST_ID = -1     -- The ID that represents a broadcast message. This is used to send messages to all machines.





---@class Message The class for message objects.
---@field sender integer The ID of the sender.
---@field receiver integer The ID of the receiver.
---@field message table | string | number | boolean | nil The message itself.
---@field protocol string | nil The protocol used to send the message.
---@field identifier integer A unique identifier for the message.
---@field jumps integer The amount of jumps the message has done to reach the receiver.
---@field time_to_live integer The maximum number of jumps the message can do. Can be infinite.
---@field distance number The distance that the message has traveled.
---@field frequency integer The frequency that the message was sent on.
---@field time_sent number The time when the message was sent.
---@field time_received number The time when the message was received.
local Message = {}
luxnet.Message = Message

Message.__index = Message
Message.__name = "Message"


---Creates a new Message object.
---@param message {["sender"]: integer, ["receiver"]: integer, ["message"]: table | string | number | boolean | nil, ["protocol"]: string | nil, ["identifier"]: integer, ["jumps"]: integer, ["time_to_live"]: integer, ["distance"]: number, ["frequency"]: integer, ["time_sent"]: number, ["time_received"]: number} The required parameters for creating a message.
---@return Message message The new message object.
function Message:new(message)
    setmetatable(message, self)
    return message
end


function Message:__tostring()
    local ok, message_str = pcall(textutils.serialize, self.message)
    if not ok then
        message_str = tostring(self.message)
    end
    local protocol = "nil"
    if self.protocol ~= nil then
        protocol = "'"..self.protocol.."'"
    end
    return "Message{sender=" .. self.sender .. ", receiver=" .. self.receiver .. ", message=" .. message_str .. ", protocol=" .. protocol .. ", identifier=" .. self.identifier .. ", jumps=" .. self.jumps .. ", time_to_live=" .. self.time_to_live .. ", distance=" .. self.distance .. ", frequency=" .. self.frequency .. ", time_sent=" .. self.time_sent .. ", time_received=" .. self.time_received .. "}"
end



---@class Response The class for response objects.
---@field sender integer The ID of the sender of the corresponding message.
---@field receiver integer The ID of the receiver of the corresponding message.
---@field identifier integer The identifier of the corresponding message.
---@field jumps integer The amount of jumps that the corresponding message has done to reach the receiver.
---@field time_to_live integer The remaining time_to_live. time_to_live + jumps = initial time_to_live.
---@field distance number The distance that the corresponding message has traveled to reach the receiver.
---@field frequency integer The frequency that the corresponding message was sent on.
---@field time_sent number The time when the corresponding message was sent.
---@field time_received number The time when the corresponding message was received.
local Response = {}
luxnet.Response = Response

Response.__index = Response
Response.__name = "Response"


---Creates a new Response object. Can only be called from kernel space.
---@param response {["sender"]: integer, ["receiver"]: integer, ["identifier"]: integer, ["jumps"]: integer, ["time_to_live"]: integer, ["distance"]: number, ["frequency"]: integer, ["time_sent"]: number, ["time_received"]: number} The required parameters for creating a response.
---@return Response response The new response object.
function Response:new(response)
    setmetatable(response, self)
    return response
end


function Response:__tostring()
    return "Response{sender=" .. self.sender .. ", receiver=" .. self.receiver .. ", identifier=" .. self.identifier .. ", jumps=" .. self.jumps .. ", time_to_live=" .. self.time_to_live .. ", distance=" .. self.distance .. ", frequency=" .. self.frequency .. ", time_sent=" .. self.time_sent .. ", time_received=" .. self.time_received .. "}"
end





luxnet.enable_frequency = syscall.new(
    "luxnet.enable_frequency",
    ---Enables the frequency of the machine for LuxNet. Each call to enable_frequency should be matched with a call to disable_frequency.
    ---@param frequency integer The frequency to enable.
    function (frequency)
        local ok, err = syscall.trampoline(frequency)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)





luxnet.disable_frequency = syscall.new(
    "luxnet.disable_frequency",
    ---Disables the frequency of the machine for LuxNet.
    ---@param frequency integer The frequency to disable.
    function (frequency)
        local ok, err = syscall.trampoline(frequency)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)





luxnet.active_frequencies = syscall.new(
    "luxnet.active_frequencies",
    ---Returns a list of all active frequencies.
    ---@return integer[] frequencies A list of all active frequencies.
    function ()
        local ok, err_or_frequencies = syscall.trampoline()
        if ok then
            return err_or_frequencies
        else
            error(err_or_frequencies, 2)
        end
    end
)





luxnet.send = syscall.new(
    "luxnet.send",
    ---Sends a message to another machine.
    ---@param receiver integer The ID of the receiver.
    ---@param message table | string | number | boolean | nil The message to send.
    ---@param protocol string? The protocol to use to send the message.
    ---@param time_to_live integer? The maximum number of jumps the message can do. Can be infinite.
    ---@param frequency integer? The frequency to use to send the message.
    ---@param timeout number? The time to wait for a response before giving up.
    ---@return Response | false response The response from the receiver, if any, or false if the receiver didn't acknowledge the message.
    function (receiver, message, protocol, time_to_live, frequency, timeout)
        local ok, err_or_awaitable = syscall.trampoline(receiver, message, protocol, time_to_live, frequency, timeout)
        if not ok then
            error(err_or_awaitable, 2)
        end
        if err_or_awaitable == false then
            return false
        end
        local ok, err_or_response = err_or_awaitable()
        if ok then
            if err_or_response == false then
                return false
            else
                return Response:new(err_or_response)
            end
        else
            error(err_or_response, 2)
        end
    end
)


  


luxnet.broadcast = syscall.new(
    "luxnet.broadcast",
    ---Sends a message to all machines.
    ---@param message table | string | number | boolean | nil The message to send.
    ---@param protocol string? The protocol to use to send the message.
    ---@param time_to_live integer? The maximum number of jumps the message can do. Can be infinite.
    ---@param frequency integer? The frequency to use to send the message.
    function (message, protocol, time_to_live, frequency)
        local ok, err = syscall.trampoline(message, protocol, time_to_live, frequency)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)





luxnet.receive = syscall.new(
    "luxnet.receive",
    --- Receives a message from another machine.
    ---@param sender integer[] | integer | nil The ID(s) of the sender(s) to receive a message from. Can be a table of integers, a single integer, or nil to receive from any sender.
    ---@param protocol string? An optional protocal to filter messages by.
    ---@param timeout number? The time to wait for a message before giving up. Defaults to no timeout.
    ---@param ferquency integer? The frequency to receive the message on. Defaults to LUXNET frequency.
    ---@return Message? message The message received, or nil if the timeout was reached.
    function (sender, protocol, timeout, ferquency)
        local ok, err_or_awaitable = syscall.trampoline(sender, protocol, timeout, ferquency)
        if not ok then
            error(err_or_awaitable, 2)
        end
        local ok, err_or_message = err_or_awaitable()
        if ok then
            if err_or_message == nil then
                return nil
            else
                return Message:new(err_or_message)
            end
        else
            error(err_or_message, 2)
        end
    end
)





---@class LuxNetContext A class that holds a set of LuxNet settings and wraps system calls.
---@field frequency integer The frequency that the context is using.
---@field send_timeout number The time to wait for a response before giving up.
---@field receive_timeout number? The time to wait for a message before giving up.
---@field time_to_live integer? The maximum number of jumps the message can do. Can be infinite.
---@field protocol string? The protocol to use to send the message.
local LuxNetContext = {}
luxnet.LuxNetContext = LuxNetContext

LuxNetContext.__index = LuxNetContext
LuxNetContext.__name = "LuxNetContext"


---Creates a new LuxNetContext object.
---@param frequency integer? The frequency to use. Defaults to LUXNET frequency.
---@param send_timeout number? The time to wait for a response before giving up. Defaults to 5 seconds.
---@param receive_timeout number? The time to wait for a message before giving up. Defaults to no timeout.
---@param time_to_live integer? The maximum number of jumps the message can do. Can be infinite. Defaults to infinite.
---@param protocol string? The protocol to use to send the message. Defaults to nil.
---@return LuxNetContext context The new LuxNetContext object.
function LuxNetContext:new(frequency, send_timeout, receive_timeout, time_to_live, protocol)
    local context = {
        frequency = frequency or luxnet.LUXNET_PORT,
        send_timeout = send_timeout or 5,
        receive_timeout = receive_timeout,
        time_to_live = time_to_live,
        protocol = protocol,
    }
    setmetatable(context, self)
    luxnet.enable_frequency(context.frequency)
    return context
end


function LuxNetContext:__tostring()
    local receive_timeout = "inf"
    if self.receive_timeout ~= nil then
        receive_timeout = tostring(self.receive_timeout)
    end
    local time_to_live = "inf"
    if self.time_to_live ~= nil then
        time_to_live = tostring(self.time_to_live)
    end
    local protocol = "nil"
    if self.protocol ~= nil then
        protocol = "'"..self.protocol.."'"
    end
    return "LuxNetContext{frequency=" .. self.frequency .. ", send_timeout=" .. self.send_timeout .. ", receive_timeout=" .. receive_timeout .. ", time_to_live=" .. time_to_live .. ", protocol=" .. protocol .. "}"
end

---Sends a message to another machine.
---@param receiver integer The ID of the receiver.
---@param message table | string | number | boolean | nil The message to send.
---@return Response | false response The response from the receiver, if any, or false if the receiver didn't acknowledge the message.
function LuxNetContext:send(receiver, message)
    return luxnet.send(receiver, message, self.protocol, self.time_to_live, self.frequency, self.send_timeout)
end

---Broadcasts a message to all machines.
---@param message table | string | number | boolean | nil The message to send.
function LuxNetContext:broadcast(message)
    return luxnet.broadcast(message, self.protocol, self.time_to_live, self.frequency)
end

---Receives a message from another machine.
---@param sender integer[] | integer | nil The ID(s) of the sender(s) to receive a message from. Can be a table of integers, a single integer, or nil to receive from any sender.
---@return Message? message The message received, or nil if the timeout was reached.
function LuxNetContext:receive(sender)
    return luxnet.receive(sender, self.protocol, self.receive_timeout, self.frequency)
end

---Sets the context frequency.
---@param frequency integer The frequency to use.
function LuxNetContext:set_frequency(frequency)
    luxnet.disable_frequency(self.frequency)
    self.frequency = frequency
    luxnet.enable_frequency(frequency)
end

---Sets the context send timeout.
---@param send_timeout number The time to wait for a response before giving up.
function LuxNetContext:set_send_timeout(send_timeout)
    self.send_timeout = send_timeout
end

---Sets the context receive timeout.
---@param receive_timeout number? The time to wait for a message before giving up. Can be nil for no timeout.
function LuxNetContext:set_receive_timeout(receive_timeout)
    self.receive_timeout = receive_timeout or math.huge
end

---Sets the context time to live.
---@param time_to_live integer? The maximum number of jumps the message can do. Can be nil for infinite.
function LuxNetContext:set_time_to_live(time_to_live)
    self.time_to_live = time_to_live
end

---Sets the context protocol.
---@param protocol string? The protocol to use to send the message. Can be nil for no protocol.
function LuxNetContext:set_protocol(protocol)
    self.protocol = protocol
end





local luxnet_metatable = table.copy(table)
setmetatable(luxnet, luxnet_metatable)

---Shortcut for creating a new LuxNet context.
---@return LuxNetContext context The new LuxNetContext object.
function luxnet_metatable:__call(...)
    return LuxNetContext:new(...)
end





return {luxnet = luxnet}]],
[[--]].."[["..[[
This is the luxnet kernel routine. It handles all modems and everything that goes through them.
]].."]]"..[[





local LUXNET_FS_STRUCTURE = kernel.filesystem_structure{

    kernel.filesystem_node{
        name = "LuxOS",
        type = kernel.DIRECTORY,
        children = {

            kernel.filesystem_node{
                name = "luxnet",
                type = kernel.DIRECTORY,
                children = {

                    kernel.filesystem_node{
                        name = "routine.lua",
                        type = kernel.FILE
                    },

                    kernel.filesystem_node{
                        name = "lib.lua",
                        type = kernel.FILE
                    }

                }
            }
        }
    }

}
local LUXNET_PORT = luxnet.LUXNET_PORT
local HOST_ID_BUFFER_SIZE = 16
local DEFAULT_RESPONSE_TIMEOUT = 5

local modems = {}      ---@type {[string] : table} The table of all modems connected to the computer. The key is the side of the modem and the value is the modem object.
local active_frequencies = {[LUXNET_PORT] = 1}           ---@type {[number] : integer} The table of all active frequencies.
local COMPUTER_ID = os.getComputerID()
local seen_messages = {[COMPUTER_ID] = {}}        ---@type {[number] : number[]} The table of used identifiers per host for messages.
local seen_responses = {[COMPUTER_ID] = {}}        ---@type {[number] : number[]} The table of used identifiers per host for responses.
local n_messages = {[COMPUTER_ID] = 0}           ---@type {[number] : number} The table of the amount of messages per host.
local awaiting_timers = {}                      ---@type {[integer] : number} The table of active timeout timers.
local awaiting_response_callbacks = {}                   ---@type {[integer] : fun(): nil} The table of callbacks in case of a received response.
local awaiting_message_callbacks = {}                    ---@type {[integer] : fun(): nil} The table of callbacks in case of a received message.
local last_response = nil                        ---@type Response? The last response received.
local last_message = nil                        ---@type Message? The last message received.

local simple_message_fields = {
    sender = "number",
    receiver = "number",
    identifier = "number",
    jumps = "number",
    time_to_live = "number",
    distance = "number",
    time_sent = "number",
    time_received = "number"
}

---Checks if a message is a luxnet response.
---@param message table The message to check.
---@return boolean ok Whether the message is a response or not.
local function is_valid_response(message)
    if type(message) ~= "table" then
        return false
    end
    for field, field_type in pairs(simple_message_fields) do
        if type(message[field]) ~= field_type then
            print("Not a response:", field, "value", message[field], "is not a", field_type)
            return false
        end
    end
    return true
end

---Checks if a message can make a valid Message object.
---@param message any The message to check.
---@return boolean ok Whether the message is valid or not.
local function is_valid_message(message)
    if type(message) ~= "table" then
        return false
    end
    if type(message["message"]) ~= "table" and type(message["message"]) ~= "string" and message["message"] ~= "number" and message["message"] ~= "boolean" and message["message"] ~= "nil" then
        return false
    end
    if type(message["protocol"]) ~= "string" and type(message["protocol"]) ~= "nil" then
        return false
    end
    for field, field_type in pairs(simple_message_fields) do
        if type(message[field]) ~= field_type then
            return false
        end
    end
    return true
end

---Generates an identifier for a message.
---@return integer identifier The generated identifier.
local function identifier_generator()
    return math.random(0, 2147483646)       -- 2^31 - 2 for some reason
end


---Inserts a seen message into the seen messages table.
---@param sender integer The ID of the sender.
---@param identifier integer The identifier of the message.
local function insert_seen_message(sender, identifier)
    local index = (#seen_messages[sender] + 1) % HOST_ID_BUFFER_SIZE
    if index == 0 then
        index = HOST_ID_BUFFER_SIZE
    end
    seen_messages[sender][index] = identifier
    n_messages[sender] = n_messages[sender] + 1
end

---Inserts a seen response into the seen responses table.
---@param sender integer The ID of the sender.
---@param identifier integer The identifier of the response.
local function insert_seen_response(sender, identifier)
    local index = (#seen_responses[sender] + 1) % HOST_ID_BUFFER_SIZE
    if index == 0 then
        index = HOST_ID_BUFFER_SIZE
    end
    seen_responses[sender][index] = identifier
end

local function answer_calls_to_enable_frequency(...)
    local args = table.pack(...)
    if #args ~= 1 then
        return false, "syscall got "..tostring(#args).." parameters, expected 1"
    else
        local frequency = args[1]
        if type(frequency) ~= "number" then
            return false, "expected number, got '"..type(frequency).."'"
        end
        if frequency < 0 or frequency > 65535 then
            return false, "frequency must be between 0 and 65535"
        end
        if math.floor(frequency) ~= frequency then
            return false, "frequency must be an integer"
        end
        if active_frequencies[frequency] == nil then
            for side, modem in pairs(modems) do
                modem.open(frequency)
            end
            active_frequencies[frequency] = 1
        else
            active_frequencies[frequency] = active_frequencies[frequency] + 1
        end
        return true
    end
end

local function answer_calls_to_disable_frequency(...)
    local args = table.pack(...)
    if #args ~= 1 then
        return false, "syscall got "..tostring(#args).." parameters, expected 1"
    else
        local frequency = args[1]
        if type(frequency) ~= "number" then
            return false, "expected number, got '"..type(frequency).."'"
        end
        if frequency < 0 or frequency > 65535 then
            return false, "frequency must be between 0 and 65535"
        end
        if math.floor(frequency) ~= frequency then
            return false, "frequency must be an integer"
        end
        if active_frequencies[frequency] == nil then
            return false, "frequency #"..frequency.." is not enabled"
        else
            active_frequencies[frequency] = active_frequencies[frequency] - 1
            if active_frequencies[frequency] == 0 then
                for side, modem in pairs(modems) do
                    modem.close(frequency)
                end
                active_frequencies[frequency] = nil
            end
        end
        return true
    end
end

local function answer_calls_to_active_frequencies(...)
    local args = table.pack(...)
    if #args ~= 0 then
        return false, "syscall got "..tostring(#args).." parameters, expected 0"
    else
        local frequencies = {}
        for frequency, _ in pairs(active_frequencies) do
            frequencies[#frequencies + 1] = frequency
        end
        return true, frequencies
    end
    
end

local function answer_calls_to_send(...)
    local args = table.pack(...)
    if #args < 2 or #args > 6 then
        return false, "syscall got "..tostring(#args).." parameters, expected 2 to 6"
    else
        local receiver, message, protocol, time_to_live, frequency, timeout = args[1], args[2], args[3], args[4], args[5], args[6]
        if type(receiver) ~= "number" or (type(message) ~= "table" and type(message) ~= "string" and type(message) ~= "number" and type(message) ~= "boolean" and type(message) ~= "nil") or (type(protocol) ~= "string" and type(protocol) ~= "nil") or (time_to_live ~= nil and type(time_to_live) ~= "number") or (frequency ~= nil and type(frequency) ~= "number") or (timeout ~= nil and type(timeout) ~= "number") then
            return false, "expected number, table | string | number | boolean | nil, string | nil, number | nil, number | nil, got '"..type(receiver).."', '"..type(message).."', '"..type(protocol).."', '"..type(time_to_live).."', '"..type(frequency).."', '"..type(timeout).."'"
        end
        if time_to_live == nil then
            time_to_live = math.huge
        end
        if frequency == nil then
            frequency = LUXNET_PORT
        end
        if timeout == nil then
            timeout = DEFAULT_RESPONSE_TIMEOUT
        end
        if math.floor(time_to_live) ~= time_to_live or time_to_live < 0 then
            return false, "time to live must be a positive integer"
        end
        if math.floor(frequency) ~= frequency or frequency < 0 or frequency > 65535 then
            return false, "frequency must be an integer between 0 and 65535"
        end
        if timeout < 0 then
            return false, "timeout must be a positive number"
        end
        if math.floor(receiver) ~= receiver or receiver < 0 or receiver > 65535 then
            return false, "receiver ID must be an integer between 0 and 65535"
        end
        if active_frequencies[frequency] == nil then
            return false, "frequency #"..frequency.." is not enabled"
        end
        if time_to_live == 0 then
            return true, false
        end
        local identifier = identifier_generator()
        local message = {
            sender = COMPUTER_ID,
            receiver = receiver,
            message = message,
            protocol = protocol,
            identifier = identifier,
            jumps = 0,
            time_to_live = time_to_live,
            distance = 0,
            time_sent = os.time(),
            time_received = 0
        }
        for side, modem in pairs(modems) do
            modem.transmit(frequency, frequency, message)
        end
        insert_seen_message(COMPUTER_ID, identifier)
        local response = nil            ---@type Response?
        local timer = os.startTimer(timeout)
        awaiting_timers[timer] = identifier
        local awaitable, completion = syscall.await(
            function ()
                if response ~= nil and response.identifier == identifier and response.receiver == receiver then
                    return true
                elseif awaiting_timers[timer] == nil then
                    return true
                end
                return false
            end,
            function ()
                awaiting_response_callbacks[identifier] = nil
                awaiting_timers[timer] = nil
                if response == nil then
                    return true, false
                end
                return true, response
            end,
            true,
            function ()
                response = last_response
            end
        )
        awaiting_response_callbacks[identifier] = completion
        return true, awaitable
    end
end

local function answer_calls_to_broadcast(...)
    local args = table.pack(...)
    if #args <1 or #args > 4 then
        return false, "syscall got "..tostring(#args).." parameters, expected 1 to 4"
    else
        local message, protocol, time_to_live, frequency = args[1], args[2], args[3], args[4]
        if (type(message) ~= "table" and type(message) ~= "string" and type(message) ~= "number" and type(message) ~= "boolean" and type(message) ~= "nil") or (type(protocol) ~= "string" and type(protocol) ~= "nil") or (time_to_live ~= nil and type(time_to_live) ~= "number") or (frequency ~= nil and type(frequency) ~= "number") then
            return false, "expected table | string | number | boolean | nil, string | nil, number | nil, number | nil, got '"..type(message).."', '"..type(protocol).."', '"..type(time_to_live).."', '"..type(frequency).."'"
        end
        if time_to_live == nil then
            time_to_live = math.huge
        end
        if frequency == nil then
            frequency = LUXNET_PORT
        end
        if math.floor(time_to_live) ~= time_to_live or time_to_live < 0 then
            return false, "time to live must be a positive integer"
        end
        if math.floor(frequency) ~= frequency or frequency < 0 or frequency > 65535 then
            return false, "frequency must be an integer between 0 and 65535"
        end
        if active_frequencies[frequency] == nil then
            return false, "frequency #"..frequency.." is not enabled"
        end
        if time_to_live == 0 then
            return true
        end
        local identifier = identifier_generator()
        local message = {
            sender = COMPUTER_ID,
            receiver = luxnet.BROADCAST_ID,
            message = message,
            protocol = protocol,
            identifier = identifier,
            jumps = 0,
            time_to_live = time_to_live,
            distance = 0,
            time_sent = os.time(),
            time_received = 0
        }
        for side, modem in pairs(modems) do
            modem.transmit(frequency, frequency, message)
        end
        insert_seen_message(COMPUTER_ID, identifier)
        return true
    end
end

local function answer_calls_to_receive(...)
    local args = table.pack(...)
    if #args > 4 then
        return false, "syscall got "..tostring(#args).." parameters, expected 0 to 4"
    else
        local sender, protocol, timeout, frequency = args[1], args[2], args[3], args[4]
        if (sender ~= nil and type(sender) ~= "number" and type(sender) ~= "table") or (protocol ~= nil and type(protocol) ~= "string") or (timeout ~= nil and type(timeout) ~= "number") or (frequency ~= nil and type(frequency) ~= "number") then
            return false, "expected number | table | nil, string | nil, number | nil, number | nil, got '"..type(sender).."', '"..type(protocol).."', '"..type(timeout).."', '"..type(frequency).."'"
        end
        if frequency == nil then
            frequency = LUXNET_PORT
        end
        if timeout ~= nil and (math.floor(timeout) ~= timeout or timeout < 0) then
            return false, "timeout must be a positive integer"
        end
        if (math.floor(frequency) ~= frequency or frequency < 0 or frequency > 65535) then
            return false, "frequency must be an integer between 0 and 65535"
        end
        if active_frequencies[frequency] == nil then
            return false, "frequency #"..frequency.." is not enabled"
        end
        local sender_table = {}
        if type(sender) == "table" then
            for _, id in ipairs(sender) do
                if math.floor(id) ~= id or id < 0 or id > 65535 then
                    return false, "sender ID must be an integer between 0 and 65535"
                end
            end
            for _, id in ipairs(sender) do
                sender_table[id] = true
            end
        elseif type(sender) == "number" then
            if math.floor(sender) ~= sender or sender < 0 or sender > 65535 then
                return false, "sender ID must be an integer between 0 and 65535"
            end
            sender_table[sender] = true
        else
            sender_table = nil
        end
        local message = nil         ---@type Message?
        local timer = nil
        local identifier = #awaiting_message_callbacks + 1
        if timeout ~= nil then
            timer = os.startTimer(timeout)
            awaiting_timers[timer] = identifier
        end
        local awaitable, completion = syscall.await(
            function ()
                if message ~= nil then
                    if (sender_table == nil or sender_table[message.sender]) and (protocol == nil or message.protocol == protocol) and message.frequency == frequency then
                        return true
                    end
                elseif timer ~= nil and awaiting_timers[timer] == nil then
                    return true
                end
                return false
            end,
            function ()
                awaiting_message_callbacks[identifier] = nil
                if timer ~= nil then
                    awaiting_timers[timer] = nil
                end
                return true, message
            end,
            true,
            function ()
                message = last_message
            end
        )
        awaiting_message_callbacks[identifier] = completion
        return true, awaitable
    end
end





local function main()
    kernel.validate_filesystem_structure(LUXNET_FS_STRUCTURE)

    kernel.make_event_private("modem_message")
    kernel.make_event_private("rednet_message")

    syscall.affect_routine(luxnet.enable_frequency, answer_calls_to_enable_frequency)
    syscall.affect_routine(luxnet.disable_frequency, answer_calls_to_disable_frequency)
    syscall.affect_routine(luxnet.active_frequencies, answer_calls_to_active_frequencies)
    syscall.affect_routine(luxnet.send, answer_calls_to_send)
    syscall.affect_routine(luxnet.broadcast, answer_calls_to_broadcast)
    syscall.affect_routine(luxnet.receive, answer_calls_to_receive)

    -- Initialize modems

    local sides = peripheral.getNames()
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            modems[side] = peripheral.wrap(side)
            modems[side].open(LUXNET_PORT)
        end
    end
    
    kernel.mark_routine_ready()

    -- Handle all modem related events

    while true do
        local event = {coroutine.yield()}
        if event[1] == "modem_message" then
            local side, sender, receiver, message, distance = event[2], event[3], event[4], event[5], event[6]
            if type(message) == "table" and active_frequencies[sender] and sender == receiver then
                if is_valid_message(message) then
                    -- It is a luxnet message
                    if distance == nil then
                        distance = math.huge
                    end
                    message.distance = message.distance + distance
                    message.jumps = message.jumps + 1
                    message.time_to_live = message.time_to_live - 1
                    message.time_received = os.time()
                    message.frequency = sender

                    -- handle its identifier
                    if seen_messages[message.sender] == nil then
                        seen_messages[message.sender] = {}
                        n_messages[message.sender] = 0
                    end
                    local seen = false
                    for index, identifier in ipairs(seen_messages[message.sender]) do
                        if identifier == message.identifier then
                            seen = true
                            break
                        end
                    end
                    if not seen then
                        insert_seen_message(message.sender, message.identifier)

                        -- What should we do with it?
                        if message.receiver == COMPUTER_ID then
                            last_message = message
                            for _, callback in pairs(awaiting_message_callbacks) do
                                callback()
                            end
                            last_message = nil
                            local response = {
                                sender = message.sender,
                                receiver = message.receiver,
                                identifier = message.identifier,
                                jumps = message.jumps,
                                time_to_live = message.time_to_live,
                                distance = message.distance,
                                frequency = sender,
                                time_sent = message.time_sent,
                                time_received = message.time_received
                            }
                            for side, modem in pairs(modems) do
                                modem.transmit(sender, sender, response)
                            end
                        else
                            if message.receiver == luxnet.BROADCAST_ID then
                                last_message = message
                                for _, callback in pairs(awaiting_message_callbacks) do
                                    callback()
                                end
                                last_message = nil
                            end
                            if message.time_to_live > 0 then
                                for side, modem in pairs(modems) do
                                    modem.transmit(sender, sender, message)
                                end
                            end
                        end
                    end
                elseif is_valid_response(message) then
                    -- It is a luxnet response
                    if seen_responses[message.sender] == nil then
                        seen_responses[message.sender] = {}
                    end
                    local seen = false
                    for index, identifier in ipairs(seen_responses[message.sender]) do
                        if identifier == message.identifier then
                            seen = true
                            break
                        end
                    end
                    if not seen then
                        insert_seen_response(message.sender, message.identifier)
                        
                        -- What should we do with it?
                        if message.sender == COMPUTER_ID then
                            last_response = message
                            for _, callback in pairs(awaiting_response_callbacks) do
                                callback()
                            end
                            last_response = nil
                        else
                            for side, modem in pairs(modems) do
                                modem.transmit(sender, sender, message)
                            end
                        end
                    end
                end
            end
        elseif event[1] == "peripheral" then
            local side = event[2]
            if peripheral.getType(side) == "modem" then
                for frequency, _ in pairs(active_frequencies) do
                    modems[side] = peripheral.wrap(side)
                    modems[side].open(LUXNET_PORT)
                end
            end
        elseif event[1] == "peripheral_detach" then
            local side = event[2]
            if modems[side] ~= nil then
                table.remove(modems, side)
            end
        elseif event[1] == "timer" then
            if awaiting_timers[event[2]].."]]"..[[ ~= nil then
                last_message = nil
                local identifier = awaiting_timers[event[2]].."]]"..[[
                awaiting_timers[event[2]].."]]"..[[ = nil
                local callback = awaiting_response_callbacks[identifier]
                awaiting_response_callbacks[identifier] = nil
                if callback then
                    callback()
                end
                local callback = awaiting_message_callbacks[identifier]
                awaiting_message_callbacks[identifier] = nil
                if callback then
                    callback()
                end
            end
        elseif kernel.is_system_shutting_down() then
            break
        end
    end

    -- Disable modems

    for side, modem in pairs(modems) do
        modem.close(LUXNET_PORT)
    end

    kernel.mark_routine_offline()
    
end

return main]],
[[--]].."[["..[[
Routine for the lightUI Lux package. Handles the User Interface.
]].."]]"..[[





local LUXUI_FS_STRUCTURE = kernel.filesystem_structure{

    kernel.filesystem_node{
        name = "LuxOS",
        type = kernel.DIRECTORY,
        children = {

            kernel.filesystem_node{
                name = "luxUI",
                type = kernel.DIRECTORY,
                children = {

                    kernel.filesystem_node{
                        name = "routine.lua",
                        type = kernel.FILE
                    },

                    -- kernel.filesystem_node{
                    --     name = "lib.lua",
                    --     type = kernel.FILE
                    -- }

                }
            }

        }
    }

}

---The main function that handles the user interface
local function run_shell()

    kernel.validate_filesystem_structure(LUXUI_FS_STRUCTURE)

    local func, err = loadfile("rom/programs/shell.lua", os.create_user_environment())
    if not func then
        kernel.panic("Could not load CraftOS shell:\n"..err)
    end
    local shell_coro = coroutine.create(func)
    local event = {}

    term.clear()
    term.setCursorPos(1, 1)

    kernel.mark_routine_ready()

    while not autorun.is_startup_finished() do
        event = {coroutine.yield()}
    end
    event = {}

    while true do
        local ok, err = coroutine.resume(shell_coro, table.unpack(event))
        if not ok then
            kernel.panic("Shell coroutine got an error:\n"..err)
        end
        if coroutine.status(shell_coro) == "dead" then
            break
        end
        if kernel.is_system_shutting_down() then
            kernel.mark_routine_offline(false)
        end
        event = {coroutine.yield()}
    end

    local c = term.getTextColor()
    term.setTextColor(colors.purple)
    term.write("Good")
    term.setTextColor(colors.blue)
    print("bye")
    term.setTextColor(c)
    sleep(1.5)
    if not kernel.is_system_shutting_down() then
        os.shutdown()
    end
    kernel.mark_routine_offline()

end

return run_shell, 1]],
[[--]].."[["..[[
LuxOS shell. Runs LuxOS applications.
]].."]]"..[[





]],
[[--]].."[["..[[
This is the main script of LuxOS. It has multiple steps:
- It makes the "lux" and "kernel" APIs available.
- It enumerates all the Lux packages APIs and all the routines of the Lux packages.
- It makes all the Lux packages APIs available.
- It runs all of the Lux packages routines in parallel and watches for "Lux_panic" events.
- It shuts down the computer.

Note that no routine should ever stop! This would cause a kernel panic.
]].."]]"..[[

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

end]],
[[--]].."[["..[[
This is the Lux process library. It defines the process class, and all its interface.
]].."]]"..[[

_G.processes = {}     -- The process Lux API. Allows you to manage and interact with processes.





return {processes = processes}]],
[[--]].."[["..[[
This is the standart Lux service API. It contains all the function to perform system calls to the service system.
]].."]]"..[[

_G.services = {}        --]].."[["..[[
The service Lux API. Allows you to register services that run in background.

To declare a service, create a lua script file that returns a Service object.
]].."]]"..[[





services.log = syscall.new(
    "services.log",
    ---Logs a message to the service journal.
    ---@param ... string The message to log in the journal. Converts all parameters to string (pretty printed if possible) and concatenates them.
    function (...)
        local args = table.pack(...)
        local message = ""
        
        ---Convert an argument to a string.
        ---@param arg any
        ---@return string
        local function convert(arg)
            if type(arg) == "table" then
                local ok, err = pcall(textutils.serialise, arg)
                if ok then
                    return err
                end
            end
            return tostring(arg)
        end

        for index, arg in ipairs(args) do
            message = message..convert(arg)
        end
        local ok, err = syscall.trampoline(message)
        if not ok then
            error(err, 2)
        end
    end
)





---@enum ON_ERROR       --- Defines what action the service scheduler should take when the service main coroutine has an error.
local ON_ERROR = {
    RESTART = 1,    --- Restarts the service if the main function has an error. Calls stop() then starts the service.
    STOP = 2        --- Marks the service as stopped. Calls stop() before.
}

services.ON_ERROR = ON_ERROR

---@enum ON_RETURN      --- Defines what action the service scheduler should take when the service main coroutine returns.
local ON_RETURN = {
    RESTART = 1,    --- Restarts the service if the main function returns. Calls stop() then starts the service.
    STOP = 2        --- Marks the service as stopped. Calls stop() before.
}

services.ON_RETURN = ON_RETURN

---@enum STATUS         --- The possible states of a service.
local STATUS = {
    DISABLED = 1,   --- The service is disabled.
    STARTING = 2,   --- The start() function is running.
    RUNNING = 3,    --- The main service coroutine is running.
    STOPPING = 4,   --- The stop() function is running or the main coroutine is still shutting down.
    UNKNOWN = 5     --- The service has not been installed.
}

services.STATUS = STATUS





---@class Service A LuxOS service descriptor.
---@field name string The name of the service.
---@field start function A function that will be called when the service needs to be started. It must return immediately.
---@field main function The main service function. Will be called right after start() returns with its identifier as only argument. Remains running in a separate coroutine.
---@field stop function A function that will be called when the service needs to be stopped. The main coroutine must stop before the stop timeout has been reached. stop() must return immediately.
---@field timeout number A timeout started when stop() is called. If the main coroutine has not exited before that timeout, it will be killed.
---@field on_error ON_ERROR What to do with the service if the main function has an error.
---@field on_return ON_RETURN What to do with the service if the main function returns without a prior call to stop().
---@field identifier integer A unique identifier for the service.
---@field filepath Path The path to the file that declares the service. Executing this file should return a service the service object.
local Service = {}
services.Service = Service

Service.__index = Service
Service.__name = "Service"


--- Creates a new Service object.
---@param name string The name of the service to create.
---@param start function The start function of the service.
---@param main function The main function of the service.
---@param stop function The stop function of the service.
---@param timeout number? The timeout for stopping the service. Defaults to 10 seconds.
---@param on_error ON_ERROR? The action to take if the main function has an error. Defaults to ON_ERROR.RESTART.
---@param on_return ON_RETURN? The action to take if the main function returns unexpectedly. Defaults to ON_RETURN.STOP.
---@return Service service The new Service object.
function Service:new(name, start, main, stop, timeout, on_error, on_return)
    if type(name) ~= "string" then
        error("bad argument #1: string expected, got '"..type(name).."'", 2)
    end
    if type(start) ~= "function" then
        error("bad argument #2: function expected, got '"..type(start).."'", 2)
    end
    if type(main) ~= "function" then
        error("bad argument #3: function expected, got '"..type(main).."'", 2)
    end
    if type(stop) ~= "function" then
        error("bad argument #4: function expected, got '"..type(stop).."'", 2)
    end
    if timeout == nil then
        timeout = 10
    end
    if type(timeout) ~= "number" then
        error("bad argument #5: number expected, got '"..type(timeout).."'", 2)
    end
    if on_error == nil then
        on_error = ON_ERROR.RESTART
    end
    if type(on_error) ~= "number" then
        error("bad argument #6: number expected, got '"..type(on_error).."'", 2)
    end
    local ok = false
    for name, value in pairs(ON_ERROR) do
        if value == on_error then
            ok = true
            break
        end
    end
    if not ok then
        error("bad argument #6: expected value in enumeration 'ON_ERROR', got '"..on_error.."'", 2)
    end
    if on_return == nil then
        on_return = ON_RETURN.STOP
    end
    if type(on_return) ~= "number" then
        error("bad argument #7: number expected, got '"..type(on_return).."'", 2)
    end
    ok = false
    for name, value in pairs(ON_RETURN) do
        if value == on_return then
            ok = true
            break
        end
    end
    if not ok then
        error("bad argument #7: expected value in enumeration 'ON_RETURN', got '"..on_return.."'", 2)
    end
    local service = {}
    setmetatable(service, self)
    service.name = name
    service.start = start
    service.main = main
    service.stop = stop
    service.timeout = timeout
    service.on_error = on_error
    service.on_return = on_return
    service.identifier = -1
    return service
end





function Service:__tostring()
    if self:status() == STATUS.RUNNING then
        return type(self).." '"..self.name.."' [running]"
    elseif self:status() == STATUS.STOPPING then
        return type(self).." '"..self.name.."' [stopping]"
    elseif self:status() == STATUS.STARTING then
        return type(self).." '"..self.name.."' [starting]"
    elseif self:status() == STATUS.DISABLED then
        return type(self).." '"..self.name.."' [disabled]"
    else
        return type(self).." '"..self.name.."' [unknown]"
    end
end





services.enumerate = syscall.new(
    "services.enumerate",
    ---Returns a table of registered services indexed by their identifiers.
    ---@return {[integer]: Service} services The table of Service objects.
    function ()
        local ok, err = syscall.trampoline()
        if not ok then
            error(err, 2)
        end
        local services = {}
        for _, service_info in ipairs(err) do
            local service = Service:new(service_info.name, service_info.start, service_info.main, service_info.stop, service_info.timeout, service_info.on_error, service_info.on_return)
            service.identifier = service_info.identifier
            service.filepath = service_info.filepath
            services[service.identifier] = service
        end
        return services
    end
)





services.install = syscall.new(
    "services.install",
    ---Installs the service from the lua script file at given path.
    ---@param filepath Path | string The path to the lua script file that returns the prepared Service object.
    ---@return Service service The newly created service object.
    function (filepath)
        if type(filepath) == "string" then
            filepath = Path:new(filepath)
        end
        local ok, err = syscall.trampoline(filepath)
        if ok then
            return err
        else
            error(err, 2)
        end
    end
)





services.uninstall = syscall.new(
    "services.uninstall",
    ---Uninstalls the service with the given identifier.
    ---@param identifier integer | Service The service identifier. Can also be a Service object.
    function (identifier)
        if type(identifier) == "Service" then
            identifier = identifier.identifier
        end
        local ok, err = syscall.trampoline(identifier)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)

---Uninstalls the service associated with the Service object.
function Service:uninstall()
    services.uninstall(self)
    self.identifier = -1
end





services.status = syscall.new(
    "services.status",
    ---Returns the status of the service with the given identifier.
    ---@param identifier integer | Service The service identifier. Can also be a Service object.
    ---@return STATUS service_status The status of the service.
    function (identifier)
        if type(identifier) == "Service" then
            identifier = identifier.identifier
        end
        local ok, err = syscall.trampoline(identifier)
        if ok then
            return err
        else
            error(err, 2)
        end
    end
)

---Returns the status of the service with the associated Service object.
---@return STATUS service_status The status of the service.
function Service:status()
    return services.status(self)
end





services.enable = syscall.new(
    "services.enable",
    ---Enables the service with the given identifier.
    ---@param identifier integer | Service The service identifier. Can also be a Service object.
    function (identifier)
        if type(identifier) == "Service" then
            identifier = identifier.identifier
        end
        local ok, err = syscall.trampoline(identifier)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)

---Enables the service associated with the Service object.
function Service:enable()
    services.enable(self)
end





services.disable = syscall.new(
    "services.disable",
    ---Disables the service with the given identifier.
    ---@param identifier integer | Service The service identifier. Can also be a Service object.
    function (identifier)
        if type(identifier) == "Service" then
            identifier = identifier.identifier
        end
        local ok, err_or_awaitable = syscall.trampoline(identifier)
        if not ok then
            error(err_or_awaitable, 2)
        end
        local ok, err = err_or_awaitable()
        if ok then
            return
        else
            error(err, 2)
        end
    end
)

---Enables the service associated with the Service object.
function Service:disable()
    services.disable(self)
end





---Restarts the service with the given identifier.
---@param identifier integer | Service The service identifier. Can also be a Service object.
function services.restart(identifier)
    services.disable(identifier)
    services.enable(identifier)
end

---Restarts the service associated with the Service object.
function Service:restart()
    services.restart(self)
end





services.get_logs = syscall.new(
    "services.get_logs",
    ---Returns the logs of the service with the given identifier.
    ---@param identifier integer | Service The service identifier. Can also be a Service object.
    ---@return {[number]: string} logs The logs of the service a table of logs indexed by time.
    function (identifier)
        if type(identifier) == "Service" then
            identifier = identifier.identifier
        end
        local ok, err = syscall.trampoline(identifier)
        if ok then
            return err
        else
            error(err, 2)
        end
    end
)

---Enables the service associated with the Service object.
---@return {[number]: string} logs The logs of the service a table of logs indexed by time.
function Service:get_logs()
    return services.get_logs(self)
end





services.reload = syscall.new(
    "services.reload",
    ---Reloads the given service. This allows to take into account any file changes to the service files. Services still need to be restarted.
    ---@param identifier integer | Service The service identifier. Can also be a Service object.
    function (identifier)
        local ok, err = syscall.trampoline(identifier)
        if not ok then
            error(err, 2)
        end
    end
)





return {
    services = services
}]],
[[--]].."[["..[[
This is the scheduler of the service system. It loads, runs and terminates all the services. 
]].."]]"..[[





local SERVICES_UNITS_DIR = "LuxOS/services/units/"      ---This is where all the services metadata will be written.
local SERVICES_LOGS = "LuxOS/services/logs/"            ---This is the log directory, which holds all the services logs.
local SERVICES = {}                                     ---@type {[integer]: boolean} The set of services identifiers with a boolean indicating if the service is enabled.
local SERVICES_NAMES = {}                               ---@type {[integer]: string} The table of the services names.
local SERVICES_START = {}                               ---@type {[integer]: function} The table of the services start functions.
local SERVICES_MAIN = {}                                ---@type {[integer]: function} The table of the services main functions.
local SERVICES_STOP = {}                                ---@type {[integer]: function} The table of the services stop functions.
local SERVICES_TIMEOUT = {}                             ---@type {[integer]: number} The table of the services timeouts.
local SERVICES_ON_ERROR = {}                            ---@type {[integer]: ON_ERROR} The table of error actions.
local SERVICES_ON_RETURN = {}                           ---@type {[integer]: ON_RETURN} The table of return actions.
local SERVICES_FILEPATHS = {}                           ---@type {[integer]: Path} The table of Paths to the services script files.
local SERVICES_ROUTINES = {}                            ---@type {[integer]: thread} A table that contains a kernel coroutine that handles each running service.
local SERVICES_LOG_FILES = {}                           ---@type {[integer]: handle} The table of handles to log files for all enabled services.
local SERVICES_STOP_CALLBACKS = {}                      ---@type {[integer]: (fun():nil)[]} A routine for each service being stopped. Will be resumed when the service stops.
local SERVICE_STOP_STATUS = true                        ---@type boolean Indicates if the service that just stopped did stop gracefully.
local SERVICES_STATUS = {}                              ---@type {[integer]: STATUS} The status of each service.
local CURRENT_SERVICE = nil                             ---@type integer? The currently running service.
local DISPLAY_NAME = "service manager"                  ---@type string The name to display on logs.
local log = services.log

local SERVICE_FS_STRUCTURE = kernel.filesystem_structure{

    kernel.filesystem_node{
        name = "LuxOS",
        type = kernel.DIRECTORY,
        children = {

            kernel.filesystem_node{
                name = "services",
                type = kernel.DIRECTORY,
                children = {

                    kernel.filesystem_node{
                        name = "units",
                        type = kernel.DIRECTORY,
                        mode = kernel.DIRECTORY.ENSURE_EXISTS
                    },

                    kernel.filesystem_node{
                        name = "logs",
                        type = kernel.DIRECTORY,
                        mode = kernel.DIRECTORY.ENSURE_EXISTS
                    },

                    kernel.filesystem_node{
                        name = "routine.lua",
                        type = kernel.FILE
                    },

                    kernel.filesystem_node{
                        name = "lib.lua",
                        type = kernel.FILE
                    }

                }
            }

        }
    }

}





---Internal function that creates a table to serve as the runtime environment of service coroutines.
local function create_service_environment()
    local env = os.create_user_environment()
    env["print"] = log
    env["write"] = log
    return env
end





---Internal function ran as a coroutine that handles the execution of a service.
---@param identifier integer The service identifier.
local function run_service(identifier)
    local coro, ok, err, event, start_coro, stop_coro, timer, disable
    coroutine.yield()

    local function cycle()
        start_coro = coroutine.create(SERVICES_START[identifier])
        CURRENT_SERVICE = identifier
        DISPLAY_NAME = "service manager"
        log("Starting service.")
        SERVICES_STATUS[identifier] = services.STATUS.STARTING
        DISPLAY_NAME = SERVICES_NAMES[identifier]
        ok, err = coroutine.resume(start_coro)
        DISPLAY_NAME = "service manager"
        if not ok then                  -- Service start function had an exception
            log("Service start() function encountered an exception: "..err)
            coroutine.yield(false, err)
            return 
        end
        if coroutine.status(start_coro) ~= "dead" then  -- Service start function did not return immediately
            log("Service start() function did not return without yielding.")
            coroutine.yield(false, "service start function did not return immediately")
            return
        end

        coro = coroutine.create(SERVICES_MAIN[identifier])
        SERVICES_STATUS[identifier] = services.STATUS.RUNNING
        DISPLAY_NAME = "service manager"
        CURRENT_SERVICE = identifier
        log("Starting service main() coroutine.")

        DISPLAY_NAME = SERVICES_NAMES[identifier]
        ok, err = coroutine.resume(coro, identifier)
        DISPLAY_NAME = "service manager"
        if not ok then              -- Service main coroutine had an exception
            disable = SERVICES_ON_ERROR[identifier] == services.ON_ERROR.STOP
            log("Service had an exception when starting the main() coroutine: "..err)
        end
        if coroutine.status(coro) == "dead" then    -- Service main coroutine returned unexpectedly
            disable = SERVICES_ON_ERROR[identifier] == services.ON_RETURN.STOP
            log("Service main() coroutine returned immediately.")
            ok = false
        end

        
        event = {coroutine.yield(true)}
        CURRENT_SERVICE = identifier
        DISPLAY_NAME = SERVICES_NAMES[identifier]
        if ok then
            while true do
                if #SERVICES_STOP_CALLBACKS[identifier] > 0 then
                    disable = true
                    break
                end
                ok, err = coroutine.resume(coro, table.unpack(event))
                DISPLAY_NAME = "service manager"
                if not ok then              -- Service main coroutine had an exception
                    disable = SERVICES_ON_ERROR[identifier] == services.ON_ERROR.STOP
                    log("Service had an exception the main() coroutine: "..err)
                    break
                end
                if coroutine.status(coro) == "dead" then    -- Service main coroutine returned unexpectedly
                    disable = SERVICES_ON_ERROR[identifier] == services.ON_RETURN.STOP
                    log("Service main() coroutine returned unexpectedly.")
                    break
                end
                event = {coroutine.yield()}
                CURRENT_SERVICE = identifier
                DISPLAY_NAME = SERVICES_NAMES[identifier]
            end
        end

        CURRENT_SERVICE = identifier
        stop_coro = coroutine.create(SERVICES_STOP[identifier])
        DISPLAY_NAME = "service manager"
        log("Stopping service.")
        SERVICES_STATUS[identifier] = services.STATUS.STOPPING
        DISPLAY_NAME = SERVICES_NAMES[identifier]
        ok, err = coroutine.resume(stop_coro)
        DISPLAY_NAME = "service manager"
        if not ok then                  -- Service stop function had an exception
            log("Service stop() function had an exception: "..err)
        elseif coroutine.status(stop_coro) ~= "dead" then  -- Service stop function did not return immediately
            log("Service stop() function did not return without yielding.")
        else
            timer = os.startTimer(SERVICES_TIMEOUT[identifier])

            event = {"service", "stop"}
            while true do
                CURRENT_SERVICE = identifier
                DISPLAY_NAME = SERVICES_NAMES[identifier]
                ok, err = coroutine.resume(coro, table.unpack(event))
                DISPLAY_NAME = "service manager"
                if not ok then              -- Service main coroutine had an exception
                    log("Service had an exception the main() coroutine while stopping: "..err)
                    os.cancelTimer(timer)
                end
                if event[1] == "timer" and event[2] == timer then   -- Service main did not stop in time
                    log("Service stop timeout reached. Cleaning main() coroutine.")
                    ok = false
                    break
                end
                if coroutine.status(coro) == "dead" then            -- Service main stopped as expected
                    log("Service main() coroutine stopped successfully.")
                    ok = true
                    os.cancelTimer(timer)
                    break
                end
                event = {coroutine.yield()}
            end
        end
        
        SERVICE_STOP_STATUS = ok
        while #SERVICES_STOP_CALLBACKS[identifier] > 0 do        -- Signal all awaiting stop routines of the termination of the service
            local cb = SERVICES_STOP_CALLBACKS[identifier][#SERVICES_STOP_CALLBACKS[identifier]].."]]"..[[
            table.remove(SERVICES_STOP_CALLBACKS[identifier], #SERVICES_STOP_CALLBACKS[identifier])
            cb()
        end

        coro = nil
        if disable then
            SERVICES[identifier] = false
            CURRENT_SERVICE = identifier
            DISPLAY_NAME = "service manager"
            log("Service successfully stopped.")
            SERVICES_STATUS[identifier] = services.STATUS.DISABLED
        end
    end

    while true do
        if SERVICES[identifier] then        -- Service should be running
            kernel.panic_pcall("cycle", cycle)
        end
        coroutine.yield()
    end
end





---Internal function that enables a service.
---@param identifier integer The service identifier.
local function enable_service(identifier)
    if SERVICES[identifier] == nil then
        kernel.panic("Unknown service identifier: "..identifier)
    end
    local table_file = kernel.panic_pcall("fs.open", fs.open, SERVICES_UNITS_DIR..identifier..".table", "w")
    kernel.panic_pcall("table_file.write", table_file.write, kernel.panic_pcall("textutils.serialise", textutils.serialise, {filepath = tostring(SERVICES_FILEPATHS[identifier]), enabled = true, identifier = identifier}))
    kernel.panic_pcall("table_file.close", table_file.close)
    local service_log_file = kernel.panic_pcall("fs.open", fs.open, SERVICES_LOGS..identifier..".log", "a")
    SERVICES_LOG_FILES[identifier] = service_log_file
end





---Internal function that disables a service.
---@param identifier integer The service identifier.
local function disable_service(identifier)
    if SERVICES[identifier] == nil then
        kernel.panic("Unknown service identifier: "..identifier)
    end
    local table_file = kernel.panic_pcall("fs.open", fs.open, SERVICES_UNITS_DIR..identifier..".table", "w")
    kernel.panic_pcall("table_file.write", table_file.write, kernel.panic_pcall("textutils.serialise", textutils.serialise, {filepath = tostring(SERVICES_FILEPATHS[identifier]), enabled = false, identifier = identifier}))
    kernel.panic_pcall("table_file.close", table_file.close)
    if SERVICES_LOG_FILES[identifier] ~= nil then
        SERVICES_LOG_FILES[identifier].close()
    end
    SERVICES_LOG_FILES[identifier] = nil
end





---Internal function that loads a service from its script file.
---@param filepath string The path to the file to load the service from.
---@param identifier integer? The identifier of the service if it already has one.
---@return boolean ok Indicates if the service was loaded successfully.
---@return integer | string indentifier_or_err The new service identifier or the error message.
local function load_service(filepath, identifier)
    local service_loading_function, err = loadfile(filepath, create_service_environment())
    if service_loading_function == nil then
        return false, err or "unknown error"
    end
    local service_loading_coro = coroutine.create(service_loading_function)
    local res = {coroutine.resume(service_loading_coro)}
    if not res[1] then
        return false, res[2]
    end
    if coroutine.status(service_loading_coro) ~= "dead" then
        return false, "service script file did not return without yielding"
    end
    table.remove(res, 1)
    if #res ~= 1 then
        return false, "service script file did not return a single value"
    end
    local service = res[1]
    if type(service) ~= "Service" then
        return false, "service script did not return a service object but a '"..type(service).."'"
    end
    local save = false
    if identifier == nil then       -- New service: save it too.
        local i = 1
        while kernel.panic_pcall("fs.exists", fs.exists, SERVICES_UNITS_DIR..i..".table") do
            i = i + 1
        end
        identifier = i
        save = true
    else                            -- Existing service: load it
        if not kernel.panic_pcall("fs.exists", fs.exists, SERVICES_UNITS_DIR..identifier..".table") then
            kernel.panic("trying to load unknown service: "..identifier.." not found in units dir.")
        end
        if SERVICES[identifier] ~= nil then
            kernel.panic("Trying to load an existing service: "..identifier)
        end    
    end
    SERVICES[identifier] = false
    SERVICES_NAMES[identifier] = service.name
    SERVICES_START[identifier] = service.start
    SERVICES_MAIN[identifier] = service.main
    SERVICES_STOP[identifier] = service.stop
    SERVICES_TIMEOUT[identifier] = service.timeout
    SERVICES_ON_ERROR[identifier] = service.on_error
    SERVICES_ON_RETURN[identifier] = service.on_return
    SERVICES_FILEPATHS[identifier] = Path:new(filepath)
    SERVICES_ROUTINES[identifier] = coroutine.create(run_service)
    SERVICES_STOP_CALLBACKS[identifier] = {}
    SERVICES_STATUS[identifier] = services.STATUS.DISABLED
    kernel.promote_coroutine(SERVICES_ROUTINES[identifier])
    coroutine.resume(SERVICES_ROUTINES[identifier], identifier)
    if save then
        disable_service(identifier)
    end
    return true, identifier
end





---Internal function that unloads (uninstalls) a loaded service.
---@param identifier integer The service identifier.
local function unload_service(identifier)
    if SERVICES[identifier] == nil then
        kernel.panic("Unknown service identifier: "..identifier)
    end
    if SERVICES[identifier] then
        kernel.panic("Trying to unload a running service: "..identifier)
    end
    kernel.panic_pcall("fs.delete", fs.delete, SERVICES_UNITS_DIR..identifier..".table")
    kernel.panic_pcall("fs.delete", fs.delete, SERVICES_LOGS..identifier..".log")
    SERVICES_NAMES[identifier] = nil
    SERVICES_START[identifier] = nil
    SERVICES_MAIN[identifier] = nil
    SERVICES_STOP[identifier] = nil
    SERVICES_TIMEOUT[identifier] = nil
    SERVICES_ON_ERROR[identifier] = nil
    SERVICES_ON_RETURN[identifier] = nil
    SERVICES_FILEPATHS[identifier] = nil
    SERVICES_ROUTINES[identifier] = nil
    SERVICES_STOP_CALLBACKS[identifier] = nil
    SERVICES_STATUS[identifier] = nil
end





---Internal function that starts the service with given identifier
---@param identifier integer The service identifier.
---@return boolean ok Indicates if the service was successfully started.
---@return string? error The error message if an error occured.
local function start_service(identifier)
    if SERVICES[identifier] == nil then
        kernel.panic("Unknown service identifier: "..identifier)
    end
    SERVICES[identifier] = true
    return coroutine.resume(SERVICES_ROUTINES[identifier])
end





---Internal function that stops the service with the given identifier.
---@param identifier integer The service identifier.
---@param callback fun():nil A function to call when the service has stopped.
local function stop_service(identifier, callback)
    table.insert(SERVICES_STOP_CALLBACKS[identifier], callback)
end





---Answers the system calls to services.log.
local function answer_calls_to_log(...)
    local args = table.pack(...)
    if #args ~= 1 then
        return false, "expected exactly one argument, got "..#args
    else
        local message = args[1]
        if type(message) ~= "string" then
            return false, "bad argument #1: string expected, got "..type(message)
        end
        if CURRENT_SERVICE == nil then
            return false, "cannot use services.log outside of a service."
        end
        if SERVICES_LOG_FILES[CURRENT_SERVICE] == nil then
            return false, "service #"..CURRENT_SERVICE.." is unknown or not running"
        end
        SERVICES_LOG_FILES[CURRENT_SERVICE].write(os.time()..", "..os.day()..", "..textutils.serialise("["..DISPLAY_NAME.."] "..message).."\n")
        SERVICES_LOG_FILES[CURRENT_SERVICE].flush()
        return true
    end
end

---Answers the system calls to services.enumerate.
local function answer_calls_to_enumerate(...)
    local args = table.pack(...)
    if #args > 0 then
        return false, "expected no arguments, got "..#args
    else
        local tab = {}
        for identifier, running in pairs(SERVICES) do
            tab[identifier] = {
                name = SERVICES_NAMES[identifier],
                start = SERVICES_START[identifier],
                main = SERVICES_MAIN[identifier],
                stop = SERVICES_STOP[identifier],
                timeout = SERVICES_TIMEOUT[identifier],
                on_error = SERVICES_ON_ERROR[identifier],
                on_return = SERVICES_ON_RETURN[identifier],
                identifier = identifier,
                filepath = SERVICES_FILEPATHS[identifier]
            }
        end
        return true, tab
    end
end

---Answers the system calls to services.install.
local function answer_calls_to_install(...)
    local args = table.pack(...)
    if #args ~= 1 then
        return false, "expected exactly one argument, got "..#args
    else
        local filepath = args[1]        ---@type string | Path
        if type(filepath) == "Path" then
            filepath = tostring(filepath)
        end
        if type(filepath) ~= "string" then
            return false, "bad argument #1: string or Path expected, got '"..type(filepath).."'"
        end
        if not kernel.panic_pcall("fs.exists", fs.exists, filepath) then
            return false, "file does not exist: '"..filepath.."'"
        end
        if kernel.panic_pcall("fs.isDir", fs.isDir, filepath) then
            return false, "file is a directory: '"..filepath.."'"
        end
        local ok, err = load_service(filepath)
        if not ok then
            return false, err
        end
        return true, err
    end
end

---Answers the system calls to services.uninstall.
local function answer_calls_to_uninstall(...)
    local args = table.pack(...)
    if #args ~= 1 then
        return false, "expected exactly one argument, got "..#args
    else
        local identifier = args[1]      ---@type integer | Service
        if type(identifier) == "Service" then
            identifier = identifier.identifier
        end
        if type(identifier) ~= "number" then
            return false, "bad argument #1: integer or Service expected, got '"..type(identifier).."'"
        end
        if SERVICES[identifier] == nil then
            return false, "unknown service identifier: "..identifier
        end
        if SERVICES[identifier] then
            return false, "service #"..identifier.." is running"
        end
        unload_service(identifier)
        return true
    end
end

---Answers the system calls to services.status.
local function answer_calls_to_status(...)
    local args = table.pack(...)
    if #args ~= 1 then
        return false, "expected exactly one argument, got "..#args
    else
        local identifier = args[1]      ---@type integer | Service
        if type(identifier) == "Service" then
            identifier = identifier.identifier
        end
        if type(identifier) ~= "number" then
            return false, "bad argument #1: integer or Service expected, got '"..type(identifier).."'"
        end
        if SERVICES[identifier] == nil then
            return false, "unknown service identifier: "..identifier
        end
        return true, SERVICES_STATUS[identifier]
    end
end

---Answers the system calls to services.enable.
local function answer_calls_to_enable(...)
    local args = table.pack(...)
    if #args ~= 1 then
        return false, "expected exactly one argument, got "..#args
    else
        local identifier = args[1]      ---@type integer | Service
        if type(identifier) == "Service" then
            identifier = identifier.identifier
        end
        if type(identifier) ~= "number" then
            return false, "bad argument #1: integer or Service expected, got '"..type(identifier).."'"
        end
        if SERVICES[identifier] == nil then
            return false, "unknown service identifier: "..identifier
        end
        if SERVICES[identifier] then
            return false, "service #"..identifier.." is already enabled"
        end
        enable_service(identifier)
        local ok, err = start_service(identifier)
        if not ok then
            return false, err
        end
        return true
    end
end

---Answers the system calls to services.disable.
local function answer_calls_to_disable(...)
    local args = table.pack(...)
    if #args ~= 1 then
        return false, "expected exactly one argument, got "..#args
    else
        local identifier = args[1]      ---@type integer | Service
        if type(identifier) == "Service" then
            identifier = identifier.identifier
        end
        if type(identifier) ~= "number" then
            return false, "bad argument #1: integer or Service expected, got '"..type(identifier).."'"
        end
        if SERVICES[identifier] == nil then
            return false, "unknown service identifier: "..identifier
        end
        if not SERVICES[identifier] then
            return false, "service #"..identifier.." is already disabled"
        end
        local ok = nil
        local awaitable, complete = syscall.await(
            function ()
                return ok ~= nil
            end,
            function ()
                if ok then
                    disable_service(identifier)
                else
                    return false, "service encountered a problem while stopping"
                end
                return true, nil
            end,
            true,
            function ()
                ok = SERVICE_STOP_STATUS
            end
        )
        stop_service(identifier, complete)
        return true, awaitable
    end
end

---Answers the system calls to services.read_logs.
local function answer_calls_to_read_logs(...)
    local args = table.pack(...)
end

---Answers the system calls to services.reload.
local function answer_calls_to_reload(...)
    local args = table.pack(...)
    if #args ~= 1 then
        return false, "expected exactly one argument, got "..#args
    else
        local identifier = args[1]      ---@type integer | Service
        if type(identifier) == "Service" then
            identifier = identifier.identifier
        end
        if type(identifier) ~= "number" then
            return false, "bad argument #1: integer or Service expected, got '"..type(identifier).."'"
        end
        if SERVICES[identifier] == nil then
            return false, "unknown service identifier: "..identifier
        end
        if SERVICES[identifier] then
            return false, "service #"..identifier.." is running"
        end
        local filepath = SERVICES_FILEPATHS[identifier]
        unload_service(identifier)
        local ok, err = load_service(filepath, identifier)
        if not ok then
            return false, err
        end
        return true
    end
end





local function main()

    kernel.validate_filesystem_structure(SERVICE_FS_STRUCTURE)

    syscall.affect_routine(services.log, answer_calls_to_log)
    syscall.affect_routine(services.enumerate, answer_calls_to_enumerate)
    syscall.affect_routine(services.install, answer_calls_to_install)
    syscall.affect_routine(services.uninstall, answer_calls_to_uninstall)
    syscall.affect_routine(services.status, answer_calls_to_status)
    syscall.affect_routine(services.enable, answer_calls_to_enable)
    syscall.affect_routine(services.disable, answer_calls_to_disable)
    syscall.affect_routine(services.get_logs, answer_calls_to_read_logs)
    syscall.affect_routine(services.reload, answer_calls_to_reload)

    kernel.mark_routine_ready()

    -- Startup : load enabled services

    for _, name in ipairs(kernel.panic_pcall("fs.list", fs.list, SERVICES_UNITS_DIR)) do
        local unit_file = kernel.panic_pcall("fs.open", fs.open, SERVICES_UNITS_DIR..name, "r")
        local ok, data = pcall(textutils.unserialise, unit_file.readAll())
        if not ok then
            kernel.panic("corrupted service unit file: "..name)
        end
        unit_file.close()
        if type(data.filepath) ~= "string" or type(data.enabled) ~= "boolean" or type(data.identifier) ~= "number" then
            kernel.panic("corrupted service unit file: "..name)
        end
        load_service(data.filepath, data.identifier)
        if data.enabled then
            enable_service(data.identifier)
            start_service(data.identifier)
        end
    end

    -- Normal runtime : forward events to services

    while not kernel.is_system_shutting_down() do
        local event = {coroutine.yield()}
        for identifier, service_routine in pairs(SERVICES_ROUTINES) do
            if service_routine ~= nil then
                coroutine.resume(service_routine, table.unpack(event))
            end
        end
    end

    -- Shutdown time : shutdown all services

    for identifier, enabled in pairs(SERVICES) do
        if enabled then
            stop_service(identifier, function () end)
        end
    end

    local remaining = true
    local event = {"tick"}
    while remaining do
        remaining = false
        for identifier, service_routine in pairs(SERVICES_ROUTINES) do
            if service_routine ~= nil and SERVICES_STATUS[identifier] ~= services.STATUS.DISABLED then
                coroutine.resume(service_routine, table.unpack(event))
            end
            if service_routine ~= nil and SERVICES_STATUS[identifier] ~= services.STATUS.DISABLED then
                remaining = true
            end
        end
        event = {coroutine.yield()}
    end

    kernel.mark_routine_offline()

end

return main, 1]],
[[--]].."[["..[[
The template for a LuxOS app.

A LuxOS application file is a lua script file that returns an Application object. It must not run the application when executed.
When LuxOS starts the application, it will execute this file, retrieve the Application object and run its main functions with the arguments passed through the command line.
Here is an example of an echo application:

local function main(...)
    print(...)
end

local app = Application:new{"echo", main}

return app
]].."]]"..[[





---@class Application The interface for an application.
---@field name string The application name.
---@field main function The application entry point. This function receives as argument the paramters passed to the command line (one string argument each).
---@field autocomplete function An autocompletion function for when typing a command with the application as first keyword. Arguments received are the different words in the command line being written. Returns a list of possible strings to complete the current word.
---@field services Service[] A list of services declared by the application.
local Application = {}
_G.Application = Application

Application.__index =  Application
Application.__name = "Application"





---A dummy autocomplete function that does not return anything.
local function dummy_autocomplete(...)
    return {}
end





---Creates a new Application object
---@param name string The application name.
---@param main function The application main function.
---@return Application app The new application object.
function Application:new(name, main)
    local app = {}
    setmetatable(app, self)
    if type(name) ~= "string" then
        error("bad argument #1: string expected, got '"..type(name).."'", 2)
    end
    if type(main) ~= "function" then
        error("bag argument #2: function expected, got '"..type(main).."'", 2)
    end
    app.name = name
    app.main = main
    app.services = {}
    app.autocomplete = dummy_autocomplete
    return app
end





---Starts the application.
---@param ... string The arguments for the application.
function Application:__call(...)
    return self.main(...)
end]],
[[--]].."[["..[[
This is LuxOS Object-Oriented standart library.
]].."]]"..[[





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
}]],
[[--]].."[["..[[
This is the Path library. It declares the Path object.
Use it to work with paths and make system calls.
]].."]]"..[[





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
    
end]],
[[--]].."[["..[[
This library is used by the kernel to define and hook system calls.
]].."]]"..[[





_G.syscall = {}     -- The Lux syscall API. Mostly restricted to kernel.
libraries.syscall = syscall
local syscall_table = {}    ---@type {[string] : SysCall} The system call table.
local syscall_routines = {} ---@type {[string] : thread} The table of kernel routines that handle the system calls.

local check_kernel_space_before_running = kernel.check_kernel_space_before_running


---@class SysCall The class for system call objects. These are special function accessible for the user that jump back into kernel space.
---@field name string The name of the system call.
---@field __user_func function The function that is called when calling the SysCall object.
local SysCall = {}

SysCall.__index = SysCall
SysCall.__name = "syscall"

---Creates a new syscall object.
---@generic P
---@generic R
---@param syscallinfo [string, fun(... : P) : R] The required parameters for creating a syscall: a name and the user function.
---@return SysCall syscall The new system call object.
function SysCall:new(syscallinfo)
    check_kernel_space_before_running()
    local syscall = {name = syscallinfo[1], __user_func = syscallinfo[2]}
    if type(syscall.name) ~= "string" then
        kernel.panic("SysCall's 'name' field should be a string, not '"..type(syscall.name).."'", 1)
    end
    if syscall_table[syscall.name] ~= nil then
        kernel.panic("Syscall '"..syscall.name.."' already exists.", 1)
    end
    if type(syscall.__user_func) ~= "function" then
        kernel.panic("SysCall's 'user_func' attribute should be a function, not '"..type(syscall.__user_func).."'", 1)
    end
    setmetatable(syscall, self)
    syscall_table[syscall.name] = syscall
    return syscall
end

local ongoing_calls = {}    ---@type string[] The ongoing system call stack.

---Calls the user function
---@param ... any
---@return any
function SysCall:__call(...)
    local args = table.pack(...)
    table.insert(ongoing_calls, self.name)
    local res = {pcall(self.__user_func, table.unpack(args, 1, args.n))}
    local ok = table.remove(res, 1)
    local exiting_call = table.remove(ongoing_calls)
    if exiting_call ~= self.name then
        kernel.panic("Corrupted system call stack: exited a call of '"..exiting_call.."' where '"..self.name.."' was expected.", 1)
    end
    if not ok then
        error(res[1], 0)
    else
        return table.unpack(res)
    end
end

---Implements tostring(self)
---@return string
function SysCall:__tostring()
    return type(self).." "..self.name
end





local report_syscall_crash_coro = coroutine.create(
---Single-use kernel coroutine that throws panic when a syscall routine crashes.
---@param syscall SysCall
---@param err string?
---@param ... any
function (syscall, err, ...)
    local ok, res = pcall(textutils.serialise, {...})
    if not ok then
        res = tostring({...})
    end
    if err == nil then
        kernel.panic("Syscall '"..syscall.name.."' routine blocked when it received arguments : '"..res.."'", 2)
    else
        kernel.panic("Syscall '"..syscall.name.."' routine got an error when it received arguments : '"..res.."' :\n"..err, 2)
    end
end)
kernel.promote_coroutine(report_syscall_crash_coro)

---Performs the actual system call: jumps into kernel space passing on the arguments.
---@param ... any The arguments that the system will work with.
---@return boolean success Did the system call succeed
---@return any ... The return values of the system call or an error message.
function syscall.trampoline(...)
    if #ongoing_calls == 0 then
        if kernel.kernel_space() then
            kernel.panic("Corrupted system call stack: syscall.trampoline() called with no running system calls.", 1)
        else
            error("This function can only be called from inside a system call.", 2)
        end
    end
    local call_name = ongoing_calls[#ongoing_calls]
    -- if kernel.kernel_space() then
    --     res = {pcall(syscall_handlers[call_name], ...)}
    --     local ok = table.remove(res, 1)
    --     if not ok then
    --         coroutine.resume(report_syscall_crash_coro, syscall_table[call_name], res[1], ...)
    --     end
    --     if coroutine.status(syscall_routines[call_name]) == "dead" then
    --         coroutine.resume(report_syscall_crash_coro, syscall_table[call_name], nil, ...)
    --     end
    -- else
    --     res = {coroutine.resume(syscall_routines[call_name], ...)}
    --     local ok = table.remove(res, 1)
    --     if not ok then
    --         coroutine.resume(report_syscall_crash_coro, syscall_table[call_name], res[1], ...)
    --     end
    --     if coroutine.status(syscall_routines[call_name]) == "dead" then
    --         coroutine.resume(report_syscall_crash_coro, syscall_table[call_name], nil, ...)
    --     end
    -- end

    local ok, syscall_coro = coroutine.resume(syscall_routines[call_name])
    local args = table.pack(...)
    if not ok then
        kernel.panic("Syscall '"..call_name.."' generating routine crashed: "..syscall_coro, 2)
    end
    local res = {coroutine.resume(syscall_coro, table.unpack(args, 1, args.n))}
    ok = table.remove(res, 1)
    if not ok then
        coroutine.resume(report_syscall_crash_coro, syscall_table[call_name], res[1], table.unpack(args, 1, args.n))
    end
    if coroutine.status(syscall_coro) ~= "dead" then
        coroutine.resume(report_syscall_crash_coro, syscall_table[call_name], nil, table.unpack(args, 1, args.n))
    end
    return table.unpack(res)
end





---Creates an awaitable condition for syscalls to use when a syscall should block.
---@generic R : any The return type of the awaitable
---@param condition fun() : boolean The condition checking function. Returns true if the condition is met, false otherwise.
---@param result fun() : boolean, R | string The result function. Should return true and any value on success and false plus an error message on error.
---@param terminable boolean? If true, the awaitable breaks if a terminate event is received. Defaults to false.
---@param pre_complete (fun():nil)? An optional function that will be called when the condition is complete.
---@return fun() : boolean, R | string awaitable An awaitable function that will block until the condition is met and will return any value returned. Should be return by the trampoline.
---@return fun() : nil completion A non-blocking function that should be called by the kernel when the condition should be checked.
function syscall.await(condition, result, terminable, pre_complete)
    check_kernel_space_before_running()
    if terminable == nil then
        terminable = false
    end

    local await_coro = coroutine.create(function ()
        while not condition() do
            local event = coroutine.yield()
            if terminable and event == "terminate" then
                return false, "terminated"
            end
        end
        return result()
    end)

    kernel.promote_coroutine(await_coro)

    local function awaitable()
        local event = {}
        while true do
            local res = {coroutine.resume(await_coro, table.unpack(event))}
            local ok = table.remove(res, 1)
            if not ok then
                kernel.panic("Awaitable syscall coroutine had an exception: "..res[1])
            end
            if coroutine.status(await_coro) == "dead" then
                return table.unpack(res)
            end
            event = table.pack(coroutine.yield())
        end
    end

    local function completion()
        lux.make_tick()
        if pre_complete ~= nil then
            pre_complete()
        end
    end

    return awaitable, completion
end





---Creates a new syscall object.
---@generic F : function
---@param name string The name of the system call.
---@param func F The user function.
---@return F syscall system call wrapped function.
function syscall.new(name, func)
    check_kernel_space_before_running()
    return SysCall:new{name, func}
end





---Affects the given function to the handling of the specified system call.
---It will receive the parameters of the system call to answer and should return back a boolean indicating if the call succeeded and any return values.
---@param syscall SysCall The system call to affect this routine to.
---@param handler_func function The function that will handle all incomming system calls.
function syscall.affect_routine(syscall, handler_func)
    check_kernel_space_before_running()
    if syscall_routines[syscall.name] ~= nil then
        kernel.panic("Syscall '"..syscall.name.."' routine has already been affected.", 1)
    end

    local function do_system_call(func, func_name)
        local res = {pcall(func, coroutine.yield())}
        local ok = table.remove(res, 1)
        if not ok then
            kernel.panic("Syscall '"..func_name.."' crashed: "..res[1], 2)
        end
        return table.unpack(res)
    end

    local generator_coro = coroutine.create(
        function (func)
            local func_name = "syscall."..syscall.name..".handler"
            coroutine.yield()
            while true do
                local coro = coroutine.create(do_system_call)
                coroutine.resume(coro, func, func_name)
                kernel.promote_coroutine(coro)
                coroutine.yield(coro)
            end
        end
    )

    kernel.promote_coroutine(generator_coro)
    syscall_routines[syscall.name] = generator_coro
    coroutine.resume(generator_coro, handler_func)
end





---Validates the system call table when the system is about to start. It ensures that each system call has a handler and routine.
function syscall.validate_syscall_table()
    check_kernel_space_before_running()
    for name, syscall in pairs(syscall_table) do
        if syscall_routines[name] == nil then
            kernel.panic("SysCall '"..syscall.name.."' has not routine affected to it!")
        end
    end
end





---Returns the table of all system calls indexed by names.
---@return {[string] : SysCall} table The system call table.
function syscall.table()
    local table = {}
    for name, syscall in pairs(syscall_table) do
        table[name] = syscall
    end
    return table
end]]
}   -- This too

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