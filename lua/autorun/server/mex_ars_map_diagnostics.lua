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
        emit(ply, "pneumatic EPK=" .. fmt(p.EmergencyValveEPK)
            .. " emergency=" .. fmt(p.EmergencyValve)
            .. " BC=" .. fmt(p.BrakeCylinderPressure)
            .. " BL=" .. fmt(p.BrakeLinePressure)
            .. " PN2=" .. fmt(train.PneumaticNo2 and train.PneumaticNo2.Value))
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
print("[MEX MAP ARS] Diagnostics ready: mex_ars_map_check [train ID], mex_ars_map_train <ID>")
