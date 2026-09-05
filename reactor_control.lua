-- =========================================================
-- MEKANISM FISSION REACTOR CONTROL
-- Control Room Computer
--
-- TOP   = Ender Modem
-- RIGHT = 6x3 Advanced Monitor
--
-- Reactor channel: 1234
-- Control reply channel: 4321
-- =========================================================

local modem = peripheral.wrap("top")
local monitor = peripheral.wrap("right")

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
-- HELPERS
-- =========================================================

local function writeAt(x, y, text, fg, bg)
    monitor.setCursorPos(x, y)

    if fg then
        monitor.setTextColor(fg)
    end

    if bg then
        monitor.setBackgroundColor(bg)
    end

    monitor.write(tostring(text))
end

local function centerText(y, text, fg, bg)
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

local function box(x1, y1, x2, y2, bg)
    fill(x1, y1, x2, y2, bg)
end

local function addButton(name, x1, y1, x2, y2, label, bg, fg)
    box(x1, y1, x2, y2, bg)

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

local function percent(value)
    if value == nil then
        return 0
    end

    return math.floor((value * 100) + 0.5)
end

local function bar(x, y, width, value, colour)
    value = math.max(0, math.min(1, value or 0))

    local filled = math.floor(width * value)

    monitor.setCursorPos(x, y)
    monitor.setBackgroundColor(colors.gray)
    monitor.write(string.rep(" ", width))

    if filled > 0 then
        monitor.setCursorPos(x, y)
        monitor.setBackgroundColor(colour)
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
-- DRAW SCREEN
-- =========================================================

