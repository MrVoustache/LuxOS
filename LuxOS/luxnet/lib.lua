--[[
This is the standart LuxNet service API. It contains all the functions to communicate with other machines running on LuxOS.
]]

_G.luxnet = {}      -- The LuxNet API. Allows you to communicate with other machines running LuxOS.





luxnet.LUXNET_PORT = 42      -- The port that LuxNet uses to communicate with other machines.
luxnet.BROADCAST_ID = -1     -- The ID that represents a broadcast message. This is used to send messages to all machines.

local check_kernel_space_before_running = kernel.check_kernel_space_before_running





---@class Message The class for message objects.
---@field sender integer The ID of the sender.
---@field receiver integer The ID of the receiver.
---@field message table | string | number | boolean | nil The message itself.
---@field protocol string | nil The protocol used to send the message.
---@field identifier integer A unique identifier for the message.
---@field jumps integer The amount of jumps the message has done to reach the receiver.
---@field time_to_live integer The maximum number of jumps the message can do. Can be infinite.
---@field distance number The distance that the message has traveled.
---@field time_sent number The time when the message was sent.
---@field time_received number The time when the message was received.
local Message = {}
luxnet.Message = Message

Message.__index = Message
Message.__name = "Message"


---Creates a new Message object.
---@param message {["sender"]: integer, ["receiver"]: integer, ["message"]: table | string | number | boolean | nil, ["protocol"]: string | nil, ["identifier"]: integer, ["jumps"]: integer, ["time_to_live"]: integer, ["distance"]: number, ["time_sent"]: number, ["time_received"]: number} The required parameters for creating a message.
---@return Message message The new message object.
function Message:new(message)
    setmetatable(message, self)
    return message
end



---@class Response The class for response objects.
---@field sender integer The ID of the sender of the corresponding message.
---@field receiver integer The ID of the receiver of the corresponding message.
---@field identifier integer The identifier of the corresponding message.
---@field jumps integer The amount of jumps that the corresponding message has done to reach the receiver.
---@field distance number The distance that the corresponding message has traveled to reach the receiver.
---@field time_sent number The time when the corresponding message was sent.
---@field time_received number The time when the corresponding message was received.
local Response = {}
luxnet.Response = Response

Response.__index = Response
Response.__name = "Response"


---Creates a new Response object. Can only be called from kernel space.
---@param response {["sender"]: integer, ["receiver"]: integer, ["identifier"]: integer, ["jumps"]: integer, ["distance"]: number, ["time_sent"]: number, ["time_received"]: number} The required parameters for creating a response.
---@return Response response The new response object.
function Response:new(response)
    setmetatable(response, self)
    return response
end





luxnet.send = syscall.new(
    "luxnet.send",
    ---Sends a message to another machine.
    ---@param receiver integer The ID of the receiver.
    ---@param message table | string | number | boolean | nil The message to send.
    ---@param protocol string | nil The protocol to use to send the message.
    ---@return Response | false response The response from the receiver, if any.
    function (receiver, message, protocol)
        local ok, err_or_response = syscall.trampoline(receiver, message, protocol)
        if ok then
            if err_or_response == false then
                return false
            else
                return Response:new(err_or_response)
            end
        else
            error(err_or_response, 2)
        end
    end
)


  


luxnet.broadcast = syscall.new(
    "luxnet.broadcast",
    ---Sends a message to all machines.
    ---@param message table | string | number | boolean | nil The message to send.
    ---@param protocol string | nil The protocol to use to send the message.
    function (message, protocol)
        local ok, err = syscall.trampoline(message, protocol)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)





luxnet.set_response_timeout = syscall.new(
    "luxnet.set_response_timeout",
    ---Sets the time to wait for a response before giving up.
    ---@param timeout number The time to wait for a response before giving up.
    function (timeout)
        local ok, err = syscall.trampoline(timeout)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)





--- Receives a message from another machine.
---@param protocol string | nil An optional protocal to filter messages by.
---@param timeout number | nil The time to wait for a message before giving up. Defaults to no timeout.
---@return Message | nil message The message received, or nil if the timeout was reached.
function luxnet.receive(protocol, timeout)
    if protocol ~= nil and type(protocol) ~= "string" then
        error("bad argument #1 (expected string, got " .. type(protocol) .. ")", 2)
    end
    if timeout ~= nil and type(timeout) ~= "number" then
        error("bad argument #2 (expected number, got " .. type(timeout) .. ")", 2)
    end
    if timeout ~= nil and timeout < 0 then
        error("bad argument #2 (expected number >= 0, got " .. timeout .. ")", 2)
    end
    local timer
    if timeout ~= nil then
        timer = os.startTimer(timeout)
    end
    while true do
        local event = {coroutine.yield()}
        if event[1] == "luxnet_message" or event[1] == "luxnet_broadcast" then
            local message = event[2]
            if protocol == nil or message.protocol == protocol then
                return Message:new(message)
            end
        elseif event[1] == "terminate" then
            error("terminated", 2)
        elseif event[1] == "timer" and event[2] == timer then
            return nil
        end
    end
end





--- Receives a message from a specific machine.
---@param sender integer The ID of the sender to receive a message from.
---@param protocol string | nil An optional protocal to filter messages by.
---@param timeout number | nil The time to wait for a message before giving up. Defaults to no timeout.
---@return Message | nil message The message received, or nil if the timeout was reached.
function luxnet.receive_from(sender, protocol, timeout)
    if type(sender) ~= "number" then
        error("bad argument #1 (expected number, got " .. type(sender) .. ")", 2)
    end
    if protocol ~= nil and type(protocol) ~= "string" then
        error("bad argument #2 (expected string, got " .. type(protocol) .. ")", 2)
    end
    if timeout ~= nil and type(timeout) ~= "number" then
        error("bad argument #3 (expected number, got " .. type(timeout) .. ")", 2)
    end
    if sender < 0 or sender > 65535 then
        error("bad argument #1 (expected number in range 0-65535, got " .. sender .. ")", 2)
    end
    if timeout ~= nil and timeout < 0 then
        error("bad argument #3 (expected number >= 0, got " .. timeout .. ")", 2)
    end
    local timer
    if timeout ~= nil then
        timer = os.startTimer(timeout)
    end
    while true do
        local event = {coroutine.yield()}
        if event[1] == "luxnet_message" or event[1] == "luxnet_broadcast" then
            local message = event[2]
            if message.sender == sender and (protocol == nil or message.protocol == protocol) then
                return Message:new(message)
            end
        elseif event[1] == "terminate" then
            error("terminated", 2)
        elseif event[1] == "timer" and event[2] == timer then
            return nil
        end
    end
end





return {luxnet = luxnet}