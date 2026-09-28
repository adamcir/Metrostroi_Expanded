-- Metrostroi Extended - Train Fixer Tool
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

TOOL.Category = "Metrostroi Extended"
TOOL.Name = "#tool.mex_train_fixer.name"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add(
        "tool.mex_train_fixer.name",
        "Train Fixer"
    )
    language.Add(
        "tool.mex_train_fixer.desc",
        "Repairs Metrostroi Extended train damage"
    )
    language.Add(
        "tool.mex_train_fixer.0",
        "Left click: repair one wagon. Right click: repair the whole consist."
    )
    language.Add(
        "tool.mex_train_fixer.left",
        "Repair wagon"
    )
    language.Add(
        "tool.mex_train_fixer.right",
        "Repair consist"
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

local function CanRepair(ply, train)
    if not IsValid(ply) or not IsSubwayTrain(train) then
        return false
    end

    if train.CPPICanTool
        and not train:CPPICanTool(ply, "mex_train_fixer")
    then
        return false
    end

    return true
end

local function RepairTrain(train)
    if not IsSubwayTrain(train) then return false end

    local damage = MetrostroiExpandedDamage
    if not istable(damage) or not isfunction(damage.Reset) then
        return false
    end

    damage.Reset(train)

    train:EmitSound(
        "items/suitchargeok1.wav",
        72,
        105,
        0.75
    )

    local effect = EffectData()
    effect:SetOrigin(train:WorldSpaceCenter())
    effect:SetEntity(train)
    util.Effect("cball_bounce", effect, true, true)

    return true
end

function TOOL:LeftClick(trace)
    local train = ResolveTrain(trace.Entity)
    if not IsSubwayTrain(train) then return false end

    if CLIENT then return true end

    local ply = self:GetOwner()
    if not CanRepair(ply, train) then return false end

    return RepairTrain(train)
end

function TOOL:RightClick(trace)
    local train = ResolveTrain(trace.Entity)
    if not IsSubwayTrain(train) then return false end

    if CLIENT then return true end

    local ply = self:GetOwner()
    if not CanRepair(ply, train) then return false end

    local repaired = 0
    local seen = {}

    local function repair(candidate)
        if not IsSubwayTrain(candidate) or seen[candidate] then
            return
        end

        seen[candidate] = true

        if CanRepair(ply, candidate) and RepairTrain(candidate) then
            repaired = repaired + 1
        end
    end

    if istable(train.WagonList) and #train.WagonList > 0 then
        for _, wagon in ipairs(train.WagonList) do
            repair(wagon)
        end
    else
        repair(train)
    end

    if repaired > 0 then
        ply:ChatPrint(
            string.format(
                "[Metrostroi Extended] Train Fixer repaired %d wagon%s.",
                repaired,
                repaired == 1 and "" or "s"
            )
        )
        return true
    end

    return false
end

function TOOL.BuildCPanel(panel)
    panel:AddControl(
        "Header",
        {
            Description = "#tool.mex_train_fixer.desc",
        }
    )

    panel:Help(
        "Left click repairs the selected wagon."
    )
    panel:Help(
        "Right click repairs every wagon in the connected consist."
    )
    panel:Help(
        "Repairs deformation, detached parts, electrical failures, blown fuses and tripped protection created by Metrostroi Extended."
    )
    panel:Help(
        "A repaired train can be damaged again immediately if it is still exposed to the original cause, for example live electrical equipment submerged in water."
    )
end
