--[[
Routine for the autorun Lux package. Runs all the scripts registered for startup then halts.
]]





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

return main