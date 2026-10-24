-- Metrostroi Expanded: ARS/EPK diagnostic and conservative LKT repair.
-- Copyright (C) 2026 Adam Cir / Adava Software. GPL-3.0-or-later.
-- Does NOT force the brake valves, release EPK or suppress overspeed protection.
if not SERVER then return end

local repairEnabled = CreateConVar("mex_ars_repair_enabled", "1", FCVAR_ARCHIVE,
    "Repair a demonstrably incorrect ARS brake-confirmation (LKT) state at a standstill")
local watchEnabled = CreateConVar("mex_ars_watch_enabled", "1", FCVAR_ARCHIVE,
    "Log EPK activation and its ARS/pneumatic state on Metrostroi trains")

local wrapped = setmetatable({}, {__mode = "k"})
local previousEPK = setmetatable({}, {__mode = "k"})
local lastRepairLog = setmetatable({}, {__mode = "k"})

local function val(relay)
    return relay and relay.Value or nil
end
local function show(value)
    return value == nil and "nil" or tostring(value)
end
local function number(value)
    return type(value) == "number" and string.format("%.3f", value) or show(value)
end
local function output(ply, line)
    print("[MEX ARS] " .. line)
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, "[MEX ARS] " .. line .. "\n") end
end
local function arsSystems(wagon)
    local result, seen = {}, {}
    local function add(name, sys)
        if type(sys) ~= "table" or seen[sys] then return end
        seen[sys] = true
        result[#result + 1] = {name = name, sys = sys}
    end
    if type(wagon.Systems) == "table" then
        for name, sys in pairs(wagon.Systems) do
            if type(name) == "string" and string.find(string.upper(name), "ARS", 1, true) then
                add(name, sys)
            end
        end
    end
    add("ALS_ARS", wagon.ALS_ARS)
    return result
end

-- Metrostroi's documented LKT requirement: every connected wagon must
-- confirm *either* electric (RKTT) or pneumatic (DKPT) braking.
-- Unknown/missing relays are NEVER interpreted as a successful check.
local function confirmedConsist(train)
    if type(train.WagonList) ~= "table" or #train.WagonList == 0 then return false, "no wagon list" end
    for i, wagon in ipairs(train.WagonList) do
        if not IsValid(wagon) then return false, "invalid wagon " .. i end
        local rktt, dkpt = val(wagon.RKTT), val(wagon.DKPT)
        if type(rktt) ~= "number" or type(dkpt) ~= "number" then
            return false, "unknown relays in wagon " .. i
        end
        if rktt < 0.5 and dkpt < 0.5 then
            return false, "braking not confirmed in wagon " .. i
        end
    end
    return true
end

local function repairLKT(system)
    if not repairEnabled:GetBool() or type(system) ~= "table" then return end
    local train = system.Train
    if not IsValid(train) or not train.Pneumatic then return end
    -- Never change an already confirmed state or any genuine emergency condition.
    if system.LKT == true or system.EnableARS ~= true or system.Overspeed == true then return end
    if system.RealNoFreq ~= false or type(system.SpeedLimit) ~= "number" or system.SpeedLimit <= 0 then return end
    if type(system.Speed) ~= "number" or system.Speed >= 0.25 then return end
    if train.Pneumatic.EmergencyValveEPK or train.Pneumatic.EmergencyValve then return end
    if val(train.STOPKRAN) and val(train.STOPKRAN) > 0.5 then return end
    local confirmed = confirmedConsist(train)
    if not confirmed then return end

    -- Correct only this exact inconsistency, before the original ARS brake logic
    -- decides whether an unconfirmed stopped train must trigger EPK.
    system.LKT = true
    if CurTime() - (lastRepairLog[system] or -1e6) > 10 then
        lastRepairLog[system] = CurTime()
        print("[MEX ARS] Repaired false LKT on " .. train:EntIndex() ..
            " (all wagons confirm braking; ARS speed valid; EPK was inactive)")
    end
end

local function attach(train)
    for _, entry in ipairs(arsSystems(train)) do
        local sys = entry.sys
        if not wrapped[sys] then
            wrapped[sys] = true
            -- These methods run AFTER Metrostroi checks RKTT/DKPT, but BEFORE
            -- it evaluates the EPK timers. Wrapping Think would be too late.
            for _, method in ipairs({"MoscowARS", "PiterARS"}) do
                local original = sys[method]
                if type(original) == "function" then
                    sys[method] = function(self, ...)
                        repairLKT(self)
                        return original(self, ...)
                    end
                end
            end
        end
    end
end

local function snapshot(train)
    local p = train.Pneumatic
    if not p then return "no pneumatic system" end
    local pieces = {
        "train=" .. train:EntIndex(), "class=" .. train:GetClass(),
        "speed=" .. number(train.Speed), "valve=" .. show(p.ValveType),
        "position=" .. show(p.DriverValvePosition),
        "BL=" .. number(p.BrakeLinePressure), "BC=" .. number(p.BrakeCylinderPressure),
        "TL=" .. number(p.TrainLinePressure),
        "PN1=" .. show(val(train.PneumaticNo1)), "PN2=" .. show(val(train.PneumaticNo2)),
        "RKTT=" .. show(val(train.RKTT)), "DKPT=" .. show(val(train.DKPT)),
        "EPK=" .. show(p.EmergencyValveEPK), "EV=" .. show(p.EmergencyValve),
        "EPKswitch=" .. show(val(train.EPK)), "wire1=" .. show(train:ReadTrainWire(1))
    }
    return table.concat(pieces, " ")
end
local function report(train, ply)
    output(ply, snapshot(train))
    for _, entry in ipairs(arsSystems(train)) do
        local s = entry.sys
        output(ply, "ARS " .. entry.name ..
            " LKT=" .. show(s.LKT) .. " enabled=" .. show(s.EnableARS) ..
            " speed=" .. number(s.Speed) .. " limit=" .. show(s.SpeedLimit) ..
            " noFreq=" .. show(s.RealNoFreq) .. " overspeed=" .. show(s.Overspeed) ..
            " brake=" .. show(s.ARSBrake) .. " PB1=" .. show(s.PneumaticBrake1) ..
            " PB2=" .. show(s.PneumaticBrake2) .. " LVD=" .. show(s.LVD) ..
            " EPKTimer=" .. show(s.EPKTimer) .. " EPKTimer2=" .. show(s.EPKTimer2))
    end
    local ok, reason = confirmedConsist(train)
    output(ply, "LKT relay check=" .. show(ok) .. (reason and " (" .. reason .. ")" or ""))
    for i, wagon in ipairs(train.WagonList or {}) do
        if IsValid(wagon) then
            output(ply, "wagon " .. i .. " #" .. wagon:EntIndex() ..
                " RKTT=" .. show(val(wagon.RKTT)) .. " DKPT=" .. show(val(wagon.DKPT)) ..
                " BC=" .. number(wagon.Pneumatic and wagon.Pneumatic.BrakeCylinderPressure))
        end
    end
end

concommand.Add("mex_ars_status", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local id = tonumber(args[1] or "")
    if id then
        local train = Entity(id)
        if not IsValid(train) or not string.StartWith(train:GetClass(), "gmod_subway_") then
            output(ply, "No train with entity ID " .. show(id))
            return
        end
        report(train, ply)
    else
        for _, train in ipairs(ents.FindByClass("gmod_subway_*")) do
            if IsValid(train) and #arsSystems(train) > 0 then report(train, ply) end
        end
    end
end)

local nextScan = 0
hook.Add("Think", "MEX_ARS_RepairAndWatch", function()
    if CurTime() < nextScan then return end
    nextScan = CurTime() + 0.15
    for _, train in ipairs(ents.FindByClass("gmod_subway_*")) do
        if IsValid(train) and train.Pneumatic and #arsSystems(train) > 0 then
            attach(train)
            local active = train.Pneumatic.EmergencyValveEPK == true
            local old = previousEPK[train]
            if watchEnabled:GetBool() and old == false and active then
                print("[MEX ARS] EPK ACTIVATED: " .. snapshot(train))
                for _, entry in ipairs(arsSystems(train)) do
                    local s = entry.sys
                    print("[MEX ARS] " .. entry.name .. " LKT=" .. show(s.LKT) ..
                        " ARS=" .. show(s.EnableARS) .. " NoFreq=" .. show(s.RealNoFreq) ..
                        " limit=" .. show(s.SpeedLimit) .. " overspeed=" .. show(s.Overspeed) ..
                        " EPKTimer=" .. show(s.EPKTimer) .. " EPKTimer2=" .. show(s.EPKTimer2))
                end
            end
            previousEPK[train] = active
        end
    end
end)

print("[MEX ARS] Brake/EPK diagnostic loaded. Use mex_ars_status [entity ID]; " ..
      "mex_ars_repair_enabled 0/1; mex_ars_watch_enabled 0/1")
