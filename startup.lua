-- =========================================================
-- MEKANISM FISSION REACTOR - REACTOR SIDE
--
-- BACK  = Fission Reactor Logic Adapter
-- RIGHT = Ender Modem
-- =========================================================

local reactor = peripheral.wrap("back")
local modem = peripheral.wrap("right")

local REACTOR_CHANNEL = 1234

modem.open(REACTOR_CHANNEL)

local function send(replyChannel, data)
    modem.transmit(replyChannel, REACTOR_CHANNEL, data)
end

local function getStatus()
    return {
        status = reactor.getStatus(),

        burn = reactor.getBurnRate(),
        actual = reactor.getActualBurnRate(),
        max = reactor.getMaxBurnRate(),

        temp = reactor.getTemperature(),
        damage = reactor.getDamagePercent(),

        fuel = reactor.getFuelFilledPercentage(),
        coolant = reactor.getCoolantFilledPercentage(),

        heated = reactor.getHeatedCoolant(),
        heatedPercent = reactor.getHeatedCoolantFilledPercentage(),
        heatedNeeded = reactor.getHeatedCoolantNeeded(),

        waste = reactor.getWasteFilledPercentage()
    }
end

while true do
    local event,
          side,
          channel,
          replyChannel,
          msg,
          distance = os.pullEvent("modem_message")

    if channel == REACTOR_CHANNEL and type(msg) == "string" then

        if msg == "STATUS" then
            send(replyChannel, getStatus())

        elseif msg == "UP" then
            local rate = reactor.getBurnRate() + 0.1
            rate = math.min(rate, reactor.getMaxBurnRate())

            reactor.setBurnRate(rate)
            send(replyChannel, getStatus())

        elseif msg == "DOWN" then
            local rate = reactor.getBurnRate() - 0.1
            rate = math.max(rate, 0.1)

            reactor.setBurnRate(rate)
            send(replyChannel, getStatus())

        elseif string.sub(msg, 1, 4) == "SET:" then
            local rate = tonumber(string.sub(msg, 5))

            if rate then
                rate = math.max(
                    0.1,
                    math.min(rate, reactor.getMaxBurnRate())
                )

                reactor.setBurnRate(rate)
            end

            send(replyChannel, getStatus())

        elseif msg == "ON" then
            if not reactor.getStatus() then
                reactor.activate()
            end

            send(replyChannel, getStatus())

        elseif msg == "OFF" then
            if reactor.getStatus() then
                reactor.scram()
            end

            send(replyChannel, getStatus())
        end
    end
end
