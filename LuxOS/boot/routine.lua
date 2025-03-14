--[[
This routine ensures that LuxOS will boot successfully.
]]

-- while true do print(textutils.serialize({os.pullEvent()})) end





local WATCH_KEYS = {keys.s, keys.r}
local CTRL_LEFT = keys.leftCtrl
local CTRL_RIGHT = keys.rightCtrl
local BOOT_SEQUENCE = {"LuxOS/main.lua"}
local BOOT_FOLDER = "LuxOS/boot/boot_files"
local BOOT_FILE = "LuxOS/boot/boot.txt"
local BOOT_FS_STRUCTURE = kernel.filesystem_structure{

    kernel.filesystem_node{
        name = "LuxOS",
        type = kernel.DIRECTORY,
        children = {

            kernel.filesystem_node{
                name = "boot",
                type = kernel.DIRECTORY,
                children = {

                    kernel.filesystem_node{
                        name = "routine.lua",
                        type = kernel.FILE
                    },

                    kernel.filesystem_node{
                        name = "lib.lua",
                        type = kernel.FILE
                    },

                    kernel.filesystem_node{
                        name = "boot_files",
                        type = kernel.DIRECTORY,
                        mode = kernel.DIRECTORY.ENSURE_EXISTS
                    }
                    
                }
            }
        }
    }

}
local settings_set = settings.set
local settings_save = settings.save
local open = fs.open
local last_save = -math.huge





local function save_boot_file()
    local f = kernel.panic_pcall("fs.open", fs.open, BOOT_FILE, "w")
    for _, file in ipairs(BOOT_SEQUENCE) do
        f.write(file.."\n")
    end
    f.close()
end

local function load_boot_sequence()
    if not kernel.panic_pcall("fs.exists", fs.exists, BOOT_FILE) then
        boot.set_boot_sequence("LuxOS/main.lua")
    else
        local f = kernel.panic_pcall("fs.open", fs.open, BOOT_FILE, "r")
        BOOT_SEQUENCE = {}
        local line = " "
        while line do
            line = f.readLine()
            if line then
                line = string.gsub(line, "\n", "")
                table.insert(BOOT_SEQUENCE, line)
            end
        end
        f.close()
    end
end

local function ensure_boot(force)
    if force or os.time() - last_save > 0.01 then
        settings_set("shell.allow_startup", true)
        settings_set("shell.allow_disk_startup", false)
        settings_save(".settings")
        local f = open("startup", "w")
        for _, file in ipairs(BOOT_SEQUENCE) do
            kernel.panic_pcall("file.write", f.write, "dofile('"..BOOT_FOLDER.."/"..kernel.panic_pcall("fs.getName", fs.getName, file).."')\n")
        end
        f.close()
        last_save = os.time()
    end
end

local function answer_calls_to_get_boot_sequence(...)
    local args = {...}
    if #args > 0 then
        return false, "syscall got "..tostring(#args).." parameters, expected 0"
    else
        local res = {}
        for _, file in ipairs(BOOT_SEQUENCE) do
            table.insert(res, file)
        end
        return true, res
    end
end

local function answer_calls_to_set_boot_sequence(...)
    local args = {...}
    for index, file in ipairs(args) do
        if type(file) ~= "string" then
            return false, "bad argument #"..tostring(index)..": expected string, got '"..type(file).."'"
        end
    end
    for index, file in ipairs(args) do
        if not kernel.panic_pcall("fs.exists", fs.exists, file) then
            return false, "given file does not exist: '"..file.."'"
        end
    end
    for index, file in ipairs(args) do
        if kernel.panic_pcall("fs.isDir", fs.isDir, file) then
            return false, "given file is a directory: '"..file.."'"
        end
    end
    for index, file in ipairs(args) do
        local ok, err = loadfile(file, os.create_user_environment())
        if not ok then
            return false, "given file '"..file.."' could be loaded: "..err
        end
    end
    for index, file in ipairs(kernel.panic_pcall("fs.list", fs.list, BOOT_FOLDER)) do
        kernel.panic_pcall("fs.delete", fs.delete, BOOT_FOLDER.."/"..file)
    end
    for index, file in ipairs(args) do
        kernel.panic_pcall("fs.copy", fs.copy, file, BOOT_FOLDER.."/"..kernel.panic_pcall("fs.getName", fs.getName, file))
    end
    BOOT_SEQUENCE = args
    save_boot_file()
    ensure_boot(true)
    return true
end





local function main()

    kernel.validate_filesystem_structure(BOOT_FS_STRUCTURE)

    syscall.affect_routine(boot.get_boot_sequence, answer_calls_to_get_boot_sequence)
    syscall.affect_routine(boot.set_boot_sequence, answer_calls_to_set_boot_sequence)

    kernel.panic_pcall("load_boot_sequence", load_boot_sequence)

    local ctrl_left = false
    local ctrl_right = false

    kernel.panic_pcall("ensure_boot", ensure_boot)

    kernel.mark_routine_ready()

    while true do
        local event = {coroutine.yield()}
        if kernel.is_system_shutting_down() then
            break
        end
        if event[1] == "key" then
            local key = event[2]
            if key == CTRL_LEFT then
                ctrl_left = true
            elseif key == CTRL_RIGHT then
                ctrl_right = true
            elseif ctrl_left or ctrl_right then
                for _, k in ipairs(WATCH_KEYS) do
                    if k == key then
                        kernel.panic_pcall("ensure_boot", ensure_boot)
                    end
                end
            end
        elseif event[1] == "key_up" then
            local key = event[2]
            if key == CTRL_LEFT then
                ctrl_left = false
            elseif key == CTRL_RIGHT then
                ctrl_right = false
            end
        end
    end

    kernel.panic_pcall("ensure_boot", ensure_boot, true)

    kernel.mark_routine_offline()

end

return main