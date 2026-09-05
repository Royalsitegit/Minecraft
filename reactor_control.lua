-- =========================================================
-- MEKANISM FISSION REACTOR CONTROL ROOM
--
-- TOP  = Ender Modem
-- BACK = Advanced Monitor
--
-- Designed so multi-reactor page selection can be
-- added later.
-- =========================================================

local modem = peripheral.wrap("top")
local monitor = peripheral.wrap("back")

local REACTOR_CHANNEL = 1234
local CONTROL_CHANNEL = 4321

modem.open(CONTROL_CHANNEL)

monitor.setTextScale(0.5)

local w, h = monitor.getSize()

local data = nil
local lastReply = 0

local scramArmed = false
local scramUntil = 0

local buttons = {}

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

    local x =
        math.floor((w - #text) / 2) + 1

    writeAt(
        x,
        y,
        text,
        fg,
        bg
    )
end

local function fill(x1, y1, x2, y2, colour)

    monitor.setBackgroundColor(colour)

    for y = y1, y2 do

        monitor.setCursorPos(x1, y)

        monitor.write(
            string.rep(
                " ",
                x2 - x1 + 1
            )
        )
    end
end

local function button(
    name,
    x1,
    y1,
    x2,
    y2,
    label,
    bg,
    fg
)

    fill(
        x1,
        y1,
        x2,
        y2,
        bg
    )

    local tx =
        math.floor(
            (x1 + x2 - #label) / 2
        )

    local ty =
        math.floor(
            (y1 + y2) / 2
        )

    writeAt(
        tx,
        ty,
        label,
        fg,
        bg
    )

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

    if value == nil then
        return 0
    end

    return math.floor(
        (value * 100) + 0.5
    )
end

local function bar(
    x,
    y,
    width,
    value,
    colour
)

    value =
        math.max(
            0,
            math.min(
                1,
                value or 0
            )
        )

    local filled =
        math.floor(width * value)

    monitor.setBackgroundColor(
        colors.gray
    )

    monitor.setCursorPos(x, y)

    monitor.write(
        string.rep(" ", width)
    )

    if filled > 0 then

        monitor.setBackgroundColor(
            colour
        )

        monitor.setCursorPos(x, y)

        monitor.write(
            string.rep(
                " ",
                filled
            )
        )
    end

    monitor.setBackgroundColor(
        colors.black
    )
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

    if
        not data or
        data.heated == nil
    then
        return 0
    end

    if type(data.heated) == "number" then
        return data.heated
    end

    if
        type(data.heated) == "table" and
        data.heated.amount
    then
        return data.heated.amount
    end

    return 0
end

local function heatedCapacity()

    local stored = heatedAmount()
    local needed = 0

    if
        data and
        type(data.heatedNeeded) == "number"
    then
        needed = data.heatedNeeded
    end

    return stored + needed
end

-- =========================================================
-- MAIN SCREEN
-- =========================================================

local function draw()

    buttons = {}

    monitor.setBackgroundColor(
        colors.black
    )

    monitor.setTextColor(
        colors.white
    )

    monitor.clear()

    -- =====================================================
    -- HEADER
    -- =====================================================

    fill(
        1,
        1,
        w,
        3,
        colors.gray
    )

    centre(
        2,
        "FISSION REACTOR CONTROL - REACTOR 1",
        colors.orange,
        colors.gray
    )

    local now = os.epoch("utc")

    local online =
        lastReply > 0 and
        (now - lastReply) < 4000

    writeAt(
        4,
        5,
        "REACTOR LINK:",
        colors.lightGray,
        colors.black
    )

    if online then

        writeAt(
            18,
            5,
            "ONLINE",
            colors.lime,
            colors.black
        )

    else

        writeAt(
            18,
            5,
            "OFFLINE",
            colors.red,
            colors.black
        )
    end

    -- =====================================================
    -- SAFETY STATUS
    -- =====================================================

    local safetyText =
        "SAFETY: ARMED - COOLANT SCRAM BELOW 10%"

    local safetyColour =
        colors.lime

    if data and data.safetyTrip then

        safetyText =
            "!!! SAFETY TRIP: " ..
            tostring(
                data.tripReason or
                "UNKNOWN"
            ) ..
            " !!!"

        safetyColour =
            colors.red
    end

    centre(
        5,
        safetyText,
        safetyColour,
        colors.black
    )

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
        -- LEFT COLUMN
        -- =================================================

        writeAt(
            col1,
            7,
            "REACTOR STATUS",
            colors.orange,
            colors.black
        )

        writeAt(
            col1,
            9,
            "State:",
            colors.lightGray,
            colors.black
        )

        if data.status then

            writeAt(
                col1 + 13,
                9,
                "RUNNING",
                colors.lime,
                colors.black
            )

        else

            writeAt(
                col1 + 13,
                9,
                "OFF",
                colors.red,
                colors.black
            )
        end

        writeAt(
            col1,
            11,
            "Set Burn:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col1 + 13,
            11,
            string.format(
                "%.2f mB/t",
                data.burn or 0
            ),
            colors.orange,
            colors.black
        )

        writeAt(
            col1,
            13,
            "Actual Burn:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col1 + 13,
            13,
            string.format(
                "%.2f mB/t",
                data.actual or 0
            ),
            colors.lime,
            colors.black
        )

        writeAt(
            col1,
            15,
            "Max Burn:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col1 + 13,
            15,
            string.format(
                "%.2f mB/t",
                data.max or 0
            ),
            colors.white,
            colors.black
        )

        -- =================================================
        -- CENTRE COLUMN
        -- =================================================

        writeAt(
            col2,
            7,
            "REACTOR CORE",
            colors.orange,
            colors.black
        )

        local tempC =
            (data.temp or 273.15) -
            273.15

        local tempColour =
            colors.lime

        if tempC > 800 then

            tempColour =
                colors.red

        elseif tempC > 500 then

            tempColour =
                colors.orange
        end

        writeAt(
            col2,
            9,
            "Temperature:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col2 + 16,
            9,
            string.format(
                "%.1f C",
                tempC
            ),
            tempColour,
            colors.black
        )

        writeAt(
            col2,
            11,
            "Core Damage:",
            colors.lightGray,
            colors.black
        )

        local damageColour =
            colors.lime

        if (data.damage or 0) > 0 then
            damageColour =
                colors.red
        end

        writeAt(
            col2 + 16,
            11,
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
            14,
            "HEATED COOLANT / STEAM",
            colors.orange,
            colors.black
        )

        local heated =
            heatedAmount()

        local capacity =
            heatedCapacity()

        writeAt(
            col2,
            16,
            "Stored:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col2 + 12,
            16,
            string.format(
                "%.0f mB",
                heated
            ),
            colors.yellow,
            colors.black
        )

        writeAt(
            col2,
            18,
            "Capacity:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col2 + 12,
            18,
            string.format(
                "%.0f mB",
                capacity
            ),
            colors.white,
            colors.black
        )

        writeAt(
            col2,
            20,
            "Steam Level:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col2 + 15,
            20,
            pct(
                data.heatedPercent
            ) .. "%",
            colors.yellow,
            colors.black
        )

        bar(
            col2,
            21,
            24,
            data.heatedPercent,
            colors.yellow
        )

        -- =================================================
        -- RIGHT COLUMN
        -- =================================================

        writeAt(
            col3,
            7,
            "REACTOR LEVELS",
            colors.orange,
            colors.black
        )

        writeAt(
            col3,
            9,
            "Fuel:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col3 + 12,
            9,
            pct(data.fuel) .. "%",
            colors.lime,
            colors.black
        )

        bar(
            col3,
            10,
            24,
            data.fuel,
            colors.lime
        )

        writeAt(
            col3,
            12,
            "Coolant:",
            colors.lightGray,
            colors.black
        )

        local coolantColour =
            colors.cyan

        if
            data.coolant and
            data.coolant < 0.10
        then
            coolantColour =
                colors.red
        end

        writeAt(
            col3 + 12,
            12,
            pct(data.coolant) .. "%",
            coolantColour,
            colors.black
        )

        bar(
            col3,
            13,
            24,
            data.coolant,
            coolantColour
        )

        writeAt(
            col3,
            15,
            "Waste:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col3 + 12,
            15,
            pct(data.waste) .. "%",
            colors.yellow,
            colors.black
        )

        bar(
            col3,
            16,
            24,
            data.waste,
            colors.yellow
        )
    end

    -- =====================================================
    -- BURN RATE CONTROL
    -- =====================================================

    local controlY = h - 11

    centre(
        controlY - 2,
        "BURN RATE CONTROL",
        colors.orange,
        colors.black
    )

    -- 11 buttons:
    -- -10 -5 -2 -1 -0.01 CURRENT +0.01 +1 +2 +5 +10

    local margin = 5
    local gap = 1
    local count = 11

    local available =
        w -
        (margin * 2) -
        (gap * (count - 1))

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
            controlY,
            x + bw - 1,
            controlY + 2,
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

    -- CURRENT RATE
    local currentLabel = "RATE"

    if data then
        currentLabel =
            string.format(
                "%.2f",
                data.burn or 0
            )
    end

    burnButton(
        "CURRENT",
        currentLabel,
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
    -- BOTTOM CONTROLS
    -- =====================================================

    local bottomY = h - 5
    local outer = 4
    local bottomGap = 3

    local total =
        w -
        (outer * 2) -
        (bottomGap * 2)

    local mainWidth =
        math.floor(total / 3)

    local onX1 = outer
    local onX2 =
        onX1 + mainWidth - 1

    local offX1 =
        onX2 + bottomGap + 1

    local offX2 =
        offX1 + mainWidth - 1

    local scramX1 =
        offX2 + bottomGap + 1

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

-- =========================================================
-- MAIN LOOP
-- =========================================================

while true do

    local event,
          p1,
          p2,
          p3,
          p4,
          p5 = os.pullEvent()

    if event == "monitor_touch" then

        handleTouch(
            p2,
            p3
        )

    elseif event == "modem_message" then

        local channel = p2
        local message = p4

        if
            channel == CONTROL_CHANNEL and
            type(message) == "table"
        then

            data = message

            lastReply =
                os.epoch("utc")

            draw()
        end

    elseif
        event == "timer" and
        p1 == refreshTimer
    then

        local now =
            os.epoch("utc")

        if
            scramArmed and
            now >= scramUntil
        then

            scramArmed = false
            scramUntil = 0
        end

        send("STATUS")

        draw()

        refreshTimer =
            os.startTimer(1)
    end
end
