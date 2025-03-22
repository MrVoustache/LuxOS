--[[
This is the luxnet kernel routine. It handles all modems and everything that goes through them.
]]





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
            if awaiting_timers[event[2]] ~= nil then
                last_message = nil
                local identifier = awaiting_timers[event[2]]
                awaiting_timers[event[2]] = nil
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

return main