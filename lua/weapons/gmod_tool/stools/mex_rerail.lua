-- Metrostroi Expanded - Rerail Tool
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

TOOL.Category = "Metrostroi Expanded"
TOOL.Name = "#tool.mex_rerail.name"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.mex_rerail.name", "Train Rerailer")
    language.Add("tool.mex_rerail.desc", "Return Metrostroi trains and bogeys to nearby rails")
    language.Add("tool.mex_rerail.0", "Left click: rerail the aimed train or bogey. Right click: rerail the nearest train you are looking at.")
end

local function IsTrain(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    return isstring(class) and class ~= "gmod_subway_base"
        and string.sub(class, 1, 12) == "gmod_subway_"
end

local function IsBogey(ent)
    return IsValid(ent) and ent:GetClass() == "gmod_train_bogey"
end

local function ResolveTarget(ent)
    if IsTrain(ent) or IsBogey(ent) then return ent end
    if not IsValid(ent) then return nil end

    local candidates = {
        ent:GetParent(), ent.TrainEntity, ent.Train,
        ent:GetNWEntity("TrainEntity"),
        ent:GetNW2Entity("TrainEntity")
    }
    for _, candidate in ipairs(candidates) do
        if IsTrain(candidate) or IsBogey(candidate) then
            return candidate
        end
    end
    return nil
end

local function CanRerail(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return false end
    if not ply:IsAdmin() then return false end
    if ent.CPPICanTool and not ent:CPPICanTool(ply, "mex_rerail") then
        return false
    end
    return true
end

local function Notify(ply, msg)
    if IsValid(ply) then ply:ChatPrint("[MEX Rerail] " .. msg) end
end

local function Rerail(ply, ent)
    if CLIENT then return true end
    if not CanRerail(ply, ent) then
        Notify(ply, "Admin access and permission to tool this train are required.")
        return false
    end
    if not Metrostroi then
        Notify(ply, "Metrostroi is not loaded.")
        return false
    end

    local fn
    if IsTrain(ent) then
        fn = Metrostroi.RerailTrain
    elseif IsBogey(ent) then
        fn = Metrostroi.RerailBogey
    end
    if not isfunction(fn) then
        Notify(ply, "No compatible Metrostroi rerail function is available.")
        return false
    end

    local ok, result = pcall(fn, ent)
    if not ok then
        ErrorNoHalt("[MEX Rerail] " .. tostring(result) .. "\n")
        Notify(ply, "Rerailing failed; see server console.")
        return false
    end
    if result == false then
        Notify(ply, "No suitable track found near the vehicle.")
        return false
    end
    Notify(ply, "Rerail operation executed.")
    return true
end

function TOOL:LeftClick(trace)
    local ent = ResolveTarget(trace.Entity)
    if not IsValid(ent) then return false end
    return Rerail(self:GetOwner(), ent)
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end

    local origin = trace.HitPos
    local best, bestDist
    for _, ent in ipairs(ents.FindInSphere(origin, 384)) do
        if IsTrain(ent) then
            local dist = ent:GetPos():DistToSqr(origin)
            if not bestDist or dist < bestDist then
                best, bestDist = ent, dist
            end
        end
    end
    if not IsValid(best) then
        Notify(ply, "No train near the aimed point.")
        return false
    end
    return Rerail(ply, best)
end

function TOOL:Reload(trace)
    return false
end

function TOOL.BuildCPanel(panel)
    panel:Help("Left click a subway car or bogey to rerail it.")
    panel:Help("Right click near a train to rerail the nearest subway car.")
    panel:Help("Requires admin permission. Works with original Metrostroi and MEX Track Builder rails when rerail support is loaded.")
end
