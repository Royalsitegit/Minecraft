-- =========================================================
-- MEKANISM FISSION REACTOR - REACTOR SIDE
--
-- BACK  = Fission Reactor Logic Adapter
-- RIGHT = Ender Modem
--
-- LOCAL SAFETY SYSTEM
-- Warning:       coolant < 20%
-- SCRAM:         coolant < 10%
-- Reset allowed: coolant >= 15%
--
-- Safety trip is LATCHED and saved to disk.
-- =========================================================

local reactor = peripheral.wrap("back")
local modem = peripheral.wrap("right")

if not reactor then
    error("No reactor logic adapter found on BACK")
end

if not modem then
    error("No modem found on RIGHT")
end

local REACTOR_CHANNEL = 1234

local COOLANT_WARNING = 0.20
local COOLANT_TRIP = 0.10
local COOLANT_RESET = 0.15

local MIN_BURN = 0.01

local STATE_FILE = "reactor_safety.state"

modem.open(REACTOR_CHANNEL)

-- =========================================================
-- SAFETY STATE
-- =========================================================

local safetyTrip = false
local tripReason = "NONE"

local function saveSafetyState()

    local file = fs.open(
        STATE_FILE,
        "w"
    )

    if file then
        file.writeLine(
            safetyTrip and
            "1" or
            "0"
        )

        file.writeLine(
            tripReason or
            "NONE"
        )

        file.close()
    end
end

local function loadSafetyState()

    if not fs.exists(STATE_FILE) then
        return
    end

    local file =
        fs.open(
            STATE_FILE,
            "r"
        )

    if not file then
        return
    end

    local tripped =
        file.readLine()

    local reason =
        file.readLine()

    file.close()

    safetyTrip =
        tripped == "1"

    tripReason =
        reason or "NONE"
end

loadSafetyState()

-- =========================================================
-- HELPERS
-- =========================================================

local function round2(value)

    return math.floor(
        value * 100 + 0.5
    ) / 100
end

local function clampBurn(value)

    local maximum =
        reactor.getMaxBurnRate()

    value =
        math.max(
            MIN_BURN,
            value
        )

    value =
        math.min(
            maximum,
            value
        )

    return round2(value)
end

local function getCoolant()

    local ok, value =
        pcall(
            reactor.getCoolantFilledPercentage
        )

    if ok and type(value) == "number" then
        return value
    end

    return nil
end

local function trip(reason)

    if reactor.getStatus() then

        pcall(
            reactor.scram
        )
    end

    safetyTrip = true
    tripReason = reason

    saveSafetyState()

    print("")
    print("!!! REACTOR SAFETY TRIP !!!")
    print("Reason: " .. tostring(reason))
end

-- =========================================================
-- LOCAL SAFETY CHECK
-- =========================================================

local function safetyCheck()

    if not reactor.getStatus() then
        return
    end

    local coolant =
        getCoolant()

    -- Sensor/read failure while running = fail-safe shutdown
    if coolant == nil then

        trip(
            "COOLANT SENSOR ERROR"
        )

        return
    end

    if coolant < COOLANT_TRIP then

        trip(
            "LOW COOLANT"
        )

        print(
            "Coolant: " ..
            string.format(
                "%.2f%%",
                coolant * 100
            )
        )
    end
end

-- =========================================================
-- OPTIONAL HEATED COOLANT DATA
-- =========================================================

local function safeCall(methodName)

    local method =
        reactor[methodName]

    if type(method) ~= "function" then
        return nil
    end

    local ok, value =
        pcall(method)

    if ok then
        return value
    end

    return nil
end

-- =========================================================
-- TELEMETRY
-- =========================================================

local function getStatus()

    local coolant =
        getCoolant()

    return {

        status =
            reactor.getStatus(),

        burn =
            reactor.getBurnRate(),

        actual =
            reactor.getActualBurnRate(),

        max =
            reactor.getMaxBurnRate(),

        temp =
            reactor.getTemperature(),

        damage =
            reactor.getDamagePercent(),

        fuel =
            reactor.getFuelFilledPercentage(),

        coolant =
            coolant or 0,

        waste =
            reactor.getWasteFilledPercentage(),

        heated =
            safeCall(
                "getHeatedCoolant"
            ),

        heatedPercent =
            safeCall(
                "getHeatedCoolantFilledPercentage"
            ),

        heatedNeeded =
            safeCall(
                "getHeatedCoolantNeeded"
            ),

        safetyTrip =
            safetyTrip,

        tripReason =
            tripReason,

        warningLevel =
            COOLANT_WARNING,

        tripLevel =
            COOLANT_TRIP,

        resetLevel =
            COOLANT_RESET
    }
