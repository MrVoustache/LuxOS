--[[
The Lux kernel API. Used only by Lux code!
]]

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





local routine_coroutines = {}   ---@type {[string] : thread}
local current_routine = nil     ---@type string?
local routines_ready = {}       ---@type {[string] : boolean}
local routines_offline = {}     ---@type {[string] : boolean}
local private_event = {}        ---@type {[string] : string}

---Register a new system routine. Only called by the main scheduler.
---@param name string The name of the coroutine.
---@param coro thread The coroutine object itself.
function kernel.register_routine(name, coro)
    check_kernel_space_before_running()
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
---@return { [string]: thread } routines The existing routine, indexed by names.
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
---@return {[string] : thread} routines The routines to run for the event.
function kernel.get_routines_for_event(event_name)
    check_kernel_space_before_running()
    if private_event[event_name] ~= nil then
        return {[private_event[event_name]] = routine_coroutines[private_event[event_name]]}
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
---@return {[string] : thread} not_ready The routines' coroutines to run to finish startup.
function kernel.starting_routines(event_name)
    check_kernel_space_before_running()
    if private_event[event_name] ~= nil and not routines_ready[private_event[event_name]] then
        return {[private_event[event_name]] = routine_coroutines[private_event[event_name]]}
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
---@return {[string] : thread} not_ready The routines' coroutines to run to finish shutdown.
function kernel.disconnecting_routines(event_name)
    check_kernel_space_before_running()
    if private_event[event_name] ~= nil and not routines_offline[private_event[event_name]] then
        return {[private_event[event_name]] = routine_coroutines[private_event[event_name]]}
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





--[[Ensures that the given filesystem structure exists. Panics if not. Here is an example of such a structure:

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

]]
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
end