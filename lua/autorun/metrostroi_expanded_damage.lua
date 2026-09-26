-- Metrostroi Expanded - Damage System
-- Simple directional crash damage and visual deformation for Metrostroi trains.
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

if SERVER then
    AddCSLuaFile()
end

MetrostroiExpandedDamage = MetrostroiExpandedDamage or {}
local MEXD = MetrostroiExpandedDamage

MEXD.Version = "0.6.3"

local ZONES = {
    front = true,
    rear = true,
    left = true,
    right = true,
    roof = true,
    floor = true,
}

local SU_TO_KMH = 0.09144 -- Source units/s (inches/s) -> km/h
local SPAWN_GRACE_SECONDS = 1.0
local MIN_CRASH_SPEED_KMH = 6.0
local MAX_CRASH_SPEED_KMH = 65.0

local function IsSubwayTrain(ent)
    if not IsValid(ent) then return false end
    local className = ent:GetClass()
    return isstring(className)
        and className ~= "gmod_subway_base"
        and string.sub(className, 1, 12) == "gmod_subway_"
end

local function DamageKey(zone)
    return "MEX.Damage." .. zone
end

function MEXD.GetZoneDamage(train, zone)
    if not IsValid(train) or not ZONES[zone] then return 0 end
    return train:GetNW2Float(DamageKey(zone), 0)
end

function MEXD.GetOverallDamage(train)
    if not IsValid(train) then return 0 end
    return math.max(
        MEXD.GetZoneDamage(train, "front"),
        MEXD.GetZoneDamage(train, "rear"),
        MEXD.GetZoneDamage(train, "left"),
        MEXD.GetZoneDamage(train, "right"),
        MEXD.GetZoneDamage(train, "roof"),
        MEXD.GetZoneDamage(train, "floor")
    )
end

function MEXD.GetStructuralHealth(train)
    return 1 - MEXD.GetOverallDamage(train)
end

local function ZoneLocalImpactPoint(train, zone)
    local mins = train:OBBMins()
    local maxs = train:OBBMaxs()
    local center = (mins + maxs) * 0.5

    if zone == "front" then
        return Vector(maxs.x, center.y, center.z)
    elseif zone == "rear" then
        return Vector(mins.x, center.y, center.z)
    elseif zone == "left" then
        return Vector(center.x, -math.max(math.abs(mins.y), math.abs(maxs.y)), center.z)
    elseif zone == "right" then
        return Vector(center.x, math.max(math.abs(mins.y), math.abs(maxs.y)), center.z)
    elseif zone == "roof" then
        return Vector(center.x, center.y, maxs.z)
    elseif zone == "floor" then
        return Vector(center.x, center.y, mins.z)
    end

    return center
end

local function ZoneOutwardNormal(train, zone)
    if zone == "front" then return train:GetForward() end
    if zone == "rear" then return -train:GetForward() end
    if zone == "left" then return -train:GetRight() end
    if zone == "right" then return train:GetRight() end
    if zone == "roof" then return train:GetUp() end
    if zone == "floor" then return -train:GetUp() end
    return train:GetUp()
end

local function UpdateDamageState(train)
    if not IsValid(train) then return end

    local front = MEXD.GetZoneDamage(train, "front")
    local rear = MEXD.GetZoneDamage(train, "rear")
    local left = MEXD.GetZoneDamage(train, "left")
    local right = MEXD.GetZoneDamage(train, "right")
    local roof = MEXD.GetZoneDamage(train, "roof")
    local floor = MEXD.GetZoneDamage(train, "floor")
    local overall = math.max(front, rear, left, right, roof, floor)

    train:SetNW2Float("MEX.Damage.overall", overall)
    train:SetNW2Float("MEX.StructuralHealth", 1 - overall)

    train:SetNW2Bool("MEX.Damage.Moderate", overall >= 0.35)
    train:SetNW2Bool("MEX.Damage.Heavy", overall >= 0.65)
    train:SetNW2Bool("MEX.Damage.Critical", overall >= 0.90)

    -- First simple subsystem damage states. These are intentionally generic.
    -- Future modules can connect them to individual Metrostroi electrical,
    -- pneumatic and door systems without modifying Metrostroi itself.
    train:SetNW2Bool("MEX.Damage.DoorsLeft", left >= 0.55)
    train:SetNW2Bool("MEX.Damage.DoorsRight", right >= 0.55)
    train:SetNW2Bool("MEX.Damage.FrontEquipment", front >= 0.55)
    train:SetNW2Bool("MEX.Damage.RearEquipment", rear >= 0.55)

    local electrical = train:GetNW2Float("MEX.Damage.electrical", 0)
    train:SetNW2Bool("MEX.Damage.ElectricalFault", electrical >= 0.45)
end

