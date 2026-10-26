-- MEX: read-only map signal / ARS diagnostics.
-- Explains why a custom map shows a speed code instead of 0 or OC (no frequency).
if not SERVER then return end

local function fmt(v)
    if v == nil then return "nil" end
    if type(v) == "table" then
        local t = {}
        for i, x in ipairs(v) do t[#t + 1] = tostring(x) end
        return "[" .. table.concat(t, ",") .. "]"
    end
    return tostring(v)
end

local function emit(ply, msg)
    local line = "[MEX MAP ARS] " .. msg
    print(line)
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line .. "\n") end
end

local function validTrain(ent)
    return IsValid(ent) and string.StartWith(ent:GetClass(), "gmod_subway_")
end

local function reportTrain(ply, train)
    if not validTrain(train) then return end
    local m = Metrostroi
    local dir = m and m.TrainDirections and m.TrainDirections[train]
    emit(ply, "train #" .. train:EntIndex() .. " " .. train:GetClass()
        .. " speed=" .. fmt(train.Speed) .. " direction=" .. fmt(dir))
    local list = m and m.TrainPositions and m.TrainPositions[train]
    local pos = list and list[1]
    if not (pos and pos.node1 and pos.x) then
        emit(ply, "No track position for train (track graph / train position issue).")
        return
    end
    emit(ply, "track path=" .. fmt(pos.node1.path and pos.node1.path.id)
        .. " x=" .. fmt(math.Round(pos.x, 2)))
    if type(m.GetARSJoint) ~= "function" then
        emit(ply, "Metrostroi.GetARSJoint not available")
        return
    end
    local ok, nextSignal, prevSignal = pcall(m.GetARSJoint, pos.node1, pos.x, dir, train)
    if not ok then
        emit(ply, "GetARSJoint ERROR: " .. fmt(nextSignal))
        return
    end
    for _, pair in ipairs({{"NEXT", nextSignal}, {"PREVIOUS", prevSignal}}) do
        local s = pair[2]
        if IsValid(s) then
            local r = s.Routes and s.Routes[s.Route or 1]
            emit(ply, pair[1] .. " " .. fmt(s.Name)
                .. " signal#" .. s:EntIndex()
                .. " path=" .. fmt(s.TrackPosition and s.TrackPosition.node1.path.id)
                .. " x=" .. fmt(s.TrackX)
                .. " code=" .. fmt(r and r.ARSCodes)
                .. " codeType=" .. type(r and r.ARSCodes)
                .. " ARSSpeedLimit=" .. fmt(s.ARSSpeedLimit)
                .. " NextSpeed=" .. fmt(s.ARSNextSpeedLimit)
                .. " occupied=" .. fmt(s.Occupied)
                .. " FreeBS=" .. fmt(s.FreeBS)
                .. " TrackDir=" .. fmt(s.TrackDir)
                .. " nextLink=" .. fmt(IsValid(s.NextSignalLink) and s.NextSignalLink.Name or nil))
        else
            emit(ply, pair[1] .. " signal NOT FOUND (check track graph / signal alignment)")
        end
    end
    if type(train.Systems) == "table" then
        for name, sys in pairs(train.Systems) do
            if type(name) == "string" and string.find(name:upper(), "ARS", 1, true)
                and type(sys) == "table" then
                emit(ply, "system " .. name .. " signal40=" .. fmt(sys.Signal40)
                    .. " signal0=" .. fmt(sys.Signal0)
                    .. " NoFreq=" .. fmt(sys.NoFreq)
                    .. " RealNoFreq=" .. fmt(sys.RealNoFreq)
                    .. " LKT=" .. fmt(sys.LKT)
                    .. " EnableARS=" .. fmt(sys.EnableARS)
                    .. " Limit=" .. fmt(sys.SpeedLimit)
                    .. " EPKTimer2=" .. fmt(sys.EPKTimer2))
            end
        end
    end
    local p = train.Pneumatic
    if p then
        -- Brake-line reduction applies the distributor even when PN2 and EPK are OFF.
        -- For the Ezh3 013 valve, position 4 targets ~4 atm in BL (service braking).
        local reduced = p.TrainToBrakeReducedPressure
        local targetBC = type(reduced) == "number" and type(p.BrakeLinePressure) == "number"
            and math.max(0, math.min(5.2, 1.5*(math.min(5.1, reduced) - p.BrakeLinePressure))) or nil
        emit(ply, "pneumatic EPK=" .. fmt(p.EmergencyValveEPK)
            .. " emergency=" .. fmt(p.EmergencyValve)
            .. " BC=" .. fmt(p.BrakeCylinderPressure)
            .. " BL=" .. fmt(p.BrakeLinePressure)
            .. " TL=" .. fmt(p.TrainLinePressure)
            .. " valveType=" .. fmt(p.ValveType)
            .. " valvePosition=" .. fmt(p.DriverValvePosition)
            .. " valveConnected=" .. fmt(train.DriverValveDisconnect and train.DriverValveDisconnect.Value)
            .. " distributorConnected=" .. fmt(train.AirDistributorDisconnect and train.AirDistributorDisconnect.Value)
            .. " targetBC=" .. fmt(targetBC)
            .. " PN1=" .. fmt(train.PneumaticNo1 and train.PneumaticNo1.Value)
            .. " PN2=" .. fmt(train.PneumaticNo2 and train.PneumaticNo2.Value))
        if p.EmergencyValveEPK == false and p.EmergencyValve == false
           and train.PneumaticNo2 and train.PneumaticNo2.Value == 0
           and type(p.BrakeLinePressure) == "number" and p.BrakeLinePressure < 4.7 then
            emit(ply, "BRAKING DIAGNOSIS: BL reduced below 4.7 atm with EPK OFF and PN2 OFF; "
                .. "the distributor can hold the brake cylinders. "
                .. "Check driver valve position; Ezh3 type-013 position 4 targets ~4.0 atm. "
                .. "Position 2 targets ~5.1 atm for release.")
        end
    end
