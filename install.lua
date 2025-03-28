local DIRECTORY = 1
local FILE = 2
local ENTRY_POINT = "LuxOS/main.lua"

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
				}
			}
		},
		{
			name = "main.lua",
			type = FILE,
			code = 10
		},
		{
			name = "processes",
			type = DIRECTORY,
			children = {
				{
					name = "lib.lua",
					type = FILE,
					code = 11
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
					code = 12
				},
				{
					name = "routine.lua",
					type = FILE,
					code = 13
				}
			}
		},
		{
			name = "syscall.lua",
			type = FILE,
			code = 14
		}
	}
}

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

return main]],
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
    kernel.check_kernel_space_before_running()
    local current_coroutine = current_coroutine()
    kernel_coroutines[coro] = current_coroutine
end





---Lux Kernel panic. Stops everything and prints the error.
---@param message string The message to print on the purple screen.
---@param level integer? The stacktrace level to trace the error back to. Default (0) is the the line where panic was called, 1 is where the function that called panic was called, etc.
function kernel.panic(message, level)
    kernel.check_kernel_space_before_running()
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
    kernel.check_kernel_space_before_running()
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
    kernel.check_kernel_space_before_running()
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





local routine_coroutines = {}   ---@type {[string] : thread}
local current_routine = nil     ---@type string?
local routines_ready = {}       ---@type {[string] : boolean}
local routines_offline = {}     ---@type {[string] : boolean}
local private_event = {}        ---@type {[string] : string}

---Register a new system routine. Only called by the main scheduler.
---@param name string The name of the coroutine.
---@param coro thread The coroutine object itself.
function kernel.register_routine(name, coro)
    kernel.check_kernel_space_before_running()
    kernel.promote_coroutine(coro)
    for iname, icoro in pairs(routine_coroutines) do
        if name == iname then
            kernel.panic("Routine '"..name.."' has already been registered.")
        end
    end
    routine_coroutines[name] = coro
    routines_ready[name] = false
    routines_offline[name] = false
end

---Sets the name of the currently running routine.
---@param name string? The name of the current routine.
function kernel.set_current_routine(name)
    kernel.check_kernel_space_before_running()
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
---@return { [string]: thread } routines The existing routine, indexed by names.
function kernel.routines()
    kernel.check_kernel_space_before_running()
    return routine_coroutines
end

---Registers an event as private to the currently running routine.
---@param event_name string The name of the event to make private.
function kernel.make_event_private(event_name)
    kernel.check_kernel_space_before_running()
    if private_event[event_name] ~= nil then
        kernel.panic("Event '"..event_name.."' is already private to routine '"..private_event[event_name].."'.")
    end
    private_event[event_name] = kernel.current_routine()
end

