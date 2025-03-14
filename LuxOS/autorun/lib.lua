--[[
This the standart autorun Lux API. Use it to register/unregister scripts that should be run at startup.
]]

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





return {autorun = autorun}