local function draw()
    buttons = {}

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()

    -- -----------------------------------------------------
    -- HEADER
    -- -----------------------------------------------------

    fill(1, 1, w, 3, colors.gray)

    centerText(
        2,
        "FISSION REACTOR CONTROL",
        colors.orange,
        colors.gray
    )

    -- -----------------------------------------------------
    -- CONNECTION
    -- -----------------------------------------------------

    local online = (os.clock() - lastReply) < 4

    writeAt(
        3,
        5,
        "REACTOR LINK:",
        colors.lightGray,
        colors.black
    )

    if online then
        writeAt(
            17,
            5,
            "ONLINE",
            colors.lime,
            colors.black
        )
    else
        writeAt(
            17,
            5,
            "OFFLINE",
            colors.red,
            colors.black
        )
    end

    if not data then
        centerText(
            math.floor(h / 2),
            "WAITING FOR REACTOR TELEMETRY...",
            colors.yellow,
            colors.black
        )
    else

        -- -------------------------------------------------
        -- REACTOR STATUS
        -- -------------------------------------------------

        writeAt(
            3,
            7,
            "REACTOR STATUS",
            colors.orange,
            colors.black
        )

        writeAt(
            3,
            9,
            "State:",
            colors.lightGray,
            colors.black
        )

        if data.status then
            writeAt(
                15,
                9,
                "RUNNING",
                colors.lime,
                colors.black
            )
        else
            writeAt(
                15,
                9,
                "OFF",
                colors.red,
                colors.black
            )
        end

        writeAt(
            3,
            11,
            "Set Burn:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            15,
            11,
            string.format("%.1f mB/t", data.burn or 0),
            colors.orange,
            colors.black
        )

        writeAt(
            3,
            13,
            "Actual Burn:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            15,
            13,
            string.format("%.1f mB/t", data.actual or 0),
            colors.lime,
            colors.black
        )

        writeAt(
            3,
            15,
            "Max Burn:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            15,
            15,
            string.format("%.1f mB/t", data.max or 0),
            colors.white,
            colors.black
        )

        -- -------------------------------------------------
        -- TEMPERATURE / DAMAGE
        -- -------------------------------------------------

        local col2 = math.floor(w * 0.34)

        writeAt(
            col2,
            7,
            "REACTOR CORE",
            colors.orange,
            colors.black
        )

        local tempK = data.temp or 0
        local tempC = tempK - 273.15

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
            string.format("%.1f C", tempC),
            colors.lime,
            colors.black
        )

        writeAt(
            col2,
            11,
            "Core Damage:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col2 + 16,
            11,
            string.format("%.2f %%", data.damage or 0),
            (data.damage or 0) > 0 and colors.red or colors.lime,
            colors.black
        )

        -- -------------------------------------------------
        -- LEVELS
        -- -------------------------------------------------

        local col3 = math.floor(w * 0.66)

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
            col3 + 10,
            9,
            percent(data.fuel) .. "%",
            colors.lime,
            colors.black
        )

        bar(
            col3,
            10,
            22,
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

        writeAt(
            col3 + 10,
            12,
            percent(data.coolant) .. "%",
            colors.cyan,
            colors.black
        )

        bar(
            col3,
            13,
            22,
            data.coolant,
            colors.cyan
        )

        writeAt(
            col3,
            15,
            "Waste:",
            colors.lightGray,
            colors.black
        )

        writeAt(
            col3 + 10,
            15,
            percent(data.waste) .. "%",
            colors.yellow,
            colors.black
        )

        bar(
            col3,
            16,
            22,
            data.waste,
            colors.yellow
        )
    end

    -- =====================================================
    -- BURN RATE CONTROLS
    -- =====================================================

    local controlY = h - 11

    centerText(
        controlY - 1,
        "BURN RATE CONTROL",
        colors.orange,
        colors.black
    )

    local buttonWidth = 15
    local gap = 2

    local totalWidth =
        (buttonWidth * 7) +
        (gap * 6)

    local startX =
        math.floor((w - totalWidth) / 2) + 1

    addButton(
        "DOWN",
        startX,
        controlY,
        startX + buttonWidth - 1,
        controlY + 2,
        "v  -0.1",
        colors.gray,
        colors.white
    )

    addButton(
        "P05",
        startX + 17,
        controlY,
        startX + 31,
        controlY + 2,
        "0.5",
        colors.brown,
        colors.white
    )

    addButton(
        "P1",
        startX + 34,
        controlY,
        startX + 48,
        controlY + 2,
        "1.0",
        colors.brown,
        colors.white
    )

    addButton(
        "P2",
        startX + 51,
        controlY,
        startX + 65,
        controlY + 2,
        "2.0",
        colors.brown,
        colors.white
    )

    addButton(
        "P5",
        startX + 68,
        controlY,
        startX + 82,
        controlY + 2,
        "5.0",
        colors.brown,
        colors.white
    )

    addButton(
        "P10",
        startX + 85,
        controlY,
        startX + 99,
        controlY + 2,
        "10.0",
        colors.brown,
        colors.white
    )

    addButton(
        "UP",
        startX + 102,
        controlY,
        startX + 116,
        controlY + 2,
        "^  +0.1",
        colors.orange,
        colors.black
    )

    -- =====================================================
    -- MAIN CONTROLS AT BOTTOM
    -- =====================================================

    local bottomY = h - 5

    local mainGap = 3
    local mainWidth = math.floor((w - 12) / 3)

    addButton(
        "ON",
        3,
        bottomY,
        3 + mainWidth,
        h - 1,
        "REACTOR ON",
        colors.green,
        colors.white
    )

    addButton(
        "OFF",
        6 + mainWidth,
        bottomY,
        6 + (mainWidth * 2),
        h - 1,
        "REACTOR OFF",
        colors.orange,
        colors.black
    )

    local scramColour = colors.red
    local scramText = "SCRAM - TAP TWICE"

    if scramArmed and os.clock() < scramUntil then
        scramColour = colors.red
        scramText = "CONFIRM SCRAM!"
    end

    addButton(
        "SCRAM",
        9 + (mainWidth * 2),
        bottomY,
        w - 3,
        h - 1,
        scramText,
        scramColour,
        colors.white
    )

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
end

-- =========================================================
-- BUTTON HANDLER
-- =========================================================

local function touched(name, x, y)
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

local function handleTouch(x, y)

    if touched("DOWN", x, y) then
        send("DOWN")
        return
    end

    if touched("UP", x, y) then
        send("UP")
        return
    end

    if touched("P05", x, y) then
        send("SET:0.5")
        return
    end

    if touched("P1", x, y) then
        send("SET:1")
        return
    end

    if touched("P2", x, y) then
        send("SET:2")
        return
    end

    if touched("P5", x, y) then
        send("SET:5")
        return
    end

    if touched("P10", x, y) then
        send("SET:10")
        return
    end

    if touched("ON", x, y) then
        send("ON")
        return
    end

    if touched("OFF", x, y) then
        send("OFF")
        return
    end

    if touched("SCRAM", x, y) then

        if scramArmed and os.clock() < scramUntil then
            send("OFF")
            scramArmed = false
            scramUntil = 0
        else
            scramArmed = true
            scramUntil = os.clock() + 3
        end

        draw()
        return
    end
end

-- =========================================================
-- STARTUP
-- =========================================================

draw()

send("STATUS")

local refreshTimer = os.startTimer(1)

-- =========================================================
-- MAIN LOOP
-- =========================================================

while true do

    local event, p1, p2, p3, p4, p5 =
        os.pullEvent()

    -- -----------------------------------------------------
    -- TOUCHSCREEN
    -- -----------------------------------------------------

    if event == "monitor_touch" then

        local side = p1
        local x = p2
        local y = p3

        handleTouch(x, y)

    -- -----------------------------------------------------
    -- REACTOR REPLY
    -- -----------------------------------------------------

    elseif event == "modem_message" then

        local side = p1
        local channel = p2
        local replyChannel = p3
        local message = p4
        local distance = p5

        if channel == CONTROL_CHANNEL and type(message) == "table" then
            data = message
            lastReply = os.clock()
            draw()
        end

    -- -----------------------------------------------------
    -- REFRESH TIMER
    -- -----------------------------------------------------

    elseif event == "timer" and p1 == refreshTimer then

        if scramArmed and os.clock() >= scramUntil then
            scramArmed = false
            scramUntil = 0
        end

        send("STATUS")

        draw()

        refreshTimer = os.startTimer(1)

    end
end
