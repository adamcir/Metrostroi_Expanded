-- Metrostroi Expanded - StormFox 2 train weather
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.
-- Standalone module: no mandatory dependency on StormFox 2 or specific train model.

if SERVER then AddCSLuaFile() end

MetrostroiExpandedWeather = MetrostroiExpandedWeather or {}
local W = MetrostroiExpandedWeather
W.Version = "1.0.0"

local function Subway(ent)
    if not IsValid(ent) then return false end
    local c = ent:GetClass()
    return isstring(c) and c ~= "gmod_subway_base"
        and string.sub(c, 1, 12) == "gmod_subway_"
end

local function SafeNumber(fn, default)
    if not isfunction(fn) then return default end
    local ok, value = pcall(fn)
    if ok and isnumber(value) and value == value then return value end
    return default
end

local function SafeBool(fn)
    if not isfunction(fn) then return false end
    local ok, value = pcall(fn)
    return ok and value == true
end

function W.Sample()
    local sf = StormFox2
    if not istable(sf) or not istable(sf.Weather)
        or not istable(sf.Temperature)
    then
        return nil
    end

    local weather = sf.Weather
    -- StormFox2.GetRainAmount deliberately returns zero for snow at <= -2 C.
    -- Snow must be read using the native IsSnowing / GetPercent pair.
    local amount = math.Clamp(SafeNumber(weather.GetRainAmount, 0), 0, 1)
    local name = ""
    if isfunction(weather.GetCurrent) then
        local ok, obj = pcall(weather.GetCurrent)
        if ok and istable(obj) then
            name = tostring(obj.Name or obj.name or obj.ID or obj.id or "")
            if name == "" and isfunction(obj.GetName) then
                local named, result = pcall(obj.GetName, obj)
                if named then name = tostring(result or "") end
            end
        end
    end
    if name == "" and isfunction(weather.GetDescription) then
        local ok, desc = pcall(weather.GetDescription)
        if ok then name = tostring(desc or "") end
    end

    local snow = SafeBool(weather.IsSnowing)
        or string.find(string.lower(name), "snow", 1, true) ~= nil
    if istable(CWI) and isfunction(CWI.IsSnowing) then
        snow = snow or SafeBool(CWI.IsSnowing)
    end
    if snow then
        amount = math.Clamp(SafeNumber(weather.GetPercent, amount), 0, 1)
    end

    local temp = math.Clamp(SafeNumber(sf.Temperature.Get, 15), -70, 60)
    local wind = istable(sf.Wind) and SafeNumber(sf.Wind.GetForce, 0) or 0
    local thunder = istable(sf.Thunder) and SafeBool(sf.Thunder.IsThundering)
    return {
        temp = temp, wind = math.Clamp(wind, 0, 70),
        rain = snow and 0 or amount,
        snow = snow and amount or 0,
        thunder = thunder, name = name
    }
end

-- Called from the original MEX neglect simulation, which owns the permanent
-- dirt/corrosion state and the Train Fixer integration.
function W.GetWearFactor(train)
    if not Subway(train) then return 0 end
    local d = W._sample
    if not d then
        -- Preserve old MEX precipitation / func_precipitation weathering when
        -- StormFox2 is absent, rather than silently disabling that feature.
        local damage = MetrostroiExpandedDamage
        if istable(damage) and isfunction(damage.IsTrainInRain) then
            return damage.IsTrainInRain(train) and 1 or 0
        end
        return 0
    end
    local wet = train:GetNW2Float("MEX.Weather.Wet", 0)
    return math.Clamp(d.rain * 1.15 + d.snow * 0.38
        + (d.temp < 0 and wet or 0) * 0.12
        + (d.wind > 12 and d.rain or 0) * 0.18, 0, 2)
end

function W.IsRaining(train)
    return Subway(train) and W._sample ~= nil
        and W._sample.rain > 0.02
end