---Returns a table of the routines to run for a given event.
---@param event_name string The name of the event to get the routines for.
---@return {[string] : thread} routines The routines to run for the event.
function kernel.get_routines_for_event(event_name)
    kernel.check_kernel_space_before_running()
    if private_event[event_name] ~= nil then
        return {[private_event[event_name]].."]]"..[[ = routine_coroutines[private_event[event_name]].."]]"..[[}
    else
        return kernel.routines()
    end
end

---Marks the currently running routine as ready to start LuxOS.
---@param halt boolean? If true (default), waits until all the other routines are ready to start.
function kernel.mark_routine_ready(halt)
    kernel.check_kernel_space_before_running()
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
---@return {[string] : thread} not_ready The routines' coroutines to run to finish startup.
function kernel.starting_routines(event_name)
    kernel.check_kernel_space_before_running()
    if private_event[event_name] ~= nil and not routines_ready[private_event[event_name]].."]]"..[[ then
        return {[private_event[event_name]].."]]"..[[ = routine_coroutines[private_event[event_name]].."]]"..[[}
    end
    local not_ready = {}
    for name, ready in pairs(routines_ready) do
        if not ready then
            not_ready[name] = routine_coroutines[name]
        end
    end
    return not_ready
end

---Marks the currently running routine as offline and ready for shutdown.
---@param halt boolean? If true (default), this function will halt forever, awaiting shutdown.
function kernel.mark_routine_offline(halt)
    kernel.check_kernel_space_before_running()
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
---@return {[string] : thread} not_ready The routines' coroutines to run to finish shutdown.
function kernel.disconnecting_routines(event_name)
    kernel.check_kernel_space_before_running()
    if private_event[event_name] ~= nil and not routines_offline[private_event[event_name]].."]]"..[[ then
        return {[private_event[event_name]].."]]"..[[ = routine_coroutines[private_event[event_name]].."]]"..[[}
    end
    local not_offline = {}
    for name, offline in pairs(routines_offline) do
        if not offline then
            not_offline[name] = routine_coroutines[name]
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
    kernel.check_kernel_space_before_running()
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
    kernel.check_kernel_space_before_running()
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
    kernel.check_kernel_space_before_running()
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
    kernel.check_kernel_space_before_running()
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
    kernel.check_kernel_space_before_running()

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
    if CURRENT_TICK == NEXT_TICK then
        NEXT_TICK = NEXT_TICK + 1
        os.queueEvent("tick")
    end
end

lux.INSTALLER_CODE = "BKahgBKz"





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
---@field distance number The distance that the message has traveled.
---@field time_sent number The time when the message was sent.
---@field time_received number The time when the message was received.
local Message = {}
luxnet.Message = Message

Message.__index = Message
Message.__name = "Message"


---Creates a new message object. Can only be called from kernel space.
---@param message {["sender"]: integer, ["receiver"]: integer, ["message"]: table | string | number | boolean | nil, ["protocol"]: string | nil, ["identifier"]: integer, ["jumps"]: integer, ["distance"]: number, ["time_sent"]: number, ["time_received"]: number} The required parameters for creating a message.
---@return Message message The new message object.
function Message:new(message)
    kernel.check_kernel_space_before_running()
    setmetatable(message, self)
    return message
end



---@class Response The class for response objects.
---@field sender integer The ID of the sender of the corresponding message.
---@field receiver integer The ID of the receiver of the corresponding message.
---@field identifier integer The identifier of the corresponding message.
---@field jumps integer The amount of jumps that the corresponding message has done to reach the receiver.
---@field distance number The distance that the corresponding message has traveled to reach the receiver.
---@field time_sent number The time when the corresponding message was sent.
---@field time_received number The time when the corresponding message was received.
local Response = {}
luxnet.Response = Response

Response.__index = Response
Response.__name = "Response"


---Creates a new response object. Can only be called from kernel space.
---@param response {["sender"]: integer, ["receiver"]: integer, ["identifier"]: integer, ["jumps"]: integer, ["distance"]: number, ["time_sent"]: number, ["time_received"]: number} The required parameters for creating a response.
---@return Response response The new response object.
function Response:new(response)
    kernel.check_kernel_space_before_running()
    setmetatable(response, self)
    return response
end





luxnet.send = syscall.new(
    "luxnet.send",
    ---Sends a message to another machine.
    ---@param receiver integer The ID of the receiver.
    ---@param message table | string | number | boolean | nil The message to send.
    ---@param protocol string | nil The protocol to use to send the message.
    ---@return Response | false response The response from the receiver, if any.
    function (receiver, message, protocol)
        local ok, err_or_response = syscall.trampoline(receiver, message, protocol)
        if ok then
            return err_or_response
        else
            error(err_or_response, 2)
        end
    end
)





luxnet.broadcast = syscall.new(
    "luxnet.broadcast",
    ---Sends a message to all machines.
    ---@param message table | string | number | boolean | nil The message to send.
    ---@param protocol string | nil The protocol to use to send the message.
    function (message, protocol)
        local ok, err = syscall.trampoline(message, protocol)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)





luxnet.set_response_timeout = syscall.new(
    "luxnet.set_response_timeout",
    ---Sets the time to wait for a response before giving up.
    ---@param timeout number The time to wait for a response before giving up.
    function (timeout)
        local ok, err = syscall.trampoline(timeout)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)





--- Receives a message from another machine.
---@param protocol string | nil An optional protocal to filter messages by.
---@param timeout number | nil The time to wait for a message before giving up. Defaults to no timeout.
---@return Message | nil message The message received, or nil if the timeout was reached.
function luxnet.receive(protocol, timeout)
    if protocol ~= nil and type(protocol) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(protocol) .. ")", 2)
    end
    if timeout ~= nil and type(timeout) ~= "number" then
        error("bad argument #2 (expected number, got " .. type(timeout) .. ")", 2)
    end
    if timeout ~= nil and timeout < 0 then
        error("bad argument #2 (expected number >= 0, got " .. timeout .. ")", 2)
    end
    local timer
    if timeout ~= nil then
        timer = os.startTimer(timeout)
    end
    while true do
        local event = {coroutine.yield()}
        if event[1] == "luxnet_message" or event[1] == "luxnet_broadcast" then
            local message = event[2]
            if protocol == nil or message.protocol == protocol then
                return message
            end
        elseif event[1] == "terminate" then
            error("terminated", 2)
        elseif event[1] == "timer" and event[2] == timer then
            return nil
        end
    end
end





--- Receives a message from a specific machine.
---@param sender integer The ID of the sender to receive a message from.
---@param protocol string | nil An optional protocal to filter messages by.
---@param timeout number | nil The time to wait for a message before giving up. Defaults to no timeout.
---@return Message | nil message The message received, or nil if the timeout was reached.
function luxnet.receive_from(sender, protocol, timeout)
    if type(sender) ~= "number" then
        error("bad argument #1 (expected number, got " .. type(sender) .. ")", 2)
    end
    if protocol ~= nil and type(protocol) ~= "string" then
        error("bad argument #2 (expected string, got " .. type(protocol) .. ")", 2)
    end
    if timeout ~= nil and type(timeout) ~= "number" then
        error("bad argument #3 (expected number, got " .. type(timeout) .. ")", 2)
    end
    if sender < 0 or sender > 65535 then
        error("bad argument #1 (expected number in range 0-65535, got " .. sender .. ")", 2)
    end
    if timeout ~= nil and timeout < 0 then
        error("bad argument #3 (expected number >= 0, got " .. timeout .. ")", 2)
    end
    local timer
    if timeout ~= nil then
        timer = os.startTimer(timeout)
    end
    while true do
        local event = {coroutine.yield()}
        if event[1] == "luxnet_message" or event[1] == "luxnet_broadcast" then
            local message = event[2]
            if message.sender == sender and (protocol == nil or message.protocol == protocol) then
                return message
            end
        elseif event[1] == "terminate" then
            error("terminated", 2)
        elseif event[1] == "timer" and event[2] == timer then
            return nil
        end
    end
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
local RESPONSE_TIMEOUT = 5

local modems = {}      ---@type {[string] : table} The table of all modems connected to the computer. The key is the side of the modem and the value is the modem object.
local COMPUTER_ID = os.getComputerID()
local seen_messages = {[COMPUTER_ID] = {}}        ---@type {[number] : number[]} The table of used identifiers per host for messages.
local seen_responses = {[COMPUTER_ID] = {}}        ---@type {[number] : number[]} The table of used identifiers per host for responses.
local n_messages = {[COMPUTER_ID] = 0}           ---@type {[number] : number} The table of the amount of messages per host.
local awaiting_responses = {}                   ---@type {[number] : Response | true} The table for receiving responses.

local simple_message_fields = {
    ["sender"] = "number",
    ["receiver"] = "number",
    ["identifier"] = "number",
    ["jumps"] = "number",
    ["distance"] = "number",
    ["time_sent"] = "number",
    ["time_received"] = "number"
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

local function answer_calls_to_send(...)
    local args = table.pack(...)
    if #args < 2 or #args > 3 then
        return false, "syscall got "..tostring(#args).." parameters, expected 2 to 3"
    else
        local receiver, message, protocol = args[1], args[2], args[3]
        if type(receiver) ~= "number" or (type(message) ~= "table" and type(message) ~= "string" and type(message) ~= "number" and type(message) ~= "boolean" and type(message) ~= "nil") or (type(protocol) ~= "string" and type(protocol) ~= "nil") then
            return false, "expected number, table | string | number | boolean | nil, string | nil, got '"..type(receiver).."', '"..type(message).."', '"..type(protocol).."'"
        end
        if receiver < 0 or receiver > 65535 then
            return false, "receiver ID must be between 0 and 65535"
        end
        local identifier = identifier_generator()
        local message = luxnet.Message:new{
            sender = COMPUTER_ID,
            receiver = receiver,
            message = message,
            protocol = protocol,
            identifier = identifier,
            jumps = 0,
            distance = 0,
            time_sent = os.time(),
            time_received = 0
        }
        for side, modem in pairs(modems) do
            modem.transmit(LUXNET_PORT, LUXNET_PORT, message)
        end
        insert_seen_message(COMPUTER_ID, identifier)
        awaiting_responses[identifier] = true
        local timer = os.startTimer(RESPONSE_TIMEOUT)
        while true do
            local event = {coroutine.yield()}
            if awaiting_responses[identifier] ~= true then
                local response = awaiting_responses[identifier]
                awaiting_responses[identifier] = nil
                return true, response
            end
            if event[1] == "terminate" then
                awaiting_responses[identifier] = nil
                return false, "terminated"
            elseif event[1] == "timer" and event[2] == timer then
                awaiting_responses[identifier] = nil
                return true, false
            end
        end
    end
end

local function answer_calls_to_broadcast(...)
    local args = table.pack(...)
    if #args <1 or #args > 2 then
        return false, "syscall got "..tostring(#args).." parameters, expected 1 to 2"
    else
        local message, protocol = args[1], args[2]
        if (type(message) ~= "table" and type(message) ~= "string" and type(message) ~= "number" and type(message) ~= "boolean" and type(message) ~= "nil") or (type(protocol) ~= "string" and type(protocol) ~= "nil") then
            return false, "expected table | string | number | boolean | nil, string | nil, got '"..type(message).."', '"..type(protocol).."'"
        end
        local identifier = identifier_generator()
        local message = luxnet.Message:new{
            sender = COMPUTER_ID,
            receiver = luxnet.BROADCAST_ID,
            message = message,
            protocol = protocol,
            identifier = identifier,
            jumps = 0,
            distance = 0,
            time_sent = os.time(),
            time_received = 0
        }
        for side, modem in pairs(modems) do
            modem.transmit(LUXNET_PORT, LUXNET_PORT, message)
        end
        insert_seen_message(COMPUTER_ID, identifier)
        return true
    end
end

local function answer_calls_to_set_response_timeout(...)
    local args = table.pack(...)
    if #args ~= 1 then
        return false, "syscall got "..tostring(#args).." parameters, expected 1"
    else
        local timeout = args[1]
        if type(timeout) ~= "number" then
            return false, "expected number, got '"..type(timeout).."'"
        end
        if timeout < 0 then
            return false, "timeout must be a positive number"
        end
        RESPONSE_TIMEOUT = timeout
        return true
    end
end





local function main()
    kernel.validate_filesystem_structure(LUXNET_FS_STRUCTURE)

    kernel.make_event_private("modem_message")
    kernel.make_event_private("rednet_message")

    syscall.affect_routine(luxnet.send, answer_calls_to_send)
    syscall.affect_routine(luxnet.broadcast, answer_calls_to_broadcast)
    syscall.affect_routine(luxnet.set_response_timeout, answer_calls_to_set_response_timeout)

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
            if type(message) == "table" then
                if is_valid_message(message) then
                    -- It is a luxnet message
                    message = luxnet.Message:new(message)
                    if distance == nil then
                        distance = math.huge
                    end
                    message.distance = message.distance + distance
                    message.jumps = message.jumps + 1
                    message.time_received = os.time()

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
                            os.queueEvent("luxnet_message", message)
                            local response = {
                                sender = message.sender,
                                receiver = message.receiver,
                                identifier = message.identifier,
                                jumps = message.jumps,
                                distance = message.distance,
                                time_sent = message.time_sent,
                                time_received = message.time_received
                            }
                            for side, modem in pairs(modems) do
                                modem.transmit(LUXNET_PORT, LUXNET_PORT, response)
                            end
                        else
                            if message.receiver == luxnet.BROADCAST_ID then
                                os.queueEvent("luxnet_broadcast", message)
                            end
                            for side, modem in pairs(modems) do
                                modem.transmit(LUXNET_PORT, LUXNET_PORT, message)
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
                        if message.sender == COMPUTER_ID and awaiting_responses[message.identifier] ~= nil then
                            awaiting_responses[message.identifier] = message
                            lux.make_tick()
                        else
                            for side, modem in pairs(modems) do
                                modem.transmit(LUXNET_PORT, LUXNET_PORT, message)
                            end
                        end
                    end
                end
            end
        elseif event[1] == "peripheral" then
            local side = event[2]
            if peripheral.getType(side) == "modem" then
                modems[side] = peripheral.wrap(side)
                modems[side].open(LUXNET_PORT)
            end
        elseif event[1] == "peripheral_detach" then
            local side = event[2]
            if modems[side] ~= nil then
                table.remove(modems, side)
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

return run_shell]],
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
        local routine_main = kernel.panic_pcall("dofile", dofile, routine_path)
        if type(routine_main) ~= "function" then
            kernel.panic("Routine loader of package '"..package_name.."' did not return a function.'")
        end
        local coro = coroutine.create(routine_main)
        kernel.register_routine(package_name, coro)
    end

    -- Start runtime : wait for all routines to be ready.

    local event = {}
    while true do
        for name, coro in pairs(kernel.starting_routines("")) do
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
        for name, coro in pairs(kernel.get_routines_for_event(event[1])) do
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
        for name, coro in pairs(kernel.disconnecting_routines(event[1])) do
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

_G.services = {}        -- The service Lux API. Allows you to register services that run in background.





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
        if type(message) ~= "string" then
            error("expected string, got '"..type(message).."'", 2)
        end
        local ok, err = syscall.trampoline(message)
        if not ok then
            error(err, 2)
        end
    end
)





services.enumerate = syscall.new(
    "services.enumerate",
    ---Returns a table of the registered services, indexed by names associated to a boolean indicating if the service is running.
    ---@return {[string] : boolean} services The table of services.
    function ()
        local ok, err = syscall.trampoline()
        if not ok then
            error(err, 2)
        end
        return err
    end
)





services.install = syscall.new(
    "services.install",
    function ()
        
    end
)





services.uninstall = syscall.new(
    "services.uninstall",
    function ()
        
    end
)





services.start = syscall.new(
    "services.start",
    function ()
        
    end
)





services.stop = syscall.new(
    "services.stop",
    function ()
        
    end
)





services.read_logs = syscall.new(
    "services.read_logs",
    function ()
        
    end
)





return {services = services}]],
[[--]].."[["..[[
This is the scheduler of the service system. It loads, runs and terminates all the services. 

Note that a service script will be transformed into a coroutine that will be run by the scheduler.
This coroutine will get all the system events and should answer to the "service" events.
These events have two versions:
("servcice", "start", "<service name>") received as script arguments.
("service", "stop", "<service name>") received when the service should stop.
Note that when the stop event is received, the service will not be run again, even if the coroutine is still alive.
In the case of a "shutdown" event, the service is guaranteed to receive the "shutdown" event followed by a "service stop" event.
]].."]]"..[[





local service_coroutines = {}     ---@type {[string] : thread} The table of services coroutines indexed by names
local CURRENT_SERVICE = nil         ---@type string? The currently running service, if any.
local SERVICES_ENABLED_DIR = "LuxOS/services/scripts/enabled/"           --- This is where all the currently enabled services script files will be located
local SERVICES_DISABLED_DIR = "LuxOS/services/scripts/disabled/"           --- This is where all the currently disabled services script files will be located
local SERVICES_LOGS = "LuxOS/services/logs"                     --- This is the log file, which holds all the services logs.
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
                        name = "scripts",
                        type = kernel.DIRECTORY,
                        mode = kernel.DIRECTORY.ENSURE_EXISTS,
                        children = {

                            kernel.filesystem_node{
                                name = "enabled",
                                type = kernel.DIRECTORY,
                                mode = kernel.DIRECTORY.ENSURE_EXISTS
                            },

                            kernel.filesystem_node{
                                name = "disabled",
                                type = kernel.DIRECTORY,
                                mode = kernel.DIRECTORY.ENSURE_EXISTS
                            }

                        }
                    },

                    kernel.filesystem_node{
                        name = "logs",
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


---Internal function that creates a table to serve as the runtime environment of service coroutines.
local function create_service_environment()
    local env = os.create_user_environment()
    env["print"] = services.log
    env["write"] = services.log
    return env
end


---Internal wrapper function to run a service script file.
---@param path string The path to the service script file.
---@param name string The name of the service.
local function service_main(path, name)
    local service, err = loadfile(path, create_service_environment())
    if not service then
        error(err, 2)
    else
        service("service", "start", name)
    end
end


---Starts a service's coroutine from its script file and adds it in the service registry.
---@param name string The name of the service
---@return boolean success If the service was successfully loaded
---@return string success_message The error message if not, (or "Success")
local function launch_service(name)
    local coro = coroutine.create(service_main)
    CURRENT_SERVICE = name
    local ok, err = coroutine.resume(coro, SERVICES_ENABLED_DIR..name, name)
    CURRENT_SERVICE = nil
    if not ok then
        return false, "Service '"..name.."' had an error at startup:\n"..tostring(err)
    end
    if coroutine.status(coro) ~= "suspended" then
        return false, "Service '"..name.."' returned at startup"
    end
    service_coroutines[name] = coro
    return true, "Success"
end


---Stops a service's coroutine and removes it from the service registry.
---Note that even on failure, the service is removed from the registry.
---@param name string The name of the service
---@return boolean success If the service was successfully stopped
---@return string success_message The error message if not, (or "Success")
local function shutdown_service(name)
    local coro = service_coroutines[name]
    coroutine.resume(coro, "service", "stop")
    service_coroutines[name] = nil
    if coroutine.status(coro) ~= "dead" then
        return false, "Coroutine of service '"..name.."' did not die when sent the 'service stop' event"
    end
    return true, "Success"
end


---Returns a table of the services indexed by name. The values are booleans indicating if the service is running.
---@return {[string] : boolean} services The table of all services by names.
local function enumerate_services()
    local tab = {}
    for i, name in ipairs(kernel.panic_pcall("fs.list", fs.list, SERVICES_ENABLED_DIR)) do
        tab[name] = true
    end
    for i, name in ipairs(kernel.panic_pcall("fs.list", fs.list, SERVICES_DISABLED_DIR)) do
        tab[name] = false
    end
    return tab
end


---Moves a service from the disabled folder into the enabled folder.
---@param name string The name of the service to enable
local function enable_service(name)
    kernel.panic_pcall("fs.move", fs.move, SERVICES_DISABLED_DIR..name, SERVICES_ENABLED_DIR..name)
end


---Moves a service from the enabled folder into the disabled folder.
---@param name string The name of the service to disable
local function disable_service(name)
    kernel.panic_pcall("fs.move", fs.move, SERVICES_ENABLED_DIR..name, SERVICES_DISABLED_DIR..name)
end


---Installs a service from the given lua script file with the given name. The service will be disabled.
---@param source string The path to the script file of the service
---@param name string The name of the new service
local function install_service(source, name)
    kernel.panic_pcall("fs.copy", fs.copy, source, SERVICES_DISABLED_DIR..name)
end


---Uninstalls the service with the given name. The service must be disabled.
---@param name string The name of the service to uninstall
local function uninstall_service(name)
    kernel.panic_pcall("fs.delete", fs.delete, SERVICES_DISABLED_DIR..name)
end





---Answers the system calls to services.log.
local function answer_calls_to_log(...)
    local args = table.pack(...)
end

---Answers the system calls to services.enumerate.
local function answer_calls_to_enumerate(...)
    local args = table.pack(...)
    if #args > 0 then
        return false, "syscall got "..tostring(#args).." parameters, expected 0"
    else
        return true, kernel.panic_pcall("enumerate_services", enumerate_services)
    end
end

---Answers the system calls to services.install.
local function answer_calls_to_install(...)
    local args = table.pack(...)
end

---Answers the system calls to services.uninstall.
local function answer_calls_to_uninstall(...)
    local args = table.pack(...)
end

---Answers the system calls to services.start.
local function answer_calls_to_start(...)
    local args = table.pack(...)
end

---Answers the system calls to services.stop.
local function answer_calls_to_stop(...)
    local args = table.pack(...)
end

---Answers the system calls to services.read_logs.
local function answer_calls_to_read_logs(...)
    local args = table.pack(...)
end





local function main()

    kernel.validate_filesystem_structure(SERVICE_FS_STRUCTURE)

    syscall.affect_routine(services.log, answer_calls_to_log)
    syscall.affect_routine(services.enumerate, answer_calls_to_enumerate)
    syscall.affect_routine(services.install, answer_calls_to_install)
    syscall.affect_routine(services.uninstall, answer_calls_to_uninstall)
    syscall.affect_routine(services.start, answer_calls_to_start)
    syscall.affect_routine(services.stop, answer_calls_to_stop)
    syscall.affect_routine(services.read_logs, answer_calls_to_read_logs)

    kernel.mark_routine_ready()

    -- Startup : load enabled services

    for name, enabled in pairs(enumerate_services()) do
        if enabled then
            local ok, err = launch_service(name)
            if not ok then
                services.log("Service '"..name.."' crashed at startup:\n"..err)
            end
        end
    end

    -- Normal runtime : forward events to services

    while not kernel.is_system_shutting_down() do
        local event = {coroutine.yield()}
        for name, coro in pairs(service_coroutines) do
            local ok, err = coroutine.resume(coro, table.unpack(event))
            if not ok then
                services.log("Service '"..name.."' stopped due to an exception:\n"..err)
                service_coroutines[name] = nil
                ok, err = launch_service(name)
                if not ok then
                    services.log("Service '"..name.."' could not be restarted after an exception as another one occured at startup:\n"..err)
                    disable_service(name)
                end
            end
        end
    end

    -- Shutdown time : shutdown all services

    for name, enabled in pairs(enumerate_services()) do
        if enabled then
            local ok, err = shutdown_service(name)
            if not ok then
                services.log("Service '"..name.."' crashed at system shutdown:\n"..err)
            end
        end
    end

    kernel.mark_routine_offline()

end

return main]],
[[--]].."[["..[[
This library is used by the kernel to define and hook system calls.
]].."]]"..[[





_G.syscall = {}     -- The Lux syscall API. Mostly restricted to kernel.
libraries.syscall = syscall
local syscall_table = {}    ---@type {[string] : SysCall} The system call table.
local syscall_routines = {} ---@type {[string] : thread} The table of kernel routines that handle the system calls.


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
    kernel.check_kernel_space_before_running()
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

local ongoing_calls = {}    ---@type string[] The ongoing system call pile.

---Calls the user function
---@param ... any
---@return any
function SysCall:__call(...)
    table.insert(ongoing_calls, self.name)
    local res = {pcall(self.__user_func, ...)}
    local ok = table.remove(res, 1)
    local exiting_call = table.remove(ongoing_calls)
    if exiting_call ~= self.name then
        kernel.panic("Corrupted system call pile: exited a call of '"..exiting_call.."' where '"..self.name.."' was expected.", 1)
    end
    if not ok then
        error(res[1], 0)
    else
        return table.unpack(res)
    end
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
        kernel.panic("Syscall '"..syscall.name.."' routine stopped unexpectedly when it received arguments : '"..res.."'", 2)
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
            kernel.panic("Corrupted system call pile: syscall.trampoline() called with no running system calls.", 1)
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
    if not ok then
        kernel.panic("Syscall '"..call_name.."' generating routine crashed: "..syscall_coro, 2)
    end
    local res = {coroutine.resume(syscall_coro, ...)}
    while true do
        ok = table.remove(res, 1)
        if not ok then
            coroutine.resume(report_syscall_crash_coro, syscall_table[call_name], res[1], ...)
        end
        if coroutine.status(syscall_coro) == "dead" then
            break
        end
        res = {coroutine.resume(syscall_coro, coroutine.yield())}
    end
    return table.unpack(res)
end





---Creates a new syscall object.
---@generic F : function
---@param name string The name of the system call.
---@param func F The user function.
---@return F syscall system call wrapped function.
function syscall.new(name, func)
    kernel.check_kernel_space_before_running()
    return SysCall:new{name, func}
end





---Affects the given function to the handling of the specified system call.
---It will receive the parameters of the system call to answer and should return back a boolean indicating if the call succeeded and any return values.
---@param syscall SysCall The system call to affect this routine to.
---@param handler_func function The function that will handle all incomming system calls.
function syscall.affect_routine(syscall, handler_func)
    kernel.check_kernel_space_before_running()
    if syscall_routines[syscall.name] ~= nil then
        kernel.panic("Syscall '"..syscall.name.."' routine has already been affected.", 1)
    end

    local function do_system_call(func, func_name)
        local res = {pcall(func, table.unpack({coroutine.yield()}))}
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
    kernel.check_kernel_space_before_running()
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
}

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
            print("Installing file '"..path.."'...")
            local file = fs.open(path, "w")
            file.write(content)
            file.close()
        end
    end
end

install(package, "")

print("Installation is finished. Press any key to boot LuxOS.")
while true do
    local event = coroutine.yield()
    if event == "key" then
        break
    end
end

dofile(ENTRY_POINT)