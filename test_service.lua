local running = false

local function start()
    services.log("Starting test service.")
    running = true
end

local function stop()
    services.log("Stopping test service.")
    running = false
end

local function main()
    while running do
        sleep(10)
        luxnet.broadcast("Hello!")
    end
end





return services.Service:new(
    "test service",
    start,
    main,
    stop
)