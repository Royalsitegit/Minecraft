-- =========================================================
-- MEKANISM FISSION REACTOR - REACTOR SIDE
--
-- BACK  = Fission Reactor Logic Adapter
-- RIGHT = Ender Modem
--
-- WARNING: coolant < 30%
-- SCRAM:   coolant < 20%
-- RESET:   coolant >= 25%
--
-- SAFETY LOOP IS COMPLETELY INDEPENDENT
-- OF THE MODEM / CONTROL ROOM.
-- =========================================================

local reactor = peripheral.wrap("back")
local modem = peripheral.wrap("right")

if not reactor then
    error("No Fission Reactor Logic Adapter on BACK")
end

if not modem then
    error("No Ender Modem on RIGHT")
end

local REACTOR_CHANNEL = 1234

local WARNING_LEVEL = 0.30
local TRIP_LEVEL = 0.20
local RESET_LEVEL = 0.25

local MIN_BURN = 0.01

local STATE_FILE = "reactor_safety.state"

modem.open(REACTOR_CHANNEL)

-- =========================================================
-- SAFETY STATE
-- =========================================================

local safetyTrip = false
local tripReason = "NONE"
local scramConfirmed = false

local function saveState()
    local f = fs.open(STATE_FILE, "w")

    if f then
        f.writeLine(safetyTrip and "1" or "0")
        f.writeLine(tripReason or "NONE")
        f.close()
    end
end

local function loadState()
    if not fs.exists(STATE_FILE) then
        return
    end

    local f = fs.open(STATE_FILE, "r")

    if not f then
        return
    end

    safetyTrip = f.readLine() == "1"
    tripReason = f.readLine() or "NONE"

    f.close()
end

loadState()

-- =========================================================
-- HELPERS
-- =========================================================

local function round2(value)
    return math.floor(value * 100 + 0.5) / 100
end

local function clampBurn(value)
    local maximum = reactor.getMaxBurnRate()

    value = math.max(MIN_BURN, value)
    value = math.min(maximum, value)

    return round2(value)
end

local function readCoolant()
    local ok, value =
        pcall(
            reactor.getCoolantFilledPercentage
        )

    if ok and type(value) == "number" then
        return value
    end

    return nil
end

local function safeOptional(name)
    local fn = reactor[name]

    if type(fn) ~= "function" then
        return nil
    end

    local ok, value = pcall(fn)

    if ok then
        return value
    end

    return nil
end

-- =========================================================
-- LATCH TRIP
-- =========================================================

local function latchTrip(reason, coolant)
    if not safetyTrip then
        safetyTrip = true
        tripReason = reason
        scramConfirmed = false

        saveState()

        print("")
        print("================================")
        print("!!! REACTOR SAFETY TRIP !!!")
        print("Reason: " .. tostring(reason))

        if coolant then
            print(
                "Coolant: " ..
                string.format(
                    "%.2f%%",
                    coolant * 100
                )
            )
        end

        print("================================")
    end
end

-- =========================================================
-- SCRAM AND KEEP SCRAMMING
--
-- Important:
-- We NEVER crash the safety program if SCRAM fails.
-- It keeps trying until getStatus() says OFF.
-- =========================================================

local function enforceShutdown()
    if not reactor.getStatus() then

        if safetyTrip and not scramConfirmed then
            scramConfirmed = true
            print("SCRAM CONFIRMED - REACTOR OFF")
        end

        return
    end

    local ok, err =
        pcall(
            reactor.scram
        )

    if not ok then
        print(
            "SCRAM RETRY: " ..
            tostring(err)
        )
    end
end

-- =========================================================
-- SAFETY CHECK
--
-- Notice there is NO:
--
-- if not reactor.getStatus() then return end
--
-- Low coolant itself creates the latch.
-- =========================================================

local function safetyCheck()
    local coolant = readCoolant()

    if coolant == nil then

        if reactor.getStatus() then
            latchTrip(
                "COOLANT SENSOR ERROR",
                nil
            )

            enforceShutdown()
        end

        return
    end

    -- HARD LOW COOLANT TRIP
    if coolant < TRIP_LEVEL then

        latchTrip(
            "LOW COOLANT",
            coolant
        )

        enforceShutdown()

        return
    end

    -- A latched reactor must NEVER be running.
    if safetyTrip then
        enforceShutdown()
    end
end

-- =========================================================
-- TELEMETRY
-- =========================================================

