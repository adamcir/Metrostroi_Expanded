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
        "Classic Train Fixer - repairs exactly the part you aim at"
    )
    language.Add(
        "tool.mex_train_fixer.0",
        "Left click: repair exactly the aimed damaged part."
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
        return nil, nil
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

    return nil, nil
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

local function RayDistanceToPoint(
    rayStart,
    rayDirection,
    point,
    maxDistance
)
    if not isvector(rayStart)
        or not isvector(rayDirection)
        or not isvector(point)
    then
        return nil, nil
    end

    local direction = rayDirection:GetNormalized()
    if direction:LengthSqr() <= 0.000001 then
        return nil, nil
    end

    local delta = point - rayStart
    local along = delta:Dot(direction)

    if along < 0
        or (
            isnumber(maxDistance)
            and along > maxDistance
        )
    then
        return nil, along
    end

    local closest = rayStart + direction * along
    return point:Distance(closest), along
end

local function NearestButtonTarget(
    train,
    rayStart,
    rayDirection,
    maxDistance
)
    if not istable(train.ButtonMap) then
        return nil, nil
    end

    local bestID
    local bestScore = math.huge

    for panelName, panel in pairs(train.ButtonMap) do
        if panelName ~= "BaseClass"
            and istable(panel)
            and istable(panel.buttons)
        then
            for _, button in pairs(panel.buttons) do
                if istable(button)
                    and isstring(button.ID)
                then
                    local localCenter =
                        ButtonCenterLocal(
                            panel,
                            button
                        )

                    if isvector(localCenter) then
                        local worldCenter =
                            train:LocalToWorld(
                                localCenter
                            )

                        local miss, along =
                            RayDistanceToPoint(
                                rayStart,
                                rayDirection,
                                worldCenter,
                                maxDistance
                            )

                        local radius =
                            tonumber(button.radius)
                            or math.max(
                                tonumber(button.w) or 0,
                                tonumber(button.h) or 0
                            ) * 0.75

                        radius = math.Clamp(
                            radius
                                * (tonumber(panel.scale) or 1)
                                + 6,
                            10,
                            38
                        )

                        if isnumber(miss)
                            and miss <= radius
                        then
                            -- Aim alignment is the important part. A very tiny
                            -- distance term only resolves overlapping controls.
                            local score =
                                miss
                                + math.max(along or 0, 0)
                                    * 0.00002

                            if score < bestScore then
                                bestScore = score
                                bestID =
                                    button.ID:gsub(
                                        "^.+:",
                                        ""
                                    )
                            end
                        end
                    end
                end
            end
        end
    end

    if bestID then
        return "control:" .. bestID,
            "Control: " .. bestID
    end

    return nil, nil
end

local function NearestLightTarget(
    train,
    rayStart,
    rayDirection,
    maxDistance
)
    if not istable(train.Lights) then
        return nil, nil
    end

    local bestIndex
    local bestScore = math.huge

    for index, light in pairs(train.Lights) do
        if istable(light)
            and isvector(light[2])
        then
            local worldCenter =
                train:LocalToWorld(light[2])

            local miss, along =
                RayDistanceToPoint(
                    rayStart,
                    rayDirection,
                    worldCenter,
                    maxDistance
                )

            local kind = tostring(light[1] or "")
            local radius =
                kind == "headlight"
                    and 72
                    or 34

            if isnumber(miss)
                and miss <= radius
            then
                local score =
                    miss
                    + math.max(along or 0, 0)
                        * 0.00002

                if score < bestScore then
                    bestScore = score
                    bestIndex = index
                end
            end
        end
    end

    if bestIndex ~= nil then
        return "light:" .. tostring(bestIndex),
            "Light #" .. tostring(bestIndex)
    end

    return nil, nil
end

local function ServiceAnchors(train)
    local mins = train:OBBMins()
    local maxs = train:OBBMaxs()
    local center = (mins + maxs) * 0.5
    local length = math.max(maxs.x - mins.x, 1)
    local width = math.max(maxs.y - mins.y, 1)
    local height = math.max(maxs.z - mins.z, 1)

    return {
        battery = Vector(
            center.x - length * 0.16,
            maxs.y - width * 0.10,
            mins.z + height * 0.16
        ),
        grkv = Vector(
            center.x + length * 0.12,
            mins.y + width * 0.10,
            mins.z + height * 0.16
        ),
        electrical = Vector(
            center.x,
            mins.y + width * 0.12,
            mins.z + height * 0.32
        ),
    }
end

local function RayServiceTarget(
    train,
    rayStart,
    rayDirection,
    maxDistance
)
    local anchors = ServiceAnchors(train)
    local choices = {
        {
            target = "battery",
            label = "Battery service point",
            point = anchors.battery,
            radius = 78,
        },
        {
            target = "grkv",
            label = "GRKV / rheostat controller service point",
            point = anchors.grkv,
            radius = 78,
        },
        {
            target = "electrical",
            label = "Electrical cabinet / relay service point",
            point = anchors.electrical,
            radius = 72,
        },
    }

    local best
    local bestScore = math.huge

    for _, choice in ipairs(choices) do
        local worldPoint =
            train:LocalToWorld(choice.point)

        local miss, along =
            RayDistanceToPoint(
                rayStart,
                rayDirection,
                worldPoint,
                maxDistance
            )

        if isnumber(miss)
            and miss <= choice.radius
        then
            local score =
                miss
                + math.max(along or 0, 0)
                    * 0.00002

            if score < bestScore then
                bestScore = score
                best = choice
            end
        end
    end

    if best then
        return best.target, best.label
    end

    return nil, nil
end

local function StructuralTarget(train, worldPos)
    if not IsSubwayTrain(train)
        or not isvector(worldPos)
    then
        return nil, "Unknown"
    end

    local localPos = train:WorldToLocal(worldPos)
    local mins = train:OBBMins()
    local maxs = train:OBBMaxs()
    local center = (mins + maxs) * 0.5

    local nx = math.abs(localPos.x - center.x)
        / math.max((maxs.x - mins.x) * 0.5, 1)
    local ny = math.abs(localPos.y - center.y)
        / math.max((maxs.y - mins.y) * 0.5, 1)
    local nz = math.abs(localPos.z - center.z)
        / math.max((maxs.z - mins.z) * 0.5, 1)

    if nx >= ny and nx >= nz then
        if localPos.x >= center.x then
            return "front", "Front structure"
        end
        return "rear", "Rear structure"
    elseif ny >= nz then
        if localPos.y >= center.y then
            return "right", "Right-side structure"
        end
        return "left", "Left-side structure"
    end

    if localPos.z >= center.z then
        return "roof", "Roof structure"
    end

    return "floor", "Floor / underframe structure"
end

local function AimRay(ply, trace)
    local startPos =
        IsValid(ply)
        and ply.GetShootPos
        and ply:GetShootPos()
        or (
            trace
            and isvector(trace.StartPos)
            and trace.StartPos
            or nil
        )

    local direction =
        IsValid(ply)
        and ply.GetAimVector
        and ply:GetAimVector()
        or nil

    if not isvector(direction)
        and isvector(startPos)
        and trace
        and isvector(trace.HitPos)
    then
        direction =
            trace.HitPos - startPos
    end

    if not isvector(startPos)
        or not isvector(direction)
        or direction:LengthSqr() <= 0.000001
    then
        return nil, nil, nil
    end

    local maxDistance = 4096

    if trace and isvector(trace.HitPos) then
        -- Controls and lights can sit a little behind the collision surface of
        -- the wagon model. Allow a small depth margin, not an infinite
        -- through-the-whole-train search.
        maxDistance = math.max(
            startPos:Distance(trace.HitPos) + 96,
            128
        )
    end

    return startPos,
        direction:GetNormalized(),
        maxDistance
end

local function TargetDescription(trace, ply)
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

    local rayStart, rayDirection, maxDistance =
        AimRay(ply, trace)

    if isvector(rayStart)
        and isvector(rayDirection)
    then
        -- On the server we also know the original mount position of parts that
        -- were torn away. Prefer that exact damaged component before falling
        -- back to the still-existing ButtonMap/structure underneath it.
        if SERVER
            and istable(MetrostroiExpandedDamage)
            and isfunction(
                MetrostroiExpandedDamage.GetDetachedRepairTargetAtRay
            )
        then
            local componentName =
                MetrostroiExpandedDamage.GetDetachedRepairTargetAtRay(
                    train,
                    rayStart,
                    rayDirection,
                    maxDistance
                )

            if isstring(componentName)
                and componentName ~= ""
            then
                return train,
                    "component:" .. componentName,
                    "Damaged component: " .. componentName
            end
        end

        local controlTarget, controlLabel =
            NearestButtonTarget(
                train,
                rayStart,
                rayDirection,
                maxDistance
            )

        if controlTarget then
            return train,
                controlTarget,
                controlLabel
        end

        local lightTarget, lightLabel =
            NearestLightTarget(
                train,
                rayStart,
                rayDirection,
                maxDistance
            )

        if lightTarget then
            return train,
                lightTarget,
                lightLabel
        end

        local serviceTarget, serviceLabel =
            RayServiceTarget(
                train,
                rayStart,
                rayDirection,
                maxDistance
            )

        if serviceTarget then
            return train,
                serviceTarget,
                serviceLabel
        end
    end

    local target, label =
        StructuralTarget(
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

    local position =
        isvector(worldPos)
        and worldPos
        or train:WorldSpaceCenter()

    sound.Play(
        "items/suitchargeok1.wav",
        position,
        62,
        105,
        0.72
    )

    local effect = EffectData()
    effect:SetOrigin(position)
    util.Effect(
        "cball_bounce",
        effect,
        true,
        true
    )
end

function TOOL:LeftClick(trace)
    local ply = self:GetOwner()
    local train, target =
        TargetDescription(trace, ply)

    if not IsSubwayTrain(train)
        or not isstring(target)
    then
        return false
    end

    if CLIENT then return true end

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
        damage.RepairServiceTarget
    ) then
        -- Do NOT resolve the target again from HitPos here. The old second
        -- lookup was the reason a neighboring button/light could be repaired.
        -- The exact ray-selected target above is the authoritative target.
        repaired =
            damage.RepairServiceTarget(
                train,
                target
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

-- Keep the normal Train Fixer intentionally classic and simple: one click,
-- one aimed part. Whole-wagon/consist/map repairs belong to Admin Train Fixer.
function TOOL:RightClick()
    return false
end

if CLIENT then
    function TOOL:DrawHUD()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local trace = ply:GetEyeTrace()
        local train, _, label =
            TargetDescription(trace, ply)

        if not IsSubwayTrain(train) then
            return
        end

        draw.SimpleText(
            "Train Fixer: "
                .. tostring(label or "unknown"),
            "DermaDefaultBold",
            ScrW() * 0.5 + 24,
            ScrH() * 0.5 + 20,
            Color(255, 215, 90),
            TEXT_ALIGN_LEFT,
            TEXT_ALIGN_TOP
        )
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
        "Left click repairs only the exact part under the crosshair."
    )
    panel:Help(
        "Buttons, switches, levers, brake controls and lights use the view ray, not the nearest body hit point."
    )
    panel:Help(
        "Detached debris, bogeys and couplers are repaired individually."
    )
    panel:Help(
        "Battery, GRKV and hidden electrical equipment have small service points on the lower underframe."
    )
    panel:Help(
        "Whole-wagon, consist and map-wide repairs are available only in Admin Train Fixer."
    )
end
