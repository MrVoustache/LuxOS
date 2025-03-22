--[[
This library is used by the kernel to define and hook system calls.
]]





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
---@param clean_up (fun():nil)? An optional function that will be called when the generator is destroyed.
---@return fun() : boolean, R | string awaitable An awaitable function that will block until the condition is met and will return any value returned. Should be return by the trampoline.
---@return fun() : nil completion A non-blocking function that should be called by the kernel when the condition should be checked.
function syscall.await(condition, result, terminable, pre_complete, clean_up)
    check_kernel_space_before_running()
    if terminable == nil then
        terminable = false
    end

    local await_coro = coroutine.create(function ()
        while not condition() do
            local event = coroutine.yield()
            if terminable and event == "terminate" then
                if clean_up ~= nil then
                    clean_up()
                end
                return false, "terminated"
            end
        end
        local res = result()
        if clean_up ~= nil then
            clean_up()
        end
        return res
    end)

    kernel.promote_coroutine(await_coro)

    local function awaitable()
        local event = {n = 0}
        while true do
            local res = table.pack(coroutine.resume(await_coro, table.unpack(event, 1, event.n)))
            local ok = table.remove(res, 1)
            if not ok then
                kernel.panic("Awaitable syscall coroutine had an exception: "..res[1])
            end
            if coroutine.status(await_coro) == "dead" then
                return table.unpack(res, 1, res.n - 1)
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





---Creates an awaitable generator for syscalls to use when a syscall should yield values and possibly block to yield the next one.
---@generic R : any The yield type of the awaitable
---@param condition fun() : boolean The condition checking function. Returns true if the condition is met and a value can be yielded, false otherwise.
---@param result fun() : boolean, R | string | nil The result function. Should return true and any value on success and false plus an error message on error. Will be called for each yield. Should return true and nil when no more values are available.
---@param terminable boolean? If true, the awaitable breaks if a terminate event is received. Defaults to false.
---@param pre_complete (fun():nil)? An optional function that will be called each time the condition is complete.
---@param clean_up (fun():nil)? An optional function that will be called when the generator is destroyed.
---@return fun() : boolean?, R | string | nil awaitable An awaitable function that will block until the condition is met and will return the yield value. Can be called multiple as long as yield values are available. Returns nil when no more values are available.
---@return fun() : nil completion A non-blocking function that should be called by the kernel when the condition should be checked. Might not be called if the awaitable does not have to block.
function syscall.await_gen(condition, result, terminable, pre_complete, clean_up)
    check_kernel_space_before_running()
    if terminable == nil then
        terminable = false
    end

    local await_coro = coroutine.create(function ()
        while true do
            local event
            while not condition() do
                event = coroutine.yield()
                if terminable and event == "terminate" then
                    if clean_up ~= nil then
                        clean_up()
                    end
                    return false, "terminated"
                end
            end
            local res = table.pack(result())
            local ok = table.remove(res, 1)
            if not ok then
                if clean_up ~= nil then
                    clean_up()
                end
                return false, res[1]
            end
            event = coroutine.yield(true, table.unpack(res, 1, res.n - 1))
        end
    end)

    kernel.promote_coroutine(await_coro)

    local function awaitable()
        if coroutine.status(await_coro) == "dead" then
            return nil
        end
        local event = {n = 0}
        while true do
            local res = table.pack(coroutine.resume(await_coro, table.unpack(event, 1, event.n)))
            local ok = table.remove(res, 1)
            if not ok then
                kernel.panic("Awaitable syscall coroutine had an exception: "..res[1])
            end
            ok = table.remove(res, 1)
            if ok == false then
                error(res[1], 2)
            elseif ok == true then
                return table.unpack(res, 1, res.n - 2)
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
end