if SERVER then
    util.AddNetworkString("MEX.DamageImpact")
    util.AddNetworkString("MEX.DetachRequest")
    util.AddNetworkString("MEX.ComponentDetached")
    util.AddNetworkString("MEX.DetachReset")
    util.AddNetworkString("MEX.ComponentImpact")

    local ClassifyFromWorldDeltaVelocity
    local ClassifyFromWorldPosition

    local function EnsureButtonEventGuard(train)
        if not IsSubwayTrain(train) then return end
        if train.MEXDamageOriginalButtonEvent then return end
        if not isfunction(train.ButtonEvent) then return end

        train.MEXDamageOriginalButtonEvent = train.ButtonEvent
        train.MEXDamageOriginalOnButtonPress = train.OnButtonPress
        train.MEXDamageOriginalOnButtonRelease = train.OnButtonRelease
        train.MEXDamageBlockedButtons = train.MEXDamageBlockedButtons or {}

        local function blocked(self, button)
            if not self.MEXDamageBlockedButtons then return false end
            button = isstring(button)
                and button:gsub("^.+:", "")
                or button
            return self.MEXDamageBlockedButtons[button] == true
        end

        train.ButtonEvent = function(self, button, state, ply)
            local normalized = isstring(button)
                and button:gsub("^.+:", "")
                or button

            if blocked(self, normalized) then
                return false
            end

            return self.MEXDamageOriginalButtonEvent(
                self,
                button,
                state,
                ply
            )
        end

        if isfunction(train.MEXDamageOriginalOnButtonPress) then
            train.OnButtonPress = function(self, button, ply)
                local normalized = isstring(button)
                    and button:gsub("^.+:", "")
                    or button

                if blocked(self, normalized) then
                    return true
                end

                return self.MEXDamageOriginalOnButtonPress(
                    self,
                    button,
                    ply
                )
            end
        end

        if isfunction(train.MEXDamageOriginalOnButtonRelease) then
            train.OnButtonRelease = function(self, button, ply)
                local normalized = isstring(button)
                    and button:gsub("^.+:", "")
                    or button

                if blocked(self, normalized) then
                    return true
                end

                return self.MEXDamageOriginalOnButtonRelease(
                    self,
                    button,
                    ply
                )
            end
        end

        -- Metrostroi calls OnKeyPress/OnKeyRelease before it forwards the
        -- KeyMap entry into ButtonEvent. Some train classes therefore react to
        -- F/R or other controls before ButtonEvent can reject the destroyed
        -- device. Guard the keyboard path one level earlier.
        if isfunction(train.OnKeyEvent)
            and not train.MEXDamageOriginalOnKeyEvent
        then
            train.MEXDamageOriginalOnKeyEvent = train.OnKeyEvent

            local function keyEntryBlocked(self, entry, depth)
                depth = depth or 0
                if depth > 5 then return false end

                if isstring(entry) then
                    local id = entry:gsub("^.+:", "")
                    return blocked(self, id)
                end

                if not istable(entry) then return false end

                for key, value in pairs(entry) do
                    if key ~= "helper" and key ~= "def"
                        and keyEntryBlocked(self, value, depth + 1)
                    then
                        return true
                    end
                end

                if isstring(entry.helper)
                    and keyEntryBlocked(self, entry.helper, depth + 1)
                then
                    return true
                end

                if isstring(entry.def)
                    and keyEntryBlocked(self, entry.def, depth + 1)
                then
                    return true
                end

                return false
            end

            train.OnKeyEvent = function(self, key, state, ply, helper)
                local keyMap = self.KeyMap
                local entry = istable(keyMap) and keyMap[key] or nil

                if keyEntryBlocked(self, entry, 0) then
                    -- Clear any stale held-key state so the control cannot stay
                    -- electrically latched after its hardware was torn off.
                    if istable(self.KeyBuffer) then
                        self.KeyBuffer[key] = nil
                    end
                    return false
                end

                return self.MEXDamageOriginalOnKeyEvent(
                    self,
                    key,
                    state,
                    ply,
                    helper
                )
            end
        end
    end

    local function KeyMapContainsButton(tbl, target, depth)
        if not istable(tbl) or depth > 3 then return false end

        for _, value in pairs(tbl) do
            if isstring(value) and value == target then
                return true
            elseif istable(value) and KeyMapContainsButton(
                value,
                target,
                depth + 1
            ) then
                return true
            end
        end

        return false
    end

    local function NormalizeButtonFamily(button)
        if not isstring(button) then return "" end

        button = button:gsub("^.+:", "")
        button = button:gsub("_Unlocked$", "")
        button = button:gsub("%d+$", "")

        local changed = true
        while changed do
            changed = false

            for _, suffix in ipairs({
                "Toggle", "Engage", "Set", "Left", "Right",
                "Up", "Down", "On", "Off",
            }) do
                if #button > #suffix
                    and string.sub(button, -#suffix) == suffix
                then
                    button = string.sub(button, 1, #button - #suffix)
                    button = button:gsub("%d+$", "")
                    changed = true
                    break
                end
            end
        end

        return string.lower(button)
    end

    local function CollectKeyMapEvents(tbl, out, seen, depth)
        if not istable(tbl) or depth > 5 then return end

        for _, value in pairs(tbl) do
            if isstring(value) then
                value = value:gsub("^.+:", "")

                if value ~= "" and not seen[value] then
                    seen[value] = true
                    out[#out + 1] = value
                end
            elseif istable(value) then
                CollectKeyMapEvents(value, out, seen, depth + 1)
            end
        end
    end

    local function ExpandDetachedButtonAliases(train, buttonIDs)
        local result = {}
        local seen = {}
        local families = {}

        local function add(id)
            if not isstring(id) or id == "" then return end
            id = id:gsub("^.+:", "")
            if seen[id] then return end
            seen[id] = true
            result[#result + 1] = id

            local family = NormalizeButtonFamily(id)
            if family ~= "" then
                families[family] = true
            end
        end

        for _, id in ipairs(buttonIDs or {}) do
            add(id)
        end

        local keyEvents = {}
        CollectKeyMapEvents(train.KeyMap, keyEvents, {}, 0)

        for _, event in ipairs(keyEvents) do
            local family = NormalizeButtonFamily(event)
            if family ~= "" and families[family] then
                add(event)
            end
        end

        return result
    end

    local function IsValidDetachedButtonID(train, button)
        if not IsSubwayTrain(train) or not isstring(button) then return false end
        if button == "" or #button > 96 or string.sub(button, 1, 1) == "!" then
            return false
        end

        button = button:gsub("^.+:", "")

        if train[button] ~= nil then return true end
        if KeyMapContainsButton(train.KeyMap, button, 0) then return true end

        local base = button
        for _, suffix in ipairs({
            "Toggle", "Set", "Left", "Right", "Up", "Down",
        }) do
            if string.sub(base, -#suffix) == suffix then
                base = string.sub(base, 1, #base - #suffix)
                break
            end
        end

        if base ~= "" and train[base] ~= nil then return true end

        if string.find(button, "ParkingBrake", 1, true)
            and train.ParkingBrake ~= nil
        then
            return true
        end

        return false
    end

    local function BlockDetachedButton(train, button)
        if not IsSubwayTrain(train) or not isstring(button) or button == "" then
            return
        end

        EnsureButtonEventGuard(train)

        button = button:gsub("^.+:", "")
        train.MEXDamageBlockedButtons = train.MEXDamageBlockedButtons or {}

        -- Release the input once before disabling it. If a key/button happened
        -- to be held during the crash, it must not remain electrically stuck.
        if not train.MEXDamageBlockedButtons[button]
            and train.MEXDamageOriginalButtonEvent
        then
            pcall(
                train.MEXDamageOriginalButtonEvent,
                train,
                button,
                false,
                nil
            )
        end

        train.MEXDamageBlockedButtons[button] = true
    end

    local function ClearDetachedButtons(train)
        if not IsSubwayTrain(train) then return end
        train.MEXDamageBlockedButtons = {}
    end

    local function FindNearestDamagedZone(train, localPos)
        local bestZone = nil
        local bestScore = 0

        for zone in pairs(ZONES) do
            local amount = MEXD.GetZoneDamage(train, zone)
            if amount <= 0.001 then continue end

            local hit = train:GetNW2Vector(
                "MEX.Damage.HitLocal." .. zone,
                ZoneLocalImpactPoint(train, zone)
            )

            local radius =
                (zone == "front" or zone == "rear") and 235
                or (zone == "left" or zone == "right") and 180
                or 150

            local distance = localPos:Distance(hit)
            local score = amount * math.Clamp(1 - distance / radius, 0, 1)

            if score > bestScore then
                bestScore = score
                bestZone = zone
            end
        end

        return bestZone, bestScore
    end

    local function BroadcastDetachedComponent(train, name, debris, receiver)
        if not IsSubwayTrain(train) or not isstring(name) then return end

        net.Start("MEX.ComponentDetached")
            net.WriteEntity(train)
            net.WriteString(name)
            net.WriteEntity(IsValid(debris) and debris or NULL)

        if IsValid(receiver) then
            net.Send(receiver)
        else
            net.Broadcast()
        end
    end

    local function RemoveDetachedServerComponents(train, broadcastReset)
        if not IsSubwayTrain(train) then return end

        if istable(train.MEXDamageDetachedServer) then
            for _, data in pairs(train.MEXDamageDetachedServer) do
                if IsValid(data.debris) then
                    data.debris:Remove()
                end

                if istable(data.debrisList) then
                    for _, debris in ipairs(data.debrisList) do
                        if IsValid(debris) then
                            debris:Remove()
                        end
                    end
                end
            end
        end

        train.MEXDamageDetachedServer = {}
        ClearDetachedButtons(train)

        if broadcastReset then
            net.Start("MEX.DetachReset")
                net.WriteEntity(train)
            net.Broadcast()
        end
    end

    local function SpawnDetachedPhysicsProp(
        train,
        name,
        model,
        localPos,
        localAng,
        mins,
        maxs,
        skin,
        color,
        material,
        bodygroups,
        isDoor,
        isControl,
        zone,
        frozenSequence,
        frozenCycle,
        frozenPose
    )
        if not util.IsValidModel(model) then return nil end

        local debris = ents.Create("mex_damage_debris")
        if not IsValid(debris) then return nil end

        debris:SetModel(model)

        if not isvector(mins) or not isvector(maxs)
            or (maxs - mins):LengthSqr() <= 1
        then
            mins = debris:OBBMins()
            maxs = debris:OBBMaxs()
        end

        if not isvector(mins) or not isvector(maxs)
            or (maxs - mins):LengthSqr() <= 1
        then
            mins = Vector(-4, -4, -4)
            maxs = Vector(4, 4, 4)
        end

        local visualCenter = (mins + maxs) * 0.5

        -- Put the *physics entity* at the actual visible geometry centre.
        -- mex_damage_debris:Draw() shifts only the rendered MDL back to its
        -- original model origin. This fixes Metrostroi models whose origin is
        -- hundreds of Source units away from the visible part.
        local anchorLocal = LocalToWorld(
            visualCenter,
            angle_zero,
            localPos,
            localAng
        )

        debris.MEXFallbackMins = mins
        debris.MEXFallbackMaxs = maxs
        debris:SetPos(train:LocalToWorld(anchorLocal))
        debris:SetAngles(train:LocalToWorldAngles(localAng))
        debris:SetSourceTrain(train)
        debris:SetComponentName(name)
        debris:SetVisualCenter(visualCenter)
        debris:SetFrozenSequence(math.max(math.floor(frozenSequence or 0), 0))
        debris:SetFrozenCycle(math.Clamp(frozenCycle or 0, 0, 1))
        debris:SetFrozenPosePosition(tonumber(frozenPose) or 0)
        debris:Spawn()

        if not IsValid(debris) then return nil end

        debris:SetSkin(math.max(0, skin or 0))
        debris:SetColor(color or color_white)
        debris:SetPlaybackRate(0)
        debris:SetSequence(debris:GetFrozenSequence())
        debris:SetCycle(debris:GetFrozenCycle())
        debris:SetPoseParameter(
            "position",
            debris:GetFrozenPosePosition()
        )

        if isstring(material) and material ~= "" then
            debris:SetMaterial(material)
        end

        if istable(bodygroups) then
            for id, value in pairs(bodygroups) do
                if isnumber(id) and isnumber(value) then
                    debris:SetBodygroup(id, value)
                end
            end
        end

        debris.MEXDamageDebris = true
        debris.MEXDamageIsDoor = isDoor
        debris.MEXDamageIsControl = isControl

        local owner = train.CPPIGetOwner and train:CPPIGetOwner() or nil
        if IsValid(owner) and debris.CPPISetOwner then
            debris:CPPISetOwner(owner)
        end

        local phys = debris:GetPhysicsObject()
        if IsValid(phys) then
            local normal = ZoneOutwardNormal(train, zone or "front")
            local seed = (tonumber(util.CRC(name)) or 0) % 1000 / 1000

            local mass
            if isDoor then
                mass = 42
            elseif isControl then
                mass = 1.8
            else
                local size = maxs - mins
                local volume = math.abs(size.x * size.y * size.z)
                mass = math.Clamp(volume / 6500, 2.5, 28)
            end

            phys:SetMass(mass)
            phys:EnableGravity(true)
            phys:EnableMotion(true)

            -- Keep the pre-detachment vehicle velocity. The actual release
            -- impulse is applied later from the collision/blast event at the
            -- real impact point, which produces physically meaningful torque.
            phys:SetVelocity(train:GetVelocity())
            phys:Wake()
        end

        return debris
    end

    local function WorldDirectionToLocal(train, worldVector)
        if not IsSubwayTrain(train) or not isvector(worldVector) then
            return Vector(0, 0, 0)
        end

        return Vector(
            worldVector:Dot(train:GetForward()),
            worldVector:Dot(train:GetRight()),
            worldVector:Dot(train:GetUp())
        )
    end

    local function LocalDirectionToWorld(train, localVector)
        if not IsSubwayTrain(train) or not isvector(localVector) then
            return Vector(0, 0, 0)
        end

        return
            train:GetForward() * localVector.x
            + train:GetRight() * localVector.y
            + train:GetUp() * localVector.z
    end

    local function ApplyBreakawayImpulse(
        train,
        debris,
        impact,
        zone,
        anchorLocal,
        isDoor,
        isControl,
        ordinal
    )
        if not IsValid(debris) then return end

        local phys = debris:GetPhysicsObject()
        if not IsValid(phys) then return end

        ordinal = tonumber(ordinal) or 1

        local velocityImpulse = Vector(0, 0, 0)
        local applicationPoint = debris:GetPos()

        if istable(impact) then
            if isvector(impact.localImpulse)
                and impact.localImpulse:LengthSqr() > 1
            then
                velocityImpulse = LocalDirectionToWorld(
                    train,
                    impact.localImpulse
                )
            end

            if isvector(impact.localPos) then
                applicationPoint = train:LocalToWorld(impact.localPos)
            end

            if impact.blast then
                -- A blast wave pushes approximately radially away from its
                -- local pressure centre. Blend that radial impulse with the
                -- Source DamageForce direction so an off-centre blast both
                -- translates and rotates the released component.
                local radialLocal = anchorLocal - impact.localPos

                if radialLocal:LengthSqr() > 1 then
                    radialLocal:Normalize()
                    local radialWorld = LocalDirectionToWorld(
                        train,
                        radialLocal
                    )

                    local blastVelocity =
                        42 + math.Clamp(impact.power or 0, 0, 2) * 92

                    velocityImpulse =
                        velocityImpulse * 0.45
                        + radialWorld * blastVelocity
                end
            end
        end

        if velocityImpulse:LengthSqr() < 1 then
            local severity = MEXD.GetZoneDamage(train, zone or "front")
            velocityImpulse =
                ZoneOutwardNormal(train, zone or "front")
                    * (22 + severity * 62)
        end

        local typeScale =
            isDoor and 1.28
            or (isControl and 0.82 or 1.0)

        velocityImpulse = velocityImpulse * typeScale

        -- Split leaves need a tiny opposite shear so the two pieces do not
        -- continue occupying the same visual volume after the mount fails.
        if isDoor and ordinal > 1 then
            velocityImpulse =
                velocityImpulse
                + train:GetForward()
                    * ((ordinal % 2 == 0) and 22 or -22)
        end

        local mass = math.max(phys:GetMass(), 0.1)
        local impulse = velocityImpulse * mass

        -- Clamp the point to a useful lever arm around the debris centre.
        local lever = applicationPoint - debris:GetPos()
        local maxLever = math.max(
            debris:OBBMaxs():Length() * 0.65,
            8
        )

        if lever:Length() > maxLever then
            lever:Normalize()
            applicationPoint = debris:GetPos() + lever * maxLever
        end

        phys:ApplyForceOffset(impulse, applicationPoint)

        local seed =
            ((tonumber(util.CRC(debris:GetComponentName() or "")) or 0)
                % 1000) / 1000

        phys:AddAngleVelocity(Vector(
            -18 + seed * 36,
            12 - seed * 24,
            -26 + seed * 52
        ))

        if isDoor then
            local mins = debris:OBBMins()
            local maxs = debris:OBBMaxs()
            local size = maxs - mins

            local longAxis
            local longHalf

            if math.abs(size.z) >= math.abs(size.x)
                and math.abs(size.z) >= math.abs(size.y)
            then
                longAxis = debris:GetUp()
                longHalf = math.abs(size.z) * 0.5
            elseif math.abs(size.y) >= math.abs(size.x) then
                longAxis = debris:GetRight()
                longHalf = math.abs(size.y) * 0.5
            else
                longAxis = debris:GetForward()
                longHalf = math.abs(size.x) * 0.5
            end

            local sideways =
                train:GetRight()
                + train:GetForward() * (seed > 0.5 and 0.45 or -0.45)

            if sideways:LengthSqr() > 0.001 then
                sideways:Normalize()
            end

            -- Door leaves are tall thin bodies. Without an explicit hinge-fail
            -- moment Source can leave a perfectly vertical box balanced on its
            -- lower edge. Apply force away from COM near the long edge so the
            -- released leaf must tumble.
            local tipPoint =
                debris:GetPos()
                + longAxis * math.max(longHalf * 0.72, 14)

            phys:ApplyForceOffset(
                sideways * mass * (75 + seed * 45),
                tipPoint
            )
            phys:AddAngleVelocity(
                sideways * (115 + seed * 95)
            )

            local tipDirection = Vector(
                sideways.x,
                sideways.y,
                sideways.z
            )
            local lever = math.max(longHalf * 0.68, 14)

            for _, delay in ipairs({0.10, 0.34}) do
                timer.Simple(delay, function()
                    if not IsValid(debris) then return end

                    local p = debris:GetPhysicsObject()
                    if not IsValid(p) then return end

                    p:Wake()

                    -- If the leaf is still suspiciously upright / nearly
                    -- motionless, give gravity a lever arm instead of letting
                    -- the VPhysics box sleep on its bottom edge.
                    if p:GetVelocity():Length() < 95 then
                        local currentLongAxis

                        if math.abs(size.z) >= math.abs(size.x)
                            and math.abs(size.z) >= math.abs(size.y)
                        then
                            currentLongAxis = debris:GetUp()
                        elseif math.abs(size.y) >= math.abs(size.x) then
                            currentLongAxis = debris:GetRight()
                        else
                            currentLongAxis = debris:GetForward()
                        end

                        if math.abs(currentLongAxis:Dot(vector_up)) > 0.48 then
                            p:ApplyForceOffset(
                                tipDirection * p:GetMass() * 62,
                                debris:GetPos()
                                    + currentLongAxis * lever
                            )
                            p:AddAngleVelocity(
                                tipDirection * 95
                            )
                        end
                    end
                end)
            end
        end

        phys:Wake()
    end

    local PASSENGER_DOOR_FAMILIES = {
        {
            prefix = "models/metrostroi_train/81-717/81-717_doors_pos",
            leafA = "models/metrostroi_train/81-717/door_right_spb.mdl",
            leafB = "models/metrostroi_train/81-717/door_left_spb.mdl",
            position = function(i, k, leaf)
                local x = 338.0 - 230.1 * i + (1 - k) * 0.8
                if leaf == 2 then x = x + 0.2 end
                return Vector(x, -65 * (1 - 2 * k), 0.761)
            end,
        },
        {
            prefix = "models/metrostroi_train/81-718/81-718_doors_pos",
            leafA = "models/metrostroi_train/81-718/door_right.mdl",
            leafB = "models/metrostroi_train/81-718/door_left.mdl",
            position = function(i, k)
                return Vector(
                    338.2 - 230.1 * i + (1 - k) * 0.8,
                    -65.449 * (1 - 2 * k),
                    0.761
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-710/81-710_doors_pos",
            leafA = "models/metrostroi_train/81-710/81-710_door_right.mdl",
            leafB = "models/metrostroi_train/81-710/81-710_door_left.mdl",
            position = function(i, k, leaf)
                local x
                if leaf == 1 then
                    x = 344.9 - 0.1 * k - 233.6 * i
                else
                    x = 344.9 - 0.1 * (1 - k) - 233.6 * i
                end

                return Vector(
                    x,
                    -63.86 * (1 - 2.02 * k),
                    -5.75
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-502/81-502_doors_pos",
            leafA = "models/metrostroi_train/81-502/81-502_door_right.mdl",
            leafB = "models/metrostroi_train/81-502/81-502_door_left.mdl",
            position = function(i, k, leaf)
                local x
                if leaf == 1 then
                    x = 344.9 - 0.1 * k - 233.6 * i
                else
                    x = 344.9 - 0.1 * (1 - k) - 233.6 * i
                end

                return Vector(
                    x,
                    -63.86 * (1 - 2.02 * k),
                    -5.75
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-702/81-702_doors_pos",
            leafA = "models/metrostroi_train/81-702/81-702_door_right.mdl",
            leafB = "models/metrostroi_train/81-702/81-702_door_left.mdl",
            position = function(i, k, leaf)
                local x
                if leaf == 1 then
                    x = 349.45 - k - 232.202 * i
                else
                    x = 349.45 - (1 - k) - 232.202 * i
                end

                return Vector(
                    x,
                    -64.6 * (1 - 2 * k),
                    -8.728
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-703/81-703_doors_pos",
            leafA = "models/metrostroi_train/81-703/81-703_door_right.mdl",
            leafB = "models/metrostroi_train/81-703/81-703_door_left.mdl",
            position = function(i, k, leaf)
                local x
                if leaf == 1 then
                    x = 323.0 - 0.5 * k - 0.8 * (1 - k) - 233.5 * i
                else
                    x = 323.0 - 0.5 * (1 - k) - 0.8 * (1 - k) - 233.5 * i
                end

                return Vector(
                    x,
                    -62.8 * (1 - 2.045 * k),
                    -5.3
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-720/81-720_doors_pos",
            leafA = "models/metrostroi_train/81-720/81-720_door_l.mdl",
            leafB = "models/metrostroi_train/81-720/81-720_door_r.mdl",
            position = function(i, k)
                return Vector(
                    341 + k - 230 * i,
                    -64 * (1 - 2 * k),
                    -10
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-722/81-722_doors_pos",
            leafA = "models/metrostroi_train/81-722/81-722_door_l.mdl",
            leafB = "models/metrostroi_train/81-722/81-722_door_r.mdl",
            position = function(i, k)
                return Vector(
                    341 + k - 230 * i,
                    -64 * (1 - 2 * k),
                    -10
                )
            end,
        },
    }

    local function GetPassengerDoorFamily(name, model)
        local lowerName = string.lower(name or "")

        if string.find(lowerName, "frontdoor", 1, true)
            or string.find(lowerName, "reardoor", 1, true)
            or string.find(lowerName, "cabindoor", 1, true)
            or string.find(lowerName, "passengerdoor", 1, true)
        then
            return nil
        end

        if not string.match(name or "", "^door%d+x[01]$") then
            return nil
        end

        local lowerModel = string.lower(model or "")

        for _, family in ipairs(PASSENGER_DOOR_FAMILIES) do
            if string.find(lowerModel, family.prefix, 1, true) == 1 then
                return family
            end
        end

        -- Generic addon fallback. A lot of Metrostroi-derived trains keep the
        -- same naming convention even when their class is not part of the
        -- stock repository. Try common individual-leaf names beside a
        -- *_doors_posN.mdl combined model.
        local base = string.match(
            lowerModel,
            "^(.*)doors_pos%d+%.mdl$"
        )

        if not base then return nil end

        local dir = string.match(lowerModel, "^(.*[/])") or ""

        local pairsToTry = {
            {
                base .. "door_right.mdl",
                base .. "door_left.mdl",
            },
            {
                base .. "door_l.mdl",
                base .. "door_r.mdl",
            },
            {
                dir .. "door_right.mdl",
                dir .. "door_left.mdl",
            },
            {
                dir .. "door_l.mdl",
                dir .. "door_r.mdl",
            },
        }

        for _, pair in ipairs(pairsToTry) do
            if util.IsValidModel(pair[1])
                and util.IsValidModel(pair[2])
            then
                return {
                    leafA = pair[1],
                    leafB = pair[2],
                    generic = true,
                }
            end
        end

        return nil
    end

    local function SpawnSplitPassengerDoorLeaves(
        train,
        name,
        model,
        originalLocalPos,
        originalLocalAng,
        zone,
        skin,
        color,
        material,
        bodygroups,
        frozenSequence,
        frozenCycle,
        frozenPose
    )
        local family = GetPassengerDoorFamily(name, model)
        if not family then return nil end

        local i, k = string.match(name, "^door(%d)x([01])$")
        i = tonumber(i)
        k = tonumber(k)

        if not i or not k then return nil end

        local specs

        if family.generic then
            local basePos = isvector(originalLocalPos)
                and originalLocalPos
                or Vector(0, 0, 0)

            specs = {
                {
                    suffix = "a",
                    model = family.leafA,
                    pos = basePos + Vector(-0.12, 0, 0),
                },
                {
                    suffix = "b",
                    model = family.leafB,
                    pos = basePos + Vector(0.12, 0, 0),
                },
            }
        else
            specs = {
                {
                    suffix = "a",
                    model = family.leafA,
                    pos = family.position(i, k, 1),
                },
                {
                    suffix = "b",
                    model = family.leafB,
                    pos = family.position(i, k, 2),
                },
            }
        end

        local leaves = {}

        for leafIndex, spec in ipairs(specs) do
            if not util.IsValidModel(spec.model) then
                for _, leaf in ipairs(leaves) do
                    if IsValid(leaf) then leaf:Remove() end
                end
                return nil
            end

            local leaf = SpawnDetachedPhysicsProp(
                train,
                name .. ":" .. spec.suffix,
                spec.model,
                spec.pos,
                family.generic and (
                    isangle(originalLocalAng)
                        and originalLocalAng
                        or Angle(0, 90 + 180 * k, 0)
                ) or Angle(0, 90 + 180 * k, 0),
                nil,
                nil,
                skin,
                color,
                material,
                bodygroups,
                true,
                false,
                zone,
                frozenSequence,
                frozenCycle,
                frozenPose
            )

            if not IsValid(leaf) then
                for _, existing in ipairs(leaves) do
                    if IsValid(existing) then existing:Remove() end
                end
                return nil
            end

            local phys = leaf:GetPhysicsObject()
            if IsValid(phys) then
                local separation =
                    train:GetForward() * (leafIndex == 1 and -1 or 1)
                    + train:GetRight() * (k == 1 and 0.18 or -0.18)

                phys:AddVelocity(separation * (26 + leafIndex * 7))
                phys:AddAngleVelocity(Vector(
                    leafIndex == 1 and 90 or -90,
                    leafIndex == 1 and -60 or 60,
                    leafIndex == 1 and 125 or -125
                ))
                phys:Wake()
            end

            leaves[#leaves + 1] = leaf
        end

        return leaves
    end

    local function IsGlassComponentName(name, model)
        local lowerModel = string.lower(model or "")

        if string.find(lowerModel, "glass", 1, true)
            or string.find(lowerModel, "window", 1, true)
            or string.find(lowerModel, "stekl", 1, true)
        then
            return true
        end

        local lowerName = string.lower(name or "")

        if string.find(lowerName, "washer", 1, true)
            or string.find(lowerName, "cleaner", 1, true)
            or string.find(lowerName, "wiper", 1, true)
            or string.find(lowerName, "button", 1, true)
            or string.find(lowerName, "switch", 1, true)
            or string.find(lowerName, "toggle", 1, true)
        then
            return false
        end

        return string.find(lowerName, "glass", 1, true) ~= nil
            or string.find(lowerName, "window", 1, true) ~= nil
            or string.find(lowerName, "stekl", 1, true) ~= nil
    end

    local function SpawnGlassShards(train, name, anchorLocal, zone)
        local shards = {}
        local worldPos = train:LocalToWorld(anchorLocal)
        local normal = ZoneOutwardNormal(train, zone or "front")

        local effect = EffectData()
        effect:SetOrigin(worldPos)
        effect:SetNormal(normal)
        effect:SetMagnitude(2)
        effect:SetScale(1.5)
        util.Effect("GlassImpact", effect, true, true)

        sound.Play(
            "physics/glass/glass_largesheet_break1.wav",
            worldPos,
            78,
            100,
            0.9
        )

        local shardModels = {
            "models/gibs/glass_shard01.mdl",
            "models/gibs/glass_shard02.mdl",
            "models/gibs/glass_shard03.mdl",
            "models/gibs/glass_shard04.mdl",
        }

        for i = 1, 6 do
            local model = shardModels[((i - 1) % #shardModels) + 1]
            if not util.IsValidModel(model) then continue end

            local offset = Vector(
                math.Rand(-7, 7),
                math.Rand(-7, 7),
                math.Rand(-5, 7)
            )

            local shard = SpawnDetachedPhysicsProp(
                train,
                name .. ":glass:" .. i,
                model,
                anchorLocal + offset,
                Angle(
                    math.Rand(-25, 25),
                    math.Rand(0, 360),
                    math.Rand(-25, 25)
                ),
                Vector(-2, -2, -2),
                Vector(2, 2, 2),
                0,
                color_white,
                "",
                {},
                false,
                false,
                zone,
                0,
                0,
                0
            )

            if IsValid(shard) then
                local phys = shard:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetMass(0.35)
                    phys:AddVelocity(
                        normal * math.Rand(45, 110)
                        + train:GetUp() * math.Rand(15, 70)
                        + train:GetRight() * math.Rand(-55, 55)
                    )
                    phys:Wake()
                end

                shards[#shards + 1] = shard

                timer.Simple(25 + i * 2, function()
                    if IsValid(shard) then shard:Remove() end
                end)
            end
        end

        return shards
    end

    local COMPONENT_IMPACT_LIFETIME = 0.90

    local function PruneComponentImpacts(train)
        if not istable(train.MEXDamageComponentImpacts) then
            train.MEXDamageComponentImpacts = {}
            return
        end

        local now = CurTime()

        for i = #train.MEXDamageComponentImpacts, 1, -1 do
            local impact = train.MEXDamageComponentImpacts[i]
            if not istable(impact)
                or impact.expires <= now
                or impact.remaining <= 0
            then
                table.remove(train.MEXDamageComponentImpacts, i)
            end
        end
    end

    local function SendComponentImpact(
        train,
        worldPos,
        power,
        radius,
        maxDetach,
        source,
        worldImpulse,
        isBlast
    )
        if not IsSubwayTrain(train) or not isvector(worldPos) then return end

        power = math.Clamp(tonumber(power) or 0, 0.05, 2.0)
        radius = math.Clamp(tonumber(radius) or 20, 8, 320)
        maxDetach = math.Clamp(math.floor(tonumber(maxDetach) or 1), 1, 96)

        local localImpulse = Vector(0, 0, 0)
        if isvector(worldImpulse) then
            localImpulse = WorldDirectionToLocal(train, worldImpulse)
        end

        PruneComponentImpacts(train)

        train.MEXDamageComponentImpactSerial =
            (train.MEXDamageComponentImpactSerial or 0) + 1

        local impact = {
            id = train.MEXDamageComponentImpactSerial,
            localPos = train:WorldToLocal(worldPos),
            localImpulse = localImpulse,
            power = power,
            radius = radius,
            remaining = maxDetach,
            source = source or "unknown",
            blast = isBlast == true,
            expires = CurTime() + COMPONENT_IMPACT_LIFETIME,
        }

        table.insert(train.MEXDamageComponentImpacts, impact)

        net.Start("MEX.ComponentImpact")
            net.WriteEntity(train)
            net.WriteUInt(impact.id % 65536, 16)
            net.WriteVector(impact.localPos)
            net.WriteVector(localImpulse)
            net.WriteFloat(power)
            net.WriteFloat(radius)
            net.WriteUInt(maxDetach, 7)
            net.WriteBool(impact.blast)
        net.Broadcast()
    end

    local function FindRecentComponentImpact(
        train,
        anchorLocal,
        componentRadius
    )
        if not IsSubwayTrain(train) or not isvector(anchorLocal) then
            return nil
        end

        PruneComponentImpacts(train)

        local best = nil
        local bestScore = 0

        for _, impact in ipairs(train.MEXDamageComponentImpacts or {}) do
            if impact.remaining <= 0 then continue end

            local distance = math.max(
                0,
                anchorLocal:Distance(impact.localPos)
                    - math.max(componentRadius or 0, 0)
            )
            if distance > impact.radius then continue end

            local falloff = 1 - distance / math.max(impact.radius, 1)
            local score = falloff * impact.power

            if score > bestScore then
                best = impact
                bestScore = score
            end
        end

        return best, bestScore
    end

    local function DamageImpactWorldPosition(train, dmginfo)
        local pos = dmginfo:GetDamagePosition()

        if isvector(pos) and pos ~= vector_origin then
            return pos
        end

        local attacker = dmginfo:GetAttacker()

        if IsValid(attacker) and attacker:IsPlayer() then
            local startPos = attacker:GetShootPos()
            local trace = util.TraceLine({
                start = startPos,
                endpos = startPos + attacker:GetAimVector() * 160,
                filter = attacker,
            })

            if trace.Entity == train and trace.Hit then
                return trace.HitPos
            end
        end

        if IsValid(attacker) then
            return train:NearestPoint(attacker:GetPos())
        end

        return train:GetPos()
    end

    local function IsComponentDamageType(dmginfo)
        return
            dmginfo:IsDamageType(DMG_BULLET)
            or dmginfo:IsDamageType(DMG_BUCKSHOT)
            or dmginfo:IsDamageType(DMG_CLUB)
            or dmginfo:IsDamageType(DMG_SLASH)
            or dmginfo:IsDamageType(DMG_CRUSH)
            or dmginfo:IsDamageType(DMG_BLAST)
            or dmginfo:IsDamageType(DMG_VEHICLE)
    end

    local function InitializeTrainDamage(train)
        if not IsSubwayTrain(train) then return end
        if train.MEXDamageInitialized then return end

        train.MEXDamageInitialized = true
        EnsureButtonEventGuard(train)
        train.MEXDamageIgnoreUntil = CurTime() + SPAWN_GRACE_SECONDS
        train.MEXDamageLastVelocity = train:GetVelocity()
        train.MEXDamageLastPosition = train:GetPos()
        train.MEXDamageLastSample = CurTime()
        train.MEXDamagePreviousSpeedKmh = train:GetVelocity():Length() * SU_TO_KMH

        train:SetNW2Bool("MEX.DamageReady", false)
        train:SetNW2Float("MEX.DamageReadyAt", train.MEXDamageIgnoreUntil)

        -- PhysicsCollide gives us the real contact point and pre-impact
        -- velocities. This is the primary crash detector in v0.4; the old
        -- velocity-change detector remains only as a fallback for collisions
        -- that Source does not report to the scripted train entity.
        if not train.MEXDamagePhysicsCallback then
            train.MEXDamagePhysicsCallback = train:AddCallback("PhysicsCollide", function(ent, data)
                if not IsSubwayTrain(ent) then return end
                if CurTime() < (ent.MEXDamageIgnoreUntil or 0) then return end
                if (ent.MEXDamageCrashCooldown or 0) > CurTime() then return end
                if not istable(data) then return end

                local ourOld = isvector(data.OurOldVelocity) and data.OurOldVelocity or ent:GetVelocity()
                local theirOld = isvector(data.TheirOldVelocity) and data.TheirOldVelocity or vector_origin
                local relativeVelocity = ourOld - theirOld

                local hitNormal = isvector(data.HitNormal) and data.HitNormal or vector_origin
                local normalSpeed = 0
                if hitNormal:LengthSqr() > 0.001 then
                    normalSpeed = math.abs(relativeVelocity:Dot(hitNormal))
                end

                local relativeSpeed = relativeVelocity:Length()
                local impactSpeedSU = math.max(normalSpeed, relativeSpeed * 0.45)

                if isvector(data.HitSpeed) then
                    impactSpeedSU = math.max(impactSpeedSU, data.HitSpeed:Length())
                end

                local impactKmh = impactSpeedSU * SU_TO_KMH
                if impactKmh < MIN_CRASH_SPEED_KMH then return end

                local hitPos = isvector(data.HitPos) and data.HitPos or ent:GetPos()
                local zone = ClassifyFromWorldPosition and ClassifyFromWorldPosition(ent, hitPos) or nil
                if not zone then
                    zone = ClassifyFromWorldDeltaVelocity and ClassifyFromWorldDeltaVelocity(ent, relativeVelocity) or "front"
                end

                local severity = math.Clamp(
                    (impactKmh - MIN_CRASH_SPEED_KMH)
                    / (MAX_CRASH_SPEED_KMH - MIN_CRASH_SPEED_KMH),
                    0.015,
                    0.90
                )

                -- Repeated sub-crash contacts in one physical impact arrive in
                -- consecutive physics steps. Count the first one and let the
                -- deformation accumulator handle later distinct impacts.
                ent.MEXDamageCrashCooldown = CurTime() + 0.12
                ent:SetNW2Float("MEX.Damage.LastImpactKmh", impactKmh)

                SendComponentImpact(
                    ent,
                    hitPos,
                    math.Clamp(impactKmh / 42, 0.15, 1.7),
                    math.Clamp(18 + impactKmh * 1.65, 22, 180),
                    math.Clamp(1 + math.floor(impactKmh / 12), 1, 16),
                    "physics",
                    relativeVelocity * 0.70,
                    false
                )

                MEXD.ApplyDamage(
                    ent,
                    zone,
                    severity,
                    hitPos,
                    ZoneOutwardNormal(ent, zone),
                    "physics"
                )
            end)
        end

        MEXD.Reset(train)

        -- Metrostroi can move/reparent/settle a newly spawned wagon very
        -- aggressively. Ignore all of that and take a fresh baseline exactly
        -- one second after creation.
        timer.Simple(SPAWN_GRACE_SECONDS, function()
            if not IsSubwayTrain(train) then return end

            MEXD.Reset(train)
            train.MEXDamageLastVelocity = train:GetVelocity()
            train.MEXDamageLastPosition = train:GetPos()
            train.MEXDamageLastSample = CurTime()
            train.MEXDamagePreviousSpeedKmh = train:GetVelocity():Length() * SU_TO_KMH
            train.MEXDamageCrashCooldown = CurTime() + 0.10
            train:SetNW2Bool("MEX.DamageReady", true)
        end)
    end

    function MEXD.Reset(train)
        if not IsValid(train) then return end

        RemoveDetachedServerComponents(train, train.MEXDamageInitialized == true)

        for zone in pairs(ZONES) do
            train:SetNW2Float(DamageKey(zone), 0)
            train:SetNW2Float("MEX.Damage.HitStrength." .. zone, 0)
            train:SetNW2Vector("MEX.Damage.HitLocal." .. zone, vector_origin)
        end

        train:SetNW2Float("MEX.Damage.electrical", 0)
        train:SetNW2Float("MEX.Damage.overall", 0)
        train:SetNW2Float("MEX.StructuralHealth", 1)
        train:SetNW2Float("MEX.Damage.LastImpactKmh", 0)
        train:SetNW2Float("MEX.Damage.BlastStrength", 0)
        train:SetNW2Float("MEX.Damage.BlastRadius", 0)
        train:SetNW2Vector("MEX.Damage.BlastLocal", vector_origin)
        train:SetNW2Vector("MEX.Damage.BlastImpulseLocal", vector_origin)
        train.MEXDamageComponentImpacts = {}

        train:SetNW2Bool("MEX.Damage.Moderate", false)
        train:SetNW2Bool("MEX.Damage.Heavy", false)
        train:SetNW2Bool("MEX.Damage.Critical", false)
        train:SetNW2Bool("MEX.Damage.DoorsLeft", false)
        train:SetNW2Bool("MEX.Damage.DoorsRight", false)
        train:SetNW2Bool("MEX.Damage.FrontEquipment", false)
        train:SetNW2Bool("MEX.Damage.RearEquipment", false)
        train:SetNW2Bool("MEX.Damage.ElectricalFault", false)

        hook.Run("MetrostroiExpandedDamageReset", train)
    end

    local function SendImpactEffect(train, zone, amount, worldPos, normal)
        if not IsValid(train) then return end

        worldPos = worldPos or train:LocalToWorld(ZoneLocalImpactPoint(train, zone))
        normal = normal or ZoneOutwardNormal(train, zone)

        net.Start("MEX.DamageImpact")
            net.WriteEntity(train)
            net.WriteString(zone)
            net.WriteFloat(amount)
            net.WriteVector(worldPos)
            net.WriteNormal(normal)
        net.Broadcast()

        if amount >= 0.10 then
            local effect = EffectData()
            effect:SetOrigin(worldPos)
            effect:SetNormal(normal)
            effect:SetMagnitude(math.Clamp(amount * 6, 1, 6))
            effect:SetScale(math.Clamp(amount * 2, 0.5, 2))
            effect:SetRadius(math.Clamp(amount * 12, 2, 12))
            util.Effect("Sparks", effect, true, true)
        end

        if amount >= 0.18 then
            util.Decal(
                "Impact.Metal",
                worldPos + normal * 12,
                worldPos - normal * 12,
                train
            )
        end
    end

    function MEXD.ApplyDamage(train, zone, amount, worldPos, normal, source)
        if not IsSubwayTrain(train) or not ZONES[zone] then return 0 end

        amount = math.Clamp(tonumber(amount) or 0, 0, 1)
        if amount <= 0 then return MEXD.GetZoneDamage(train, zone) end

        local old = MEXD.GetZoneDamage(train, zone)

        -- Damage accumulation gets progressively less effective as the zone is
        -- already crushed, so repeated tiny contacts cannot instantly destroy it.
        local effective = amount * (1 - old * 0.45)
        local new = math.Clamp(old + effective, 0, 1)

        train:SetNW2Float(DamageKey(zone), new)

        if isvector(worldPos) then
            local hitLocal = train:WorldToLocal(worldPos)
            local hitKey = "MEX.Damage.HitLocal." .. zone
            local strengthKey = "MEX.Damage.HitStrength." .. zone
            local oldStrength = train:GetNW2Float(strengthKey, 0)
            local oldHit = train:GetNW2Vector(hitKey, hitLocal)
            local combinedStrength = math.Clamp(oldStrength + amount, 0, 1)

            if oldStrength <= 0.001 then
                oldHit = hitLocal
            end

            local blend = math.Clamp(amount / math.max(oldStrength + amount, 0.001), 0, 1)
            train:SetNW2Vector(hitKey, LerpVector(blend, oldHit, hitLocal))
            train:SetNW2Float(strengthKey, combinedStrength)
        end

        -- Hard impacts can disturb electrical equipment even when the physical
        -- deformation is elsewhere. This is a generic state for the future
        -- electrical subsystem module.
        if amount >= 0.22 then
            local electrical = train:GetNW2Float("MEX.Damage.electrical", 0)
            electrical = math.Clamp(electrical + amount * 0.30, 0, 1)
            train:SetNW2Float("MEX.Damage.electrical", electrical)
        end

        UpdateDamageState(train)
        SendImpactEffect(train, zone, amount, worldPos, normal)

        if amount >= 0.10 then
            local pitch = math.floor(Lerp(math.Clamp(amount, 0, 1), 115, 80))
            train:EmitSound("physics/metal/metal_box_impact_hard3.wav", 82, pitch, 0.8)
        end

        hook.Run(
            "MetrostroiExpandedTrainDamaged",
            train,
            zone,
            amount,
            old,
            new,
            source or "unknown"
        )

        return new
    end

    ClassifyFromWorldDeltaVelocity = function(train, deltaVelocity)
        local x = deltaVelocity:Dot(train:GetForward())
        local y = deltaVelocity:Dot(train:GetRight())
        local z = deltaVelocity:Dot(train:GetUp())

        local ax, ay, az = math.abs(x), math.abs(y), math.abs(z)

        if ax >= ay and ax >= az then
            -- A front impact pushes/decelerates the train towards -local X.
            return x < 0 and "front" or "rear"
        elseif ay >= az then
            -- A hit on the right side pushes the train towards -local Y.
            return y < 0 and "right" or "left"
        end

        -- Roof contact pushes down; floor contact pushes up.
        return z < 0 and "roof" or "floor"
    end

    ClassifyFromWorldPosition = function(train, worldPos)
        if not isvector(worldPos) then return nil end

        local localPos = train:WorldToLocal(worldPos)
        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()

        local centerX = (mins.x + maxs.x) * 0.5
        local centerY = (mins.y + maxs.y) * 0.5
        local centerZ = (mins.z + maxs.z) * 0.5

        local nx = math.abs(localPos.x - centerX) / math.max((maxs.x - mins.x) * 0.5, 1)
        local ny = math.abs(localPos.y - centerY) / math.max((maxs.y - mins.y) * 0.5, 1)
        local nz = math.abs(localPos.z - centerZ) / math.max((maxs.z - mins.z) * 0.5, 1)

        if nx >= ny and nx >= nz then
            return localPos.x >= centerX and "front" or "rear"
        elseif ny >= nz then
            return localPos.y >= centerY and "right" or "left"
        end

        return localPos.z >= centerZ and "roof" or "floor"
    end

    net.Receive("MEX.DetachRequest", function(_, ply)
        local train = net.ReadEntity()
        local name = net.ReadString()
        local model = net.ReadString()
        local localPos = net.ReadVector()
        local localAng = net.ReadAngle()
        local anchorLocal = net.ReadVector()
        local mins = net.ReadVector()
        local maxs = net.ReadVector()
        local isDoor = net.ReadBool()
        local isControl = net.ReadBool()
        local skin = net.ReadUInt(8)
        local color = net.ReadColor()
        local material = net.ReadString()
        local frozenSequence = net.ReadUInt(16)
        local frozenCycle = net.ReadFloat()
        local frozenPose = net.ReadFloat()

        local bodygroups = {}
        local bodygroupCount = math.min(net.ReadUInt(5), 31)
        for _ = 1, bodygroupCount do
            local id = net.ReadUInt(5)
            local value = net.ReadUInt(8)
            bodygroups[id] = value
        end

        local buttonIDs = {}
        local buttonCount = math.min(net.ReadUInt(6), 48)
        for _ = 1, buttonCount do
            local id = net.ReadString()
            if #id <= 96 and id ~= "" then
                buttonIDs[#buttonIDs + 1] = id:gsub("^.+:", "")
            end
        end

        if not IsSubwayTrain(train) then return end
        InitializeTrainDamage(train)
        if CurTime() < (train.MEXDamageIgnoreUntil or 0) then return end

        if not isstring(name) or name == "" or #name > 128 then return end
        if not isstring(model) or #model > 192 then return end
        if string.sub(string.lower(model), 1, 7) ~= "models/" then return end
        if not util.IsValidModel(model) then return end
        if not isvector(localPos) or not isangle(localAng) then return end
        if not isvector(anchorLocal) then return end
        if not isvector(mins) or not isvector(maxs) then return end
        if not isstring(material) or #material > 160 then return end

        local obbMins = train:OBBMins() - Vector(100, 100, 100)
        local obbMaxs = train:OBBMaxs() + Vector(100, 100, 100)

        if localPos.x < obbMins.x or localPos.x > obbMaxs.x
            or localPos.y < obbMins.y or localPos.y > obbMaxs.y
            or localPos.z < obbMins.z or localPos.z > obbMaxs.z
            or anchorLocal.x < obbMins.x or anchorLocal.x > obbMaxs.x
            or anchorLocal.y < obbMins.y or anchorLocal.y > obbMaxs.y
            or anchorLocal.z < obbMins.z or anchorLocal.z > obbMaxs.z
        then
            return
        end

        train.MEXDamageDetachedServer = train.MEXDamageDetachedServer or {}

        local now = CurTime()
        if not ply.MEXDamageDetachWindow
            or now - ply.MEXDamageDetachWindow >= 1
        then
            ply.MEXDamageDetachWindow = now
            ply.MEXDamageDetachCount = 0
        end

        ply.MEXDamageDetachCount = (ply.MEXDamageDetachCount or 0) + 1
        if ply.MEXDamageDetachCount > 192 then return end

        local detachedCount = table.Count(train.MEXDamageDetachedServer)
        if detachedCount >= 160 then return end

        if train.MEXDamageDetachedServer[name] then
            BroadcastDetachedComponent(
                train,
                name,
                train.MEXDamageDetachedServer[name].debris,
                ply
            )
            return
        end

        local zone, localScore = FindNearestDamagedZone(train, anchorLocal)
        local overall = MEXD.GetOverallDamage(train)
        local componentSize = maxs - mins
        local componentRadius = math.Clamp(
            math.max(
                math.abs(componentSize.x),
                math.abs(componentSize.y),
                math.abs(componentSize.z)
            ) * 0.30,
            3,
            isDoor and 34 or 20
        )

        local directImpact, directScore =
            FindRecentComponentImpact(
                train,
                anchorLocal,
                componentRadius
            )

        -- A mounting can fail either from accumulated structural deformation
        -- or from a direct local hit (crowbar, bullet, local collision).
        -- Direct hits are intentionally local and consume one slot from that
        -- impact so a pistol shot does not detach an entire dashboard.
        local structuralMinimum =
            isDoor and 0.055
            or (isControl and 0.020 or 0.035)

        local directMinimum

        if directImpact and directImpact.blast then
            -- Blast attachment failure is driven by impulse/movement. If the
            -- mounting is displaced at all, fragile hardware should tear away
            -- instead of elastically snapping back into the train.
            directMinimum =
                isDoor and 0.045
                or (isControl and 0.018 or 0.035)
        else
            directMinimum =
                isDoor and 0.20
                or (isControl and 0.11 or 0.20)
        end

        local structuralOK =
            zone ~= nil
            and localScore >= structuralMinimum
            and overall >= (isDoor and 0.18 or 0.08)

        local directOK =
            directImpact ~= nil
            and directScore >= directMinimum

        if not structuralOK and not directOK then
            return
        end

        if directOK then
            directImpact.remaining = math.max(0, directImpact.remaining - 1)
            zone = zone or ClassifyFromWorldPosition(
                train,
                train:LocalToWorld(anchorLocal)
            )
        end

        local debris
        local debrisList
        local isGlass = IsGlassComponentName(name, model)

        if isGlass then
            debrisList = SpawnGlassShards(
                train,
                name,
                anchorLocal,
                zone
            )
            debris = istable(debrisList) and debrisList[1] or nil
        elseif isDoor and GetPassengerDoorFamily(name, model) then
            debrisList = SpawnSplitPassengerDoorLeaves(
                train,
                name,
                model,
                localPos,
                localAng,
                zone,
                skin,
                color,
                material,
                bodygroups,
                frozenSequence,
                frozenCycle,
                frozenPose
            )

            if istable(debrisList) and #debrisList > 0 then
                debris = debrisList[1]
            else
                debrisList = nil
                debris = SpawnDetachedPhysicsProp(
                    train,
                    name,
                    model,
                    localPos,
                    localAng,
                    mins,
                    maxs,
                    skin,
                    color,
                    material,
                    bodygroups,
                    isDoor,
                    isControl,
                    zone,
                    frozenSequence,
                    frozenCycle,
                    frozenPose
                )

                if not IsValid(debris) then return end
            end
        else
            debris = SpawnDetachedPhysicsProp(
                train,
                name,
                model,
                localPos,
                localAng,
                mins,
                maxs,
                skin,
                color,
                material,
                bodygroups,
                isDoor,
                isControl,
                zone,
                frozenSequence,
                frozenCycle,
                frozenPose
            )

            if not IsValid(debris) then return end
        end

        if not isGlass then
            if istable(debrisList) and #debrisList > 0 then
                for ordinal, released in ipairs(debrisList) do
                    ApplyBreakawayImpulse(
                        train,
                        released,
                        directImpact,
                        zone,
                        anchorLocal,
                        isDoor,
                        isControl,
                        ordinal
                    )
                end
            elseif IsValid(debris) then
                ApplyBreakawayImpulse(
                    train,
                    debris,
                    directImpact,
                    zone,
                    anchorLocal,
                    isDoor,
                    isControl,
                    1
                )
            end
        end

        local validButtons = {}
        local seenButtons = {}

        local function rememberAndBlock(button)
            if not isstring(button) or button == "" then return end
            button = button:gsub("^.+:", "")
            if #button > 96 or seenButtons[button] then return end

            seenButtons[button] = true
            BlockDetachedButton(train, button)
            validButtons[#validButtons + 1] = button
        end

        -- These IDs were resolved client-side from the actual physical
        -- ClientEnt/ButtonMap relationship of the component whose detach the
        -- server has just validated by location/model/recent impact. Some old
        -- trains expose mouse-only ButtonMap IDs which do not exist in KeyMap
        -- and used to be incorrectly discarded here.
        for _, button in ipairs(buttonIDs) do
            rememberAndBlock(button)
        end

        local expandedButtons = ExpandDetachedButtonAliases(
            train,
            buttonIDs
        )

        for _, button in ipairs(expandedButtons) do
            if not seenButtons[button]
                and IsValidDetachedButtonID(train, button)
            then
                rememberAndBlock(button)
            end
        end

        train.MEXDamageDetachedServer[name] = {
            debris = debris,
            debrisList = debrisList,
            buttons = validButtons,
        }

        BroadcastDetachedComponent(train, name, debris)
    end)

    hook.Add("PlayerInitialSpawn", "MEX.Damage.SyncDetachedComponents", function(ply)
        timer.Simple(2, function()
            if not IsValid(ply) then return end

            for _, train in ipairs(ents.GetAll()) do
                if not IsSubwayTrain(train)
                    or not istable(train.MEXDamageDetachedServer)
                then
                    continue
                end

                for name, data in pairs(train.MEXDamageDetachedServer) do
                    BroadcastDetachedComponent(
                        train,
                        name,
                        data.debris,
                        ply
                    )
                end
            end
        end)
    end)

    hook.Add("EntityTakeDamage", "MEX.Damage.FromEntityDamage", function(ent, dmginfo)
        if not IsSubwayTrain(ent) then return end

        InitializeTrainDamage(ent)
        if CurTime() < (ent.MEXDamageIgnoreUntil or 0) then return end

        local rawDamage = math.max(dmginfo:GetDamage(), 0)

        if IsComponentDamageType(dmginfo) and rawDamage > 0 then
            local componentPos = DamageImpactWorldPosition(ent, dmginfo)
            local isBlast = dmginfo:IsDamageType(DMG_BLAST)
            local isBuckshot = dmginfo:IsDamageType(DMG_BUCKSHOT)
            local isCrush = dmginfo:IsDamageType(DMG_CRUSH)
                or dmginfo:IsDamageType(DMG_VEHICLE)

            local radius
            local maxDetach

            if isBlast then
                radius = math.Clamp(58 + rawDamage * 1.15, 70, 280)
                maxDetach = math.Clamp(10 + math.floor(rawDamage / 8), 10, 80)
            elseif isCrush then
                radius = math.Clamp(22 + rawDamage * 0.45, 24, 105)
                maxDetach = math.Clamp(1 + math.floor(rawDamage / 32), 1, 7)
            elseif isBuckshot then
                radius = math.Clamp(25 + rawDamage * 0.22, 26, 55)
                maxDetach = math.Clamp(1 + math.floor(rawDamage / 35), 1, 4)
            else
                -- Crowbar/pistol/rifle: a very local hit. Normally only the
                -- nearest mounted object loses its attachment.
                radius = math.Clamp(13 + rawDamage * 0.18, 14, 30)
                maxDetach = 1
            end

            local damageForce = dmginfo:GetDamageForce()
            local impulseWorld = Vector(0, 0, 0)

            if isvector(damageForce) and damageForce:LengthSqr() > 1 then
                local dir = damageForce:GetNormalized()
                local speedImpulse

                if isBlast then
                    speedImpulse = math.Clamp(45 + rawDamage * 1.65, 55, 260)
                elseif isCrush then
                    speedImpulse = math.Clamp(25 + rawDamage * 0.85, 30, 170)
                elseif isBuckshot then
                    speedImpulse = math.Clamp(18 + rawDamage * 0.55, 20, 105)
                else
                    speedImpulse = math.Clamp(10 + rawDamage * 0.35, 12, 70)
                end

                impulseWorld = dir * speedImpulse
            end

            SendComponentImpact(
                ent,
                componentPos,
                math.Clamp(
                    (isBlast and 0.55 or 0.32) + rawDamage / 40,
                    isBlast and 0.55 or 0.32,
                    isBlast and 1.9 or 1.35
                ),
                radius,
                maxDetach,
                isBlast and "blast" or "damageinfo",
                impulseWorld,
                isBlast
            )
        end

        if not (
            dmginfo:IsDamageType(DMG_CRUSH)
            or dmginfo:IsDamageType(DMG_BLAST)
        ) then
            return
        end

        if rawDamage <= 1 then return end

        local pos = dmginfo:GetDamagePosition()
        local zone = nil

        if isvector(pos) and pos ~= vector_origin then
            zone = ClassifyFromWorldPosition(ent, pos)
        end

        if not zone then
            local force = dmginfo:GetDamageForce()
            if isvector(force) and force:LengthSqr() > 1 then
                zone = ClassifyFromWorldDeltaVelocity(ent, force)
            end
        end

        zone = zone or "front"
        local amount = math.Clamp(rawDamage / 260, 0.025, 0.42)
        local normal = ZoneOutwardNormal(ent, zone)

        if dmginfo:IsDamageType(DMG_BLAST) then
            local blastWorldPos = DamageImpactWorldPosition(ent, dmginfo)
            local blastForce = dmginfo:GetDamageForce()
            local blastImpulseLocal = Vector(0, 0, 0)

            if isvector(blastForce) and blastForce:LengthSqr() > 1 then
                local dir = blastForce:GetNormalized()
                local velocityLike =
                    math.Clamp(45 + rawDamage * 1.65, 55, 260)
                blastImpulseLocal = WorldDirectionToLocal(
                    ent,
                    dir * velocityLike
                )
            end

            ent:SetNW2Vector(
                "MEX.Damage.BlastLocal",
                ent:WorldToLocal(blastWorldPos)
            )
            ent:SetNW2Vector(
                "MEX.Damage.BlastImpulseLocal",
                blastImpulseLocal
            )
            ent:SetNW2Float(
                "MEX.Damage.BlastStrength",
                math.Clamp(rawDamage / 180, 0.08, 1.25)
            )
            ent:SetNW2Float(
                "MEX.Damage.BlastRadius",
                math.Clamp(58 + rawDamage * 1.15, 70, 280)
            )
        end

        -- Prevent the velocity-change detector from counting the same physical
        -- collision a second time on the next scan.
        ent.MEXDamageCrashCooldown = CurTime() + 0.18

        MEXD.ApplyDamage(ent, zone, amount, pos, normal, "damageinfo")
    end)

    local nextVelocityScan = 0

    hook.Add("Think", "MEX.Damage.VelocityCrashDetection", function()
        if CurTime() < nextVelocityScan then return end
        nextVelocityScan = CurTime() + 0.05

        for _, train in ipairs(ents.GetAll()) do
            if not IsSubwayTrain(train) then continue end

            InitializeTrainDamage(train)

            local velocity = train:GetVelocity()
            local position = train:GetPos()
            local now = CurTime()

            if not train.MEXDamageLastVelocity then
                train.MEXDamageLastVelocity = velocity
                train.MEXDamageLastPosition = position
                train.MEXDamageLastSample = now
                continue
            end

            local dt = now - (train.MEXDamageLastSample or now)
            local moved = position:Distance(train.MEXDamageLastPosition or position)
            local deltaVelocity = velocity - train.MEXDamageLastVelocity

            train.MEXDamageLastVelocity = velocity
            train.MEXDamageLastPosition = position
            train.MEXDamageLastSample = now
            train.MEXDamagePreviousSpeedKmh = velocity:Length() * SU_TO_KMH

            -- A newly created Metrostroi wagon receives several large position
            -- and velocity corrections while bogeys, couplers and systems are
            -- being initialized. Keep updating the baseline, but never turn
            -- those corrections into crash damage.
            if now < (train.MEXDamageIgnoreUntil or 0) then continue end

            -- Ignore teleports, respawns and physics reinitialisation.
            if dt <= 0 or dt > 0.25 or moved > 600 then continue end

            local deltaKmh = deltaVelocity:Length() * SU_TO_KMH
            if deltaKmh < 12 then continue end
            if (train.MEXDamageCrashCooldown or 0) > now then continue end

            local previousSpeedKmh = math.max(
                0,
                (velocity - deltaVelocity):Length() * SU_TO_KMH
            )

            -- A very low-speed train can receive a physics correction while
            -- spawning/coupling. Require either meaningful movement or a strong
            -- velocity impulse.
            if previousSpeedKmh < 5 and deltaKmh < 18 then continue end

            train.MEXDamageCrashCooldown = now + 0.22

            local zone = ClassifyFromWorldDeltaVelocity(train, deltaVelocity)
            local amount = math.Clamp((deltaKmh - 12) / 65, 0.015, 0.55)
            local localImpact = ZoneLocalImpactPoint(train, zone)
            local worldImpact = train:LocalToWorld(localImpact)

            MEXD.ApplyDamage(
                train,
                zone,
                amount,
                worldImpact,
                ZoneOutwardNormal(train, zone),
                "velocity"
            )
        end
    end)

    hook.Add("OnEntityCreated", "MEX.Damage.InitializeTrain", function(ent)
        timer.Simple(0, function()
            if not IsSubwayTrain(ent) then return end
            InitializeTrainDamage(ent)
        end)
    end)

    hook.Add("InitPostEntity", "MEX.Damage.InitializeExistingTrains", function()
        timer.Simple(0.25, function()
            for _, train in ipairs(ents.GetAll()) do
                if IsSubwayTrain(train) then
                    InitializeTrainDamage(train)
                end
            end
        end)
    end)

    local function GetAimedTrain(ply)
        if not IsValid(ply) then return nil end
        local tr = ply:GetEyeTrace()
        if not tr or not IsSubwayTrain(tr.Entity) then return nil end
        return tr.Entity
    end

    concommand.Add("mex_damage_test", function(ply, _, args)
        if IsValid(ply) and not ply:IsAdmin() then return end

        local train = GetAimedTrain(ply)
        if not IsValid(train) then
            print("[Metrostroi Expanded/Damage] Aim at a Metrostroi train.")
            return
        end

        InitializeTrainDamage(train)
        if CurTime() < (train.MEXDamageIgnoreUntil or 0) then
            print("[Metrostroi Expanded/Damage] Damage system is still in the 1000 ms spawn grace period.")
            return
        end

        local zone = string.lower(args[1] or "front")
        if not ZONES[zone] then
            print("[Metrostroi Expanded/Damage] Zone must be: front, rear, left, right, roof or floor.")
            return
        end

        local amount = math.Clamp(tonumber(args[2]) or 0.25, 0.01, 1)
        local worldPos = train:LocalToWorld(ZoneLocalImpactPoint(train, zone))

        MEXD.ApplyDamage(
            train,
            zone,
            amount,
            worldPos,
            ZoneOutwardNormal(train, zone),
            "console"
        )
    end)

    concommand.Add("mex_damage_reset", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end

        local train = GetAimedTrain(ply)
        if not IsValid(train) then
            print("[Metrostroi Expanded/Damage] Aim at a Metrostroi train.")
            return
        end

        MEXD.Reset(train)
        print("[Metrostroi Expanded/Damage] Damage reset for " .. train:GetClass())
    end)

    concommand.Add("mex_damage_status", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end

        local train = GetAimedTrain(ply)
        if not IsValid(train) then
            print("[Metrostroi Expanded/Damage] Aim at a Metrostroi train.")
            return
        end

        print(string.format(
            "[Metrostroi Expanded/Damage] %s | front %.2f rear %.2f left %.2f right %.2f roof %.2f floor %.2f | structural health %.2f | electrical %.2f | last impact %.1f km/h | detached %d | blocked controls %d",
            train:GetClass(),
            MEXD.GetZoneDamage(train, "front"),
            MEXD.GetZoneDamage(train, "rear"),
            MEXD.GetZoneDamage(train, "left"),
            MEXD.GetZoneDamage(train, "right"),
            MEXD.GetZoneDamage(train, "roof"),
            MEXD.GetZoneDamage(train, "floor"),
            train:GetNW2Float("MEX.StructuralHealth", 1),
            train:GetNW2Float("MEX.Damage.electrical", 0),
            train:GetNW2Float("MEX.Damage.LastImpactKmh", 0),
            istable(train.MEXDamageDetachedServer)
                and table.Count(train.MEXDamageDetachedServer)
                or 0,
            istable(train.MEXDamageBlockedButtons)
                and table.Count(train.MEXDamageBlockedButtons)
                or 0
        ))
    end)

    hook.Add("EntityRemoved", "MEX.Damage.CleanupServerDebris", function(ent)
        if not IsSubwayTrain(ent) then return end

        if istable(ent.MEXDamageDetachedServer) then
            for _, data in pairs(ent.MEXDamageDetachedServer) do
                if IsValid(data.debris) then
                    data.debris:Remove()
                end

                if istable(data.debrisList) then
                    for _, debris in ipairs(data.debrisList) do
                        if IsValid(debris) then
                            debris:Remove()
                        end
                    end
                end
            end
        end
    end)
end

if CLIENT then
    ---------------------------------------------------------------------------
    -- v0.4 deformation model
    --
    -- No global RenderMultiply scaling is used here. A rail vehicle does not
    -- realistically turn into a uniformly scaled box during a collision.
    --
    -- Instead, every visible part uses one local deformation field:
    --   * existing MDL bones are displaced/rotated with BuildBonePositions,
    --   * localized rigid ClientEnts follow the deformed structure,
    --   * full-car interior shells stay at the train origin and deform only
    --     through their own bones,
    --   * ButtonMap panels are shallow-cloned per wagon and moved as rigid
    --     planes together with their generated button props.
    --
    -- This keeps the cab/salon attached to the carbody while retaining
    -- Metrostroi's original animation and interaction code.
    ---------------------------------------------------------------------------

    local STRUCTURAL_WORDS = {
        "body", "interior", "salon", "cabin", "cabine", "mask",
        "pult", "panel", "door", "window", "glass", "stekl",
        "seat", "couch", "handler", "handrail", "lamp", "headlight",
        "frame", "roof",
    }

    local CABIN_WORDS = {
        "cabin", "cabine", "cab_", "cab-", "pult", "panel",
        "controller", "brake_valve", "crane", "driver",
    }

    local GLASS_WORDS = {
        "glass", "window", "stekl",
    }

    -- Use Source's real nodraw material for broken embedded glazing.
    -- A custom white/alpha material can still show as an opaque white lens on
    -- some Metrostroi shaders, especially gauge/control glass.
    local MEX_INVISIBLE_GLASS_NAME = "tools/toolsnodraw"

    local function CopyVector(v)
        return Vector(v.x, v.y, v.z)
    end

    local function CopyAngle(a)
        return Angle(a.p, a.y, a.r)
    end

    local function Smooth01(x)
        x = math.Clamp(x, 0, 1)
        return x * x * (3 - 2 * x)
    end

    local function IsFiniteVector(v)
        return isvector(v)
            and v.x == v.x and v.y == v.y and v.z == v.z
            and math.abs(v.x) < 1000000
            and math.abs(v.y) < 1000000
            and math.abs(v.z) < 1000000
    end

    local function DefaultHitLocal(train, zone)
        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()
        local center = (mins + maxs) * 0.5

        if zone == "front" then
            return Vector(maxs.x, center.y, center.z)
        elseif zone == "rear" then
            return Vector(mins.x, center.y, center.z)
        elseif zone == "left" then
            return Vector(center.x, mins.y, center.z)
        elseif zone == "right" then
            return Vector(center.x, maxs.y, center.z)
        elseif zone == "roof" then
            return Vector(center.x, center.y, maxs.z)
        elseif zone == "floor" then
            return Vector(center.x, center.y, mins.z)
        end

        return center
    end

    local function ReadHitLocal(train, zone)
        if train:GetNW2Float("MEX.Damage.HitStrength." .. zone, 0) <= 0.001 then
            return DefaultHitLocal(train, zone)
        end

        return train:GetNW2Vector(
            "MEX.Damage.HitLocal." .. zone,
            DefaultHitLocal(train, zone)
        )
    end

    local function BuildDamageState(train)
        if not train:GetNW2Bool("MEX.DamageReady", false) then return nil end

        local front = train:GetNW2Float("MEX.Damage.front", 0)
        local rear = train:GetNW2Float("MEX.Damage.rear", 0)
        local left = train:GetNW2Float("MEX.Damage.left", 0)
        local right = train:GetNW2Float("MEX.Damage.right", 0)
        local roof = train:GetNW2Float("MEX.Damage.roof", 0)
        local floor = train:GetNW2Float("MEX.Damage.floor", 0)
        local blastStrength =
            train:GetNW2Float("MEX.Damage.BlastStrength", 0)
        local overall = math.max(
            front,
            rear,
            left,
            right,
            roof,
            floor,
            math.min(blastStrength, 1)
        )

        if overall <= 0.001 then return nil end

        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()
        local center = (mins + maxs) * 0.5

        return {
            front = front,
            rear = rear,
            left = left,
            right = right,
            roof = roof,
            floor = floor,
            overall = overall,
            blast = {
                strength = blastStrength,
                radius = train:GetNW2Float(
                    "MEX.Damage.BlastRadius",
                    0
                ),
                localPos = train:GetNW2Vector(
                    "MEX.Damage.BlastLocal",
                    center
                ),
                impulse = train:GetNW2Vector(
                    "MEX.Damage.BlastImpulseLocal",
                    vector_origin
                ),
            },
            mins = mins,
            maxs = maxs,
            center = center,
            halfLength = math.max((maxs.x - mins.x) * 0.5, 1),
            halfWidth = math.max((maxs.y - mins.y) * 0.5, 1),
            halfHeight = math.max((maxs.z - mins.z) * 0.5, 1),
            hits = {
                front = ReadHitLocal(train, "front"),
                rear = ReadHitLocal(train, "rear"),
                left = ReadHitLocal(train, "left"),
                right = ReadHitLocal(train, "right"),
                roof = ReadHitLocal(train, "roof"),
                floor = ReadHitLocal(train, "floor"),
            },
        }
    end

    ---------------------------------------------------------------------------
    -- Continuous local-space deformation field
    ---------------------------------------------------------------------------

    local function AddEndCrush(offset, localPos, state, zone, damage, inwardSign)
        if damage <= 0.001 then return end

        local hit = state.hits[zone]
        local surfaceX = zone == "front" and state.maxs.x or state.mins.x
        local depth = zone == "front"
            and (surfaceX - localPos.x)
            or (localPos.x - surfaceX)

        -- A light crash mainly damages the end structure. Only heavy damage
        -- reaches deep into the cab/saloon survival space.
        local survivalIntrusion = math.max(damage - 0.48, 0) / 0.52
        local reach = 92 + damage * 104 + survivalIntrusion * 128

        if depth < -8 or depth > reach then return end

        local axial = Smooth01(1 - math.Clamp(depth / reach, 0, 1))

        local radiusY = 34 + damage * 38 + survivalIntrusion * 24
        local radiusZ = 38 + damage * 38 + survivalIntrusion * 22
        local dy = (localPos.y - hit.y) / radiusY
        local dz = (localPos.z - hit.z) / radiusZ
        local radial = Smooth01(1 - math.Clamp(dy * dy + dz * dz, 0, 1))

        -- The strong underframe/longitudinal structure does not fold as easily
        -- as thin cab/interior sheetwork.
        local z01 = math.Clamp(
            (localPos.z - state.mins.z) / math.max(state.maxs.z - state.mins.z, 1),
            0,
            1
        )
        local frameFactor = Lerp(Smooth01(math.Clamp(z01 * 2.2, 0, 1)), 0.48, 1.0)

        local influence = axial * radial
        if influence <= 0.0001 then return end

        local primaryCrush = 7 + damage * 39
        local deepIntrusion = survivalIntrusion * 56
        local crush = (primaryCrush + deepIntrusion) * influence * frameFactor

        offset.x = offset.x + inwardSign * crush

        -- Draw nearby structure towards the contact point. This gives the end
        -- a crease/bowl instead of translating a flat rectangle.
        offset.y = offset.y + (hit.y - localPos.y)
            * (0.055 + damage * 0.08) * influence
        offset.z = offset.z + (hit.z - localPos.z)
            * (0.040 + damage * 0.055) * influence

        -- Real carbody collapse develops folds/crippling near the boundary
        -- between the crushed end and the still-stiff survival structure.
        -- Reproduce that with an inward shell buckle instead of stretching the
        -- whole wagon. This only becomes pronounced after a substantial hit.
        if damage >= 0.34 then
            local creaseCenter = reach * (0.34 + damage * 0.18)
            local creaseWidth = math.max(reach * 0.16, 12)
            local crease =
                math.exp(
                    -((depth - creaseCenter) / creaseWidth)
                    * ((depth - creaseCenter) / creaseWidth)
                )
                * radial
                * math.Clamp((damage - 0.30) / 0.70, 0, 1)

            local yNorm = math.Clamp(
                (localPos.y - state.center.y) / state.halfWidth,
                -1,
                1
            )
            local zNorm = math.Clamp(
                (localPos.z - state.center.z) / state.halfHeight,
                -1,
                1
            )

            -- Side posts and roof/floor edges bow into the occupied volume as
            -- the end frame loses column stability.
            offset.y = offset.y
                - yNorm * crease * (4 + damage * 10)
            offset.z = offset.z
                - zNorm * crease * (3 + damage * 8)

            -- A small alternating longitudinal ripple approximates sheet-metal
            -- folding where multiple deformation bones are available.
            local ripple = math.sin(
                math.Clamp(depth / math.max(reach, 1), 0, 1)
                * math.pi * 3
            )

            offset.x = offset.x
                + inwardSign
                    * ripple
                    * crease
                    * damage
                    * 4.5
        end

        -- Severe off-centre impacts also bend the occupied structure slightly.
        if survivalIntrusion > 0 then
            local offY = math.Clamp(
                (hit.y - state.center.y) / state.halfWidth,
                -1,
                1
            )
            local offZ = math.Clamp(
                (hit.z - state.center.z) / state.halfHeight,
                -1,
                1
            )
            local deep = Smooth01(1 - math.Clamp(depth / math.max(reach, 1), 0, 1))

            offset.y = offset.y + inwardSign * offY
                * survivalIntrusion * deep * 8
            offset.z = offset.z + inwardSign * offZ
                * survivalIntrusion * deep * 5
        end
    end

    local function AddSideIntrusion(offset, localPos, state, zone, damage, inwardSign)
        if damage <= 0.001 then return end

        local hit = state.hits[zone]
        local surfaceY = zone == "right" and state.maxs.y or state.mins.y
        local depth = zone == "right"
            and (surfaceY - localPos.y)
            or (localPos.y - surfaceY)

        local severe = math.max(damage - 0.52, 0) / 0.48
        local reach = 52 + damage * 62 + severe * 76
        if depth < -7 or depth > reach then return end

        local inward = Smooth01(1 - math.Clamp(depth / reach, 0, 1))
        local radiusX = 55 + damage * 75 + severe * 55
        local radiusZ = 36 + damage * 40 + severe * 34

        local dx = (localPos.x - hit.x) / radiusX
        local dz = (localPos.z - hit.z) / radiusZ
        local radial = Smooth01(1 - math.Clamp(dx * dx + dz * dz, 0, 1))
        local influence = inward * radial
        if influence <= 0.0001 then return end

        local intrusion = (5 + damage * 30 + severe * 35) * influence
        offset.y = offset.y + inwardSign * intrusion

        offset.x = offset.x + (hit.x - localPos.x)
            * (0.035 + damage * 0.055) * influence
        offset.z = offset.z + (hit.z - localPos.z)
            * (0.030 + damage * 0.040) * influence

        if damage >= 0.38 then
            local crease =
                math.exp(
                    -((depth - reach * 0.42) / math.max(reach * 0.19, 10))
                    ^ 2
                )
                * radial
                * math.Clamp((damage - 0.34) / 0.66, 0, 1)

            local xNorm = math.Clamp(
                (localPos.x - hit.x) / math.max(radiusX, 1),
                -1,
                1
            )
            local zNorm = math.Clamp(
                (localPos.z - state.center.z) / state.halfHeight,
                -1,
                1
            )

            offset.x = offset.x - xNorm * crease * (4 + damage * 8)
            offset.z = offset.z - zNorm * crease * (3 + damage * 7)
        end
    end

    local function AddVerticalIntrusion(offset, localPos, state, zone, damage, inwardSign)
        if damage <= 0.001 then return end

        local hit = state.hits[zone]
        local surfaceZ = zone == "roof" and state.maxs.z or state.mins.z
        local depth = zone == "roof"
            and (surfaceZ - localPos.z)
            or (localPos.z - surfaceZ)

        local severe = math.max(damage - 0.55, 0) / 0.45
        local reach = 40 + damage * 52 + severe * 62
        if depth < -7 or depth > reach then return end

        local inward = Smooth01(1 - math.Clamp(depth / reach, 0, 1))
        local radiusX = 62 + damage * 80
        local radiusY = 34 + damage * 42

        local dx = (localPos.x - hit.x) / radiusX
        local dy = (localPos.y - hit.y) / radiusY
        local radial = Smooth01(1 - math.Clamp(dx * dx + dy * dy, 0, 1))
        local influence = inward * radial
        if influence <= 0.0001 then return end

        local intrusion = (4 + damage * 23 + severe * 27) * influence
        offset.z = offset.z + inwardSign * intrusion
        offset.x = offset.x + (hit.x - localPos.x)
            * (0.025 + damage * 0.04) * influence
        offset.y = offset.y + (hit.y - localPos.y)
            * (0.025 + damage * 0.04) * influence
    end

    local function AddBlastDeformation(offset, localPos, state)
        local blast = state and state.blast
        if not istable(blast) or (blast.strength or 0) <= 0.001 then return end
        if not isvector(blast.localPos) then return end

        local radius = math.max(blast.radius or 0, 1)
        local delta = localPos - blast.localPos
        local distance = delta:Length()

        if distance > radius then return end

        local falloff = Smooth01(
            1 - math.Clamp(distance / radius, 0, 1)
        )
        if falloff <= 0.0001 then return end

        local dir = blast.impulse
        if not isvector(dir) or dir:LengthSqr() < 0.001 then
            dir = delta
        end

        if dir:LengthSqr() < 0.001 then return end
        dir = dir:GetNormalized()

        -- Blast loading is very local: nearby sheet/panel structure is kicked
        -- in the pressure-wave direction, then rapidly decays with distance.
        local strength = math.Clamp(blast.strength or 0, 0, 1.25)
        local push = (3 + strength * 18) * falloff

        offset:Add(dir * push)

        -- Thin sheet-metal wrinkling around the blast footprint. The ripple is
        -- deliberately small compared with the primary impulse and only shows
        -- where the MDL has enough weighted bones/independent ClientEnts.
        local radialDir = delta
        if radialDir:LengthSqr() > 0.001 then
            radialDir:Normalize()
            local wrinkle = math.sin(distance * 0.11)
                * falloff
                * strength
                * 2.8
            offset:Add(radialDir * wrinkle)
        end
    end

    local function DeformLocalPoint(localPos, state)
        if not state then return CopyVector(localPos) end

        local offset = Vector(0, 0, 0)

        -- Positive X is the front on current Metrostroi subway bodies.
        AddEndCrush(offset, localPos, state, "front", state.front, -1)
        AddEndCrush(offset, localPos, state, "rear", state.rear, 1)

        -- Positive Y = right side, negative Y = left side.
        AddSideIntrusion(offset, localPos, state, "right", state.right, -1)
        AddSideIntrusion(offset, localPos, state, "left", state.left, 1)

        -- Roof impact goes down; floor/underframe impact goes up.
        AddVerticalIntrusion(offset, localPos, state, "roof", state.roof, -1)
        AddVerticalIntrusion(offset, localPos, state, "floor", state.floor, 1)

        AddBlastDeformation(offset, localPos, state)

        return localPos + offset
    end

    local function DeformLocalAngle(localPos, localAng, state)
        if not state then return CopyAngle(localAng) end

        local step = 5
        local p0 = DeformLocalPoint(localPos, state)
        local pf = DeformLocalPoint(localPos + localAng:Forward() * step, state)
        local pu = DeformLocalPoint(localPos + localAng:Up() * step, state)

        local forward = pf - p0
        local up = pu - p0

        if forward:LengthSqr() < 0.001 or up:LengthSqr() < 0.001 then
            return CopyAngle(localAng)
        end

        forward:Normalize()
        up:Normalize()

        local side = forward:Cross(up)
        if side:LengthSqr() < 0.001 then
            return CopyAngle(localAng)
        end

        side:Normalize()
        up = side:Cross(forward)
        up:Normalize()

        return forward:AngleEx(up)
    end

    local function DeformLocalPointStrength(localPos, state, strength)
        strength = tonumber(strength) or 1

        if not state or math.abs(strength - 1) < 0.001 then
            return DeformLocalPoint(localPos, state)
        end

        local base = DeformLocalPoint(localPos, state)
        return localPos + (base - localPos) * strength
    end

    local function DeformLocalAngleStrength(
        localPos,
        localAng,
        state,
        strength
    )
        strength = tonumber(strength) or 1

        if not state or math.abs(strength - 1) < 0.001 then
            return DeformLocalAngle(localPos, localAng, state)
        end

        local step = 5
        local p0 = DeformLocalPointStrength(
            localPos,
            state,
            strength
        )
        local pf = DeformLocalPointStrength(
            localPos + localAng:Forward() * step,
            state,
            strength
        )
        local pu = DeformLocalPointStrength(
            localPos + localAng:Up() * step,
            state,
            strength
        )

        local forward = pf - p0
        local up = pu - p0

        if forward:LengthSqr() < 0.001 or up:LengthSqr() < 0.001 then
            return CopyAngle(localAng)
        end

        forward:Normalize()
        up:Normalize()

        local side = forward:Cross(up)
        if side:LengthSqr() < 0.001 then
            return CopyAngle(localAng)
        end

        side:Normalize()
        up = side:Cross(forward)
        up:Normalize()

        return forward:AngleEx(up)
    end

    local function CabStrengthAtPoint(localPos, state)
        if not state then return 1 end

        local endness = math.Clamp(
            math.abs(localPos.x - state.center.x)
                / math.max(state.halfLength, 1),
            0,
            1
        )

        if endness < 0.45 then return 1 end

        local endDamage =
            localPos.x >= state.center.x and state.front or state.rear

        return 1 + Smooth01((endness - 0.45) / 0.55)
            * math.Clamp(endDamage, 0, 1)
            * 0.35
    end

    local function LocalDisplacement(localPos, state)
        return DeformLocalPoint(localPos, state) - localPos
    end

    ---------------------------------------------------------------------------
    -- Legacy cleanup
    ---------------------------------------------------------------------------

    local function RecoverLegacyButtonMap(train)
        if not IsValid(train) then return end

        if train.MEXDamageButtonMapOriginal then
            train.ButtonMap = train.MEXDamageButtonMapOriginal
            train.MEXDamageButtonMapOriginal = nil
        elseif train.MEXDamagePrivateButtonMap then
            local stored = scripted_ents.GetStored(train:GetClass())
            local original = stored and stored.t and stored.t.ButtonMap
            if istable(original) then
                train.ButtonMap = original
            end
        end

        train.MEXDamagePrivateButtonMap = nil
    end

    local function ClearLegacyTransforms(train)
        if not IsValid(train) then return end
        if train.MEXDamageV4LegacyCleared then return end
        train.MEXDamageV4LegacyCleared = true

        -- v0.1-v0.3 used RenderMultiply on the whole car. Never allow that
        -- transform to survive into the bone-based system.
        train:DisableMatrix("RenderMultiply")
        train.MEXDamageMatrixApplied = nil

        RecoverLegacyButtonMap(train)

        if istable(train.ClientEnts) then
            for _, prop in pairs(train.ClientEnts) do
                if not IsValid(prop) then continue end

                prop:DisableMatrix("RenderMultiply")
                prop:SetRenderOrigin(nil)
                prop:SetRenderAngles(nil)
                prop.MEXDamageMatrixApplied = nil
                prop.MEXDamageRenderOrigin = nil
                prop.MEXDamageRenderAngles = nil
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Per-wagon ButtonMap clone
    --
    -- This is intentionally SHALLOW. Nested buttons/config tables stay the
    -- original Metrostroi objects. The old deep copy in v0.3 could disconnect
    -- generated controls from Metrostroi's runtime state.
    ---------------------------------------------------------------------------

    local function CloneInteractivePanels(train)
        if not istable(train.ButtonMap) then return false end
        if train.MEXDamageV4ButtonMapOriginal then return true end

        RecoverLegacyButtonMap(train)

        local original = train.ButtonMap
        local clone = {}

        for key, panel in pairs(original) do
            if key ~= "BaseClass" and istable(panel) and isvector(panel.pos) then
                local p = {}
                for k, v in pairs(panel) do
                    p[k] = v
                end

                p.MEXDamageBasePos = CopyVector(panel.pos)
                p.MEXDamageBaseAng = isangle(panel.ang)
                    and CopyAngle(panel.ang)
                    or Angle(0, 0, 0)
                p.MEXDamageBaseScale = panel.scale
                clone[key] = p
            else
                clone[key] = panel
            end
        end

        train.MEXDamageV4ButtonMapOriginal = original
        train.ButtonMap = clone
        train.MEXDamageV4PanelProps = nil
        return true
    end

    local function RestoreInteractivePanels(train)
        if not IsValid(train) then return end

        if train.MEXDamageV4ButtonMapOriginal then
            train.ButtonMap = train.MEXDamageV4ButtonMapOriginal
            train.MEXDamageV4ButtonMapOriginal = nil
        end

        train.MEXDamageV4PanelProps = nil
    end

    local function BuildPanelPropMap(train)
        local map = {}

        if not istable(train.ButtonMap) then
            train.MEXDamageV4PanelProps = map
            return map
        end

        for panelName, panel in pairs(train.ButtonMap) do
            if panelName == "BaseClass" or not istable(panel) then continue end

            if istable(panel.props) then
                for _, propName in pairs(panel.props) do
                    if isstring(propName) then
                        map[propName] = panelName
                    end
                end
            end

            if istable(panel.buttons) then
                for _, button in pairs(panel.buttons) do
                    if not istable(button) then continue end

                    if isstring(button.PropName) then
                        map[button.PropName] = panelName
                    end

                    local config = button.model
                    if istable(config) then
                        local generatedName = config.name or button.ID
                        if isstring(generatedName) then
                            map[generatedName] = panelName
                        end

                        if istable(config.lamp) then
                            local lampName = config.lamp.name
                            if isstring(lampName) then
                                map[lampName] = panelName
                            end
                        end
                    end
                end
            end
        end

        train.MEXDamageV4PanelProps = map
        return map
    end

    local function ApplyPanelDeformation(train, state)
        if not state then
            RestoreInteractivePanels(train)
            return
        end

        if not CloneInteractivePanels(train) then return end

        for _, panel in pairs(train.ButtonMap) do
            if not istable(panel) or not panel.MEXDamageBasePos then continue end

            local strength = CabStrengthAtPoint(
                panel.MEXDamageBasePos,
                state
            )

            panel.pos = DeformLocalPointStrength(
                panel.MEXDamageBasePos,
                state,
                strength
            )
            panel.ang = DeformLocalAngleStrength(
                panel.MEXDamageBasePos,
                panel.MEXDamageBaseAng,
                state,
                strength
            )

            -- Keep the 2D coordinate system unchanged. It means the visual
            -- control and hit target remain exactly the same size.
            panel.scale = panel.MEXDamageBaseScale
        end
    end

    ---------------------------------------------------------------------------
    -- ClientEnt geometry cache / attachment logic
    ---------------------------------------------------------------------------

    local function ModelLooksStructural(name, model)
        local text = string.lower((name or "") .. " " .. (model or ""))

        for _, word in ipairs(STRUCTURAL_WORDS) do
            if string.find(text, word, 1, true) then
                return true
            end
        end

        return false
    end

    local function ModelMatchesWords(name, model, words)
        local text = string.lower((name or "") .. " " .. (model or ""))

        for _, word in ipairs(words) do
            if string.find(text, word, 1, true) then
                return true
            end
        end

        return false
    end

    local function ModelLooksCabin(name, model)
        return ModelMatchesWords(name, model, CABIN_WORDS)
    end

    local function ModelLooksGlass(name, model)
        local lowerModel = string.lower(model or "")

        for _, word in ipairs(GLASS_WORDS) do
            if string.find(lowerModel, word, 1, true) then
                return true
            end
        end

        local lowerName = string.lower(name or "")
        local excluded = {
            "washer", "cleaner", "wiper", "button", "switch",
            "toggle", "control",
        }

        for _, word in ipairs(excluded) do
            if string.find(lowerName, word, 1, true) then
                return false
            end
        end

        for _, word in ipairs(GLASS_WORDS) do
            if string.find(lowerName, word, 1, true) then
                return true
            end
        end

        return false
    end

    local function GetStaticClientPropTransform(train, name, prop)
        local def = istable(train.ClientProps) and train.ClientProps[name] or nil

        if istable(def) and isvector(def.pos) then
            local ang = isangle(def.ang) and def.ang or Angle(0, 0, 0)
            return CopyVector(def.pos), CopyAngle(ang)
        end

        if prop:GetParent() == train then
            return CopyVector(prop:GetLocalPos()), CopyAngle(prop:GetLocalAngles())
        end

        local localPos, localAng = WorldToLocal(
            prop:GetPos(),
            prop:GetAngles(),
            train:GetPos(),
            train:GetAngles()
        )

        return localPos, localAng
    end

    local function CacheClientProp(train, name, prop)
        train.MEXDamageV4PropCache = train.MEXDamageV4PropCache or {}

        local cached = train.MEXDamageV4PropCache[name]
        if cached and cached.entity == prop then
            return cached
        end

        prop:SetRenderOrigin(nil)
        prop:SetRenderAngles(nil)
        prop:DisableMatrix("RenderMultiply")

        local basePos, baseAng = GetStaticClientPropTransform(train, name, prop)
        local mins = prop:OBBMins()
        local maxs = prop:OBBMaxs()
        local obbCenter = (mins + maxs) * 0.5
        local size = maxs - mins

        -- Convert the model's actual visual center into train-local space.
        local anchorPos = LocalToWorld(
            obbCenter,
            Angle(0, 0, 0),
            basePos,
            baseAng
        )

        local model = prop:GetModel() or ""
        local spanX = math.abs(size.x)
        local spanY = math.abs(size.y)
        local spanZ = math.abs(size.z)

        cached = {
            entity = prop,
            basePos = basePos,
            baseAng = baseAng,
            obbCenter = obbCenter,
            anchorPos = anchorPos,
            size = size,
            model = model,
            structural = ModelLooksStructural(name, model),
            cabin = ModelLooksCabin(name, model),
            glass = ModelLooksGlass(name, model),

            -- A full saloon/interior shell must not be translated as one rigid
            -- object. Its ends should move only through its bones.
            fullLength = spanX >= 330,

            -- Small/localized pieces may follow one structural attachment point.
            localPiece = spanX < 330 and spanY < 230 and spanZ < 230,
        }

        train.MEXDamageV4PropCache[name] = cached
        return cached
    end

    local function OriginForAnchoredModel(anchorInModel, desiredAnchor, desiredAng)
        local rotated =
            desiredAng:Forward() * anchorInModel.x
            + desiredAng:Right() * anchorInModel.y
            + desiredAng:Up() * anchorInModel.z

        return desiredAnchor - rotated
    end

    local function ApplyLocalStructuralCrushMatrix(
        name,
        prop,
        cached,
        state
    )
        if not IsValid(prop)
            or not cached
            or not cached.structural
            or not cached.localPiece
            or not state
        then
            return
        end

        local text = string.lower(
            (name or "") .. " " .. (cached.model or "")
        )

        local excludedStructuralWords = {
            "door", "dver",
            "button", "switch", "tumbler", "toggle", "knob",
            "reverser", "controller", "handle", "lever",
            "valve", "kran", "wheel", "parking",
            "manualbrake", "brake",
            "panel", "pult", "lamp", "light",
        }

        for _, word in ipairs(excludedStructuralWords) do
            if string.find(text, word, 1, true) then
                return
            end
        end

        local structuralShell =
            cached.cabin
            or string.find(text, "mask", 1, true)
            or string.find(text, "body", 1, true)
            or string.find(text, "shell", 1, true)
            or string.find(text, "interior", 1, true)

        if not structuralShell then return end

        local size = cached.size
        local largest = math.max(
            math.abs(size.x),
            math.abs(size.y),
            math.abs(size.z)
        )

        if largest < 42 then return end

        local displacement =
            DeformLocalPoint(cached.anchorPos, state)
            - cached.anchorPos

        if displacement:LengthSqr() < 0.16 then
            prop:DisableMatrix("RenderMultiply")
            prop.MEXDamageMatrixApplied = nil
            return
        end

        local sx = 1 - math.Clamp(
            math.abs(displacement.x)
                / math.max(math.abs(size.x), 28)
                * 0.42,
            0,
            0.24
        )
        local sy = 1 - math.Clamp(
            math.abs(displacement.y)
                / math.max(math.abs(size.y), 28)
                * 0.34,
            0,
            0.18
        )
        local sz = 1 - math.Clamp(
            math.abs(displacement.z)
                / math.max(math.abs(size.z), 28)
                * 0.30,
            0,
            0.15
        )

        local matrix = Matrix()
        matrix:Translate(cached.obbCenter)
        matrix:Scale(Vector(sx, sy, sz))
        matrix:Translate(-cached.obbCenter)

        prop:EnableMatrix("RenderMultiply", matrix)
        prop.MEXDamageMatrixApplied = true
    end

    local function ApplyRigidAttachment(train, prop, cached, state)
        local strength = cached.cabin
            and math.max(1.18, CabStrengthAtPoint(cached.anchorPos, state))
            or 1

        local desiredAnchor = DeformLocalPointStrength(
            cached.anchorPos,
            state,
            strength
        )
        local desiredAng = DeformLocalAngleStrength(
            cached.anchorPos,
            cached.baseAng,
            state,
            strength
        )

        local desiredOrigin = OriginForAnchoredModel(
            cached.obbCenter,
            desiredAnchor,
            desiredAng
        )

        prop:SetRenderOrigin(train:LocalToWorld(desiredOrigin))
        prop:SetRenderAngles(train:LocalToWorldAngles(desiredAng))
        prop.MEXDamageV4RenderMoved = true
    end

    local function ApplyPanelAttachment(train, name, prop, cached, panelName)
        local panel = train.ButtonMap and train.ButtonMap[panelName]
        if not istable(panel) or not panel.MEXDamageBasePos then return false end

        -- Client props generated by Metrostroi are defined in train-local space.
        -- Express the prop relative to the original panel and replay the exact
        -- same rigid relationship on the deformed panel.
        local relPos, relAng = WorldToLocal(
            cached.basePos,
            cached.baseAng,
            panel.MEXDamageBasePos,
            panel.MEXDamageBaseAng
        )

        local newPos, newAng = LocalToWorld(
            relPos,
            relAng,
            panel.pos,
            panel.ang
        )

        prop:SetRenderOrigin(train:LocalToWorld(newPos))
        prop:SetRenderAngles(train:LocalToWorldAngles(newAng))
        prop.MEXDamageV4RenderMoved = true
        return true
    end

    local function ClearClientPropRenderTransform(prop)
        if not IsValid(prop) then return end

        if prop.MEXDamageV4RenderMoved
            or prop.MEXDamageRenderOrigin
            or prop.MEXDamageRenderAngles
        then
            prop:SetRenderOrigin(nil)
            prop:SetRenderAngles(nil)
            prop.MEXDamageV4RenderMoved = nil
            prop.MEXDamageRenderOrigin = nil
            prop.MEXDamageRenderAngles = nil
        end

        if prop.MEXDamageMatrixApplied then
            prop:DisableMatrix("RenderMultiply")
            prop.MEXDamageMatrixApplied = nil
        end
    end


    ---------------------------------------------------------------------------
    -- Breakaway components
    --
    -- Doors, controls and other mounted Metrostroi ClientEnt models may lose
    -- their mounting points under heavy local deformation. The original
    -- ClientEnt is hidden only after the server accepts the failure request;
    -- the server then creates a real networked physics debris entity.
    ---------------------------------------------------------------------------

    local DOOR_WORDS = {
        "door", "dver", "doors",
    }

    local CONTROL_WORDS = {
        "button", "switch", "tumbler", "toggle", "knob", "reverser",
        "controller", "handle", "lever", "valve", "kran", "wheel",
        "parking", "manualbrake", "brake",
    }

    local BREAKAWAY_WORDS = {
        "lamp", "light", "headlight", "mirror", "sign", "cover", "cap",
        "window", "glass", "box", "case", "guard", "panel", "seat",
        "couch", "handrail",
        "handler", "wiper", "meter", "gauge", "indicator", "display",
        "wheel", "brake", "parking", "button", "switch", "tumbler",
        "toggle", "knob", "reverser", "controller", "handle", "lever",
        "valve", "kran", "door", "dver",
    }

    local function ContainsAnyWord(text, words)
        text = string.lower(text or "")
        for _, word in ipairs(words) do
            if string.find(text, word, 1, true) then
                return true
            end
        end
        return false
    end

    local function StableFraction(text)
        local crc = tonumber(util.CRC(text or "")) or 0
        return (crc % 1000) / 1000
    end

    local function IsGlassComponent(name, cached)
        if cached.glass then return true end

        local text = string.lower(
            (name or "") .. " " .. (cached.model or "")
        )

        return ContainsAnyWord(text, GLASS_WORDS)
    end

    local function IsDoorComponent(name, cached)
        local text = (name or "") .. " " .. (cached.model or "")
        if not ContainsAnyWord(text, DOOR_WORDS) then return false end

        local model = string.lower(cached.model or "")
        if model == "" or model == "models/error.mdl" then return false end

        local s = cached.size
        local largest = math.max(math.abs(s.x), math.abs(s.y), math.abs(s.z))

        -- Ignore tiny handles/labels whose name merely contains "door".
        return largest >= 22
    end

    local function IsSmallControlComponent(name, cached, panelName)
        local s = cached.size
        local largest = math.max(math.abs(s.x), math.abs(s.y), math.abs(s.z))

        local text =
            (name or "")
            .. " "
            .. (cached.model or "")
            .. " "
            .. (panelName or "")

        local namedControl = ContainsAnyWord(text, CONTROL_WORDS)

        -- Standalone driver's valves, disconnect cocks and controllers are
        -- often not generated from ButtonMap at all. Treat explicitly named
        -- control hardware as a control even without panelName.
        if namedControl then
            return largest <= 145
        end

        -- Tiny generated ButtonMap props are controls even when their file
        -- name does not literally contain "button".
        return panelName ~= nil and largest <= 28
    end

    local function IsGeneralBreakawayComponent(
        name,
        cached,
        panelName
    )
        if cached.fullLength then return false end

        local s = cached.size
        local largest = math.max(math.abs(s.x), math.abs(s.y), math.abs(s.z))

        local text =
            (name or "")
            .. " "
            .. (cached.model or "")
            .. " "
            .. (panelName or "")

        local explicit = ContainsAnyWord(text, BREAKAWAY_WORDS)

        if explicit then
            return largest <= 220
        end

        return cached.localPiece and largest <= 85
    end

    local function ButtonCenterLocal(panel, button)
        if not istable(panel) or not istable(button) then return nil end
        if not isvector(panel.pos) or not isangle(panel.ang) then return nil end

        local x = tonumber(button.x) or 0
        local y = tonumber(button.y) or 0

        if not button.radius then
            x = x + (tonumber(button.w) or 0) * 0.5
            y = y + (tonumber(button.h) or 0) * 0.5
        end

        local pos = Vector(x, -y, 0)
        local ang = panel.MEXDamageBaseAng or panel.ang
        local basePos = panel.MEXDamageBasePos or panel.pos
        local scale = tonumber(panel.MEXDamageBaseScale)
            or tonumber(panel.scale)
            or 1

        pos:Rotate(ang)
        return basePos + pos * scale
    end

    local function GetNearbyButtonIDs(train, cached)
        local result = {}
        local candidates = {}

        if not cached or not isvector(cached.anchorPos)
            or not istable(train.ButtonMap)
        then
            return result
        end

        local s = cached.size
        local largest = math.max(
            math.abs(s.x),
            math.abs(s.y),
            math.abs(s.z)
        )

        local text = string.lower(
            (cached.model or "")
        )

        local valveLike =
            string.find(text, "valve", 1, true)
            or string.find(text, "cran", 1, true)
            or string.find(text, "kran", 1, true)
            or string.find(text, "/334", 1, true)
            or string.find(text, "/013", 1, true)

        local searchRadius = valveLike
            and math.Clamp(largest * 0.70, 28, 72)
            or math.Clamp(largest * 0.45, 10, 38)

        for panelName, panel in pairs(train.ButtonMap) do
            if panelName == "BaseClass"
                or not istable(panel)
                or not istable(panel.buttons)
            then
                continue
            end

            for _, button in pairs(panel.buttons) do
                if not istable(button) or not isstring(button.ID) then
                    continue
                end

                local buttonPos = ButtonCenterLocal(panel, button)
                if not isvector(buttonPos) then continue end

                local distance = cached.anchorPos:Distance(buttonPos)
                if distance > searchRadius then continue end

                candidates[#candidates + 1] = {
                    id = button.ID:gsub("^.+:", ""),
                    panelName = panelName,
                    distance = distance,
                }
            end
        end

        table.sort(candidates, function(a, b)
            return a.distance < b.distance
        end)

        if #candidates == 0 then return result end

        local best = candidates[1].distance
        local keepDistance = math.min(
            searchRadius,
            best + (valveLike and 18 or 8)
        )
        local seen = {}

        for _, candidate in ipairs(candidates) do
            if candidate.distance > keepDistance then break end
            if not seen[candidate.id] then
                seen[candidate.id] = true
                result[#result + 1] = candidate.id
            end
        end

        return result
    end

    local function GetButtonIDsForProp(train, panelName, propName, cached)
        local out = {}
        local seen = {}

        local function add(id)
            if not isstring(id) or id == "" then return end
            id = id:gsub("^.+:", "")
            if seen[id] then return end
            seen[id] = true
            out[#out + 1] = id
        end

        local exactPhysicalBinding = false

        if panelName and istable(train.ButtonMap) then
            local panel = train.ButtonMap[panelName]
            if istable(panel) and istable(panel.buttons) then
                for _, button in pairs(panel.buttons) do
                    if not istable(button) then continue end

                    local model = button.model
                    local generatedName = nil

                    if istable(model) then
                        generatedName = model.name or button.ID
                    end

                    local matches =
                        button.PropName == propName
                        or generatedName == propName
                        or (
                            istable(model)
                            and istable(model.lamp)
                            and model.lamp.name == propName
                        )

                    if matches and isstring(button.ID) then
                        exactPhysicalBinding = true
                        add(button.ID)
                    end
                end
            end
        end

        -- Core invariant: an attached physical button stays usable. When a
        -- generated ButtonMap prop has an exact identity, never infer nearby
        -- controls from geometry or model-name heuristics. Only this physical
        -- button's own ID is sent to the server; related keyboard aliases are
        -- expanded there after the detach is confirmed.
        if exactPhysicalBinding then
            return out
        end

        local text = string.lower(
            (propName or "") .. " " .. (cached.model or "")
        )

        -- Spatial ButtonMap association is intentionally restricted to
        -- standalone mechanical/electro-pneumatic hardware. Applying this to
        -- arbitrary props (especially doors) can steal a nearby large
        -- FrontDoor/RearDoor hitbox and make an unrelated door stop behaving.
        local needsSpatialAssociation =
            string.find(text, "brake_valve", 1, true)
            or string.find(text, "disconnect", 1, true)
            or string.find(text, "valve", 1, true)
            or string.find(text, "cran", 1, true)
            or string.find(text, "kran", 1, true)
            or string.find(text, "controller", 1, true)
            or string.find(text, "grkv", 1, true)
            or string.find(text, "/334", 1, true)
            or string.find(text, "/013", 1, true)

        if needsSpatialAssociation then
            -- Standalone hardware has no direct ButtonMap prop identity. Use
            -- only the single nearest hit target as a fallback; explicit
            -- hardware mappings below can still disable the complete function
            -- of one physical controller/valve after it visibly detaches.
            local nearby = GetNearbyButtonIDs(train, cached)
            if nearby[1] then
                add(nearby[1])
            end
        elseif string.find(text, "door", 1, true)
            or string.find(text, "dver", 1, true)
        then
            -- Legacy manual doors likewise bind to only the nearest Door event.
            for _, nearbyID in ipairs(GetNearbyButtonIDs(train, cached)) do
                if string.find(
                    string.lower(nearbyID),
                    "door",
                    1,
                    true
                ) then
                    add(nearbyID)
                    break
                end
            end
        end

        -- Some older trains render the manual/parking-brake mechanism as a
        -- standalone ClientEnt while keyboard bindings operate its ButtonEvent
        -- IDs. Add those well-known IDs as a fallback so the physical wheel
        -- cannot be bypassed with a shortcut after it tears off.
        if string.find(text, "parking", 1, true)
            or string.find(text, "manualbrake", 1, true)
        then
            add("ParkingBrakeToggle")
            add("ParkingBrakeLeft")
            add("ParkingBrakeRight")
        end

        if string.find(text, "wiper", 1, true) then
            add("WiperToggle")
            add("WiperSet")
            add("Wiper")
        end

        -- Main traction/braking controller (KV/GRKV). If the physical
        -- controller is gone, no keyboard shortcut may still move its
        -- electrical positions.
        if string.find(text, "controller", 1, true)
            or string.find(text, "grkv", 1, true)
            or string.find(text, "/kv_", 1, true)
        then
            add("KVUp")
            add("KVDown")
            add("KV_Unlock")
            add("KVSetX1")
            add("KVSetX1B")
            add("KVSetX2")
            add("KVSetX3")
            add("KVSet0")
            add("KVSet0Fast")
            add("KVSetT1")
            add("KVSetT1A")
            add("KVSetT2")
        end

        -- Driver brake valve / crane. The visible valve may be a standalone
        -- ClientEnt with no ButtonMap entry, while F/R and numpad keys still
        -- operate the Pneumatic system through ButtonEvent.
        if string.find(text, "brake_valve", 1, true)
            or string.find(text, "brake valve", 1, true)
            or string.find(text, "crane", 1, true)
            or string.find(text, "/334", 1, true)
            or string.find(text, "/013", 1, true)
        then
            add("PneumaticBrakeUp")
            add("PneumaticBrakeDown")
            add("PneumaticBrakeSet1")
            add("PneumaticBrakeSet2")
            add("PneumaticBrakeSet3")
            add("PneumaticBrakeSet4")
            add("PneumaticBrakeSet5")
            add("PneumaticBrakeSet6")
            add("PneumaticBrakeSet7")
            add("EmergencyBrake")
        end

        if string.find(text, "stopkran", 1, true)
            or string.find(text, "emergencybrake", 1, true)
            or string.find(text, "emergency_brake", 1, true)
        then
            add("EmergencyBrake")
            add("EmergencyBrakeValveToggle")
        end

        if string.find(text, "driver_valve_bl", 1, true)
            or string.find(text, "brake_disconnect", 1, true)
        then
            add("DriverValveBLDisconnect")
            add("DriverValveBLDisconnectToggle")
        end

        if string.find(text, "driver_valve_tl", 1, true)
            or string.find(text, "train_disconnect", 1, true)
        then
            add("DriverValveTLDisconnect")
            add("DriverValveTLDisconnectToggle")
        end

        if string.find(text, "valve_disconnect", 1, true)
            and not string.find(text, "brake_disconnect", 1, true)
            and not string.find(text, "train_disconnect", 1, true)
        then
            add("DriverValveDisconnect")
            add("DriverValveDisconnectToggle")
        end

        if string.find(text, "epk_disconnect", 1, true) then
            add("EPKToggle")
        end

        if string.find(text, "epv_disconnect", 1, true) then
            add("EPKToggle")
        end

        -- Standalone 334/013 driver's brake valves are not tied to a clickable
        -- ButtonMap prop on many trains. Their physical loss disables the
        -- complete pneumatic-brake control family.
        if string.find(text, "brake_valve", 1, true)
            or string.find(text, "/334", 1, true)
            or string.find(text, "/013", 1, true)
        then
            add("PneumaticBrakeUp")
            add("PneumaticBrakeDown")
            add("PneumaticBrakeSet1")
            add("PneumaticBrakeSet2")
            add("PneumaticBrakeSet3")
            add("PneumaticBrakeSet4")
            add("PneumaticBrakeSet5")
            add("PneumaticBrakeSet6")
            add("PneumaticBrakeSet7")
        end

        return out
    end

    local function EnforceDisabledButtonHitboxes(train)
        if not IsSubwayTrain(train) then return end
        if not istable(train.MEXDamageDisabledButtonIDs)
            or table.IsEmpty(train.MEXDamageDisabledButtonIDs)
        then
            return
        end

        -- A direct bullet/crowbar hit can detach a component without creating
        -- structural deformation. Keep a private ButtonMap even in that case;
        -- otherwise Metrostroi can resurrect an invisible clickable control.
        if not train.MEXDamageV4ButtonMapOriginal then
            CloneInteractivePanels(train)
        end

        if not istable(train.ButtonMap) then return end

        for _, panel in pairs(train.ButtonMap) do
            if not istable(panel) or not istable(panel.buttons) then continue end

            if not panel.MEXDamageButtonsPrivate then
                local privateButtons = {}
                for k, v in pairs(panel.buttons) do
                    privateButtons[k] = v
                end
                panel.buttons = privateButtons
                panel.MEXDamageButtonsPrivate = true
            end

            for key, button in pairs(panel.buttons) do
                if not istable(button) or not isstring(button.ID) then continue end

                local id = button.ID:gsub("^.+:", "")
                if not train.MEXDamageDisabledButtonIDs[id] then continue end

                -- Do not rely on removing the entry alone: Metrostroi may keep
                -- a local reference to a button object for part of a frame.
                -- Replace it with a private dead hitbox object at an impossible
                -- location and zero size, preserving only harmless metadata.
                if not button.MEXDamageDeadHitbox then
                    local dead = {}
                    for k, v in pairs(button) do dead[k] = v end

                    dead.x = 100000000
                    dead.y = 100000000
                    dead.w = 0
                    dead.h = 0
                    dead.radius = 0
                    dead.tooltip = ""
                    dead.MEXDamageDeadHitbox = true

                    panel.buttons[key] = dead
                else
                    button.x = 100000000
                    button.y = 100000000
                    button.w = 0
                    button.h = 0
                    button.radius = 0
                    button.tooltip = ""
                end
            end
        end
    end

    local function DisableDetachedButtonIDs(train, buttonIDs)
        if not IsSubwayTrain(train) or not istable(buttonIDs) then return end

        train.MEXDamageDisabledButtonIDs =
            train.MEXDamageDisabledButtonIDs or {}

        for _, id in ipairs(buttonIDs) do
            if isstring(id) and id ~= "" then
                train.MEXDamageDisabledButtonIDs[
                    id:gsub("^.+:", "")
                ] = true
            end
        end

        EnforceDisabledButtonHitboxes(train)
    end

    local function GetPanelAttachedLocalTransform(train, cached, panelName)
        local panel = train.ButtonMap and train.ButtonMap[panelName]
        if not istable(panel) or not panel.MEXDamageBasePos then
            return nil, nil
        end

        local relPos, relAng = WorldToLocal(
            cached.basePos,
            cached.baseAng,
            panel.MEXDamageBasePos,
            panel.MEXDamageBaseAng
        )

        return LocalToWorld(
            relPos,
            relAng,
            panel.pos,
            panel.ang
        )
    end

    local function GetRigidAttachedLocalTransform(cached, state)
        local desiredAnchor = DeformLocalPoint(cached.anchorPos, state)
        local desiredAng = DeformLocalAngle(
            cached.anchorPos,
            cached.baseAng,
            state
        )

        local desiredOrigin = OriginForAnchoredModel(
            cached.obbCenter,
            desiredAnchor,
            desiredAng
        )

        return desiredOrigin, desiredAng
    end

    local function DisableDetachedPanelControl(train, panelName, propName)
        if not panelName or not istable(train.ButtonMap) then return end

        local panel = train.ButtonMap[panelName]
        if not istable(panel) or not istable(panel.buttons) then return end

        -- Make only the button-list table private. The button objects themselves
        -- remain Metrostroi's originals; removing an entry only disables the
        -- local hit target for this damaged wagon.
        if not panel.MEXDamageButtonsPrivate then
            local privateButtons = {}
            for k, v in pairs(panel.buttons) do
                privateButtons[k] = v
            end
            panel.buttons = privateButtons
            panel.MEXDamageButtonsPrivate = true
        end

        for key, button in pairs(panel.buttons) do
            if not istable(button) then continue end

            local model = button.model
            local generatedName = nil

            if istable(model) then
                generatedName = model.name or button.ID
            end

            local matches =
                button.PropName == propName
                or generatedName == propName
                or (
                    istable(model)
                    and istable(model.lamp)
                    and model.lamp.name == propName
                )

            if matches then
                if isstring(button.ID) then
                    DisableDetachedButtonIDs(
                        train,
                        {button.ID:gsub("^.+:", "")}
                    )
                else
                    panel.buttons[key] = nil
                end
            end
        end
    end

    local function CopyVisualState(source, debris)
        if not IsValid(source) or not IsValid(debris) then return end

        debris:SetSkin(source:GetSkin() or 0)
        debris:SetColor(source:GetColor())
        debris:SetMaterial(source:GetMaterial() or "")

        local groups = source:GetNumBodyGroups() or 0
        for id = 0, groups - 1 do
            debris:SetBodygroup(id, source:GetBodygroup(id))
        end
    end

    local WINDOW_MATERIAL_WORDS = {
        "window", "windows", "windscreen", "windshield",
        "stekl", "stec",
    }

    local GLASS_CARRIER_EXCLUDED_WORDS = {
        "lamp", "light", "indicator", "gauge", "meter", "manometer",
        "button", "switch", "tumbler", "toggle", "display", "screen",
        "speed", "volt", "amp", "pressure", "panel", "pult",
    }

    local function MaterialPathLooksWindow(path)
        path = string.lower(path or "")

        for _, word in ipairs(GLASS_CARRIER_EXCLUDED_WORDS) do
            if string.find(path, word, 1, true) then
                return false
            end
        end

        for _, word in ipairs(WINDOW_MATERIAL_WORDS) do
            if string.find(path, word, 1, true) then
                return true
            end
        end

        return false
    end

    local function LooksLikeWindowCarrier(name, cached, mode)
        local text = string.lower(
            (name or "") .. " " .. ((cached and cached.model) or "")
        )

        for _, word in ipairs(GLASS_CARRIER_EXCLUDED_WORDS) do
            if string.find(text, word, 1, true) then
                return false
            end
        end

        if cached and cached.glass then return true end

        if mode == "passenger" then
            return string.find(text, "salon", 1, true) ~= nil
                or string.find(text, "interior", 1, true) ~= nil
                or string.find(text, "body", 1, true) ~= nil
                or string.find(text, "window", 1, true) ~= nil
        end

        return string.find(text, "cabin", 1, true) ~= nil
            or string.find(text, "cabine", 1, true) ~= nil
            or string.find(text, "mask", 1, true) ~= nil
            or string.find(text, "body", 1, true) ~= nil
            or string.find(text, "window", 1, true) ~= nil
    end

    local function HideGlassSubMaterials(train, ent)
        if not IsValid(ent) then return 0 end

        local materials = ent:GetMaterials() or {}
        local changed = 0

        train.MEXDamageBrokenGlassMaterials =
            train.MEXDamageBrokenGlassMaterials or {}

        local record = train.MEXDamageBrokenGlassMaterials[ent]
        if not record then
            record = {}
            train.MEXDamageBrokenGlassMaterials[ent] = record
        end

        for materialIndex, path in ipairs(materials) do
            -- Embedded fallback only touches materials that are explicitly
            -- window/windscreen-like. Generic "glass" is intentionally not
            -- enough because many old panels use it for indicator lenses.
            if not MaterialPathLooksWindow(path) then continue end

            local subIndex = materialIndex - 1

            if record[subIndex] == nil then
                record[subIndex] = ent:GetSubMaterial(subIndex) or ""
            end

            ent:SetSubMaterial(
                subIndex,
                MEX_INVISIBLE_GLASS_NAME
            )
            changed = changed + 1
        end

        return changed
    end

    local function RestoreBrokenGlassMaterials(train)
        if not istable(train.MEXDamageBrokenGlassMaterials) then return end

        for ent, materials in pairs(train.MEXDamageBrokenGlassMaterials) do
            if not IsValid(ent) then continue end

            for subIndex, previous in pairs(materials) do
                if isstring(previous) and previous ~= "" then
                    ent:SetSubMaterial(subIndex, previous)
                else
                    ent:SetSubMaterial(subIndex, "")
                end
            end
        end

        train.MEXDamageBrokenGlassMaterials = nil
    end

    local function ShatterEmbeddedGlass(
        train,
        hitLocal,
        power,
        radius
    )
        if not IsSubwayTrain(train) or not isvector(hitLocal) then
            return false
        end

        power = tonumber(power) or 0
        if power < 0.30 then return false end

        local shattered = 0
        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()
        local center = (mins + maxs) * 0.5
        local halfLength = math.max((maxs.x - mins.x) * 0.5, 1)
        local halfWidth = math.max((maxs.y - mins.y) * 0.5, 1)
        local halfHeight = math.max((maxs.z - mins.z) * 0.5, 1)

        local endness =
            math.abs(hitLocal.x - center.x) / halfLength
        local sideness =
            math.abs(hitLocal.y - center.y) / halfWidth
        local height01 =
            (hitLocal.z - mins.z) / math.max(maxs.z - mins.z, 1)

        local cabHit =
            endness >= 0.58
            and height01 >= 0.42

        local passengerWindowHit =
            endness < 0.82
            and sideness >= 0.58
            and height01 >= 0.42

        if not cabHit and not passengerWindowHit then
            return false
        end

        -- Many stock bodies (for example older 81-717 derivatives) keep
        -- passenger/cab glazing in a dedicated *windows*.vmt slot on the main
        -- body. Hiding that slot is safe; generic glass materials are excluded.
        shattered = shattered + HideGlassSubMaterials(train, train)

        if istable(train.ClientEnts) then
            for name, prop in pairs(train.ClientEnts) do
                if not IsValid(prop) then continue end

                local cached = CacheClientProp(train, name, prop)
                local mode = passengerWindowHit and "passenger" or "cab"

                if not LooksLikeWindowCarrier(name, cached, mode) then
                    continue
                end

                local distance = cached.anchorPos:Distance(hitLocal)

                -- Full-length salon/interior shells often have their model
                -- origin at the wagon origin, so do not require their anchor to
                -- be close. Local window/cab pieces still use distance gating.
                if not cached.fullLength
                    and distance > math.max(radius or 0, 24) + 65
                then
                    continue
                end

                shattered = shattered
                    + HideGlassSubMaterials(train, prop)
            end
        end

        if shattered > 0 then
            local worldPos = train:LocalToWorld(hitLocal)
            local effect = EffectData()
            effect:SetOrigin(worldPos)
            effect:SetScale(math.Clamp(power, 0.5, 2.4))
            effect:SetMagnitude(3)
            util.Effect("GlassImpact", effect)

            surface.PlaySound(
                "physics/glass/glass_largesheet_break1.wav"
            )
        end

        return shattered > 0
    end

    local function RequestServerDetach(
        train,
        name,
        prop,
        cached,
        state,
        panelName,
        isDoor,
        isControl
    )
        train.MEXDamageV4DetachPending = train.MEXDamageV4DetachPending or {}

        local nextAllowed = train.MEXDamageV4DetachPending[name] or 0
        if nextAllowed > CurTime() then return false end
        train.MEXDamageV4DetachPending[name] = CurTime() + 1.0

        local localPos, localAng

        if panelName then
            localPos, localAng = GetPanelAttachedLocalTransform(
                train,
                cached,
                panelName
            )
        end

        if not isvector(localPos) or not isangle(localAng) then
            localPos, localAng = GetRigidAttachedLocalTransform(cached, state)
        end

        if not isvector(localPos) or not isangle(localAng) then
            return false
        end

        local buttons = GetButtonIDsForProp(
            train,
            panelName,
            name,
            cached
        )

        net.Start("MEX.DetachRequest")
            net.WriteEntity(train)
            net.WriteString(name)
            net.WriteString(cached.model)
            net.WriteVector(localPos)
            net.WriteAngle(localAng)
            net.WriteVector(cached.anchorPos)
            net.WriteVector(prop:OBBMins())
            net.WriteVector(prop:OBBMaxs())
            net.WriteBool(isDoor)
            net.WriteBool(isControl)
            net.WriteUInt(math.Clamp(prop:GetSkin() or 0, 0, 255), 8)
            net.WriteColor(prop:GetColor())
            net.WriteString(prop:GetMaterial() or "")
            net.WriteUInt(
                math.Clamp(prop:GetSequence() or 0, 0, 65535),
                16
            )
            net.WriteFloat(
                math.Clamp(prop:GetCycle() or 0, 0, 1)
            )
            net.WriteFloat(
                prop:GetPoseParameter("position") or 0
            )

            local bodygroupCount = math.min(prop:GetNumBodyGroups() or 0, 31)
            net.WriteUInt(bodygroupCount, 5)
            for id = 0, bodygroupCount - 1 do
                net.WriteUInt(id, 5)
                net.WriteUInt(
                    math.Clamp(prop:GetBodygroup(id) or 0, 0, 255),
                    8
                )
            end

            net.WriteUInt(math.min(#buttons, 48), 6)
            for i = 1, math.min(#buttons, 48) do
                net.WriteString(buttons[i])
            end
        net.SendToServer()

        return true
    end

    local function ComponentCandidateRadius(cached, isDoor, isControl)
        local s = cached.size
        local largest = math.max(math.abs(s.x), math.abs(s.y), math.abs(s.z))

        if cached.glass then
            return math.Clamp(largest * 0.18, 5, 24)
        elseif isDoor then
            return math.Clamp(largest * 0.22, 8, 30)
        elseif isControl then
            return math.Clamp(largest * 0.38, 3, 12)
        end

        return math.Clamp(largest * 0.28, 4, 18)
    end

    local function DirectImpactMountThreshold(name, isDoor, isControl)
        local seed = StableFraction(name)

        if isDoor then
            return 0.20 + seed * 0.14
        elseif isControl then
            return 0.055 + seed * 0.085
        end

        return 0.13 + seed * 0.14
    end

    local function HandleDirectComponentImpact(
        train,
        hitLocal,
        impulseLocal,
        power,
        radius,
        maxDetach,
        isBlast
    )
        if not IsSubwayTrain(train) or not istable(train.ClientEnts) then
            return
        end

        local panelMap = train.MEXDamageV4PanelProps
            or BuildPanelPropMap(train)
        local state = BuildDamageState(train)
        local candidates = {}

        for name, prop in pairs(train.ClientEnts) do
            if not IsValid(prop) then continue end

            if train.MEXDamageV4ServerDetached
                and train.MEXDamageV4ServerDetached[name]
            then
                continue
            end

            if prop.GetNoDraw and prop:GetNoDraw() then continue end
            if prop:GetColor().a <= 5 then continue end

            local cached = CacheClientProp(train, name, prop)
            local panelName = panelMap[name]

            local isGlass = IsGlassComponent(name, cached)
            local isDoor = IsDoorComponent(name, cached)
            local isControl = IsSmallControlComponent(
                name,
                cached,
                panelName
            )
            local isBreakaway = IsGeneralBreakawayComponent(
                name,
                cached,
                panelName
            )

            if not isGlass
                and not isDoor
                and not isControl
                and not isBreakaway
            then
                continue
            end

            local centerDistance = cached.anchorPos:Distance(hitLocal)
            local componentRadius = ComponentCandidateRadius(
                cached,
                isDoor,
                isControl
            )
            local edgeDistance = math.max(
                0,
                centerDistance - componentRadius
            )

            if edgeDistance > radius then continue end

            local falloff = 1 - edgeDistance / math.max(radius, 1)
            local score = falloff * power
            local threshold = isGlass
                and (0.018 + StableFraction(name) * 0.035)
                or DirectImpactMountThreshold(
                    name,
                    isDoor,
                    isControl
                )

            local predictedMove = 0

            if isBlast then
                local impulseMagnitude = isvector(impulseLocal)
                    and impulseLocal:Length()
                    or 0

                local compliance =
                    isGlass and 2.2
                    or (isControl and 1.65)
                    or (isDoor and 0.92 or 1.15)

                predictedMove =
                    impulseMagnitude
                    * falloff
                    * compliance
                    / 95

                local movementThreshold =
                    isGlass and 0.025
                    or (isControl and 0.045)
                    or (isDoor and 0.085 or 0.065)

                -- Explosion rule: once a mounted part would visibly move even
                -- a small amount relative to the carbody, its fasteners are
                -- considered failed and it becomes independent debris.
                if predictedMove < movementThreshold
                    and score < threshold * 0.55
                then
                    continue
                end
            elseif score < threshold then
                continue
            end

            candidates[#candidates + 1] = {
                name = name,
                prop = prop,
                cached = cached,
                panelName = panelName,
                isGlass = isGlass,
                isDoor = isDoor,
                isControl = isControl,
                score = score,
                predictedMove = predictedMove,
                edgeDistance = edgeDistance,
                priority =
                    isGlass and 5
                    or (isControl and 4)
                    or (isDoor and 2 or 3),
            }
        end

        table.sort(candidates, function(a, b)
            if isBlast
                and math.abs(
                    (a.predictedMove or 0)
                    - (b.predictedMove or 0)
                ) > 0.001
            then
                return (a.predictedMove or 0)
                    > (b.predictedMove or 0)
            end

            -- Within a small local neighborhood, prefer the actually mounted
            -- control over a large panel/case behind it.
            local neighborhood = math.min(8, radius * 0.35)
            local aRank = a.edgeDistance - a.priority * neighborhood
            local bRank = b.edgeDistance - b.priority * neighborhood

            if math.abs(aRank - bRank) > 0.01 then
                return aRank < bRank
            end

            if a.priority ~= b.priority then
                return a.priority > b.priority
            end

            return a.score > b.score
        end)

        local requested = 0
        local limit = math.Clamp(maxDetach or 1, 1, 96)

        for _, candidate in ipairs(candidates) do
            if requested >= limit then break end

            if RequestServerDetach(
                train,
                candidate.name,
                candidate.prop,
                candidate.cached,
                state,
                candidate.panelName,
                candidate.isDoor,
                candidate.isControl
            ) then
                requested = requested + 1

                -- Do not let a fragile prop visibly ride away with a distorted
                -- panel while waiting one network round-trip for confirmation.
                ClearClientPropRenderTransform(candidate.prop)
            end
        end
    end

    net.Receive("MEX.ComponentImpact", function()
        local train = net.ReadEntity()
        net.ReadUInt(16) -- serial is currently only used server-side
        local hitLocal = net.ReadVector()
        local impulseLocal = net.ReadVector()
        local power = net.ReadFloat()
        local radius = net.ReadFloat()
        local maxDetach = net.ReadUInt(7)
        local isBlast = net.ReadBool()

        if not IsSubwayTrain(train) then return end

        -- Even when glass is baked into a larger carbody/cab model, try to
        -- remove the model's dedicated glass material slots at the impact.
        ShatterEmbeddedGlass(
            train,
            hitLocal,
            power,
            radius
        )

        -- ClientEnts/ButtonMap may be created later in the same frame as the
        -- impact callback. One zero-delay retry is enough without accumulating
        -- stale hit events.
        timer.Simple(0, function()
            if not IsSubwayTrain(train) then return end
            HandleDirectComponentImpact(
                train,
                hitLocal,
                impulseLocal,
                power,
                radius,
                maxDetach,
                isBlast
            )
        end)
    end)

    local function EnsureDamagedLightGuard(train)
        if train.MEXDamageOriginalSetLightPower then return end
        if not isfunction(train.SetLightPower) then return end

        train.MEXDamageOriginalSetLightPower = train.SetLightPower
        train.MEXDamageDisabledLights = train.MEXDamageDisabledLights or {}

        train.SetLightPower = function(self, index, power, brightness)
            if self.MEXDamageDisabledLights
                and self.MEXDamageDisabledLights[index]
            then
                return self.MEXDamageOriginalSetLightPower(
                    self,
                    index,
                    false,
                    0
                )
            end

            return self.MEXDamageOriginalSetLightPower(
                self,
                index,
                power,
                brightness
            )
        end
    end

    local function DisableLightsForDetachedComponent(
        train,
        name,
        cached
    )
        if not istable(train.Lights) or not cached then return end

        local text = string.lower(
            (name or "") .. " " .. (cached.model or "")
        )

        local isLamp =
            string.find(text, "lamp", 1, true)
            or string.find(text, "light", 1, true)
            or string.find(text, "headlight", 1, true)

        if not isLamp then return end

        EnsureDamagedLightGuard(train)

        local candidates = {}
        for index, light in pairs(train.Lights) do
            if not istable(light) or not isvector(light[2]) then continue end

            local distance = cached.anchorPos:Distance(light[2])
            candidates[#candidates + 1] = {
                index = index,
                distance = distance,
            }
        end

        table.sort(candidates, function(a, b)
            return a.distance < b.distance
        end)

        local radius =
            string.find(text, "headlight", 1, true) and 135 or 75

        local disabled = 0
        for _, candidate in ipairs(candidates) do
            if candidate.distance > radius then continue end

            train.MEXDamageDisabledLights[candidate.index] = true
            train:MEXDamageOriginalSetLightPower(
                candidate.index,
                false,
                0
            )
            disabled = disabled + 1
        end

        -- Some Metrostroi lamp group models are authored around train origin,
        -- while their visible mesh sits at the front. In that case the cached
        -- model anchor and the light definition may not be close enough. For a
        -- clearly named headlight group, disable the nearest light as a safe
        -- fallback.
        if disabled == 0
            and string.find(text, "headlight", 1, true)
            and candidates[1]
        then
            local index = candidates[1].index
            train.MEXDamageDisabledLights[index] = true
            train:MEXDamageOriginalSetLightPower(index, false, 0)
        end
    end

    local function MarkDetachedClient(train, name, debris)
        -- This function is reached only from MEX.ComponentDetached, i.e. after
        -- the server accepted the physical detach. Never disable controls from
        -- a mere detach request/prediction: if the original ClientEnt is still
        -- visibly attached, it must remain fully interactive.
        train.MEXDamageV4ServerDetached =
            train.MEXDamageV4ServerDetached or {}

        local previous = train.MEXDamageV4ServerDetached[name]

        if not previous then
            previous = {
                debris = debris,
                oldNoDraw = nil,
            }

            train.MEXDamageV4ServerDetached[name] = previous
        else
            previous.debris = debris
        end

        local panelMap =
            train.MEXDamageV4PanelProps or BuildPanelPropMap(train)
        local panelName = panelMap[name]

        if istable(train.ClientEnts) then
            local prop = train.ClientEnts[name]

            if IsValid(prop) then
                if previous.oldNoDraw == nil then
                    previous.oldNoDraw = prop:GetNoDraw()
                end

                local cached = CacheClientProp(train, name, prop)
                previous.anchorPos = cached and cached.anchorPos or nil
                previous.model = cached and cached.model or nil

                DisableLightsForDetachedComponent(
                    train,
                    name,
                    cached
                )

                local mappedButtons = GetButtonIDsForProp(
                    train,
                    panelName,
                    name,
                    cached
                )
                DisableDetachedButtonIDs(train, mappedButtons)

                prop:SetRenderOrigin(nil)
                prop:SetRenderAngles(nil)
                prop:DisableMatrix("RenderMultiply")
                prop:SetNoDraw(true)
            end
        end

        if panelName then
            DisableDetachedPanelControl(train, panelName, name)
        end

        EnforceDisabledButtonHitboxes(train)
    end

    local function MaybeDetachClientComponent(
        train,
        name,
        prop,
        cached,
        state,
        panelName
    )
        if not IsValid(prop) then return false end

        if train.MEXDamageV4ServerDetached
            and train.MEXDamageV4ServerDetached[name]
        then
            prop:SetNoDraw(true)
            return true
        end

        -- Do not request a hidden variant which Metrostroi is not currently
        -- displaying.
        if prop.GetNoDraw and prop:GetNoDraw() then return false end
        if prop:GetColor().a <= 5 then return false end

        local displacement = LocalDisplacement(cached.anchorPos, state):Length()
        if displacement <= 0.01 then return false end

        local seed = StableFraction(name)
        local isGlass = IsGlassComponent(name, cached)
        local isDoor = IsDoorComponent(name, cached)
        local isControl = IsSmallControlComponent(name, cached, panelName)
        local isBreakaway = IsGeneralBreakawayComponent(
            name,
            cached,
            panelName
        )

        if isGlass then
            local threshold = 0.20 + seed * 0.45
            if displacement >= threshold then
                local requested = RequestServerDetach(
                    train,
                    name,
                    prop,
                    cached,
                    state,
                    panelName,
                    false,
                    false
                )

                if requested then
                    ClearClientPropRenderTransform(prop)
                    return true
                end
            end
            return false
        end

        if isDoor then
            local threshold = 2.2 + seed * 2.8
            if displacement >= threshold then
                local requested = RequestServerDetach(
                    train,
                    name,
                    prop,
                    cached,
                    state,
                    panelName,
                    true,
                    false
                )

                if requested then
                    ClearClientPropRenderTransform(prop)
                    return true
                end
            end
            return false
        end

        if isControl then
            -- Small controls should not ride metres away together with a bent
            -- ButtonMap. Their mounts fail after only a small local movement.
            local threshold = 0.45 + seed * 1.05
            if displacement >= threshold then
                local requested = RequestServerDetach(
                    train,
                    name,
                    prop,
                    cached,
                    state,
                    panelName,
                    false,
                    true
                )

                if requested then
                    ClearClientPropRenderTransform(prop)
                    return true
                end
            end
            return false
        end

        if isBreakaway then
            local threshold = 1.0 + seed * 2.4
            if displacement >= threshold then
                local requested = RequestServerDetach(
                    train,
                    name,
                    prop,
                    cached,
                    state,
                    panelName,
                    false,
                    false
                )

                if requested then
                    ClearClientPropRenderTransform(prop)
                    return true
                end
            end
        end

        return false
    end

    local function RestoreDetachedComponents(train)
        if not IsValid(train) then return end

        if istable(train.MEXDamageV4ServerDetached) then
            for name, data in pairs(train.MEXDamageV4ServerDetached) do
                if istable(train.ClientEnts) then
                    local prop = train.ClientEnts[name]
                    if IsValid(prop) then
                        prop:SetNoDraw(data.oldNoDraw or false)
                        prop:SetRenderOrigin(nil)
                        prop:SetRenderAngles(nil)
                    end
                end
            end
        end

        train.MEXDamageV4ServerDetached = nil
        train.MEXDamageV4DetachPending = nil
        train.MEXDamageDisabledLights = {}
        train.MEXDamageDisabledButtonIDs = {}
    end

    net.Receive("MEX.ComponentDetached", function()
        local train = net.ReadEntity()
        local name = net.ReadString()
        local debris = net.ReadEntity()

        if not IsSubwayTrain(train) or not isstring(name) then return end

        MarkDetachedClient(train, name, debris)

        surface.PlaySound(
            "physics/metal/metal_solid_impact_hard5.wav"
        )
    end)

    net.Receive("MEX.DetachReset", function()
        local train = net.ReadEntity()
        if not IsSubwayTrain(train) then return end

        RestoreDetachedComponents(train)
        RestoreBrokenGlassMaterials(train)

        -- Rebuild a clean per-wagon panel copy on the next damage update.
        RestoreInteractivePanels(train)
        train.MEXDamageV4PanelProps = nil
        train.MEXDamageV4PropCache = nil
    end)

    ---------------------------------------------------------------------------
    -- Bone deformation
    ---------------------------------------------------------------------------

    local function ToTrainLocalAngle(train, worldAng)
        local _, localAng = WorldToLocal(
            vector_origin,
            worldAng,
            vector_origin,
            train:GetAngles()
        )
        return localAng
    end

    local function InstallBoneField(
        modelEnt,
        train,
        skipRoot,
        strength
    )
        if not IsValid(modelEnt) or not IsValid(train) then return end
        strength = tonumber(strength) or 1
        if modelEnt.MEXDamageV4BoneCallback then return end

        modelEnt.MEXDamageV4BoneCallback = modelEnt:AddCallback(
            "BuildBonePositions",
            function(ent, boneCount)
                if not IsValid(train) then return end

                local state = BuildDamageState(train)
                if not state or boneCount <= 0 then return end

                for bone = 0, boneCount - 1 do
                    if skipRoot and bone == 0 then continue end
                    if ent:GetBoneName(bone) == "__INVALIDBONE__" then continue end

                    local matrix = ent:GetBoneMatrix(bone)
                    if not matrix then continue end

                    local worldPos = matrix:GetTranslation()
                    if not IsFiniteVector(worldPos) then continue end

                    local trainLocalPos = train:WorldToLocal(worldPos)
                    local baseDeformed = DeformLocalPointStrength(
                        trainLocalPos,
                        state,
                        strength
                    )
                    local displacement = baseDeformed - trainLocalPos
                    if displacement:LengthSqr() < 0.0025 then continue end

                    local worldAng = matrix:GetAngles()
                    local trainLocalAng = ToTrainLocalAngle(train, worldAng)
                    local deformedPos = trainLocalPos + displacement
                    local deformedAng = DeformLocalAngleStrength(
                        trainLocalPos,
                        trainLocalAng,
                        state,
                        strength
                    )

                    matrix:SetTranslation(train:LocalToWorld(deformedPos))
                    matrix:SetAngles(train:LocalToWorldAngles(deformedAng))
                    ent:SetBoneMatrix(bone, matrix)
                end
            end
        )
    end

    local function CheckFrontBoneCapability(train)
        if not IsValid(train) or train.MEXDamageV4BoneCapabilityChecked then return end

        train.MEXDamageV4BoneCapabilityChecked = true
        train:SetupBones()

        local count = train:GetBoneCount() or 0
        local frontBones = 0
        local maxX = train:OBBMaxs().x

        for bone = 1, math.max(count - 1, 0) do
            if train:GetBoneName(bone) == "__INVALIDBONE__" then continue end

            local matrix = train:GetBoneMatrix(bone)
            if not matrix then continue end

            local localPos = train:WorldToLocal(matrix:GetTranslation())
            if localPos.x >= maxX - 140 then
                frontBones = frontBones + 1
            end
        end

        train.MEXDamageV4BodyBoneCount = count
        train.MEXDamageV4FrontBoneCount = frontBones

        if count <= 1 or frontBones == 0 then
            print(string.format(
                "[Metrostroi Expanded/Damage] %s: stock body model %s has no usable non-root bones near the front. True local front-sheet denting cannot be produced from Lua alone; separate front ClientEnt parts can still move/break away.",
                train:GetClass(),
                tostring(train:GetModel())
            ))
        end
    end

    local function InstallTrainBoneField(train)
        if not IsValid(train) then return end
        CheckFrontBoneCapability(train)
        InstallBoneField(train, train, true, 1.12)
    end

    ---------------------------------------------------------------------------
    -- Lights follow the same deformed mounting points.
    ---------------------------------------------------------------------------

    local function CloneLights(train)
        if train.MEXDamageV4LightsOriginal then return true end
        if not istable(train.Lights) then return false end

        local original = train.Lights
        local clone = {}

        for id, light in pairs(original) do
            if istable(light) then
                local l = {}
                for k, v in pairs(light) do l[k] = v end

                if isvector(light[2]) then
                    l.MEXDamageBasePos = CopyVector(light[2])
                    l[2] = CopyVector(light[2])
                end
                if isangle(light[3]) then
                    l.MEXDamageBaseAng = CopyAngle(light[3])
                    l[3] = CopyAngle(light[3])
                end

                clone[id] = l
            else
                clone[id] = light
            end
        end

        train.MEXDamageV4LightsOriginal = original
        train.Lights = clone
        return true
    end

    local function ApplyLightDeformation(train, state)
        if not state then
            if train.MEXDamageV4LightsOriginal then
                train.Lights = train.MEXDamageV4LightsOriginal
                train.MEXDamageV4LightsOriginal = nil
            end
            return
        end

        if not CloneLights(train) then return end

        for _, light in pairs(train.Lights) do
            if not istable(light) or not light.MEXDamageBasePos then continue end

            light[2] = DeformLocalPoint(light.MEXDamageBasePos, state)

            if light.MEXDamageBaseAng then
                light[3] = DeformLocalAngle(
                    light.MEXDamageBasePos,
                    light.MEXDamageBaseAng,
                    state
                )
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Apply / clear the complete visual deformation
    ---------------------------------------------------------------------------

    local function ApplyClientEnts(train, state)
        if not istable(train.ClientEnts) then return end

        local panelMap = train.MEXDamageV4PanelProps or BuildPanelPropMap(train)

        for name, prop in pairs(train.ClientEnts) do
            if not IsValid(prop) then continue end

            if train.MEXDamageV4ServerDetached
                and train.MEXDamageV4ServerDetached[name]
            then
                prop:SetNoDraw(true)
                continue
            end

            if not state then
                ClearClientPropRenderTransform(prop)
                continue
            end

            local cached = CacheClientProp(train, name, prop)
            local panelName = panelMap[name]

            -- A sufficiently damaged mounting point can release a door or a
            -- small panel control. Its original Metrostroi ClientEnt is hidden
            -- and a physics debris copy takes over.
            if MaybeDetachClientComponent(
                train,
                name,
                prop,
                cached,
                state,
                panelName
            ) then
                continue
            end

            -- Existing bones deform the actual mesh instead of stretching the
            -- complete client entity. Root is skipped because it would move the
            -- whole full-length shell.
            if cached.structural then
                local boneStrength = cached.cabin
                    and math.max(
                        1.22,
                        CabStrengthAtPoint(cached.anchorPos, state)
                    )
                    or 1

                InstallBoneField(
                    prop,
                    train,
                    true,
                    boneStrength
                )
            end

            if panelName and ApplyPanelAttachment(
                train,
                name,
                prop,
                cached,
                panelName
            ) then
                continue
            end

            if cached.localPiece then
                -- Doors, front masks, lamp groups, localized cab shells,
                -- localized panel bodies etc. remain rigid but follow the
                -- deformed mounting point. Their own child bones can still bend.
                ApplyRigidAttachment(train, prop, cached, state)
                ApplyLocalStructuralCrushMatrix(
                    name,
                    prop,
                    cached,
                    state
                )
            else
                -- Full saloon/interior models are kept at the train origin.
                -- Only their existing child bones are allowed to deform. This
                -- prevents the entire interior from "driving away" from the car.
                ClearClientPropRenderTransform(prop)
            end
        end
    end

    local function EnforceDetachedVisuals(train)
        if not IsSubwayTrain(train)
            or not istable(train.MEXDamageV4ServerDetached)
            or not istable(train.ClientEnts)
        then
            return
        end

        for name in pairs(train.MEXDamageV4ServerDetached) do
            local prop = train.ClientEnts[name]
            if IsValid(prop) then
                prop:SetRenderOrigin(nil)
                prop:SetRenderAngles(nil)
                prop:DisableMatrix("RenderMultiply")
                prop:SetNoDraw(true)
            end
        end
    end

    local function ClearAllVisualDamage(train)
        RestoreInteractivePanels(train)
        ApplyLightDeformation(train, nil)

        if istable(train.ClientEnts) then
            for _, prop in pairs(train.ClientEnts) do
                if IsValid(prop) then
                    ClearClientPropRenderTransform(prop)
                end
            end
        end

        -- Failure state is independent of deformation state.
        EnforceDisabledButtonHitboxes(train)
        EnforceDetachedVisuals(train)
    end

    local function ApplyCompleteDamage(train)
        if not IsSubwayTrain(train) then return end

        ClearLegacyTransforms(train)

        local state = BuildDamageState(train)
        if not state then
            ClearAllVisualDamage(train)
            return
        end

        InstallTrainBoneField(train)
        ApplyPanelDeformation(train, state)

        -- Panel props may be generated after the map was cloned.
        train.MEXDamageV4PanelProps = BuildPanelPropMap(train)

        EnforceDisabledButtonHitboxes(train)
        ApplyClientEnts(train, state)
        ApplyLightDeformation(train, state)
        EnforceDisabledButtonHitboxes(train)
        EnforceDetachedVisuals(train)
    end

    ---------------------------------------------------------------------------
    -- Update timing
    ---------------------------------------------------------------------------

    local nextDamageUpdate = 0

    hook.Add("Think", "MEX.Damage.V4StructuralUpdate", function()
        if CurTime() < nextDamageUpdate then return end
        nextDamageUpdate = CurTime() + 0.02

        for _, train in ipairs(ents.GetAll()) do
            if IsSubwayTrain(train) then
                ApplyCompleteDamage(train)
            end
        end
    end)

    -- Some Metrostroi train classes move client props late in their own Think.
    -- Reapply rigid attachment render transforms immediately before drawing.
    hook.Add("PreDrawOpaqueRenderables", "MEX.Damage.V4OpaqueAttachments", function()
        for _, train in ipairs(ents.GetAll()) do
            if not IsSubwayTrain(train) then continue end

            local state = BuildDamageState(train)
            if state then
                ApplyClientEnts(train, state)
            end
        end
    end)

    hook.Add("PreDrawTranslucentRenderables", "MEX.Damage.V4TranslucentAttachments", function()
        for _, train in ipairs(ents.GetAll()) do
            if not IsSubwayTrain(train) then continue end

            local state = BuildDamageState(train)
            if state then
                ApplyClientEnts(train, state)
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Impact visual effects
    ---------------------------------------------------------------------------

    net.Receive("MEX.DamageImpact", function()
        local train = net.ReadEntity()
        local zone = net.ReadString()
        local amount = net.ReadFloat()
        local worldPos = net.ReadVector()
        local normal = net.ReadNormal()

        if not IsValid(train) then return end

        if amount >= 0.14 then
            local dlight = DynamicLight(train:EntIndex())
            if dlight then
                dlight.pos = worldPos
                dlight.r = 255
                dlight.g = 145
                dlight.b = 65
                dlight.brightness = math.Clamp(amount * 3.2, 0.5, 2.7)
                dlight.Decay = 1700
                dlight.Size = math.Clamp(70 + amount * 140, 70, 210)
                dlight.DieTime = CurTime() + 0.08
            end
        end

        if amount >= 0.38 then
            local emitter = ParticleEmitter(worldPos)
            if emitter then
                for i = 1, math.floor(2 + amount * 5) do
                    local particle = emitter:Add(
                        "particle/particle_smokegrenade",
                        worldPos
                    )

                    if particle then
                        particle:SetVelocity(
                            normal * math.Rand(6, 24) + VectorRand() * 7
                        )
                        particle:SetDieTime(math.Rand(0.8, 1.7))
                        particle:SetStartAlpha(math.random(50, 85))
                        particle:SetEndAlpha(0)
                        particle:SetStartSize(math.Rand(4, 8))
                        particle:SetEndSize(math.Rand(16, 28))
                        particle:SetRoll(math.Rand(-180, 180))
                        particle:SetRollDelta(math.Rand(-0.5, 0.5))
                        particle:SetAirResistance(85)
                        particle:SetGravity(Vector(0, 0, math.Rand(4, 10)))
                    end
                end
                emitter:Finish()
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Debug / inspection commands
    ---------------------------------------------------------------------------

    local function GetAimedClientTrain()
        local ply = LocalPlayer()
        if not IsValid(ply) then return nil end

        local trace = ply:GetEyeTrace()
        if trace and IsSubwayTrain(trace.Entity) then
            return trace.Entity
        end

        local seat = ply:GetVehicle()
        if IsValid(seat) then
            local train = seat:GetNW2Entity("TrainEntity")
            if IsSubwayTrain(train) then return train end
        end

        return nil
    end

    concommand.Add("mex_controls_restore", function()
        for _, train in ipairs(ents.GetAll()) do
            if IsSubwayTrain(train) then
                RestoreInteractivePanels(train)
                train.MEXDamageV4PanelProps = nil

                if istable(train.ClientEnts) then
                    for _, prop in pairs(train.ClientEnts) do
                        if IsValid(prop) then
                            ClearClientPropRenderTransform(prop)
                        end
                    end
                end
            end
        end

        chat.AddText(
            Color(120, 255, 120),
            "[Metrostroi Expanded] Visual control layout restored. Detached server components stay disabled until mex_damage_reset."
        )
    end)

    concommand.Add("mex_damage_bones", function()
        local train = GetAimedClientTrain()
        if not IsValid(train) then
            print("[Metrostroi Expanded/Damage] Aim at a Metrostroi train.")
            return
        end

        train:SetupBones()

        print("------------------------------------------------------------")
        print("[Metrostroi Expanded/Damage] Bone dump: " .. train:GetClass())
        print("model: " .. tostring(train:GetModel()))
        CheckFrontBoneCapability(train)
        print("body bones: " .. tostring(train:GetBoneCount()))
        print("front-region non-root bones: " .. tostring(train.MEXDamageV4FrontBoneCount or 0))

        if (train.MEXDamageV4FrontBoneCount or 0) == 0 then
            print("front sheet deformation: NOT AVAILABLE on this stock body MDL")
            print("reason: no usable weighted front-region bone can be driven from Lua")
        else
            print("front sheet deformation: bone candidates exist (vertex weighting still determines the visible result)")
        end

        for bone = 0, math.max(train:GetBoneCount() - 1, -1) do
            print(string.format(
                "  body [%d] %s parent=%d",
                bone,
                tostring(train:GetBoneName(bone)),
                train:GetBoneParent(bone)
            ))
        end

        if istable(train.ClientEnts) then
            for name, prop in pairs(train.ClientEnts) do
                if not IsValid(prop) then continue end

                local model = string.lower(prop:GetModel() or "")
                if not ModelLooksStructural(name, model) then continue end

                prop:SetupBones()
                print(string.format(
                    "client %s | %s | bones=%d",
                    tostring(name),
                    tostring(prop:GetModel()),
                    prop:GetBoneCount()
                ))

                for bone = 0, math.max(prop:GetBoneCount() - 1, -1) do
                    print(string.format(
                        "    [%d] %s parent=%d",
                        bone,
                        tostring(prop:GetBoneName(bone)),
                        prop:GetBoneParent(bone)
                    ))
                end
            end
        end

        print("------------------------------------------------------------")
    end)

    local debugDamage = CreateClientConVar(
        "mex_damage_debug",
        "0",
        true,
        false,
        "Draw Metrostroi Expanded impact/deformation debug markers"
    )

    hook.Add("PostDrawTranslucentRenderables", "MEX.Damage.V4Debug", function()
        if not debugDamage:GetBool() then return end

        for _, train in ipairs(ents.GetAll()) do
            if not IsSubwayTrain(train) then continue end

            local state = BuildDamageState(train)
            if not state then continue end

            local colors = {
                front = Color(255, 90, 70),
                rear = Color(255, 170, 70),
                left = Color(80, 180, 255),
                right = Color(170, 100, 255),
                roof = Color(255, 235, 90),
                floor = Color(80, 255, 150),
            }

            for _, zone in ipairs({"front", "rear", "left", "right", "roof", "floor"}) do
                local amount = state[zone]
                if amount <= 0.001 then continue end

                local pos = train:LocalToWorld(state.hits[zone])
                render.DrawWireframeSphere(
                    pos,
                    7 + amount * 18,
                    10,
                    8,
                    colors[zone],
                    true
                )
            end
        end
    end)

    hook.Add("EntityRemoved", "MEX.Damage.V4Cleanup", function(ent)
        if not IsSubwayTrain(ent) then return end
        RestoreDetachedComponents(ent)
        RestoreInteractivePanels(ent)
    end)
end
