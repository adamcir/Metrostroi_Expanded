-- Metrostroi Expanded - Damage System
-- Simple directional crash damage and visual deformation for Metrostroi trains.
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

if SERVER then
    AddCSLuaFile()
end

MetrostroiExpandedDamage = MetrostroiExpandedDamage or {}
local MEXD = MetrostroiExpandedDamage

MEXD.Version = "0.4.3"

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
        train.MEXDamageBlockedButtons = train.MEXDamageBlockedButtons or {}

        train.ButtonEvent = function(self, button, state, ply)
            if self.MEXDamageBlockedButtons
                and self.MEXDamageBlockedButtons[button]
            then
                return false
            end

            return self.MEXDamageOriginalButtonEvent(
                self,
                button,
                state,
                ply
            )
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
        zone
    )
        if not util.IsValidModel(model) then return nil end

        local debris = ents.Create("mex_damage_debris")
        if not IsValid(debris) then return nil end

        debris:SetModel(model)
        debris.MEXFallbackMins = mins
        debris.MEXFallbackMaxs = maxs
        debris:SetPos(train:LocalToWorld(localPos))
        debris:SetAngles(train:LocalToWorldAngles(localAng))
        debris:SetSourceTrain(train)
        debris:SetComponentName(name)
        debris:Spawn()

        if not IsValid(debris) then return nil end

        debris:SetSkin(math.max(0, skin or 0))
        debris:SetColor(color or color_white)

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
            phys:SetVelocity(
                train:GetVelocity()
                + normal * (35 + seed * 55)
                + train:GetUp() * (18 + seed * 22)
            )
            phys:AddAngleVelocity(Vector(
                -110 + seed * 220,
                70 - seed * 140,
                -140 + seed * 280
            ))
            phys:Wake()
        end

        return debris
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
        source
    )
        if not IsSubwayTrain(train) or not isvector(worldPos) then return end

        power = math.Clamp(tonumber(power) or 0, 0.05, 1.5)
        radius = math.Clamp(tonumber(radius) or 20, 8, 180)
        maxDetach = math.Clamp(math.floor(tonumber(maxDetach) or 1), 1, 12)

        PruneComponentImpacts(train)

        train.MEXDamageComponentImpactSerial =
            (train.MEXDamageComponentImpactSerial or 0) + 1

        local impact = {
            id = train.MEXDamageComponentImpactSerial,
            localPos = train:WorldToLocal(worldPos),
            power = power,
            radius = radius,
            remaining = maxDetach,
            source = source or "unknown",
            expires = CurTime() + COMPONENT_IMPACT_LIFETIME,
        }

        table.insert(train.MEXDamageComponentImpacts, impact)

        net.Start("MEX.ComponentImpact")
            net.WriteEntity(train)
            net.WriteUInt(impact.id % 65536, 16)
            net.WriteVector(impact.localPos)
            net.WriteFloat(power)
            net.WriteFloat(radius)
            net.WriteUInt(maxDetach, 4)
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
                    math.Clamp(impactKmh / 42, 0.15, 1.5),
                    math.Clamp(16 + impactKmh * 1.45, 20, 150),
                    math.Clamp(1 + math.floor(impactKmh / 16), 1, 10),
                    "physics"
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

        local bodygroups = {}
        local bodygroupCount = math.min(net.ReadUInt(5), 31)
        for _ = 1, bodygroupCount do
            local id = net.ReadUInt(5)
            local value = net.ReadUInt(8)
            bodygroups[id] = value
        end

        local buttonIDs = {}
        local buttonCount = math.min(net.ReadUInt(5), 16)
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
        if ply.MEXDamageDetachCount > 64 then return end

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

        local directMinimum =
            isDoor and 0.62
            or (isControl and 0.11 or 0.20)

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

        local debris = SpawnDetachedPhysicsProp(
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
            zone
        )

        if not IsValid(debris) then return end

        local validButtons = {}
        for _, button in ipairs(buttonIDs) do
            if IsValidDetachedButtonID(train, button) then
                BlockDetachedButton(train, button)
                validButtons[#validButtons + 1] = button
            end
        end

        train.MEXDamageDetachedServer[name] = {
            debris = debris,
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
                radius = math.Clamp(38 + rawDamage * 0.75, 45, 150)
                maxDetach = math.Clamp(2 + math.floor(rawDamage / 24), 2, 10)
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

            SendComponentImpact(
                ent,
                componentPos,
                math.Clamp(0.32 + rawDamage / 40, 0.32, 1.35),
                radius,
                maxDetach,
                "damageinfo"
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
        "pult", "panel", "door", "window", "glass", "seat", "couch",
        "handler", "handrail", "lamp", "headlight", "frame", "roof",
    }

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
        local overall = math.max(front, rear, left, right, roof, floor)

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

            panel.pos = DeformLocalPoint(panel.MEXDamageBasePos, state)
            panel.ang = DeformLocalAngle(
                panel.MEXDamageBasePos,
                panel.MEXDamageBaseAng,
                state
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

    local function ApplyRigidAttachment(train, prop, cached, state)
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

    local function IsDoorComponent(name, cached)
        local text = (name or "") .. " " .. (cached.model or "")
        if not ContainsAnyWord(text, DOOR_WORDS) then return false end

        local s = cached.size
        local largest = math.max(math.abs(s.x), math.abs(s.y), math.abs(s.z))

        -- Ignore tiny props whose model happens to contain "door".
        return largest >= 22
    end

    local function IsSmallControlComponent(name, cached, panelName)
        if not panelName then return false end

        local s = cached.size
        local largest = math.max(math.abs(s.x), math.abs(s.y), math.abs(s.z))
        if largest > 55 then return false end

        local text =
            (name or "")
            .. " "
            .. (cached.model or "")
            .. " "
            .. (panelName or "")

        -- Generated ButtonMap props are controls even when their file name does
        -- not literally contain "button".
        return ContainsAnyWord(text, CONTROL_WORDS) or largest <= 28
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

                    if matches then
                        add(button.ID)
                    end
                end
            end
        end

        local text = string.lower(
            (propName or "") .. " " .. (cached.model or "")
        )

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

        return out
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
                panel.buttons[key] = nil
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

            local bodygroupCount = math.min(prop:GetNumBodyGroups() or 0, 31)
            net.WriteUInt(bodygroupCount, 5)
            for id = 0, bodygroupCount - 1 do
                net.WriteUInt(id, 5)
                net.WriteUInt(
                    math.Clamp(prop:GetBodygroup(id) or 0, 0, 255),
                    8
                )
            end

            net.WriteUInt(math.min(#buttons, 16), 5)
            for i = 1, math.min(#buttons, 16) do
                net.WriteString(buttons[i])
            end
        net.SendToServer()

        return true
    end

    local function ComponentCandidateRadius(cached, isDoor, isControl)
        local s = cached.size
        local largest = math.max(math.abs(s.x), math.abs(s.y), math.abs(s.z))

        if isDoor then
            return math.Clamp(largest * 0.22, 8, 30)
        elseif isControl then
            return math.Clamp(largest * 0.38, 3, 12)
        end

        return math.Clamp(largest * 0.28, 4, 18)
    end

    local function DirectImpactMountThreshold(name, isDoor, isControl)
        local seed = StableFraction(name)

        if isDoor then
            return 0.52 + seed * 0.22
        elseif isControl then
            return 0.055 + seed * 0.085
        end

        return 0.13 + seed * 0.14
    end

    local function HandleDirectComponentImpact(
        train,
        hitLocal,
        power,
        radius,
        maxDetach
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

            if not isDoor and not isControl and not isBreakaway then
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
            local threshold = DirectImpactMountThreshold(
                name,
                isDoor,
                isControl
            )

            if score < threshold then continue end

            candidates[#candidates + 1] = {
                name = name,
                prop = prop,
                cached = cached,
                panelName = panelName,
                isDoor = isDoor,
                isControl = isControl,
                score = score,
                edgeDistance = edgeDistance,
                priority =
                    isControl and 3
                    or (isDoor and 1 or 2),
            }
        end

        table.sort(candidates, function(a, b)
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
        local limit = math.Clamp(maxDetach or 1, 1, 12)

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
        local power = net.ReadFloat()
        local radius = net.ReadFloat()
        local maxDetach = net.ReadUInt(4)

        if not IsSubwayTrain(train) then return end

        -- ClientEnts/ButtonMap may be created later in the same frame as the
        -- impact callback. One zero-delay retry is enough without accumulating
        -- stale hit events.
        timer.Simple(0, function()
            if not IsSubwayTrain(train) then return end
            HandleDirectComponentImpact(
                train,
                hitLocal,
                power,
                radius,
                maxDetach
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

                prop:SetRenderOrigin(nil)
                prop:SetRenderAngles(nil)
                prop:DisableMatrix("RenderMultiply")
                prop:SetNoDraw(true)
            end
        end

        local panelMap = train.MEXDamageV4PanelProps or BuildPanelPropMap(train)
        local panelName = panelMap[name]

        if panelName then
            DisableDetachedPanelControl(train, panelName, name)
        end
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
        local isDoor = IsDoorComponent(name, cached)
        local isControl = IsSmallControlComponent(name, cached, panelName)
        local isBreakaway = IsGeneralBreakawayComponent(
            name,
            cached,
            panelName
        )

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

    local function InstallBoneField(modelEnt, train, skipRoot)
        if not IsValid(modelEnt) or not IsValid(train) then return end
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
                    local displacement = LocalDisplacement(trainLocalPos, state)
                    if displacement:LengthSqr() < 0.0025 then continue end

                    local worldAng = matrix:GetAngles()
                    local trainLocalAng = ToTrainLocalAngle(train, worldAng)
                    local deformedPos = trainLocalPos + displacement
                    local deformedAng = DeformLocalAngle(
                        trainLocalPos,
                        trainLocalAng,
                        state
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
        InstallBoneField(train, train, true)
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
                InstallBoneField(prop, train, true)
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
            else
                -- Full saloon/interior models are kept at the train origin.
                -- Only their existing child bones are allowed to deform. This
                -- prevents the entire interior from "driving away" from the car.
                ClearClientPropRenderTransform(prop)
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

        ApplyClientEnts(train, state)
        ApplyLightDeformation(train, state)
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
