--[[
This is the standart LuxNet service API. It contains all the functions to communicate with other machines running on LuxOS.

Use luxnet() to create a new LuxNet context.
]]

_G.luxnet = {}      -- The LuxNet API. Allows you to communicate with other machines running LuxOS.





luxnet.LUXNET_PORT = 42      -- The port that LuxNet uses to communicate with other machines.
luxnet.BROADCAST_ID = -1     -- The ID that represents a broadcast message. This is used to send messages to all machines.





---@class Message The class for message objects.
---@field sender integer The ID of the sender.
---@field receiver integer The ID of the receiver.
---@field message table | string | number | boolean | nil The message itself.
---@field protocol string | nil The protocol used to send the message.
---@field identifier integer A unique identifier for the message.
---@field jumps integer The amount of jumps the message has done to reach the receiver.
---@field time_to_live integer The maximum number of jumps the message can do. Can be infinite.
---@field distance number The distance that the message has traveled.
---@field frequency integer The frequency that the message was sent on.
---@field time_sent number The time when the message was sent.
---@field time_received number The time when the message was received.
local Message = {}
luxnet.Message = Message

Message.__index = Message
Message.__name = "Message"


---Creates a new Message object.
---@param message {["sender"]: integer, ["receiver"]: integer, ["message"]: table | string | number | boolean | nil, ["protocol"]: string | nil, ["identifier"]: integer, ["jumps"]: integer, ["time_to_live"]: integer, ["distance"]: number, ["frequency"]: integer, ["time_sent"]: number, ["time_received"]: number} The required parameters for creating a message.
---@return Message message The new message object.
function Message:new(message)
    setmetatable(message, self)
    return message
end


function Message:__tostring()
    local ok, message_str = pcall(textutils.serialize, self.message)
    if not ok then
        message_str = tostring(self.message)
    end
    local protocol = "nil"
    if self.protocol ~= nil then
        protocol = "'"..self.protocol.."'"
    end
    return "Message{sender=" .. self.sender .. ", receiver=" .. self.receiver .. ", message=" .. message_str .. ", protocol=" .. protocol .. ", identifier=" .. self.identifier .. ", jumps=" .. self.jumps .. ", time_to_live=" .. self.time_to_live .. ", distance=" .. self.distance .. ", frequency=" .. self.frequency .. ", time_sent=" .. self.time_sent .. ", time_received=" .. self.time_received .. "}"
end



---@class Response The class for response objects.
---@field sender integer The ID of the sender of the corresponding message.
---@field receiver integer The ID of the receiver of the corresponding message.
---@field identifier integer The identifier of the corresponding message.
---@field jumps integer The amount of jumps that the corresponding message has done to reach the receiver.
---@field time_to_live integer The remaining time_to_live. time_to_live + jumps = initial time_to_live.
---@field distance number The distance that the corresponding message has traveled to reach the receiver.
---@field frequency integer The frequency that the corresponding message was sent on.
---@field time_sent number The time when the corresponding message was sent.
---@field time_received number The time when the corresponding message was received.
local Response = {}
luxnet.Response = Response

Response.__index = Response
Response.__name = "Response"


---Creates a new Response object. Can only be called from kernel space.
---@param response {["sender"]: integer, ["receiver"]: integer, ["identifier"]: integer, ["jumps"]: integer, ["time_to_live"]: integer, ["distance"]: number, ["frequency"]: integer, ["time_sent"]: number, ["time_received"]: number} The required parameters for creating a response.
---@return Response response The new response object.
function Response:new(response)
    setmetatable(response, self)
    return response
end


function Response:__tostring()
    return "Response{sender=" .. self.sender .. ", receiver=" .. self.receiver .. ", identifier=" .. self.identifier .. ", jumps=" .. self.jumps .. ", time_to_live=" .. self.time_to_live .. ", distance=" .. self.distance .. ", frequency=" .. self.frequency .. ", time_sent=" .. self.time_sent .. ", time_received=" .. self.time_received .. "}"
