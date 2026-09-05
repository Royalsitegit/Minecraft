-- =========================================================
-- MEKANISM FISSION REACTOR CONTROL ROOM
--
-- TOP  = Ender Modem
-- BACK = Advanced Monitor
--
-- Reactor 1
-- Future multi-reactor page system can be added later.
-- =========================================================

local modem = peripheral.wrap("top")
local monitor = peripheral.wrap("back")

if not modem then
    error("No modem found on TOP")
end

if not monitor then
    error("No monitor found on BACK")
end

local REACTOR_CHANNEL = 1234
local CONTROL_CHANNEL = 4321

modem.open(CONTROL_CHANNEL)

monitor.setTextScale(0.5)

local w, h = monitor.getSize()

local data = nil
local lastReply = 0

local buttons = {}

local scramArmed = false
local scramUntil = 0

local flashOn = true

-- =========================================================
-- DRAWING HELPERS
-- =========================================================

local function writeAt(x, y, text, fg, bg)
    if bg then
        monitor.setBackgroundColor(bg)
    end

    if fg then
        monitor.setTextColor(fg)
    end

    monitor.setCursorPos(x, y)
    monitor.write(tostring(text))
end

local function centre(y, text, fg, bg)
    local x = math.floor((w - #text) / 2) + 1
    writeAt(x, y, text, fg, bg)
end

local function fill(x1, y1, x2, y2, colour)
    monitor.setBackgroundColor(colour)

    for y = y1, y2 do
        monitor.setCursorPos(x1, y)
        monitor.write(string.rep(" ", x2 - x1 + 1))
    end
end

local function button(name, x1, y1, x2, y2, label, bg, fg)
    fill(x1, y1, x2, y2, bg)

    local tx = math.floor((x1 + x2 - #label) / 2)
    local ty = math.floor((y1 + y2) / 2)

    writeAt(tx, ty, label, fg, bg)

    buttons[name] = {
        x1 = x1,
        y1 = y1,
        x2 = x2,
        y2 = y2
    }
end

local function hit(name, x, y)
    local b = buttons[name]

    if not b then
        return false
    end

    return
        x >= b.x1 and
        x <= b.x2 and
        y >= b.y1 and
        y <= b.y2
end

local function pct(value)
    if type(value) ~= "number" then
        return 0
    end

    return math.floor(value * 100 + 0.5)
end

local function bar(x, y, width, value, colour)
    value = tonumber(value) or 0
    value = math.max(0, math.min(1, value))

    local filled = math.floor(width * value)

    monitor.setBackgroundColor(colors.gray)
    monitor.setCursorPos(x, y)
    monitor.write(string.rep(" ", width))

    if filled > 0 then
        monitor.setBackgroundColor(colour)
        monitor.setCursorPos(x, y)
        monitor.write(string.rep(" ", filled))
    end

    monitor.setBackgroundColor(colors.black)
end

local function send(command)
    modem.transmit(
        REACTOR_CHANNEL,
        CONTROL_CHANNEL,
        command
    )
end

-- =========================================================
-- HEATED COOLANT HELPERS
-- =========================================================

local function heatedAmount()
    if not data or data.heated == nil then
        return 0
    end

    if type(data.heated) == "number" then
        return data.heated
    end

    if
        type(data.heated) == "table" and
        type(data.heated.amount) == "number"
    then
        return data.heated.amount
    end

    return 0
end

local function heatedCapacity()
    local stored = heatedAmount()
    local needed = 0

    if data and type(data.heatedNeeded) == "number" then
        needed = data.heatedNeeded
    end

    return stored + needed
end

-- =========================================================
-- MAIN SCREEN
-- =========================================================

local function draw()
    buttons = {}

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()

    -- HEADER
    fill(1, 1, w, 3, colors.gray)

    centre(
        2,
        "FISSION REACTOR CONTROL - REACTOR 1",
        colors.orange,
        colors.gray
    )

    local now = os.epoch("utc")

    local online =
        lastReply > 0 and
        now - lastReply < 4000

    writeAt(
        4,
        5,
        "LINK:",
        colors.lightGray,
        colors.black
    )

    if online then
        writeAt(
            10,
            5,
            "ONLINE",
            colors.lime,
            colors.black
        )
    else
        writeAt(
            10,
            5,
            "OFFLINE",
            colors.red,
            colors.black
        )
    end

    -- =====================================================
    -- SAFETY BANNER
    -- =====================================================

    if data then
        local coolant = data.coolant or 0

        if data.safetyTrip then

            local canReset =
                coolant >= 0.25

            if flashOn then
                fill(
                    28,
                    4,
                    w - 28,
                    6,
                    colors.red
                )

                centre(
                    5,
                    "SAFETY TRIP: " ..
                    tostring(data.tripReason or "UNKNOWN"),
                    colors.white,
                    colors.red
                )
            else
                centre(
                    5,
                    "SAFETY TRIP: " ..
                    tostring(data.tripReason or "UNKNOWN"),
                    colors.red,
                    colors.black
                )
            end

            if canReset then
                centre(
                    6,
                    "COOLANT SAFE - RESET AVAILABLE",
                    colors.orange,
                    colors.black
                )
            end

        elseif coolant < 0.30 then

            if flashOn then
                fill(
                    28,
                    4,
                    w - 28,
                    6,
                    colors.orange
                )

                centre(
                    5,
                    "WARNING - COOLANT BELOW 30%",
                    colors.black,
                    colors.orange
                )
            else
                centre(
                    5,
                    "WARNING - COOLANT BELOW 30%",
                    colors.orange,
                    colors.black
                )
            end

        else
            centre(
                5,
                "SAFETY ARMED - SCRAM BELOW 20%",
                colors.lime,
                colors.black
            )
        end
    end

    -- =====================================================
    -- WAITING
    -- =====================================================

    if not data then
        centre(
            math.floor(h / 2),
            "WAITING FOR REACTOR TELEMETRY...",
            colors.yellow,
            colors.black
        )

    else
        local col1 = 4
        local col2 = math.floor(w * 0.34)
        local col3 = math.floor(w * 0.67)

        -- =================================================
        -- REACTOR STATUS
        -- =================================================

        writeAt(
            col1,
            8,
            "REACTOR STATUS",
            colors.orange,
            colors.black
        )

        writeAt(
            col1,
            10,
            "State:",
            colors.lightGray,
            colors.black
        )

        if data.status then
            writeAt(
                col1 + 13,
                10,
                "RUNNING",
                colors.lime,
                colors.black
            )
        else
            writeAt(
                col1 + 13,
                10,
                "OFF",
                colors.red,
                colors.black
            )
        end

        writeAt(
            col1,
            12,
            "Set Burn:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col1 + 13,
            12,
            string.format(
                "%.2f mB/t",
                data.burn or 0
            ),
            colors.orange,
            colors.black
        )

        writeAt(
            col1,
            14,
            "Actual:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col1 + 13,
            14,
            string.format(
                "%.2f mB/t",
                data.actual or 0
            ),
            colors.lime,
            colors.black
        )

        writeAt(
            col1,
            16,
            "Maximum:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col1 + 13,
            16,
            string.format(
                "%.2f mB/t",
                data.max or 0
            ),
            colors.white,
            colors.black
        )

        -- =================================================
        -- CORE
        -- =================================================

        writeAt(
            col2,
            8,
            "REACTOR CORE",
            colors.orange,
            colors.black
        )

        local tempC =
            (data.temp or 273.15) - 273.15

        local tempColour = colors.lime

        if tempC > 800 then
            tempColour = colors.red
        elseif tempC > 500 then
            tempColour = colors.orange
        end

        writeAt(
            col2,
            10,
            "Temperature:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col2 + 16,
            10,
            string.format(
                "%.1f C",
                tempC
            ),
            tempColour,
            colors.black
        )

        writeAt(
            col2,
            12,
            "Core Damage:",
            colors.lightGray,
            colors.black
        )

        local damageColour = colors.lime

        if (data.damage or 0) > 0 then
            damageColour = colors.red
        end

        writeAt(
            col2 + 16,
            12,
            string.format(
                "%.2f %%",
                data.damage or 0
            ),
            damageColour,
            colors.black
        )

        -- =================================================
        -- HEATED COOLANT / STEAM
        -- =================================================

        writeAt(
            col2,
            15,
            "HEATED COOLANT / STEAM",
            colors.orange,
            colors.black
        )

        writeAt(
            col2,
            17,
            "Stored:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col2 + 12,
            17,
            string.format(
                "%.0f mB",
                heatedAmount()
            ),
            colors.yellow,
            colors.black
        )

        writeAt(
            col2,
            19,
            "Capacity:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col2 + 12,
            19,
            string.format(
                "%.0f mB",
                heatedCapacity()
            ),
            colors.white,
            colors.black
        )

        writeAt(
            col2,
            21,
            "Level:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col2 + 12,
            21,
            pct(data.heatedPercent) .. "%",
            colors.yellow,
            colors.black
        )

        bar(
            col2,
            22,
            24,
            data.heatedPercent,
            colors.yellow
        )

        -- =================================================
        -- REACTOR LEVELS
        -- =================================================

        writeAt(
            col3,
            8,
            "REACTOR LEVELS",
            colors.orange,
            colors.black
        )

        writeAt(
            col3,
            10,
            "Fuel:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col3 + 12,
            10,
            pct(data.fuel) .. "%",
            colors.lime,
            colors.black
        )

        bar(
            col3,
            11,
            24,
            data.fuel,
            colors.lime
        )

        local coolantColour = colors.cyan

        if data.coolant < 0.20 then
            coolantColour = colors.red

        elseif data.coolant < 0.30 then
            if flashOn then
                coolantColour = colors.orange
            else
                coolantColour = colors.yellow
            end
        end

        writeAt(
            col3,
            13,
            "Coolant:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col3 + 12,
            13,
            pct(data.coolant) .. "%",
            coolantColour,
            colors.black
        )

        bar(
            col3,
            14,
            24,
            data.coolant,
            coolantColour
        )

        writeAt(
            col3,
            16,
            "Waste:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col3 + 12,
            16,
            pct(data.waste) .. "%",
            colors.yellow,
            colors.black
        )

        bar(
            col3,
            17,
            24,
            data.waste,
            colors.yellow
        )
    end

    -- =====================================================
    -- BURN RATE CONTROL
    -- moved down to give steam bar clear breathing space
    -- =====================================================

    local controlY = h - 11

    centre(
        controlY - 1,
        "BURN RATE CONTROL",
        colors.orange,
        colors.black
    )

    local margin = 5
    local gap = 1
    local count = 11

    local available =
        w -
        margin * 2 -
        gap * (count - 1)

    local bw =
        math.floor(
            available / count
        )

    local x = margin

    local function burnButton(
        name,
        label,
        colour
    )
        button(
            name,
            x,
            controlY + 1,
            x + bw - 1,
            controlY + 3,
            label,
            colour,
            colors.white
        )

        x = x + bw + gap
    end

    burnButton(
        "DOWN10",
        "-10",
        colors.red
    )

    burnButton(
        "DOWN5",
        "-5",
        colors.brown
    )

    burnButton(
        "DOWN2",
        "-2",
        colors.brown
    )

    burnButton(
        "DOWN1",
        "-1",
        colors.gray
    )

    burnButton(
        "DOWN001",
        "-0.01",
        colors.gray
    )

    local current = "RATE"

    if data then
        current =
            string.format(
                "%.2f",
                data.burn or 0
            )
    end

    burnButton(
        "CURRENT",
        current,
        colors.blue
    )

    burnButton(
        "UP001",
        "+0.01",
        colors.gray
    )

    burnButton(
        "UP1",
        "+1",
        colors.gray
    )

    burnButton(
        "UP2",
        "+2",
        colors.brown
    )

    burnButton(
        "UP5",
        "+5",
        colors.brown
    )

    burnButton(
        "UP10",
        "+10",
        colors.green
    )

    -- =====================================================
    -- RESET SAFETY
    -- =====================================================

    local resetY = h - 7

    if data and data.safetyTrip then
        local resetReady =
            data.coolant >= 0.25

        if resetReady then
            button(
                "RESET",
                15,
                resetY,
                w - 15,
                resetY + 1,
                "RESET SAFETY - COOLANT SAFE",
                colors.orange,
                colors.black
            )
        else
            button(
                "RESET_BLOCKED",
                15,
                resetY,
                w - 15,
                resetY + 1,
                "SAFETY LOCKED - COOLANT MUST REACH 25%",
                colors.red,
                colors.white
            )
        end
    end

    -- =====================================================
    -- MAIN CONTROLS
    -- =====================================================

    local bottomY = h - 4

    local outer = 4
    local gapBottom = 3

    local usable =
        w -
        outer * 2 -
        gapBottom * 2

    local buttonWidth =
        math.floor(
            usable / 3
        )

    local onX1 = outer
    local onX2 =
        onX1 + buttonWidth - 1

    local offX1 =
        onX2 + gapBottom + 1

    local offX2 =
        offX1 + buttonWidth - 1

    local scramX1 =
        offX2 + gapBottom + 1

    local scramX2 =
        w - outer

    button(
        "ON",
        onX1,
        bottomY,
        onX2,
        h - 1,
        "REACTOR ON",
        colors.green,
        colors.white
    )

    button(
        "OFF",
        offX1,
        bottomY,
        offX2,
        h - 1,
        "REACTOR OFF",
        colors.orange,
        colors.black
    )

    local scramText =
        "SCRAM - TAP TWICE"

    if
        scramArmed and
        os.epoch("utc") < scramUntil
    then
        scramText =
            "CONFIRM SCRAM!"
    end

    button(
        "SCRAM",
        scramX1,
        bottomY,
        scramX2,
        h - 1,
        scramText,
        colors.red,
        colors.white
    )

    monitor.setBackgroundColor(
        colors.black
    )

    monitor.setTextColor(
        colors.white
    )
end

-- =========================================================
-- TOUCH HANDLER
-- =========================================================

local function handleTouch(x, y)

    if hit("DOWN10", x, y) then
        send("DOWN_10")

    elseif hit("DOWN5", x, y) then
        send("DOWN_5")

    elseif hit("DOWN2", x, y) then
        send("DOWN_2")

    elseif hit("DOWN1", x, y) then
        send("DOWN_1")

    elseif hit("DOWN001", x, y) then
        send("DOWN_001")

    elseif hit("UP001", x, y) then
        send("UP_001")

    elseif hit("UP1", x, y) then
        send("UP_1")

    elseif hit("UP2", x, y) then
        send("UP_2")

    elseif hit("UP5", x, y) then
        send("UP_5")

    elseif hit("UP10", x, y) then
        send("UP_10")

    elseif hit("RESET", x, y) then
        send("RESET_SAFETY")

    elseif hit("ON", x, y) then
        send("ON")

    elseif hit("OFF", x, y) then
        send("OFF")

    elseif hit("SCRAM", x, y) then
        local now =
            os.epoch("utc")

        if
            scramArmed and
            now < scramUntil
        then
            send("OFF")
            scramArmed = false
            scramUntil = 0
        else
            scramArmed = true
            scramUntil =
                now + 3000
        end

        draw()
    end
end

-- =========================================================
-- START
-- =========================================================

draw()
send("STATUS")

local refreshTimer =
    os.startTimer(1)

local flashTimer =
    os.startTimer(0.5)

-- =========================================================
-- EVENT LOOP
-- =========================================================

while true do
    local event,
          p1,
          p2,
          p3,
          p4 =
        os.pullEvent()

    if event == "monitor_touch" then

        handleTouch(
            p2,
            p3
        )

    elseif event == "modem_message" then

        local channel =
            p2

        local message =
            p4

        if
            channel == CONTROL_CHANNEL and
            type(message) == "table"
        then
            data = message
            lastReply =
                os.epoch("utc")

            draw()
        end

    elseif event == "timer" then

        if p1 == refreshTimer then
            send("STATUS")

            local now =
                os.epoch("utc")

            if
                scramArmed and
                now >= scramUntil
            then
                scramArmed = false
                scramUntil = 0
            end

            refreshTimer =
                os.startTimer(1)

        elseif p1 == flashTimer then
            flashOn = not flashOn

            draw()

            flashTimer =
                os.startTimer(0.5)
        end
    end
end
