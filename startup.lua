-- =========================================================
-- MEKANISM FISSION REACTOR - REACTOR SIDE
--
-- BACK  = Fission Reactor Logic Adapter
-- RIGHT = Ender Modem
--
-- SAFETY:
-- Warning below 30%
-- HARD SCRAM below 20%
-- Reset permitted at 25%+
--
-- Trip is latched and survives reboot.
-- =========================================================

local reactor = peripheral.wrap("back")
local modem = peripheral.wrap("right")

if not reactor then
    error("No reactor logic adapter found on BACK")
end

if not modem then
    error("No Ender Modem found on RIGHT")
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
local lastCoolant = 0
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

local function round2(n)
    return math.floor(n * 100 + 0.5) / 100
end

local function getCoolant()
    local value = reactor.getCoolantFilledPercentage()

    if type(value) ~= "number" then
        error("Invalid coolant reading")
    end

    lastCoolant = value

    return value
end

local function clampBurn(value)
    local maxBurn = reactor.getMaxBurnRate()

    value = math.max(MIN_BURN, value)
    value = math.min(maxBurn, value)

    return round2(value)
end

local function safeOptional(methodName)
    local fn = reactor[methodName]

    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn)

    if ok then
        return result
    end

    return nil
end

-- =========================================================
-- HARD SCRAM
-- =========================================================

local function hardScram(reason)
    safetyTrip = true
    tripReason = reason
    scramConfirmed = false

    saveState()

    print("")
    print("!!!!!!!!!!!!!!!!!!!!!!!!")
    print("!!! REACTOR SAFETY !!!")
    print("TRIP: " .. tostring(reason))
    print(
        "Coolant: " ..
        string.format("%.2f%%", lastCoolant * 100)
    )
    print("!!!!!!!!!!!!!!!!!!!!!!!!")

    -- IMPORTANT:
    -- Do NOT silently hide a failed SCRAM.
    if reactor.getStatus() then

        print("Sending SCRAM...")

        reactor.scram()

        sleep(0.05)
    end

    -- Verify shutdown.
    if not reactor.getStatus() then
        scramConfirmed = true
        print("SCRAM CONFIRMED - REACTOR OFF")
        return
    end

    -- Retry aggressively if it did not stop.
    print("WARNING: First SCRAM did not confirm.")
    print("Retrying...")

    for attempt = 1, 10 do

        if not reactor.getStatus() then
            scramConfirmed = true
            print(
                "SCRAM CONFIRMED on retry " ..
                attempt
            )
            return
        end

        reactor.scram()

        sleep(0.05)
    end

    -- If this happens we WANT a loud error.
    -- Never silently pretend the reactor stopped.
    error(
        "CRITICAL: REACTOR FAILED TO SCRAM"
    )
end

-- =========================================================
-- SAFETY CHECK
-- =========================================================

local function safetyCheck()
    if not reactor.getStatus() then
        return
    end

    local ok, coolant =
        pcall(getCoolant)

    if not ok then
        hardScram(
            "COOLANT SENSOR ERROR"
        )
        return
    end

    if coolant < TRIP_LEVEL then
        hardScram(
            "LOW COOLANT"
        )
    end
end

-- =========================================================
-- TELEMETRY
-- =========================================================

local function getStatus()
    local coolant

    local ok, result =
        pcall(getCoolant)

    if ok then
        coolant = result
    else
        coolant = 0
    end

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
        getStatus()
    )
end

-- =========================================================
-- BURN RATE
-- =========================================================

local function changeBurn(amount)
    local target =
        clampBurn(
            reactor.getBurnRate() +
            amount
        )

    reactor.setBurnRate(target)
end

-- =========================================================
-- COMMAND HANDLER
-- =========================================================

local function handleCommand(command, replyChannel)

    if command == "STATUS" then
        sendStatus(replyChannel)
        return
    end

    -- Burn controls
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

    -- Future direct-set support
    elseif string.sub(command, 1, 4) == "SET:" then

        local rate =
            tonumber(
                string.sub(command, 5)
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
            getCoolant()

        if reactor.getStatus() then

            print(
                "RESET BLOCKED: reactor is running"
            )

        elseif coolant < RESET_LEVEL then

            print(
                "RESET BLOCKED: coolant " ..
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
    -- ON
    -- =====================================================

    elseif command == "ON" then

        local coolant =
            getCoolant()

        if safetyTrip then

            print(
                "START BLOCKED: safety trip latched"
            )

        elseif coolant < RESET_LEVEL then

            print(
                "START BLOCKED: coolant below 25%"
            )

        elseif not reactor.getStatus() then

            reactor.activate()

            print("")
            print("REACTOR ACTIVATED")

            -- Check immediately after activation.
            sleep(0.05)
            safetyCheck()
        end

    -- =====================================================
    -- MANUAL SCRAM
    -- =====================================================

    elseif command == "OFF" then

        if reactor.getStatus() then

            reactor.scram()

            sleep(0.05)

            if reactor.getStatus() then
                error(
                    "Manual SCRAM failed"
                )
            end

            print("")
            print("MANUAL SCRAM CONFIRMED")
        end
    end

    safetyCheck()

    sendStatus(replyChannel)
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
    os.startTimer(0.10)

while true do

    local event,
          p1,
          p2,
          p3,
          p4 =
        os.pullEvent()

    if
        event == "timer" and
        p1 == safetyTimer
    then

        safetyCheck()

        safetyTimer =
            os.startTimer(0.10)

    elseif event == "modem_message" then

        local channel =
            p2

        local replyChannel =
            p3

        local command =
            p4

        if
            channel ==
            REACTOR_CHANNEL and
            type(command) ==
            "string"
        then

            handleCommand(
                command,
                replyChannel
            )
        end
    end
end