end





luxnet.enable_frequency = syscall.new(
    "luxnet.enable_frequency",
    ---Enables the frequency of the machine for LuxNet. Each call to enable_frequency should be matched with a call to disable_frequency.
    ---@param frequency integer The frequency to enable.
    function (frequency)
        local ok, err = syscall.trampoline(frequency)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)





luxnet.disable_frequency = syscall.new(
    "luxnet.disable_frequency",
    ---Disables the frequency of the machine for LuxNet.
    ---@param frequency integer The frequency to disable.
    function (frequency)
        local ok, err = syscall.trampoline(frequency)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)





luxnet.active_frequencies = syscall.new(
    "luxnet.active_frequencies",
    ---Returns a list of all active frequencies.
    ---@return integer[] frequencies A list of all active frequencies.
    function ()
        local ok, err_or_frequencies = syscall.trampoline()
        if ok then
            return err_or_frequencies
        else
            error(err_or_frequencies, 2)
        end
    end
)





luxnet.send = syscall.new(
    "luxnet.send",
    ---Sends a message to another machine.
    ---@param receiver integer The ID of the receiver.
    ---@param message table | string | number | boolean | nil The message to send.
    ---@param protocol string? The protocol to use to send the message.
    ---@param time_to_live integer? The maximum number of jumps the message can do. Can be infinite.
    ---@param frequency integer? The frequency to use to send the message.
    ---@param timeout number? The time to wait for a response before giving up.
    ---@return Response | false response The response from the receiver, if any, or false if the receiver didn't acknowledge the message.
    function (receiver, message, protocol, time_to_live, frequency, timeout)
        local ok, err_or_awaitable = syscall.trampoline(receiver, message, protocol, time_to_live, frequency, timeout)
        if not ok then
            error(err_or_awaitable, 2)
        end
        if err_or_awaitable == false then
            return false
        end
        local ok, err_or_response = err_or_awaitable()
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
    ---@param protocol string? The protocol to use to send the message.
    ---@param time_to_live integer? The maximum number of jumps the message can do. Can be infinite.
    ---@param frequency integer? The frequency to use to send the message.
    function (message, protocol, time_to_live, frequency)
        local ok, err = syscall.trampoline(message, protocol, time_to_live, frequency)
        if ok then
            return
        else
            error(err, 2)
        end
    end
)





luxnet.receive = syscall.new(
    "luxnet.receive",
    --- Receives a message from another machine.
    ---@param sender integer[] | integer | nil The ID(s) of the sender(s) to receive a message from. Can be a table of integers, a single integer, or nil to receive from any sender.
    ---@param protocol string? An optional protocal to filter messages by.
    ---@param timeout number? The time to wait for a message before giving up. Defaults to no timeout.
    ---@param ferquency integer? The frequency to receive the message on. Defaults to LUXNET frequency.
    ---@return Message? message The message received, or nil if the timeout was reached.
    function (sender, protocol, timeout, ferquency)
        local ok, err_or_awaitable = syscall.trampoline(sender, protocol, timeout, ferquency)
        if not ok then
            error(err_or_awaitable, 2)
        end
        local ok, err_or_message = err_or_awaitable()
        if ok then
            if err_or_message == nil then
                return nil
            else
                return Message:new(err_or_message)
            end
        else
            error(err_or_message, 2)
        end
    end
)





---@class LuxNetContext A class that holds a set of LuxNet settings and wraps system calls.
---@field frequency integer The frequency that the context is using.
---@field send_timeout number The time to wait for a response before giving up.
---@field receive_timeout number? The time to wait for a message before giving up.
---@field time_to_live integer? The maximum number of jumps the message can do. Can be infinite.
---@field protocol string? The protocol to use to send the message.
local LuxNetContext = {}
luxnet.LuxNetContext = LuxNetContext

LuxNetContext.__index = LuxNetContext
LuxNetContext.__name = "LuxNetContext"


