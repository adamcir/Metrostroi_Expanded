-- MEX AI Driver - 81-717 panel/ARS adapter (real Metrostroi systems).
-- OCh (ОЧ) is the NO-FREQUENCY INDICATOR, not a switch to set arbitrarily.
local Cab = {}

local LIGHTS = {
    panel = { system = "L_3", button = "L_3Toggle", title = "osvetleni pultu" },
    cabin = { system = "L_2", button = "L_2Toggle", title = "osvetleni kabiny" },
    saloon = { system = "L_1", button = "L_1Toggle", title = "osvetleni salonu" },
    headlights = { system = "L_4", button = "L_4Toggle", title = "predni svetlomety" }
}

local function ValidRelay(system)
    return system ~= nil and tonumber(system.Value) ~= nil
end

function Cab.ReadARS(train)
    if not IsValid(train) or not train.ALS_ARS then
        return { valid = false, text = "ARS neni dostupne" }
    end
    local ars = train.ALS_ARS
    local frequencyMissing = ars.NoFreq == true or ars.RealNoFreq == true
    local limit = tonumber(ars.SpeedLimit)
    local enabled = ars.EnableARS == true and ars.EnableALS == true
    if not enabled then
        return { valid = false, noch = frequencyMissing, speed_limit = limit,
            text = "ARS/ALS neni aktivni; samostatnou jizdu nepovoluji" }
    end
    if frequencyMissing then
        return { valid = true, noch = true, speed_limit = 0,
            text = "OČ sviti: chybi frekvence ARS. Brzdim a cekam." }
    end
    if not limit or limit <= 0 then
        return { valid = true, noch = false, speed_limit = 0,
            text = "ARS: signal 0 / zakaz jizdy. Zastavuji." }
    end
    return {valid = true, noch = false, speed_limit = math.Clamp(limit,0,120),
        text = string.format("ARS aktivni: %d km/h, OČ nesviti.", math.floor(limit))}
end

-- Trigger the SAME physical switch input that a player would press.
-- Never use SetPackedBool / SetLightPower to fake a panel state.
function Cab.SetLight(train, key, enabled)
    local info = LIGHTS[key]
    if not info then return false, "unknown_light" end
    if not IsValid(train) or type(train.ButtonEvent) ~= "function" then
        return false, "not_supported"
    end
    local relay = train[info.system]
    if not ValidRelay(relay) then return false, "light_switch_missing" end
    local currentlyOn = tonumber(relay.Value) > 0.5
    if currentlyOn == enabled then
        return true, info.title .. " uz je " .. (enabled and "zapnuto" or "vypnuto")
    end
    local success, err = pcall(train.ButtonEvent, train, info.button, true)
    if not success then return false, tostring(err) end
    timer.Simple(0.10, function()
        if IsValid(train) then
            pcall(train.ButtonEvent, train, info.button, false)
        end
    end)
    return true, info.title .. (enabled and " zapinam" or " vypinam")
end

function Cab.Lights() return LIGHTS end

return Cab
