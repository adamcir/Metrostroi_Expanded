-- Metrostroi Expanded - Admin Train Fixer Tool
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

TOOL.Category = "Metrostroi Expanded"
TOOL.Name = "#tool.mex_admin_train_fixer.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.AdminOnly = true

if CLIENT then
    language.Add(
        "tool.mex_admin_train_fixer.name",
        "Admin Train Fixer"
    )
    language.Add(
        "tool.mex_admin_train_fixer.desc",
        "Admin-only full repair tool for Metrostroi Expanded"
    )
    language.Add(
        "tool.mex_admin_train_fixer.0",
        "Left: whole wagon. Right: whole consist. Reload: all trains on the map."
    )
end

local function IsSubwayTrain(ent)
    if not IsValid(ent) then return false end

    local className = ent:GetClass()
    return isstring(className)
        and className ~= "gmod_subway_base"
        and string.sub(className, 1, 12) == "gmod_subway_"
end

local function ResolveTrain(ent)
    if IsSubwayTrain(ent) then return ent end
    if not IsValid(ent) then return nil end

    if ent:GetClass() == "mex_damage_debris"
        and ent.GetSourceTrain
    then
        local source = ent:GetSourceTrain()
        if IsSubwayTrain(source) then
            return source
        end
    end

    local candidates = {
        ent:GetParent(),
        ent:GetNW2Entity("TrainEntity"),
        ent:GetNWEntity("TrainEntity"),
        ent.TrainEntity,
        ent.Train,
    }

    for _, candidate in ipairs(candidates) do
        if IsSubwayTrain(candidate) then
            return candidate
        end
    end

    return nil
end

local function IsAdmin(ply)
    return IsValid(ply)
        and ply:IsPlayer()
        and ply:IsAdmin()
end

local function RepairTrain(train)
    if not IsSubwayTrain(train) then
        return false
    end

    local damage = MetrostroiExpandedDamage
    if not istable(damage)
        or not isfunction(damage.Reset)
    then
        return false
    end

    damage.Reset(train)

    sound.Play(
        "items/suitchargeok1.wav",
        train:WorldSpaceCenter(),
        66,
        103,
        0.78
    )

    return true
end

function TOOL:LeftClick(trace)
    local train = ResolveTrain(trace.Entity)
    if not IsSubwayTrain(train) then
        return false
    end

    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsAdmin(ply) then return false end

    local repaired = RepairTrain(train)

    if repaired then
        ply:ChatPrint(
            "[Metrostroi Expanded] Admin Train Fixer repaired the entire wagon."
        )
    end

    return repaired
end

function TOOL:RightClick(trace)
    local train = ResolveTrain(trace.Entity)
    if not IsSubwayTrain(train) then
        return false
    end

    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsAdmin(ply) then return false end

    local seen = {}
    local repaired = 0

    local function repair(candidate)
        if not IsSubwayTrain(candidate)
            or seen[candidate]
        then
            return
        end

        seen[candidate] = true

        if RepairTrain(candidate) then
            repaired = repaired + 1
        end
    end

    if istable(train.WagonList)
        and #train.WagonList > 0
    then
        for _, wagon in ipairs(train.WagonList) do
            repair(wagon)
        end
    else
        repair(train)
    end

    if repaired > 0 then
        ply:ChatPrint(
            string.format(
                "[Metrostroi Expanded] Admin Train Fixer repaired %d wagon%s in the consist.",
                repaired,
                repaired == 1 and "" or "s"
            )
        )
        return true
    end

    return false
end

function TOOL:Reload()
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsAdmin(ply) then return false end

    local repaired = 0

    for _, ent in ipairs(ents.GetAll()) do
        if IsSubwayTrain(ent)
            and RepairTrain(ent)
        then
            repaired = repaired + 1
        end
    end

    ply:ChatPrint(
        string.format(
            "[Metrostroi Expanded] Admin Train Fixer repaired %d train wagon%s on the map.",
            repaired,
            repaired == 1 and "" or "s"
        )
    )

    return repaired > 0
end

function TOOL.BuildCPanel(panel)
    panel:AddControl(
        "Header",
        {
            Description =
                "#tool.mex_admin_train_fixer.desc",
        }
    )

    panel:Help(
        "ADMIN ONLY."
    )
    panel:Help(
        "Left click: fully repair the aimed wagon."
    )
    panel:Help(
        "Right click: fully repair every wagon in the connected consist."
    )
    panel:Help(
        "Reload (R): fully repair every Metrostroi train wagon currently on the map."
    )
    panel:Help(
        "This resets structural/component damage, water/electrical failures, battery damage, GRKV/relay wear, detached bogeys/couplers and detached hardware, and completely removes neglect, moss, dirt, interior decay and corrosion."
    )
end