---Creates a new LuxNetContext object.
---@param frequency integer? The frequency to use. Defaults to LUXNET frequency.
---@param send_timeout number? The time to wait for a response before giving up. Defaults to 5 seconds.
---@param receive_timeout number? The time to wait for a message before giving up. Defaults to no timeout.
---@param time_to_live integer? The maximum number of jumps the message can do. Can be infinite. Defaults to infinite.
---@param protocol string? The protocol to use to send the message. Defaults to nil.
---@return LuxNetContext context The new LuxNetContext object.
function LuxNetContext:new(frequency, send_timeout, receive_timeout, time_to_live, protocol)
    local context = {
        frequency = frequency or luxnet.LUXNET_PORT,
        send_timeout = send_timeout or 5,
        receive_timeout = receive_timeout,
        time_to_live = time_to_live,
        protocol = protocol,
    }
    setmetatable(context, self)
    luxnet.enable_frequency(context.frequency)
    return context
end


function LuxNetContext:__tostring()
    local receive_timeout = "inf"
    if self.receive_timeout ~= nil then
        receive_timeout = tostring(self.receive_timeout)
    end
    local time_to_live = "inf"
    if self.time_to_live ~= nil then
        time_to_live = tostring(self.time_to_live)
    end
    local protocol = "nil"
    if self.protocol ~= nil then
        protocol = "'"..self.protocol.."'"
    end
    return "LuxNetContext{frequency=" .. self.frequency .. ", send_timeout=" .. self.send_timeout .. ", receive_timeout=" .. receive_timeout .. ", time_to_live=" .. time_to_live .. ", protocol=" .. protocol .. "}"
end

---Sends a message to another machine.
---@param receiver integer The ID of the receiver.
---@param message table | string | number | boolean | nil The message to send.
---@return Response | false response The response from the receiver, if any, or false if the receiver didn't acknowledge the message.
function LuxNetContext:send(receiver, message)
    return luxnet.send(receiver, message, self.protocol, self.time_to_live, self.frequency, self.send_timeout)
end

---Broadcasts a message to all machines.
---@param message table | string | number | boolean | nil The message to send.
function LuxNetContext:broadcast(message)
    return luxnet.broadcast(message, self.protocol, self.time_to_live, self.frequency)
end

---Receives a message from another machine.
---@param sender integer[] | integer | nil The ID(s) of the sender(s) to receive a message from. Can be a table of integers, a single integer, or nil to receive from any sender.
---@return Message? message The message received, or nil if the timeout was reached.
function LuxNetContext:receive(sender)
    return luxnet.receive(sender, self.protocol, self.receive_timeout, self.frequency)
end

---Sets the context frequency.
---@param frequency integer The frequency to use.
function LuxNetContext:set_frequency(frequency)
    luxnet.disable_frequency(self.frequency)
    self.frequency = frequency
    luxnet.enable_frequency(frequency)
end

---Sets the context send timeout.
---@param send_timeout number The time to wait for a response before giving up.
function LuxNetContext:set_send_timeout(send_timeout)
    self.send_timeout = send_timeout
end

---Sets the context receive timeout.
---@param receive_timeout number? The time to wait for a message before giving up. Can be nil for no timeout.
function LuxNetContext:set_receive_timeout(receive_timeout)
    self.receive_timeout = receive_timeout or math.huge
end

---Sets the context time to live.
---@param time_to_live integer? The maximum number of jumps the message can do. Can be nil for infinite.
function LuxNetContext:set_time_to_live(time_to_live)
    self.time_to_live = time_to_live
end

---Sets the context protocol.
---@param protocol string? The protocol to use to send the message. Can be nil for no protocol.
function LuxNetContext:set_protocol(protocol)
    self.protocol = protocol
end





local luxnet_metatable = table.copy(table)
setmetatable(luxnet, luxnet_metatable)

---Shortcut for creating a new LuxNet context.
---@return LuxNetContext context The new LuxNetContext object.
function luxnet_metatable:__call(...)
    return LuxNetContext:new(...)
end





return {luxnet = luxnet}