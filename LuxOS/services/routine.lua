--[[
This is the scheduler of the service system. It loads, runs and terminates all the services. 
]]





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
local SERVICES_READING_LOGS = {}                        ---@type {[integer]: integer} Indicates how many readers are waiting for logs for each service.
local SERVICES_LOG_CALLBACKS = {}                       ---@type {[integer]: (fun():nil)[]} A list of callbacks for each service that is waiting for logs.
local SERVICES_LAST_LOG = nil                           ---@type string? The last service log made.
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
            local cb = SERVICES_STOP_CALLBACKS[identifier][#SERVICES_STOP_CALLBACKS[identifier]]
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
    SERVICES_READING_LOGS[identifier] = 0
    SERVICES_LOG_CALLBACKS[identifier] = {}
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
    SERVICES_READING_LOGS[identifier] = nil
    SERVICES_LOG_CALLBACKS[identifier] = nil
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
        local full_message = "day "..os.day()..": "..textutils.formatTime(os.time())..", "..textutils.serialise("["..DISPLAY_NAME.."] "..message)
        SERVICES_LOG_FILES[CURRENT_SERVICE].write(full_message.."\n")
        SERVICES_LOG_FILES[CURRENT_SERVICE].flush()
        SERVICES_LAST_LOG = full_message
        if SERVICES_READING_LOGS[CURRENT_SERVICE] > 0 then
            for _, cb in ipairs(SERVICES_LOG_CALLBACKS[CURRENT_SERVICE]) do
                cb()
            end
        end
        SERVICES_LAST_LOG = nil
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
        local next_logs = {}     ---@type string[]
        SERVICES_READING_LOGS[identifier] = SERVICES_READING_LOGS[identifier] + 1
        local callback_identifier = #SERVICES_LOG_CALLBACKS[identifier] + 1
        local function clean_up()
            SERVICES_READING_LOGS[identifier] = SERVICES_READING_LOGS[identifier] - 1
            SERVICES_LOG_CALLBACKS[identifier][callback_identifier] = nil
        end
        print("Now, "..SERVICES_READING_LOGS[identifier].." are reading logs for service #"..identifier)
        local awaitable, complete = syscall.await_gen(
            function ()
                return #next_logs > 0 or SERVICES_STATUS[identifier] == services.STATUS.DISABLED
            end,
            function ()
                if #next_logs == 0 then
                    clean_up()
                    return true, nil
                else
                    return true, table.remove(next_logs, 1)
                end
            end,
            true,
            function ()
                table.insert(next_logs, SERVICES_LAST_LOG)
            end,
            clean_up
        )
        SERVICES_LOG_CALLBACKS[identifier][callback_identifier] = complete

        if kernel.panic_pcall("fs.exists", fs.exists, SERVICES_LOGS..identifier..".log") then
            local file = kernel.panic_pcall("fs.open", fs.open, SERVICES_LOGS..identifier..".log", "r")
            if file == nil then
                kernel.panic("could not open log file for service #"..identifier)
            end
            for line in file.readLine do
                table.insert(next_logs, line)
            end
            file.close()
        end

        return true, awaitable
    end
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
        local ok, err = load_service(tostring(filepath), identifier)
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
    syscall.affect_routine(services.read_logs, answer_calls_to_read_logs)
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

return main, 1