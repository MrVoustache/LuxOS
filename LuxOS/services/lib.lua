--[[
This is the standart Lux service API. It contains all the function to perform system calls to the service system.
]]

_G.services = {}        --[[
The service Lux API. Allows you to register services that run in background.

To declare a service, create a lua script file that returns a Service object.
]]





services.log = syscall.new(
    "services.log",
    ---Logs a message to the service journal.
    ---@param ... string The message to log in the journal. Converts all parameters to string (pretty printed if possible) and concatenates them.
    function (...)
        local args = {...}
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
        local ok, err = syscall.trampoline(identifier)
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
}