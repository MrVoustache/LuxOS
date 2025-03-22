--[[
Routine for the lightUI Lux package. Handles the User Interface.
]]





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

return run_shell, 1