local function getTelemetry()
    local coolant =
        readCoolant() or 0

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
            coolant,

        waste =
            reactor.getWasteFilledPercentage(),

        heated =
            safeOptional(
                "getHeatedCoolant"
            ),

        heatedPercent =
            safeOptional(
                "getHeatedCoolantFilledPercentage"
            ),

        heatedNeeded =
            safeOptional(
                "getHeatedCoolantNeeded"
            ),

        safetyTrip =
            safetyTrip,

        tripReason =
            tripReason,

        scramConfirmed =
            scramConfirmed,

        warningLevel =
            WARNING_LEVEL,

        tripLevel =
            TRIP_LEVEL,

        resetLevel =
            RESET_LEVEL
    }
end

local function sendStatus(replyChannel)
    modem.transmit(
        replyChannel,
        REACTOR_CHANNEL,
        getTelemetry()
    )
end

-- =========================================================
-- BURN RATE
-- =========================================================

local function changeBurn(amount)
    local current =
        reactor.getBurnRate()

    reactor.setBurnRate(
        clampBurn(
            current + amount
        )
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
        sendStatus(replyChannel)
        return
    end

    -- BURN DOWN
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

    -- BURN UP
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

    -- DIRECT SET
    elseif string.sub(
        command,
        1,
        4
    ) == "SET:" then

        local rate =
            tonumber(
                string.sub(
                    command,
                    5
                )
            )

        if rate then
            reactor.setBurnRate(
                clampBurn(rate)
            )
        end

    -- =====================================================
    -- RESET SAFETY
    -- =====================================================

    elseif command == "RESET_SAFETY" then

        local coolant =
            readCoolant()

        if reactor.getStatus() then

            print(
                "RESET BLOCKED - REACTOR RUNNING"
            )

        elseif not coolant then

            print(
                "RESET BLOCKED - NO COOLANT READING"
            )

        elseif coolant < RESET_LEVEL then

            print(
                "RESET BLOCKED - COOLANT " ..
                string.format(
                    "%.2f%%",
                    coolant * 100
                )
            )

        else

            safetyTrip = false
            tripReason = "NONE"
            scramConfirmed = false

            saveState()

            print("")
            print("SAFETY RESET")
            print(
                "Coolant: " ..
                string.format(
                    "%.2f%%",
                    coolant * 100
                )
            )
        end

    -- =====================================================
    -- REACTOR ON
    -- =====================================================

    elseif command == "ON" then

        local coolant =
            readCoolant()

        if safetyTrip then

            print(
                "START BLOCKED - SAFETY TRIP LATCHED"
            )

        elseif not coolant then

            latchTrip(
                "COOLANT SENSOR ERROR"
            )

        elseif coolant < RESET_LEVEL then

            print(
                "START BLOCKED - COOLANT BELOW 25%"
            )

        elseif not reactor.getStatus() then

            reactor.activate()

            print("")
            print("REACTOR ACTIVATED")
        end

    -- =====================================================
    -- MANUAL SCRAM
    -- =====================================================

    elseif command == "OFF" then

        if reactor.getStatus() then
            reactor.scram()
        end

        print("")
        print("MANUAL SCRAM REQUESTED")
    end

    -- Always run safety after ANY command.
    safetyCheck()

    sendStatus(replyChannel)
end

-- =========================================================
-- DEDICATED SAFETY LOOP
--
-- Completely independent from modem traffic.
-- =========================================================

local function safetyLoop()
    while true do
        safetyCheck()

        -- 20 safety checks per second
        sleep(0.05)
    end
end

-- =========================================================
-- MODEM LOOP
-- =========================================================

local function modemLoop()
    while true do
        local event,
              side,
              channel,
              replyChannel,
              command,
              distance =
            os.pullEvent(
                "modem_message"
            )

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

-- =========================================================
-- STARTUP
-- =========================================================

print("")
print("Fission Reactor Safety Controller")
print("---------------------------------")
print("Channel: " .. REACTOR_CHANNEL)
print("WARNING: coolant < 30%")
print("SCRAM:   coolant < 20%")
print("RESET:   coolant >= 25%")
print("Safety scan: 20 checks/sec")

local startupCoolant =
    readCoolant()

if startupCoolant then
    print(
        "Current coolant: " ..
        string.format(
            "%.2f%%",
            startupCoolant * 100
        )
    )
end

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

-- Check immediately before loops start.
safetyCheck()

-- Run both systems independently forever.
parallel.waitForAll(
    safetyLoop,
    modemLoop
)
