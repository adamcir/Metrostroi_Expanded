-- Metrostroi Expanded - Cinematic helpers for singleplayer filming.
-- Copyright (C) 2026 Adam Cir / Adava Software - GPL-3.0.
-- No global physics pause: Metrostroi electrical simulation must keep ticking.
if not SERVER then return end

MEXCinematic = MEXCinematic or {}
local C = MEXCinematic
C.Pending = C.Pending or {}

local function Train(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    return isstring(class) and class ~= "gmod_subway_base"
        and class:sub(1, 12) == "gmod_subway_"
end

local function Message(ply, msg)
    if IsValid(ply) then ply:ChatPrint("[MEX Cinematic] " .. msg) end
    print("[MEX Cinematic] " .. msg)
end

local function Allowed(ply)
    return IsValid(ply) and ply:IsAdmin()
end

local function AimedTrain(ply)
    if not IsValid(ply) then return nil end
    local tr = ply:GetEyeTrace()
    local ent = tr and tr.Entity
    if Train(ent) then return ent end
    if IsValid(ent) then
        local list = {ent:GetParent(), ent.TrainEntity, ent.Train,
            ent:GetNW2Entity("TrainEntity"), ent:GetNWEntity("TrainEntity")}
        for _, v in ipairs(list) do
            if Train(v) then return v end
        end
    end
end

local function FindVehicle(ply)
    local eye = ply:EyePos()
    local tr = ply:GetEyeTrace()
    local preferred = tr and tr.Entity
    local best, bestDistance
    for _, ent in ipairs(ents.FindInSphere(eye, 500)) do
        if IsValid(ent) and ent:IsVehicle() and ent:GetClass() == "prop_vehicle_prisoner_pod"
            and not IsValid(ent:GetDriver()) then
            local train = ent:GetParent()
            if not Train(train) then
                train = ent:GetNW2Entity("TrainEntity")
            end
            if Train(train) and (ent == preferred or (ent:GetPos():DistToSqr(eye) < 150*150)) then
                local dist = ent:GetPos():DistToSqr(eye)
                if ent == preferred then dist = -1 end
                if not bestDistance or dist < bestDistance then
                    best, bestDistance = ent, dist
                end
            end
        end
    end
    return best
end

concommand.Add("mex_cinematic_seat", function(ply)
    if not Allowed(ply) then return end
    if ply:InVehicle() then Message(ply, "Leave your current vehicle first.") return end
    local vehicle = FindVehicle(ply)
    if not IsValid(vehicle) then
        Message(ply, "Stand by an empty MEX passenger seat and aim at it.")
        return
    end
    -- Use GMod's normal vehicle entry path, not a position or physics hack.
    ply:EnterVehicle(vehicle)
    Message(ply, ply:InVehicle() and "Seated." or "Could not enter seat.")
end)

local function Stop(ply, silent)
    local state = C.Pending[ply]
    if not state then return end
    timer.Remove(state.timerName)
    C.Pending[ply] = nil
    if not silent then Message(ply, "Departure cancelled.") end
end

-- Commands may vary between different Metrostroi trains. ButtonEvent is
-- deliberately used instead of writing low-level electrical/physics values.
local function Press(train, button)
    if not IsValid(train) or not isfunction(train.ButtonEvent) then return false end
    local ok, err = pcall(train.ButtonEvent, train, button, true)
    if not ok then
        ErrorNoHalt("[MEX Cinematic] " .. tostring(err) .. "\n")
        return false
    end
    timer.Simple(0.15, function()
        if IsValid(train) and isfunction(train.ButtonEvent) then
            pcall(train.ButtonEvent, train, button, false)
        end
    end)
    return true
end

-- mex_cinematic_departure <delay seconds> <door event> <traction event>
-- Default: door event VUD1Set; traction event KVUp. Use "none" to skip.
concommand.Add("mex_cinematic_departure", function(ply, _, args)
    if not Allowed(ply) then return end
    local train = AimedTrain(ply)
    if not Train(train) then
        Message(ply, "Aim at the driver car before arming a departure.")
        return
    end
    if train.CPPICanTool and not train:CPPICanTool(ply, "mex_cinematic") then
        Message(ply, "Permission denied for this train.")
        return
    end
    local delay = math.Clamp(tonumber(args[1]) or 10, 2, 120)
    local door = tostring(args[2] or "VUD1Set")
    local traction = tostring(args[3] or "KVUp")
    -- Reject arbitrary button names that could contain separators/invalid input.
    if not door:match("^[%w_]+$") or not traction:match("^[%w_]+$") then
        Message(ply, "Invalid button name.")
        return
    end
    Stop(ply, true)
    local name = "mex_cinematic_departure_" .. ply:EntIndex()
    C.Pending[ply] = {timerName = name, train = train, due = CurTime() + delay}
    timer.Create(name, delay, 1, function()
        local pending = C.Pending[ply]
        if not pending or pending.timerName ~= name then return end
        C.Pending[ply] = nil
        if not IsValid(ply) or not Train(train) then return end
        if door ~= "none" and not Press(train, door) then
            Message(ply, "Door event unavailable. Departure aborted.")
            return
        end
        -- The door animation completes before traction command is sent.
        timer.Simple(3, function()
            if not IsValid(ply) or not Train(train) then return end
            if traction ~= "none" and not Press(train, traction) then
                Message(ply, "Traction event unavailable.")
                return
            end
            Message(ply, "Departure commands sent (train safety systems remain active).")
        end)
    end)
    Message(ply, string.format("Armed #%d: %.1f s to door command, then 3 s to traction. Sit down now.", train:EntIndex(), delay))
end)

concommand.Add("mex_cinematic_cancel", function(ply)
    if not Allowed(ply) then return end
    Stop(ply, false)
end)

concommand.Add("mex_cinematic_status", function(ply)
    if not Allowed(ply) then return end
    local state = C.Pending[ply]
    Message(ply, state and string.format("Pending train #%d, %.1f seconds remaining.",
        IsValid(state.train) and state.train:EntIndex() or -1, math.max(0, state.due - CurTime()))
        or "No departure armed.")
end)

hook.Add("PlayerDisconnected", "MEXCinematicCleanup", function(ply)
    Stop(ply, true)
end)
