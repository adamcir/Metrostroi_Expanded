-- Metrostroi Expanded - read-only player position/track diagnostics.
-- Integrated from the user's standalone ars_player_pos.lua utility.
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
        ply:PrintMessage(HUD_PRINTCONSOLE,text.."\n")
    end
end

local function WithPlayer(ply)
    local p=TargetPlayer(ply)
    if not IsValid(p) then Emit(ply,"Player not found") end
    return p
end

concommand.Add("mex_ars_player_pos",function(ply)
    local p=WithPlayer(ply)
    if not IsValid(p) then return end
    local pos=p:GetPos()
    Emit(ply,string.format("Player position: %.4f %.4f %.4f",
        pos.x,pos.y,pos.z))
end)

concommand.Add("mex_ars_player_pos_full",function(ply)
    local p=WithPlayer(ply)
    if not IsValid(p) then return end
    local pos=p:GetPos()
    local ang=p:EyeAngles()
    Emit(ply,string.format(
        "Player position: %.4f %.4f %.4f | EyeAngles: %.4f %.4f %.4f",
        pos.x,pos.y,pos.z,ang.p,ang.y,ang.r))
end)

concommand.Add("mex_ars_player_pos_json",function(ply)
    local p=WithPlayer(ply)
    if not IsValid(p) then return end
    local pos=p:GetPos()
    Emit(ply,util.TableToJSON({
        Pos=string.format("[%.4f %.4f %.4f]",pos.x,pos.y,pos.z)
    }) or "{}")
end)

concommand.Add("mex_ars_player_pos_track",function(ply)
    local p=WithPlayer(ply)
    if not IsValid(p) then return end
    if not Metrostroi or not isfunction(Metrostroi.GetPositionOnTrack) then
        Emit(ply,"Metrostroi track network is not available")
        return
    end
    local ok,result=pcall(Metrostroi.GetPositionOnTrack,p:GetPos(),p:GetAngles())
    if not ok then
        Emit(ply,"Metrostroi track lookup failed: "..tostring(result))
        return
    end
    local track=istable(result) and result[1]
    if not track then
        Emit(ply,"Player is not close enough to a Metrostroi track")
        return
    end
    Emit(ply,string.format(
        "Player track: Path=%s Node=%s TrackX=%.3f | lateral=%.3f vertical=%.3f distance=%.3f",
        tostring(track.path and track.path.id or "nil"),
        tostring(track.node1 and track.node1.id or "nil"),
        tonumber(track.x) or 0,
        tonumber(track.y) or 0,
        tonumber(track.z) or 0,
        tonumber(track.distance) or 0))
end)
