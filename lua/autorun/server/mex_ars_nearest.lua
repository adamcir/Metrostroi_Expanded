-- Metrostroi Expanded - read-only ARS nearest signal diagnostics.
-- Integrated from the user's standalone ars_nearest.lua utility.
-- All console commands use the mex_ars_* prefix.
if not SERVER then return end

local function TargetPlayer(ply)
    if IsValid(ply) then return ply end
    return player.GetAll()[1]
end

local function Emit(ply, message)
    local text="[MEX ARS] "..message
    print(text)
    if IsValid(ply) then
        ply:PrintMessage(HUD_PRINTCONSOLE, text.."\n")
    end
end

local function FindNearestSignal(ply, maxDistance)
    local p=TargetPlayer(ply)
    if not IsValid(p) then return nil, nil, nil end
    local best, bestDistSqr
    local pos=p:GetPos()
    local limitSqr=maxDistance and maxDistance * maxDistance
    for _,ent in ipairs(ents.FindByClass("gmod_track_signal")) do
        if IsValid(ent) then
            local d=pos:DistToSqr(ent:GetPos())
            if (not limitSqr or d<=limitSqr)
                and (not bestDistSqr or d<bestDistSqr) then
                best=ent
                bestDistSqr=d
            end
        end
    end
    if not IsValid(best) then return p, nil, nil end
    return p, best, math.sqrt(bestDistSqr)
end

local function GetSignal(ply, maxDistance)
    local target,signal,dist=FindNearestSignal(ply,maxDistance)
    if not IsValid(target) then
        Emit(ply,"Player not found (specify a player by running in-game, or connect a player).")
    elseif not IsValid(signal) then
        Emit(ply,maxDistance
            and string.format("No signal found within %.1f units",maxDistance)
            or "No gmod_track_signal found")
    end
    return signal,dist
end

local function SignalTrack(signal)
    local pos=signal.TrackPosition
    return tostring(pos and pos.path and pos.path.id or "nil"),
        tostring(pos and pos.node1 and pos.node1.id or "nil")
end

concommand.Add("mex_ars_nearest",function(ply)
    local signal,dist=GetSignal(ply)
    if not IsValid(signal) then return end
    Emit(ply,string.format("Nearest ARS: %s | %.2f units",
        tostring(signal.Name or "(unnamed)"),dist or -1))
end)

concommand.Add("mex_ars_nearest_full",function(ply)
    local signal,dist=GetSignal(ply)
    if not IsValid(signal) then return end
    local pos=signal:GetPos()
    local pathId,nodeId=SignalTrack(signal)
    local maxARS=signal.GetMaxARS and signal:GetMaxARS() or "nil"
    Emit(ply,string.format("Name=%s | EntIndex=%d | Distance=%.2f",
        tostring(signal.Name or "(unnamed)"),signal:EntIndex(),dist or -1))
    Emit(ply,string.format("Pos=[%.4f %.4f %.4f] | Path=%s | Node=%s | TrackX=%s",
        pos.x,pos.y,pos.z,pathId,nodeId,tostring(signal.TrackX)))
    Emit(ply,string.format("MaxARS=%s | ARSOnly=%s | Left=%s | TrackDir=%s",
        tostring(maxARS),tostring(signal.ARSOnly),tostring(signal.Left),
        tostring(signal.TrackDir)))
end)

concommand.Add("mex_ars_nearest_pos",function(ply)
    local signal=GetSignal(ply)
    if not IsValid(signal) then return end
    local pos=signal:GetPos()
    Emit(ply,string.format("%s Pos: %.4f %.4f %.4f",
        tostring(signal.Name or "(unnamed)"),pos.x,pos.y,pos.z))
end)

concommand.Add("mex_ars_nearest_json",function(ply)
    local signal=GetSignal(ply)
    if not IsValid(signal) then return end
    local pos=signal:GetPos()
    local result={
        Name=tostring(signal.Name or ""),
        Pos=string.format("[%.4f %.4f %.4f]",pos.x,pos.y,pos.z)
    }
    Emit(ply,util.TableToJSON(result) or "{}")
end)

concommand.Add("mex_ars_nearest_track",function(ply)
    local signal,dist=GetSignal(ply)
    if not IsValid(signal) then return end
    local pathId,nodeId=SignalTrack(signal)
    Emit(ply,string.format("%s | Distance=%.2f | Path=%s | Node=%s | TrackX=%s | TrackDir=%s",
        tostring(signal.Name or "(unnamed)"),dist or -1,pathId,nodeId,
        tostring(signal.TrackX),tostring(signal.TrackDir)))
end)

concommand.Add("mex_ars_nearest_within",function(ply,_,args)
    local maxDistance=tonumber(args and args[1]) or 500
    if maxDistance<=0 or maxDistance>100000 then
        Emit(ply,"Usage: mex_ars_nearest_within <units> (1 to 100000)")
        return
    end
    local signal,dist=GetSignal(ply,maxDistance)
    if not IsValid(signal) then return end
    Emit(ply,string.format("%s | %.2f units",
        tostring(signal.Name or "(unnamed)"),dist or -1))
end)
