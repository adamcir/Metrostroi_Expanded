-- Metrostroi Expanded - Train Fixer Tool
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

TOOL.Category = "Metrostroi Expanded"
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
        "Repairs only the Metrostroi Expanded part you are aiming at"
    )
    language.Add(
        "tool.mex_train_fixer.0",
        "Left click: repair only the targeted component, service point or damage zone."
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

local function CanRepair(ply, train)
    if not IsValid(ply) or not IsSubwayTrain(train) then
        return false
    end

    if train.CPPICanTool
        and not train:CPPICanTool(
            ply,
            "mex_train_fixer"
        )
    then
        return false
    end

    return true
end

local function RunningGearTarget(train, ent)
    if not IsSubwayTrain(train)
        or not IsValid(ent)
    then
        return nil
    end

    if ent == train.FrontBogey then
        return "front_bogey", "Front bogey"
    elseif ent == train.RearBogey then
        return "rear_bogey", "Rear bogey"
    elseif ent == train.FrontCouple then
        return "front_coupler", "Front coupler"
    elseif ent == train.RearCouple then
        return "rear_coupler", "Rear coupler"
    end

    return nil
end

local function ButtonCenterLocal(panel, button)
    if not istable(panel)
        or not istable(button)
        or not isvector(panel.pos)
        or not isangle(panel.ang)
    then
        return nil
    end

    local x = tonumber(button.x) or 0
    local y = tonumber(button.y) or 0

    if not button.radius then
        x = x + (tonumber(button.w) or 0) * 0.5
        y = y + (tonumber(button.h) or 0) * 0.5
    end

    local pos = Vector(x, -y, 0)
    pos:Rotate(panel.ang)

    return panel.pos
        + pos * (tonumber(panel.scale) or 1)
end

local function NearestButtonTarget(train, localPos)
    if not istable(train.ButtonMap) then
        return nil, nil
    end

    local bestID
    local bestDistance = math.huge

    for panelName, panel in pairs(train.ButtonMap) do
        if panelName == "BaseClass"
            or not istable(panel)
            or not istable(panel.buttons)
        then
            continue
        end

        for _, button in pairs(panel.buttons) do
            if not istable(button)
                or not isstring(button.ID)
            then
                continue
            end

            local pos = ButtonCenterLocal(panel, button)
            if not isvector(pos) then continue end

            local distance = localPos:Distance(pos)
            local radius =
                tonumber(button.radius)
                or math.max(
                    tonumber(button.w) or 0,
                    tonumber(button.h) or 0
                ) * 0.75

            radius = math.Clamp(
                radius
                    * (tonumber(panel.scale) or 1)
                    + 7,
                12,
                42
            )

            if distance <= radius
                and distance < bestDistance
            then
                bestDistance = distance
                bestID =
                    button.ID:gsub("^.+:", "")
            end
        end
    end

    if bestID then
        return "control:" .. bestID,
            "Control: " .. bestID
    end

    return nil, nil
end

local function NearestLightTarget(train, localPos)
    if not istable(train.Lights) then
        return nil, nil
    end

    local bestIndex
    local bestDistance = math.huge

    for index, light in pairs(train.Lights) do
        if not istable(light)
            or not isvector(light[2])
        then
            continue
        end

        local distance = localPos:Distance(light[2])
        local kind = tostring(light[1] or "")
        local radius =
            kind == "headlight" and 90 or 48

        if distance <= radius
            and distance < bestDistance
        then
            bestDistance = distance
            bestIndex = index
        end
    end

    if bestIndex ~= nil then
        return "light:" .. tostring(bestIndex),
            "Light #" .. tostring(bestIndex)
    end

    return nil, nil
end

local function LocalServiceTarget(
    train,
    worldPos
)
    if not IsSubwayTrain(train)
        or not isvector(worldPos)
    then
        return nil, "Unknown"
    end

    local localPos = train:WorldToLocal(worldPos)

    local controlTarget, controlLabel =
        NearestButtonTarget(train, localPos)

    if controlTarget then
        return controlTarget, controlLabel
    end

    local lightTarget, lightLabel =
        NearestLightTarget(train, localPos)

    if lightTarget then
        return lightTarget, lightLabel
    end

    local mins = train:OBBMins()
    local maxs = train:OBBMaxs()
    local center = (mins + maxs) * 0.5
    local length = math.max(maxs.x - mins.x, 1)
    local width = math.max(maxs.y - mins.y, 1)
    local height = math.max(maxs.z - mins.z, 1)

    -- These are service hotspots rather than claims about an exact battery-box
    -- location on every supported train model. They give the player a stable
    -- place to target hidden equipment that has no separate server entity.
    local battery = Vector(
        center.x - length * 0.16,
        maxs.y - width * 0.10,
        mins.z + height * 0.16
    )
    local grkv = Vector(
        center.x + length * 0.12,
        mins.y + width * 0.10,
        mins.z + height * 0.16
    )
    local electrical = Vector(
        center.x,
        mins.y + width * 0.12,
        mins.z + height * 0.32
    )

    local batteryDistance =
        localPos:Distance(battery)
    local grkvDistance =
        localPos:Distance(grkv)
    local electricalDistance =
        localPos:Distance(electrical)

    if batteryDistance <= 115
        and batteryDistance <= grkvDistance
        and batteryDistance <= electricalDistance
    then
        return "battery", "Battery service point"
    end

    if grkvDistance <= 115
        and grkvDistance <= electricalDistance
    then
        return "grkv", "GRKV / rheostat controller service point"
    end

    if electricalDistance <= 115 then
        return "electrical",
            "Electrical cabinet / relay & indicator service"
    end

    local centerX = center.x
    local centerY = center.y
    local centerZ = center.z

    local nx = math.abs(localPos.x - centerX)
        / math.max((maxs.x - mins.x) * 0.5, 1)
    local ny = math.abs(localPos.y - centerY)
        / math.max((maxs.y - mins.y) * 0.5, 1)
    local nz = math.abs(localPos.z - centerZ)
        / math.max((maxs.z - mins.z) * 0.5, 1)

    if nx >= ny and nx >= nz then
        if localPos.x >= centerX then
            return "front", "Front structure"
        end
        return "rear", "Rear structure"
    elseif ny >= nz then
        if localPos.y >= centerY then
            return "right", "Right-side structure"
        end
        return "left", "Left-side structure"
    end

    if localPos.z >= centerZ then
        return "roof", "Roof structure"
    end

    return "floor", "Floor / underframe structure"
end

local function TargetDescription(trace)
    if not trace or not IsValid(trace.Entity) then
        return nil, nil, nil
    end

    local ent = trace.Entity

    if ent:GetClass() == "mex_damage_debris"
        and ent.GetSourceTrain
        and ent.GetComponentName
    then
        local train = ent:GetSourceTrain()
        if IsSubwayTrain(train) then
            local name = ent:GetComponentName()
            return train,
                "component:" .. tostring(name),
                "Detached component: " .. tostring(name)
        end
    end

    local train = ResolveTrain(ent)
    if not IsSubwayTrain(train) then
        return nil, nil, nil
    end

    local runningTarget, runningLabel =
        RunningGearTarget(train, ent)

    if runningTarget then
        return train, runningTarget, runningLabel
    end

    local target, label =
        LocalServiceTarget(
            train,
            trace.HitPos
        )

    return train, target, label
end

local function PlayRepairFeedback(
    train,
    worldPos
)
    if not IsSubwayTrain(train) then return end

    sound.Play(
        "items/suitchargeok1.wav",
        isvector(worldPos)
            and worldPos
            or train:WorldSpaceCenter(),
        62,
        105,
        0.72
    )

    local effect = EffectData()
    effect:SetOrigin(
        isvector(worldPos)
            and worldPos
            or train:WorldSpaceCenter()
    )
    util.Effect(
        "cball_bounce",
        effect,
        true,
        true
    )
end

function TOOL:LeftClick(trace)
    local train, target =
        TargetDescription(trace)

    if not IsSubwayTrain(train)
        or not isstring(target)
    then
        return false
    end

    if CLIENT then return true end

    local ply = self:GetOwner()
    if not CanRepair(ply, train) then
        return false
    end

    local damage = MetrostroiExpandedDamage
    if not istable(damage) then
        return false
    end

    local repaired = false

    if string.sub(target, 1, 10) == "component:" then
        local name = string.sub(target, 11)

        if isfunction(
            damage.RepairDetachedComponent
        ) then
            repaired =
                damage.RepairDetachedComponent(
                    train,
                    name
                )
        end
    elseif target == "front_bogey"
        or target == "rear_bogey"
        or target == "front_coupler"
        or target == "rear_coupler"
    then
        if isfunction(
            damage.RepairRunningGearEntity
        ) then
            repaired =
                damage.RepairRunningGearEntity(
                    trace.Entity
                )
        end
    elseif isfunction(
        damage.GetServiceTargetAtPosition
    ) and isfunction(
        damage.RepairServiceTarget
    ) then
        local authoritativeTarget =
            damage.GetServiceTargetAtPosition(
                train,
                trace.HitPos
            )

        repaired =
            damage.RepairServiceTarget(
                train,
                authoritativeTarget or target
            )
    end

    if repaired then
        PlayRepairFeedback(
            train,
            trace.HitPos
        )
    end

    return repaired == true
end

-- The ordinary fixer intentionally has no whole-wagon/whole-consist action.
-- Those operations belong to Admin Train Fixer.
function TOOL:RightClick()
    return false
end

if CLIENT then
    local function BoolState(value)
        return value and "DAMAGED" or "OK"
    end

    function TOOL:DrawHUD()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local trace = ply:GetEyeTrace()
        local train, _, label =
            TargetDescription(trace)

        if not IsSubwayTrain(train) then
            return
        end

        local x = ScrW() * 0.5 + 28
        local y = ScrH() * 0.5 + 22

        draw.SimpleText(
            "Train Fixer target: "
                .. tostring(label or "unknown"),
            "DermaDefaultBold",
            x,
            y,
            Color(255, 215, 90),
            TEXT_ALIGN_LEFT,
            TEXT_ALIGN_TOP
        )

        local batteryHealth = math.Clamp(
            train:GetNW2Float(
                "MEX.Damage.BatteryHealth",
                1
            ),
            0,
            1
        )
        local grkvWear = math.Clamp(
            train:GetNW2Float(
                "MEX.Damage.GRKVWear",
                0
            ),
            0,
            1
        )

        local lines = {
            string.format(
                "Battery: %.0f%% %s",
                batteryHealth * 100,
                (
                    train:GetNW2Bool(
                        "MEX.Damage.BatteryFailed",
                        false
                    )
                    or train:GetNW2Bool(
                        "MEX.Damage.BatteryWaterFailed",
                        false
                    )
                ) and "FAILED" or "OK"
            ),
            string.format(
                "GRKV wear: %.0f%% %s",
                grkvWear * 100,
                train:GetNW2Bool(
                    "MEX.Damage.GRKVFailed",
                    false
                ) and "FAILED" or ""
            ),
            "Front bogey: "
                .. BoolState(
                    train:GetNW2Bool(
                        "MEX.Damage.FrontBogeyDetached",
                        false
                    )
                ),
            "Rear bogey: "
                .. BoolState(
                    train:GetNW2Bool(
                        "MEX.Damage.RearBogeyDetached",
                        false
                    )
                ),
            "Front coupler: "
                .. BoolState(
                    train:GetNW2Bool(
                        "MEX.Damage.FrontCouplerDetached",
                        false
                    )
                ),
            "Rear coupler: "
                .. BoolState(
                    train:GetNW2Bool(
                        "MEX.Damage.RearCouplerDetached",
                        false
                    )
                ),
            string.format(
                "Failed controls: %d",
                train:GetNW2Int(
                    "MEX.Damage.FailedControlCount",
                    0
                )
            ),
            string.format(
                "Failed relays: %d",
                train:GetNW2Int(
                    "MEX.Damage.FailedRelayCount",
                    0
                )
            ),
            string.format(
                "Failed lights: %d",
                train:GetNW2Int(
                    "MEX.Damage.FailedLightCount",
                    0
                )
            ),
            string.format(
                "Failed indicators: %d",
                train:GetNW2Int(
                    "MEX.Damage.FailedIndicatorCount",
                    0
                )
            ),
        }

        for i, line in ipairs(lines) do
            draw.SimpleText(
                line,
                "DermaDefault",
                x,
                y + 18 + i * 15,
                Color(235, 235, 235),
                TEXT_ALIGN_LEFT,
                TEXT_ALIGN_TOP
            )
        end
    end
end

function TOOL.BuildCPanel(panel)
    panel:AddControl(
        "Header",
        {
            Description = "#tool.mex_train_fixer.desc",
        }
    )

    panel:Help(
        "Left click repairs only the exact target."
    )
    panel:Help(
        "Aim at detached debris to restore only that component."
    )
    panel:Help(
        "Aim directly at a bogey or coupler to repair only that running-gear item."
    )
    panel:Help(
        "Buttons, switches, levers and brake controls are targeted individually through their ButtonMap position."
    )
    panel:Help(
        "Lights/headlights are targeted individually at their light position."
    )
    panel:Help(
        "Hidden Battery and GRKV systems have service hotspots on the lower underframe."
    )
    panel:Help(
        "The electrical cabinet service hotspot repairs one failed hidden relay or indicator circuit at a time."
    )
    panel:Help(
        "A normal body hit repairs only the structural damage zone you are pointing at."
    )
    panel:Help(
        "Whole-wagon, whole-consist and all-train repairs are available only through Admin Train Fixer."
    )
end
