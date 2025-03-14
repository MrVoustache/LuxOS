--[[
The template for a LuxOS app.

A LuxOS application file is a lua script file that returns an Application object. It must not run the application when executed.
When LuxOS starts the application, it will execute this file, retrieve the Application object and run its main functions with the arguments passed through the command line.
Here is an example of an echo application:

local function main(...)
    print(...)
end

local app = Application:new{"echo", main}

return app
]]





---@class Application The interface for an application.
---@field name string The application name.
---@field main function The application entry point. This function receives as argument the paramters passed to the command line (one string argument each).
---@field autocomplete function An autocompletion function for when typing a command with the application as first keyword. Arguments received are the different words in the command line being written. Returns a list of possible strings to complete the current word.
---@field services Service[] A list of services declared by the application.
local Application = {}
_G.Application = Application

Application.__index =  Application
Application.__name = "Application"





---A dummy autocomplete function that does not return anything.
local function dummy_autocomplete(...)
    return {}
end





---Creates a new Application object
---@param name string The application name.
---@param main function The application main function.
---@return Application app The new application object.
function Application:new(name, main)
    local app = {}
    setmetatable(app, self)
    if type(name) ~= "string" then
        error("bad argument #1: string expected, got '"..type(name).."'", 2)
    end
    if type(main) ~= "function" then
        error("bag argument #2: function expected, got '"..type(main).."'", 2)
    end
    app.name = name
    app.main = main
    app.services = {}
    app.autocomplete = dummy_autocomplete
    return app
end





---Starts the application.
---@param ... string The arguments for the application.
function Application:__call(...)
    return self.main(...)
end