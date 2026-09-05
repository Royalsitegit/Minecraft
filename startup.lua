-- =========================================================
-- MEKANISM FISSION REACTOR - REACTOR SIDE
--
-- BACK  = Fission Reactor Logic Adapter
-- RIGHT = Ender Modem
--
-- LOCAL SAFETY:
-- Coolant below 10% while running = automatic SCRAM
-- Manual restart required after a safety trip
-- =========================================================

local reactor = peripheral.wrap("back")
local modem = peripheral.wrap("right")

local REACTOR_CHANNEL = 1234

local COOLANT_TRIP_LEVEL = 0.10
local MIN_BURN_RATE = 0.01

modem.open(REACTOR_CHANNEL)

local safetyTrip = false
local tripReason = "NONE"

-- =========================================================
-- HELPERS
-- =========================================================

local function roundBurn(value)
    return math.floor((value * 100) + 0.5) / 100
end

local function clampBurn(value)
    local maxBurn = reactor.getMaxBurnRate()

    value = math.max(MIN_BURN_RATE, value)
    value = math.min(maxBurn, value)

    return roundBurn(value)
end

local function getStatus()
    local heated = nil
    local heatedPercent = nil
    local heatedNeeded = nil

    -- These are protected so a telemetry method mismatch
    -- cannot kill the reactor safety program.
    pcall(function()
        heated = reactor.getHeatedCoolant()
    end)

    pcall(function()
        heatedPercent = reactor.getHeatedCoolantFilledPercentage()
    end)

    pcall(function()
        heatedNeeded = reactor.getHeatedCoolantNeeded()
    end)

    return {
        status = reactor.getStatus(),

        burn = reactor.getBurnRate(),
        actual = reactor.getActualBurnRate(),
        max = reactor.getMaxBurnRate(),

        temp = reactor.getTemperature(),
        damage = reactor.getDamagePercent(),

        fuel = reactor.getFuelFilledPercentage(),
        coolant = reactor.getCoolantFilledPercentage(),

        heated = heated,
        heatedPercent = heatedPercent,
        heatedNeeded = heatedNeeded,

        waste = reactor.getWasteFilledPercentage(),

        safetyTrip = safetyTrip,
        tripReason = tripReason,
        coolantTripLevel = COOLANT_TRIP_LEVEL
    }
end

local function send(replyChannel)
    modem.transmit(
        replyChannel,
        REACTOR_CHANNEL,
        getStatus()
    )
end

-- =========================================================
-- LOCAL SAFETY SYSTEM
-- =========================================================

local function safetyCheck()
    local running = reactor.getStatus()
    local coolant = reactor.getCoolantFilledPercentage()

    if running and coolant < COOLANT_TRIP_LEVEL then

        safetyTrip = true
        tripReason = "LOW COOLANT"

        reactor.scram()

        print("!!! SAFETY SCRAM !!!")
        print("Reason: LOW COOLANT")
        print(
            "Coolant: " ..
            string.format("%.1f%%", coolant * 100)
        )
    end
end

-- =========================================================
-- COMMAND HANDLER
-- =========================================================

local function changeBurn(amount)
    local current = reactor.getBurnRate()
    local newRate = clampBurn(current + amount)

    reactor.setBurnRate(newRate)
end

local function handleCommand(msg, replyChannel)

    if msg == "STATUS" then
        send(replyChannel)
        return
    end

    -- -----------------------------------------------------
    -- FINE CONTROL
    -- -----------------------------------------------------

    if msg == "DOWN_001" then
        changeBurn(-0.01)

    elseif msg == "UP_001" then
        changeBurn(0.01)

    -- -----------------------------------------------------
    -- +/- 1
    -- -----------------------------------------------------

    elseif msg == "DOWN_1" then
        changeBurn(-1)

    elseif msg == "UP_1" then
        changeBurn(1)

    -- -----------------------------------------------------
    -- +/- 2
    -- -----------------------------------------------------

    elseif msg == "DOWN_2" then
        changeBurn(-2)

    elseif msg == "UP_2" then
        changeBurn(2)

    -- -----------------------------------------------------
    -- +/- 5
    -- -----------------------------------------------------

    elseif msg == "DOWN_5" then
        changeBurn(-5)

    elseif msg == "UP_5" then
        changeBurn(5)

    -- -----------------------------------------------------
    -- +/- 10
    -- -----------------------------------------------------

    elseif msg == "DOWN_10" then
        changeBurn(-10)

    elseif msg == "UP_10" then
        changeBurn(10)

    -- -----------------------------------------------------
    -- DIRECT SET
    -- Kept for future multi-reactor/control features
    -- -----------------------------------------------------

    elseif string.sub(msg, 1, 4) == "SET:" then

        local rate = tonumber(string.sub(msg, 5))

        if rate then
            reactor.setBurnRate(
                clampBurn(rate)
            )
        end

    -- -----------------------------------------------------
    -- REACTOR ON
    -- -----------------------------------------------------

    elseif msg == "ON" then

        local coolant =
            reactor.getCoolantFilledPercentage()

        -- A reactor may NOT be started below 10% coolant.
        if coolant < COOLANT_TRIP_LEVEL then

            safetyTrip = true
            tripReason = "LOW COOLANT"

        else

            -- Manual ON clears an old trip,
            -- but ONLY if coolant is now safe.
            safetyTrip = false
            tripReason = "NONE"

            if not reactor.getStatus() then
                reactor.activate()
            end
        end

    -- -----------------------------------------------------
    -- REACTOR OFF / SCRAM
    -- -----------------------------------------------------

    elseif msg == "OFF" then

        if reactor.getStatus() then
            reactor.scram()
        end
    end

    safetyCheck()
    send(replyChannel)
end

-- =========================================================
-- STARTUP
-- =========================================================

print("Fission Reactor Controller")
print("Channel: " .. REACTOR_CHANNEL)
print("Coolant SCRAM: < 10%")
print("Safety system ACTIVE")

-- =========================================================
-- MAIN LOOP
--
-- Timer means safety checks continue even if the
-- control-room computer or wireless modem disappears.
-- =========================================================

local safetyTimer = os.startTimer(0.25)

while true do

    local event,
          p1,
          p2,
          p3,
          p4,
          p5 = os.pullEvent()

    if event == "timer" and p1 == safetyTimer then

        safetyCheck()

        safetyTimer = os.startTimer(0.25)

    elseif event == "modem_message" then

        local channel = p2
        local replyChannel = p3
        local msg = p4

        if
            channel == REACTOR_CHANNEL and
            type(msg) == "string"
        then
            handleCommand(
                msg,
                replyChannel
            )
        end
    end
end