end

concommand.Add("mex_ars_map_check", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    if not Metrostroi or not Metrostroi.Paths then
        emit(ply, "Track graph is not initialized.")
        return
    end
    emit(ply, "map=" .. game.GetMap()
        .. " metrostroi_ars_independent=" .. fmt(GetConVarNumber("metrostroi_ars_independent")))
    emit(ply, "ARS coding: 1=no frequency (OC), 0=stop, 4=40, 6=60.")
    for id, path in ipairs(Metrostroi.Paths) do
        local first, last = path[1], path[#path]
        if first and last then
            emit(ply, "path " .. id .. " nodes=" .. #path
                .. " startPrev=" .. fmt(first.prev ~= nil)
                .. " endNext=" .. fmt(last.next ~= nil)
                .. " startBranches=" .. fmt(first.branches and #first.branches or 0)
                .. " endBranches=" .. fmt(last.branches and #last.branches or 0))
        end
    end
    local count, wrongType, missingOC = 0, 0, 0
    local signals = ents.FindByClass("gmod_track_signal")
    table.sort(signals, function(a, b) return (a.Name or "") < (b.Name or "") end)
    for _, signal in ipairs(signals) do
        local route = signal.Routes and signal.Routes[signal.Route or 1]
        if route then
            count = count + 1
            local codes = route.ARSCodes
            if type(codes) ~= "string" then wrongType = wrongType + 1 end
            local asString = type(codes) == "table" and table.concat(codes) or tostring(codes or "")
            if not string.find(asString, "1", 1, true) then missingOC = missingOC + 1 end
            emit(ply, fmt(signal.Name) .. " code=" .. fmt(codes)
                .. " type=" .. type(codes)
                .. " nextConfig=" .. fmt(route.NextSignal)
                .. " nextResolved=" .. fmt(IsValid(signal.NextSignalLink) and signal.NextSignalLink.Name or nil)
                .. " path=" .. fmt(signal.TrackPosition and signal.TrackPosition.node1.path.id)
                .. " dir=" .. fmt(signal.TrackDir)
                .. " occupied=" .. fmt(signal.Occupied)
                .. " free=" .. fmt(signal.FreeBS)
                .. " output=" .. fmt(signal.ARSSpeedLimit))
        end
    end
    emit(ply, "SUMMARY signals=" .. count .. " non-string ARSCodes=" .. wrongType
        .. " routes without OC code=" .. missingOC)
    local id = tonumber(args[1] or "")
    if id then reportTrain(ply, Entity(id)) end
end)

concommand.Add("mex_ars_map_train", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local id = tonumber(args[1] or "")
    if not id or not validTrain(Entity(id)) then
        emit(ply, "Usage: mex_ars_map_train <train entity ID>")
        return
    end
    reportTrain(ply, Entity(id))
end)
-- Read-only live tracking of brief NO-FREQUENCY transitions and EPK states.
local watchId = nil
local lastWatch = nil
local watchTime = 0
concommand.Add("mex_ars_map_watch", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local id = tonumber(args[1] or "")
    if id == 0 then
        watchId, lastWatch = nil, nil
        emit(ply, "Live watch disabled.")
    elseif id and validTrain(Entity(id)) then
        watchId, lastWatch, watchTime = id, nil, 0
        emit(ply, "Live watch started for train #" .. id ..
            "; prints only when received joint, brake state, or EPK state changes.")
    else
        emit(ply, "Usage: mex_ars_map_watch <train entity ID | 0>")
    end
end)

hook.Add("Think", "MEX_ARS_MapPassiveWatch", function()
    if not watchId or CurTime() < watchTime then return end
    watchTime = CurTime() + 0.25
    local train = Entity(watchId)
    if not validTrain(train) then
        watchId, lastWatch = nil, nil
        print("[MEX MAP ARS] Watched train was removed.")
        return
    end
    local p = train.Pneumatic
    local m = Metrostroi
    if not p or not m or not m.GetARSJoint or not m.TrainPositions then return end
    local positions = m.TrainPositions[train]
    local pos = positions and positions[1]
    local signal, prev
    if pos and pos.node1 then
        local ok, a, b = pcall(m.GetARSJoint, pos.node1, pos.x, m.TrainDirections[train], train)
        if ok then signal, prev = a, b end
    end
    local name = IsValid(signal) and signal.Name or "NONE/OC"
    local code = IsValid(signal) and tostring(signal.ARSSpeedLimit or "?") or "NO SIGNAL"
    local epk = p.EmergencyValveEPK == true
    local ev = p.EmergencyValve == true
    local pn2 = train.PneumaticNo2 and train.PneumaticNo2.Value or "?"
    local valve = p.DriverValvePosition or "?"
    local state = table.concat({name, code, tostring(epk), tostring(ev),
        tostring(pn2), tostring(valve)}, "/")
    if state ~= lastWatch then
        print("[MEX MAP ARS] WATCH train=" .. train:EntIndex()
            .. " speed=" .. fmt(math.Round(train.Speed or 0, 2))
            .. " next=" .. name
            .. " prev=" .. (IsValid(prev) and fmt(prev.Name) or "NONE")
            .. " ARSCode=" .. code
            .. " EPK=" .. fmt(epk)
            .. " emergency=" .. fmt(ev)
            .. " PN2=" .. fmt(pn2)
            .. " valvePos=" .. fmt(valve)
            .. " BL=" .. fmt(math.Round(p.BrakeLinePressure or 0, 3))
            .. " BC=" .. fmt(math.Round(p.BrakeCylinderPressure or 0, 3))
            .. " path=" .. (pos and fmt(pos.node1.path and pos.node1.path.id) or "nil"))
        lastWatch = state
    end
end)

print("[MEX MAP ARS] Diagnostics ready: mex_ars_map_check [train ID], mex_ars_map_train <ID>, mex_ars_map_watch <ID|0>")
