-- Metrostroi Expanded - instant damage scenarios for filming and testing.
-- Copyright (C) 2026 Adam Cir / Adava Software - GPL-3.0.
if not SERVER then return end

local function IsTrain(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    return isstring(class) and class ~= "gmod_subway_base"
        and string.sub(class, 1, 12) == "gmod_subway_"
end

local function Target(ply, args)
    if IsValid(ply) and not ply:IsAdmin() then return nil, "Admin access required." end
    local id = tonumber(args[2])
    local ent = id and Entity(math.floor(id)) or nil
    if not IsValid(ent) and IsValid(ply) then
        local tr = ply:GetEyeTrace()
        ent = tr and tr.Entity
        if IsValid(ent) and not IsTrain(ent) then
            local parent = ent:GetParent()
            if IsTrain(parent) then ent = parent end
        end
    end
    if not IsTrain(ent) then return nil, "Aim at a subway train or provide its entity ID." end
    if IsValid(ply) and ent.CPPICanTool and not ent:CPPICanTool(ply, "mex_damage_scenario") then
        return nil, "No permission to modify this train."
    end
    return ent
end

local function Say(ply, msg)
    local line = "[MEX Damage Scenario] " .. msg
    print(line)
    if IsValid(ply) then ply:ChatPrint(line) end
end

local function RunScenario(kind, ply, args)
    local train, err = Target(ply, args)
    if not train then Say(ply, err) return end

    local MEXD = MetrostroiExpandedDamage
    if not MEXD then Say(ply, "Damage system not loaded.") return end

    local strength = tonumber(args[1]) or 0.7
    strength = math.Clamp(strength, 0, 1)
    if strength <= 0 then
        Say(ply, "Use a strength from 0.01 to 1. Use mex_damage_reset to repair.")
        return
    end

    if kind == "impact" then
        if not MEXD.IsPhysicalDamageEnabled or not MEXD.IsPhysicalDamageEnabled() then
            Say(ply, "Enable physical damage first: mex_damage_set_enabled 1")
            return
        end
        local zone = string.lower(args[3] or "front")
        local allowed = {front=true, rear=true, left=true, right=true, roof=true, floor=true}
        if not allowed[zone] then Say(ply, "Invalid zone: front/rear/left/right/roof/floor") return end
        local mins, maxs = train:OBBMins(), train:OBBMaxs()
        local center = (mins + maxs) * 0.5
        local point = Vector(center.x, center.y, center.z)
        if zone == "front" then point.x = maxs.x
        elseif zone == "rear" then point.x = mins.x
        elseif zone == "left" then point.y = mins.y
        elseif zone == "right" then point.y = maxs.y
        elseif zone == "roof" then point.z = maxs.z
        elseif zone == "floor" then point.z = mins.z end
        local pos = train:LocalToWorld(point)
        local normal = pos - train:WorldSpaceCenter()
        normal:Normalize()
        if not isfunction(MEXD.ApplyDamage) then Say(ply, "Impact API unavailable.") return end
        MEXD.ApplyDamage(train, zone, strength, pos, normal, "console")
        if isfunction(MEXD.ApplyImpactElectricalDamage)
            and MEXD.IsElectricalDamageEnabled and MEXD.IsElectricalDamageEnabled() then
            MEXD.ApplyImpactElectricalDamage(train, 18 + strength * 85, strength, pos)
        end
        Say(ply, string.format("Impact applied: %.0f%% (%s) to #%d.", strength*100, zone, train:EntIndex()))
        return
    end

    if not MEXD.IsElectricalDamageEnabled or not MEXD.IsElectricalDamageEnabled() then
        Say(ply, "Enable electrical damage first: mex_damage_set_electrical_enabled 1")
        return
    end

    if kind == "electrical" then
        local key = "MEX.Damage.electrical"
        train:SetNW2Float(key, math.max(train:GetNW2Float(key, 0), strength))
        if isfunction(MEXD.ApplyImpactElectricalDamage) then
            MEXD.ApplyImpactElectricalDamage(train, 30 + strength*110, strength, train:WorldSpaceCenter())
        end
    elseif kind == "water" then
        -- Seed the existing persistent water-exposure and damage state.
        -- Real water detection will continue updating wetness from map geometry.
        train.MEXDamageWaterExposure = math.max(tonumber(train.MEXDamageWaterExposure) or 0, strength * 10)
        train:SetNW2Float("MEX.Damage.WaterExposure", math.max(train:GetNW2Float("MEX.Damage.WaterExposure", 0), strength * 10))
        train:SetNW2Float("MEX.Damage.electrical", math.max(train:GetNW2Float("MEX.Damage.electrical", 0), strength * 0.55))
        if isfunction(MEXD.DamageWaterRunningGear) then
            MEXD.DamageWaterRunningGear(train, 10 * strength, strength, strength, false)
        end
    end
    Say(ply, string.format("%s damage applied: %.0f%% to #%d.", kind, strength*100, train:EntIndex()))
end

for _, kind in ipairs({"electrical", "water", "impact"}) do
    local scenario = kind
    concommand.Add("mex_damage_" .. scenario .. "_set", function(ply, _, args)
        RunScenario(scenario, ply, args or {})
    end)
end