end

local function sendStatus(replyChannel)

    modem.transmit(
        replyChannel,
        REACTOR_CHANNEL,
        getStatus()
    )
end

-- =========================================================
-- BURN RATE
-- =========================================================

local function changeBurn(amount)

    local current =
        reactor.getBurnRate()

    local target =
        clampBurn(
            current + amount
        )

    reactor.setBurnRate(
        target
    )
end

-- =========================================================
-- COMMAND HANDLER
-- =========================================================

local function handleCommand(
    command,
    replyChannel
)

    if command == "STATUS" then

        sendStatus(
            replyChannel
        )

        return
    end

    -- -----------------------------------------------------
    -- BURN DOWN
    -- -----------------------------------------------------

    if command == "DOWN_001" then

        changeBurn(-0.01)

    elseif command == "DOWN_1" then

        changeBurn(-1)

    elseif command == "DOWN_2" then

        changeBurn(-2)

    elseif command == "DOWN_5" then

        changeBurn(-5)

    elseif command == "DOWN_10" then

        changeBurn(-10)

    -- -----------------------------------------------------
    -- BURN UP
    -- -----------------------------------------------------

    elseif command == "UP_001" then

        changeBurn(0.01)

    elseif command == "UP_1" then

        changeBurn(1)

    elseif command == "UP_2" then

        changeBurn(2)

    elseif command == "UP_5" then

        changeBurn(5)

    elseif command == "UP_10" then

        changeBurn(10)

    -- -----------------------------------------------------
    -- DIRECT SET - retained for future reactor pages
    -- -----------------------------------------------------

    elseif string.sub(
        command,
        1,
        4
    ) == "SET:" then

        local value =
            tonumber(
                string.sub(
                    command,
                    5
                )
            )

        if value then

            reactor.setBurnRate(
                clampBurn(value)
            )
        end

    -- -----------------------------------------------------
    -- RESET SAFETY
    -- -----------------------------------------------------

    elseif command == "RESET_SAFETY" then

        local coolant =
            getCoolant()

        if
            not reactor.getStatus() and
            coolant and
            coolant >= COOLANT_RESET
        then

            safetyTrip = false
            tripReason = "NONE"

            saveSafetyState()

            print("")
            print("Safety trip RESET")

        end

    -- -----------------------------------------------------
    -- REACTOR ON
    -- -----------------------------------------------------

    elseif command == "ON" then

        local coolant =
            getCoolant()

        if safetyTrip then

            print(
                "START BLOCKED: safety trip active"
            )

        elseif not coolant then

            trip(
                "COOLANT SENSOR ERROR"
            )

        elseif coolant < COOLANT_RESET then

            print(
                "START BLOCKED: coolant below 15%"
            )

        elseif not reactor.getStatus() then

            reactor.activate()

            print("")
            print("Reactor ACTIVATED")

        end

    -- -----------------------------------------------------
    -- NORMAL OFF / SCRAM
    -- -----------------------------------------------------

    elseif command == "OFF" then

        if reactor.getStatus() then

            reactor.scram()

            print("")
            print("Reactor SCRAMMED manually")
        end
    end

    safetyCheck()

    sendStatus(
        replyChannel
    )
end

-- =========================================================
-- STARTUP DISPLAY
-- =========================================================

print("")
print("Fission Reactor Controller")
print("--------------------------")
print(
    "Channel: " ..
    REACTOR_CHANNEL
)

print(
    "Warning: coolant < 20%"
)

print(
    "SCRAM: coolant < 10%"
)

print(
    "Reset: coolant >= 15%"
)

if safetyTrip then

    print("")
    print("SAFETY TRIP LATCHED")
    print(
        "Reason: " ..
        tostring(tripReason)
    )

else

    print("")
    print("Safety system ARMED")
end

-- =========================================================
-- MAIN LOOP
-- =========================================================

local safetyTimer =
    os.startTimer(0.25)

while true do

    local event,
          p1,
          p2,
          p3,
          p4,
          p5 =
        os.pullEvent()

    if
        event == "timer" and
        p1 == safetyTimer
    then

        safetyCheck()

        safetyTimer =
            os.startTimer(0.25)

    elseif event == "modem_message" then

        local channel =
            p2

        local replyChannel =
            p3

        local command =
            p4

        if
            channel == REACTOR_CHANNEL and
            type(command) == "string"
        then

            handleCommand(
                command,
                replyChannel
            )
        end
    end
end
