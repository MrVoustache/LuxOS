local inputs = {...}
local FILE_PATH = ".sgbook"

local function print_color(color, text)
    local old_color = term.getTextColor()
    term.setTextColor(color)
    print(text)
    term.setTextColor(old_color)
end

local function print_usage()
    print_color(colors.red, "Usage:\nsgbook help\nsgbook\nsgbook call <name>\nsgbook add <name>\nsgbook del <name>\nsgbook list\nsgbook server <stargate side>")
    print_color(colors.red, "sgbook usage:")
    print_color(colors.red, "  help: Show this help message")
    print_color(colors.red, "  dial <name>: Dial a stargate by name")
    print_color(colors.red, "  hang: Hang up the current connection")
    print_color(colors.red, "  search: Searches for a nearby stargate")
    print_color(colors.red, "  save <name>: Saves a nearby stargate with given name")
    print_color(colors.red, "  del <name>: Deletes a saved stargate by name")
    print_color(colors.red, "  list: Lists all saved stargates")
    print_color(colors.red, "  server <stargate side>: Handles the stargate connected to the given side")
end

local function read_table()
    if not fs.exists(FILE_PATH) then
        return {}
    end
    local tab = {}
    local h = fs.open(FILE_PATH, "r")
    local line = h.readLine()
    while line do
        tab[string.sub(line, 1, 9)] = string.sub(line, 11)
        line = h.readLine()
    end
    h.close()
    return tab
end

local function write_table(tab)
    local h = fs.open(FILE_PATH, "w")
    for key, value in pairs(tab) do
        h.writeLine(tostring(key).." "..tostring(value))
    end
    h.close()
end

local function dial(address)
    luxnet.broadcast({"dial", address}, "sgbook")
end

local function hang()
    luxnet.broadcast({"hang"}, "sgbook")
end

local function ping()
    luxnet.broadcast({"ping"}, "sgbook")
    local timer = os.startTimer(2)
    while true do
        local event = {coroutine.yield()}
        if event[1] == "luxnet_message" or event[1] == "luxnet_broadcast" then
            local message_data = event[2]        ---@type Message
            if message_data.protocol == "sgbook" then
                if message_data.message[1] == "pong" and message_data.distance < 50 then
                    return message_data.message[2]
                end
            end
        elseif event[1] == "terminate" or (event[1] == "timer" and event[2] == timer) then
            return false
        end
    end
end

if #inputs <= 0 then
    print_usage()
    return
else
    local mode = inputs[1]
    if mode == "help" then
        print_usage()
        return
    elseif mode == "dial" then
        if #inputs ~= 2 then
            print_usage()
            return
        end
        local name = inputs[2]
        local tab = read_table()
        local address = false
        for key, value in pairs(tab) do
            if value == name then
                address = key
            end
        end
        if not address then
            print_color(colors.orange, "No such address "..name)
            return
        end
        dial(address)
        while true do
            local event = {coroutine.yield()}
            if event[1] == "luxnet_message" or event[1] == "luxnet_broadcast" then
                local message_data = event[2]        ---@type Message
                if message_data.protocol == "sgbook" then
                    if message_data.message[1] == "state" then
                        if message_data.message[2] == "Dialling" then
                            print_color(colors.yellow, "Dialling "..name)
                        elseif message_data.message[2] == "Connected" then
                            print_color(colors.green, "Connected to "..name)
                        elseif message_data.message[2] == "Disconnected" then
                            print_color(colors.red, "Disconnected from "..name)
                            return
                        end
                    end
                end
            end
            if event[1] == "terminate" then
                print_color(colors.red, "Disconnecting from "..name)
                break
            end
        end
        hang()
    elseif mode == "hang" then
        if #inputs ~= 1 then
            print_usage()
            return
        end
        hang()
    elseif mode == "search" then
        if #inputs ~= 1 then
            print_usage()
            return
        end
        local address = ping()
        if not address then
            print_color(colors.red, "No near stargate found")
            return
        end
        address = string.gsub(address, "[%s%-]", "")
        print_color(colors.green, "Near stargate found:")
        local tab = read_table()
        if tab[address] then
            print_color(colors.cyan, tab[address])
        else
            print_color(colors.purple, string.sub(address, 1, 4).."-"..string.sub(address, 5, 7).."-"..string.sub(address, 8))
        end
    elseif mode == "save" then
        if #inputs ~= 2 then
            print_usage()
            return
        end
        local name = inputs[2]
        local address = ping()
        if not address then
            print_color(colors.red, "No near stargate found")
            return
        end
        address = string.gsub(address, "[%s%-]", "")
        local tab = read_table()
        tab[address] = name
        write_table(tab)
    elseif mode == "del" then
        if #inputs ~= 2 then
            print_usage()
            return
        end
        local name = inputs[2]
        local tab = read_table()
        local address = false
        for key, value in pairs(tab) do
            if value == name then
                address = key
            end
        end
        if not address then
            print_color(colors.orange, "No such address "..name)
            return
        end
        tab[address] = nil
        write_table(tab)
    elseif mode == "list" then
        if #inputs ~= 1 then
            print_usage()
            return
        end
        local tab = read_table()
        print()
        for address, name in pairs(tab) do
            local color = term.getTextColor()
            term.setTextColor(colors.cyan)
            write(name)
            term.setTextColor(colors.white)
            write(" : ")
            term.setTextColor(colors.purple)
            write(string.sub(address, 1, 4).."-"..string.sub(address, 5, 7).."-"..string.sub(address, 8).."\n")
            term.setTextColor(color)
        end
        print()
    elseif mode == "server" then
        if #inputs ~= 2 then
            print_usage()
            return
        end
        local stargate_side = inputs[2]
        local sg = peripheral.wrap(stargate_side)
        if sg == nil then
            print_color(colors.red, "No stargate on side '"..stargate_side.."'")
            return
        end

        local function answer_to_requests()
            while true do
                local message_data = luxnet.receive("sgbook")
                if message_data == nil then
                    error("No message received with no timeout")
                end
                if message_data.distance < 50 then
                    if message_data.message[1] == "dial" then
                        local address = message_data.message[2]
                        print_color(colors.lime, "> Calling "..address)
                        sg.dial(address)
                    elseif message_data.message[1] == "hang" then
                        print_color(colors.orange, "> Disconnecting")
                        sg.disconnect()
                    elseif message_data.message[1] == "ping" then
                        print_color(colors.blue, "> Sharing address")
                        luxnet.broadcast({"pong", sg.localAddress()}, "sgbook")
                    else
                        print_color(colors.orange, "Unknown message: '"..textutils.serialise(message_data.message).."'")
                    end
                end
            end
        end

        local function broadcast_stargate_state()
            while true do
                local event = {coroutine.yield()}
                if event[1] == "terminate" then
                    return
                elseif event[1] == "sgStargateStateChange" and event[2] == stargate_side then
                    print_color(colors.purple, "> Stargate state changed to '"..event[3].."'")
                    luxnet.broadcast({"state", event[3]}, "sgbook")
                else
                    -- print("Received event: "..textutils.serialise(event))
                end
            end
        end

        print_color(colors.yellow, "> Managing stargate on "..stargate_side)

        parallel.waitForAny(answer_to_requests, broadcast_stargate_state)
    else
        print_usage()
        return
    end
end