function W.IsControlFrozen(train, action)
    if not Subway(train) or not isstring(action)
        or not train:GetNW2Bool("MEX.Weather.DoorsIced", false)
    then return false end
    local name = string.lower(action)
    -- Only passenger door OPEN commands. Never block a close, emergency
    -- release, brake, traction, or ordinary control.
    return string.find(name, "kdl", 1, true) ~= nil
        or string.find(name, "kdp", 1, true) ~= nil
        or string.find(name, "doorleft", 1, true) ~= nil
        or string.find(name, "doorright", 1, true) ~= nil
        or string.find(name, "openleft", 1, true) ~= nil
        or string.find(name, "openright", 1, true) ~= nil
end

if SERVER then
    local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED)
    local enabled = CreateConVar("mex_weather_enabled", "1", flags,
        "Enable StormFox2 train weather response", 0, 1)
    local visual = CreateConVar("mex_weather_visuals", "1", flags,
        "Enable replicated train wetness, frost and snow visuals", 0, 1)
    local mechanics = CreateConVar("mex_weather_mechanics", "1", flags,
        "Enable weather battery wear and frozen passenger door commands", 0, 1)
    local lightning = CreateConVar("mex_weather_lightning", "1", flags,
        "Allow rare outdoor train lightning strikes in SF2 thunderstorms", 0, 1)

    local function Exposed(train)
        local d = MetrostroiExpandedDamage
        if istable(d) and isfunction(d.IsTrainWeatherExposed) then
            return d.IsTrainWeatherExposed(train)
        end
        local roof = train:LocalToWorld(Vector(0, 0, train:OBBMaxs().z + 8))
        local tr = util.TraceLine({
            start = roof, endpos = roof + Vector(0, 0, 8192),
            filter = train, mask = MASK_SOLID_BRUSHONLY
        })
        return tr.HitSky or tr.Fraction >= 0.999
    end

    function W.Clear(train)
        if not Subway(train) then return end
        train.MEXWeatherStationary = 0
        train.MEXWeatherWetDuration = 0
        for _, key in ipairs({"Wet", "Frost", "Snow"}) do
            train:SetNW2Float("MEX.Weather." .. key, 0)
        end
        train:SetNW2Float("MEX.Weather.Adhesion", 1)
        train:SetNW2Bool("MEX.Weather.DoorsIced", false)
        train:SetNW2Bool("MEX.Weather.Exposed", false)
    end

    local function IsHighest(train, roof)
        -- The train needs direct sky access. Other nearby solid entities,
        -- including other wagons, must not rise significantly above its roof.
        for _, ent in ipairs(ents.FindInSphere(roof, 500)) do
            if ent ~= train and IsValid(ent) and not ent:IsPlayer()
                and ent:GetSolid() ~= SOLID_NONE
            then
                local _, maxs = ent:WorldSpaceAABB()
                if isvector(maxs) and maxs.z > roof.z + 20 then
                    return false
                end
            end
        end
        return true
    end

    local nextScan = 0
    local lastScan = CurTime()
    local nextLightning = CurTime() + 90

    hook.Add("Think", "MEX.Weather.StormFox2Server", function()
        local now = CurTime()
        if now < nextScan then return end
        nextScan = now + 1
        local dt = math.Clamp(now - lastScan, 0, 2)
        lastScan = now
        local data = enabled:GetBool() and W.Sample() or nil
        W._sample = data
        local candidates = {}

        for _, train in ipairs(ents.FindByClass("gmod_subway_*")) do
            if not Subway(train) then continue end
            if not data then
                if train:GetNW2Bool("MEX.Weather.Active", false) then
                    W.Clear(train)
                    train:SetNW2Bool("MEX.Weather.Active", false)
                end
                continue
            end

            local exposed = Exposed(train)
            local speed = train:GetVelocity():Length() * 0.06858
            local wet = train:GetNW2Float("MEX.Weather.Wet", 0)
            local frost = train:GetNW2Float("MEX.Weather.Frost", 0)
            local snow = train:GetNW2Float("MEX.Weather.Snow", 0)
            local rain = exposed and data.rain or 0
            local snowfall = exposed and data.snow or 0
            local stopped = speed < 2
            train.MEXWeatherStationary = stopped
                and (train.MEXWeatherStationary or 0) + dt or 0

            -- Exterior water beads quickly, then slowly dries in the wind.
            wet = math.Clamp(wet + dt * (
                rain * 0.027 + snowfall * 0.008
                - (rain + snowfall < 0.01 and (0.009
                    + data.wind * 0.0004
                    + math.max(0, data.temp) * 0.0003) or 0)
            ), 0, 1)

            -- Freezing is local to exposed wagons. Frost persists briefly after
            -- sheltering, and thaws with warmer temperatures.
            local freeze = exposed and data.temp < 0
                and math.Clamp((-data.temp + 1) / 12, 0.1, 1) or 0
            frost = math.Clamp(frost + dt * (
                freeze * (0.003 + wet * 0.012)
                - (freeze == 0 and (data.temp > 0 and
                    0.006 + data.temp * 0.001 or 0.002) or 0)
            ), 0, 1)

            -- Snow stays on the roof only if the vehicle is parked.
            snow = math.Clamp(snow + dt * (
                (stopped and train.MEXWeatherStationary > 12
                    and data.temp < 2 and snowfall * 0.010 or 0)
                - (not stopped and speed > 15 and 0.024 or 0)
                - (data.temp > 0 and 0.003 + data.temp * 0.0009 or 0)
                - (not exposed and 0.004 or 0)
            ), 0, 1)

            local adhesion = math.Clamp(1 - wet * 0.10
                - frost * 0.13 - snow * 0.13, 0.64, 1)
            train:SetNW2Bool("MEX.Weather.Active", true)
            train:SetNW2Bool("MEX.Weather.Exposed", exposed)
            train:SetNW2Float("MEX.Weather.Temperature", data.temp)
            train:SetNW2Float("MEX.Weather.Wind", data.wind)
            train:SetNW2Float("MEX.Weather.Rain", rain)
            train:SetNW2Float("MEX.Weather.Wet", wet)
            train:SetNW2Float("MEX.Weather.Frost", frost)
            train:SetNW2Float("MEX.Weather.Snow", snow)
            train:SetNW2Float("MEX.Weather.Adhesion", adhesion)
            train:SetNW2Bool("MEX.Weather.Visuals", visual:GetBool())

            local iced = mechanics:GetBool() and exposed and stopped
                and train.MEXWeatherStationary > 75
                and data.temp < -1 and frost > 0.45 and wet > 0.18
            train:SetNW2Bool("MEX.Weather.DoorsIced", iced)

            if mechanics:GetBool() and exposed and wet > 0.45 then
                train.MEXWeatherWetDuration =
                    (train.MEXWeatherWetDuration or 0) + dt
                local damage = MetrostroiExpandedDamage
                if train.MEXWeatherWetDuration > 300 and istable(damage)
                    and isfunction(damage.IsElectricalDamageEnabled)
                    and damage.IsElectricalDamageEnabled()
                    and isfunction(damage.ApplyBatteryDamage)
                then
                    damage.ApplyBatteryDamage(train,
                        dt * wet * 0.0000012, "stormfox2_corrosion")
                end
            else
                train.MEXWeatherWetDuration = math.max(0,
                    (train.MEXWeatherWetDuration or 0) - dt * 3)
            end

            if lightning:GetBool() and exposed and data.thunder then
                local roof = train:LocalToWorld(Vector(
                    0, 0, train:OBBMaxs().z + 12))
                if IsHighest(train, roof) then
                    candidates[#candidates + 1] = train
                end
            end
        end

        -- One global random lightning roll, not one per wagon (large consists
        -- must not amplify the strike frequency). SF2 creates the actual bolt.
        if data and data.thunder and lightning:GetBool()
            and now >= nextLightning
        then
            nextLightning = now + math.Rand(180, 420)
            if #candidates > 0
                and istable(StormFox2.Thunder)
                and isfunction(StormFox2.Thunder.Strike)
            then
                local train = candidates[math.random(#candidates)]
                local roof = train:LocalToWorld(Vector(0, 0,
                    train:OBBMaxs().z + 12))
                local ok, struck = pcall(StormFox2.Thunder.Strike, roof, false)
                if ok and struck ~= false and IsValid(train) then
                    local damage = MetrostroiExpandedDamage
                    if mechanics:GetBool() and istable(damage)
                        and isfunction(damage.IsElectricalDamageEnabled)
                        and damage.IsElectricalDamageEnabled()
                    then
                        if isfunction(damage.ApplyBatteryDamage) then
                            damage.ApplyBatteryDamage(train,
                                math.Rand(0.10, 0.24), "lightning")
                        end
                        local severity = math.Clamp(
                            train:GetNW2Float("MEX.Damage.electrical", 0)
                                + math.Rand(0.15, 0.34), 0, 1)
                        train:SetNW2Float("MEX.Damage.electrical", severity)
                        train:SetNW2Bool("MEX.Damage.ElectricalFault",
                            severity >= 0.45)
                    end
                    train:SetNW2Float("MEX.Weather.LastLightning", now)
                end
            end
        end
    end)

    -- Metrostroi bogeys calculate traction and pneumatic braking from their
    -- MotorForce/PneumaticBrakeForce each Think. Scale only *during* that
    -- calculation, then restore the values: no cumulative multiplication,
    -- altered pressure gauges, network hacks or direct velocity teleporting.
    local function AttachBogeyGrip(bogey)
        if not IsValid(bogey) or bogey:GetClass() ~= "gmod_train_bogey"
            or bogey.MEXWeatherGripWrapped or not isfunction(bogey.Think)
        then return end
        local original = bogey.Think
        bogey.MEXWeatherGripWrapped = true
        bogey.Think = function(self, ...)
            local train = self:GetNW2Entity("TrainEntity")
            local grip = IsValid(train)
                and train:GetNW2Float("MEX.Weather.Adhesion", 1) or 1
            if not mechanics:GetBool() or grip >= 0.999 then
                return original(self, ...)
            end
            local oldMotor = self.MotorForce
            local oldBrake = self.PneumaticBrakeForce
            if isnumber(oldMotor) then self.MotorForce = oldMotor * grip end
            if isnumber(oldBrake) then self.PneumaticBrakeForce = oldBrake * grip end
            local ok, result = pcall(original, self, ...)
            self.MotorForce = oldMotor
            self.PneumaticBrakeForce = oldBrake
            if not ok then error(result) end
            return result
        end
    end

    hook.Add("OnEntityCreated", "MEX.Weather.BogeyCreated", function(ent)
        if not IsValid(ent) or ent:GetClass() ~= "gmod_train_bogey" then return end
        timer.Simple(0, function() AttachBogeyGrip(ent) end)
    end)
    timer.Create("MEX.Weather.BogeyRefresh", 15, 0, function()
        for _, bogey in ipairs(ents.FindByClass("gmod_train_bogey")) do
            AttachBogeyGrip(bogey)
        end
    end)
    timer.Simple(1, function()
        for _, bogey in ipairs(ents.FindByClass("gmod_train_bogey")) do
            AttachBogeyGrip(bogey)
        end
    end)

    concommand.Add("mex_weather_status", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end
        local data = W._sample
        local count, outside, iced = 0, 0, 0
        for _, train in ipairs(ents.FindByClass("gmod_subway_*")) do
            if Subway(train) then
                count = count + 1
                if train:GetNW2Bool("MEX.Weather.Exposed", false) then
                    outside = outside + 1
                end
                if train:GetNW2Bool("MEX.Weather.DoorsIced", false) then
                    iced = iced + 1
                end
            end
        end
        local line = string.format(
            "[MEX Weather] SF2: %s | temp %.1f C | rain %.2f | snow %.2f | wind %.1f m/s | thunder %s | wagons %d (outside %d, iced %d)",
            data and "active" or "unavailable/disabled",
            data and data.temp or 0, data and data.rain or 0,
            data and data.snow or 0, data and data.wind or 0,
            data and tostring(data.thunder) or "false", count, outside, iced)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line .. "\n")
        else print(line) end
    end)

    -- The full Train Fixer/reset also clears local removable weather deposits.
    timer.Simple(0, function()
        local damage = MetrostroiExpandedDamage
        if not istable(damage) or not isfunction(damage.Reset)
            or damage._stormfox2ResetWrapped then return end
        damage._stormfox2ResetWrapped = true
        local oldReset = damage.Reset
        damage.Reset = function(train, ...)
            local result = oldReset(train, ...)
            if Subway(train) then W.Clear(train) end
            return result
        end
    end)
else
    local film = CreateMaterial("mex_weather_translucent_film_v1", "UnlitGeneric", {
        ["$basetexture"] = "models/debug/debugwhite",
        ["$translucent"] = "1",
        ["$vertexalpha"] = "1",
        ["$vertexcolor"] = "1",
        ["$nocull"] = "1"
    })
    local streak = Material("effects/beam_generic01")
    local maxDistSq = 2800 * 2800
    local quality = CreateClientConVar("mex_weather_quality", "1", true, false,
        "Client-side weather detail: 0=off, 1=standard, 2=high", 0, 2)
    local cachedTrains = {}
    local refreshAt = 0

    local function WindowOverlay(train, mins, maxs, wet, frost, wind, highQuality)
        local length = maxs.x - mins.x
        local height = maxs.z - mins.z
        if length < 160 or height < 70 then return end
        local y = math.max(math.abs(mins.y), math.abs(maxs.y)) + 1.5
        local glassZ = mins.z + height * 0.67
        local paneWidth = math.min(105, length / 9)
        local paneHeight = math.min(54, height * 0.26)
        local count = math.Clamp(math.floor(length / (highQuality and 110 or 155)),
            2, highQuality and 12 or 9)
        for side = -1, 1, 2 do
            local normal = train:LocalToWorldAngles(
                Angle(0, side > 0 and 90 or -90, 0)):Forward()
            for i = 1, count do
                local x = mins.x + length * (i - 0.5) / count
                local center = train:LocalToWorld(Vector(x, side * y, glassZ))
                if frost > 0.01 then
                    render.SetMaterial(film)
                    render.DrawQuadEasy(center, normal, paneWidth,
                        paneHeight, Color(212, 232, 244,
                            math.floor(42 * frost)), 0)
                    -- Uneven frozen edges leave the centre relatively clear.
                    render.DrawQuadEasy(train:LocalToWorld(Vector(
                        x, side * (y + 0.15), glassZ + paneHeight * 0.44)),
                        normal, paneWidth, paneHeight * 0.12,
                        Color(238, 247, 252, math.floor(105 * frost)), 0)
                end
                if wet > 0.02 then
                    render.SetMaterial(film)
                    render.DrawQuadEasy(center, normal, paneWidth,
                        paneHeight, Color(145, 172, 198,
                            math.floor(15 * wet)), 0)
                    render.SetMaterial(streak)
                    local n = math.floor(1 + wet * (highQuality and 6 or 3))
                    for j = 1, n do
                        local seed = i * 13.37 + j * 5.71 + side * 9
                        local shift = math.sin(seed * 13.17) * 0.45
                        local localX = x + shift * paneWidth
                        local phase = (CurTime() * (0.35 + wet * 0.85)
                            + seed * 0.31) % 1
                        local zTop = glassZ + paneHeight * (0.5 - phase)
                        local drop = paneHeight * (0.10
                            + (0.10 + math.abs(math.sin(seed))) * wet)
                        local drift = math.Clamp(wind * 0.25, -10, 10)
                        local start = train:LocalToWorld(Vector(
                            localX, side * (y + 0.5), zTop))
                        local finish = train:LocalToWorld(Vector(
                            localX - drift * drop / paneHeight,
                            side * (y + 0.5), zTop - drop))
                        render.DrawBeam(start, finish, 0.55 + wet * 0.9,
                            0, 1, Color(194, 222, 242,
                                math.floor(55 + wet * 95)))
                    end
                end
            end
        end
    end

    local function BodyDrips(train, mins, maxs, amount)
        if amount < 0.12 then return end
        local span = maxs.x - mins.x
        local top = mins.z + (maxs.z - mins.z) * 0.90
        local y = math.max(math.abs(mins.y), math.abs(maxs.y)) + 1.75
        render.SetMaterial(streak)
        for side = -1, 1, 2 do
            for i = 1, 9 do
                local seed = i * 1.83 + side * 3.33
                local x = mins.x + span * (i - 0.5) / 9
                local phase = (CurTime() * 0.72 + seed) % 1
                local startZ = top - phase * 18
                local length = 6 + amount * (10 + 14 * math.abs(math.sin(seed)))
                local start = train:LocalToWorld(Vector(x, side * y, startZ))
                local finish = train:LocalToWorld(Vector(
                    x - amount * 2.5, side * y, startZ - length))
                render.DrawBeam(start, finish, 0.5 + amount * 0.6,
                    0, 1, Color(175, 203, 224, math.floor(amount * 75)))
            end
        end
    end

    local function RoofSnow(train, mins, maxs, amount)
        if amount < 0.015 then return end
        local z = maxs.z + 1.8
        local length = maxs.x - mins.x
        local width = maxs.y - mins.y
        if length <= 0 or width <= 0 then return end
        render.SetMaterial(film)
        for i = 1, 7 do
            local x = mins.x + length * (i - 0.5) / 7
            local p = train:LocalToWorld(Vector(x, 0, z))
            render.DrawQuadEasy(p, train:GetUp(),
                length / 7 * 0.92, width * (0.60
                    + math.abs(math.sin(i * 7.3)) * 0.25),
                Color(235, 241, 247,
                    math.floor((85 + (i % 3) * 12) * amount)), 90)
        end
    end

    hook.Add("PostDrawTranslucentRenderables",
        "MEX.Weather.TrainSurfaceEffects",
        function(depth, skybox)
            if depth or skybox or quality:GetInt() <= 0 then return end
            local now = CurTime()
            if now >= refreshAt then
                refreshAt = now + 0.75
                cachedTrains = ents.FindByClass("gmod_subway_*")
            end
            local me = EyePos()
            local drawn = 0
            local highQuality = quality:GetInt() >= 2
            for _, train in ipairs(cachedTrains) do
                if not Subway(train)
                    or not train:GetNW2Bool("MEX.Weather.Active", false)
                    or not train:GetNW2Bool("MEX.Weather.Visuals", true)
                    or me:DistToSqr(train:WorldSpaceCenter()) > maxDistSq
                then continue end
                local wet = train:GetNW2Float("MEX.Weather.Wet", 0)
                local frost = train:GetNW2Float("MEX.Weather.Frost", 0)
                local snow = train:GetNW2Float("MEX.Weather.Snow", 0)
                if wet + frost + snow < 0.02 then continue end
                local mins, maxs = train:OBBMins(), train:OBBMaxs()
                WindowOverlay(train, mins, maxs, wet, frost,
                    train:GetNW2Float("MEX.Weather.Wind", 0), highQuality)
                BodyDrips(train, mins, maxs, wet)
                RoofSnow(train, mins, maxs, snow)
                drawn = drawn + 1
                if drawn >= (highQuality and 12 or 7) then break end
            end
        end)
end
