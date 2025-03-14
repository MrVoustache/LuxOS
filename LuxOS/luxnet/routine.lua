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
local RESPONSE_TIMEOUT = 5

local modems = {}      ---@type {[string] : table} The table of all modems connected to the computer. The key is the side of the modem and the value is the modem object.
local COMPUTER_ID = os.getComputerID()
local seen_messages = {[COMPUTER_ID] = {}}        ---@type {[number] : number[]} The table of used identifiers per host for messages.
local seen_responses = {[COMPUTER_ID] = {}}        ---@type {[number] : number[]} The table of used identifiers per host for responses.
local n_messages = {[COMPUTER_ID] = 0}           ---@type {[number] : number} The table of the amount of messages per host.
local awaiting_responses = {}                   ---@type {[number] : Response | true} The table for receiving responses.

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
    local args = {...}
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
        local message = {
            sender = COMPUTER_ID,
            receiver = receiver,
            message = message,
            protocol = protocol,
            identifier = identifier,
            jumps = 0,
            time_to_live = math.huge,
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
    local args = {...}
    if #args <1 or #args > 2 then
        return false, "syscall got "..tostring(#args).." parameters, expected 1 to 2"
    else
        local message, protocol = args[1], args[2]
        if (type(message) ~= "table" and type(message) ~= "string" and type(message) ~= "number" and type(message) ~= "boolean" and type(message) ~= "nil") or (type(protocol) ~= "string" and type(protocol) ~= "nil") then
            return false, "expected table | string | number | boolean | nil, string | nil, got '"..type(message).."', '"..type(protocol).."'"
        end
        local identifier = identifier_generator()
        local message = {
            sender = COMPUTER_ID,
            receiver = luxnet.BROADCAST_ID,
            message = message,
            protocol = protocol,
            identifier = identifier,
            jumps = 0,
            time_to_live = math.huge,
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
    local args = {...}
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
                    if distance == nil then
                        distance = math.huge
                    end
                    message.distance = message.distance + distance
                    message.jumps = message.jumps + 1
                    message.time_to_live = message.time_to_live - 1
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
                            if message.time_to_live > 0 then
                                for side, modem in pairs(modems) do
                                    modem.transmit(LUXNET_PORT, LUXNET_PORT, message)
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

return main