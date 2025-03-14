--[[
This is the library to handle the boot sequence of LuxOS. By default, this directly lauches the operating system but it can be changed.
]]

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





return {boot = boot}