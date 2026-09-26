-- Metrostroi Expanded - Damage System
-- Simple directional crash damage and visual deformation for Metrostroi trains.
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

if SERVER then
    AddCSLuaFile()
end

MetrostroiExpandedDamage = MetrostroiExpandedDamage or {}
local MEXD = MetrostroiExpandedDamage

MEXD.Version = "0.3.1"

local ZONES = {
    front = true,
    rear = true,
    left = true,
    right = true,
}

local SU_TO_KMH = 0.09144 -- Source units/s (inches/s) -> km/h
local SPAWN_GRACE_SECONDS = 1.0

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
        MEXD.GetZoneDamage(train, "right")
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
    end

    return center
end

local function ZoneOutwardNormal(train, zone)
    if zone == "front" then return train:GetForward() end
    if zone == "rear" then return -train:GetForward() end
    if zone == "left" then return -train:GetRight() end
    if zone == "right" then return train:GetRight() end
    return train:GetUp()
end

local function UpdateDamageState(train)
    if not IsValid(train) then return end

    local front = MEXD.GetZoneDamage(train, "front")
    local rear = MEXD.GetZoneDamage(train, "rear")
    local left = MEXD.GetZoneDamage(train, "left")
    local right = MEXD.GetZoneDamage(train, "right")
    local overall = math.max(front, rear, left, right)

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

    local function InitializeTrainDamage(train)
        if not IsSubwayTrain(train) then return end
        if train.MEXDamageInitialized then return end

        train.MEXDamageInitialized = true
        train.MEXDamageIgnoreUntil = CurTime() + SPAWN_GRACE_SECONDS
        train.MEXDamageLastVelocity = train:GetVelocity()
        train.MEXDamageLastPosition = train:GetPos()
        train.MEXDamageLastSample = CurTime()
        train.MEXDamagePreviousSpeedKmh = train:GetVelocity():Length() * SU_TO_KMH

        train:SetNW2Bool("MEX.DamageReady", false)
        train:SetNW2Float("MEX.DamageReadyAt", train.MEXDamageIgnoreUntil)

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

        for zone in pairs(ZONES) do
            train:SetNW2Float(DamageKey(zone), 0)
            train:SetNW2Float("MEX.Damage.HitStrength." .. zone, 0)
            train:SetNW2Vector("MEX.Damage.HitLocal." .. zone, vector_origin)
        end

        train:SetNW2Float("MEX.Damage.electrical", 0)
        train:SetNW2Float("MEX.Damage.overall", 0)
        train:SetNW2Float("MEX.StructuralHealth", 1)

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

    local function ClassifyFromWorldDeltaVelocity(train, deltaVelocity)
        local x = deltaVelocity:Dot(train:GetForward())
        local y = deltaVelocity:Dot(train:GetRight())

        if math.abs(x) >= math.abs(y) then
            -- A front impact pushes/decelerates the train towards -local X.
            return x < 0 and "front" or "rear"
        end

        -- A hit on the right side pushes the train towards -local Y.
        return y < 0 and "right" or "left"
    end

    local function ClassifyFromWorldPosition(train, worldPos)
        if not isvector(worldPos) then return nil end

        local localPos = train:WorldToLocal(worldPos)
        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()

        local centerX = (mins.x + maxs.x) * 0.5
        local centerY = (mins.y + maxs.y) * 0.5

        local nx = math.abs(localPos.x - centerX) / math.max((maxs.x - mins.x) * 0.5, 1)
        local ny = math.abs(localPos.y - centerY) / math.max((maxs.y - mins.y) * 0.5, 1)

        if nx >= ny then
            return localPos.x >= centerX and "front" or "rear"
        end

        return localPos.y >= centerY and "right" or "left"
    end

    hook.Add("EntityTakeDamage", "MEX.Damage.FromEntityDamage", function(ent, dmginfo)
        if not IsSubwayTrain(ent) then return end

        InitializeTrainDamage(ent)
        if CurTime() < (ent.MEXDamageIgnoreUntil or 0) then return end
        if not (
            dmginfo:IsDamageType(DMG_CRUSH)
            or dmginfo:IsDamageType(DMG_BLAST)
        ) then
            return
        end

        local rawDamage = dmginfo:GetDamage()
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
            if deltaKmh < 8 then continue end
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
            local amount = math.Clamp((deltaKmh - 8) / 55, 0.02, 0.75)
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
            print("[Metrostroi Expanded/Damage] Zone must be: front, rear, left or right.")
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
            "[Metrostroi Expanded/Damage] %s | front %.2f rear %.2f left %.2f right %.2f | structural health %.2f | electrical %.2f",
            train:GetClass(),
            MEXD.GetZoneDamage(train, "front"),
            MEXD.GetZoneDamage(train, "rear"),
            MEXD.GetZoneDamage(train, "left"),
            MEXD.GetZoneDamage(train, "right"),
            train:GetNW2Float("MEX.StructuralHealth", 1),
            train:GetNW2Float("MEX.Damage.electrical", 0)
        ))
    end)
end



if CLIENT then
    ---------------------------------------------------------------------------
    -- Unified deformation field
    --
    -- The train body, interior ClientEnts and ButtonMap panels all use the
    -- exact same local-space mapping. This is important: a control must never
    -- be rendered somewhere different from the panel/hitbox that Metrostroi
    -- uses for mouse interaction.
    ---------------------------------------------------------------------------

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
        end

        return center
    end

    local function ReadHitLocal(train, zone)
        local strength = train:GetNW2Float("MEX.Damage.HitStrength." .. zone, 0)
        if strength <= 0.001 then
            return DefaultHitLocal(train, zone)
        end

        return train:GetNW2Vector(
            "MEX.Damage.HitLocal." .. zone,
            DefaultHitLocal(train, zone)
        )
    end

    local function GetDamageState(train)
        if not train:GetNW2Bool("MEX.DamageReady", false) then
            return nil
        end

        local front = train:GetNW2Float("MEX.Damage.front", 0)
        local rear = train:GetNW2Float("MEX.Damage.rear", 0)
        local left = train:GetNW2Float("MEX.Damage.left", 0)
        local right = train:GetNW2Float("MEX.Damage.right", 0)
        local overall = math.max(front, rear, left, right)

        if overall <= 0.001 then
            return nil
        end

        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()
        local center = (mins + maxs) * 0.5
        local halfLength = math.max((maxs.x - mins.x) * 0.5, 1)
        local halfWidth = math.max((maxs.y - mins.y) * 0.5, 1)
        local halfHeight = math.max((maxs.z - mins.z) * 0.5, 1)

        local hits = {
            front = ReadHitLocal(train, "front"),
            rear = ReadHitLocal(train, "rear"),
            left = ReadHitLocal(train, "left"),
            right = ReadHitLocal(train, "right"),
        }

        -- Main structural crush. Instead of scaling around the model origin,
        -- choose a pivot towards the opposite, less damaged side. This makes a
        -- front impact crush the cab while the far end stays much closer to its
        -- original position.
        local scale = Vector(
            1 - math.Clamp((front + rear) * 0.13, 0, 0.20),
            1 - math.Clamp((left + right) * 0.16, 0, 0.24),
            1 - math.Clamp(overall * 0.03, 0, 0.035)
        )

        local longitudinal = front + rear
        local lateral = left + right

        local pivot = Vector(center.x, center.y, center.z)
        if longitudinal > 0.001 then
            pivot.x = center.x
                + ((rear - front) / longitudinal) * halfLength * 0.82
        end
        if lateral > 0.001 then
            pivot.y = center.y
                + ((left - right) / lateral) * halfWidth * 0.82
        end

        -- Asymmetric impacts bend the body a little instead of producing a
        -- perfectly symmetric "scaled box".
        local yaw = 0
        local pitch = 0
        local roll = 0

        if front > 0 then
            yaw = yaw - front * math.Clamp((hits.front.y - center.y) / halfWidth, -1, 1) * 5.5
            pitch = pitch + front * math.Clamp((hits.front.z - center.z) / halfHeight, -1, 1) * 3.5
        end
        if rear > 0 then
            yaw = yaw + rear * math.Clamp((hits.rear.y - center.y) / halfWidth, -1, 1) * 5.5
            pitch = pitch - rear * math.Clamp((hits.rear.z - center.z) / halfHeight, -1, 1) * 3.5
        end
        if right > 0 then
            yaw = yaw + right * math.Clamp((hits.right.x - center.x) / halfLength, -1, 1) * 3.0
            roll = roll - right * math.Clamp((hits.right.z - center.z) / halfHeight, -1, 1) * 4.5
        end
        if left > 0 then
            yaw = yaw - left * math.Clamp((hits.left.x - center.x) / halfLength, -1, 1) * 3.0
            roll = roll + left * math.Clamp((hits.left.z - center.z) / halfHeight, -1, 1) * 4.5
        end

        local bend = Angle(
            math.Clamp(pitch, -5, 5),
            math.Clamp(yaw, -7, 7),
            math.Clamp(roll, -5, 5)
        )

        local affine = Matrix()
        affine:Translate(pivot)
        affine:Rotate(bend)
        affine:Scale(scale)
        affine:Translate(-pivot)

        return {
            front = front,
            rear = rear,
            left = left,
            right = right,
            overall = overall,
            mins = mins,
            maxs = maxs,
            center = center,
            halfLength = halfLength,
            halfWidth = halfWidth,
            halfHeight = halfHeight,
            hits = hits,
            scale = scale,
            bend = bend,
            affine = affine,
        }
    end

    local function SmoothFalloff(value)
        value = math.Clamp(value, 0, 1)
        return value * value * (3 - 2 * value)
    end

    -- Additional local "dent" displacement layered on top of the structural
    -- crush. It is deliberately continuous: objects embedded in the affected
    -- cab/salon volume receive nearly the same movement as the sheet metal
    -- around them, so the interior cannot visually separate from the carbody.
    local function LocalDentOffset(localPos, state)
        local out = Vector(0, 0, 0)

        local function frontRear(zone, damage, sign)
            if damage <= 0.001 then return end

            local hit = state.hits[zone]
            local surfaceX = sign < 0 and state.maxs.x or state.mins.x
            local depthIntoBody = sign < 0
                and (surfaceX - localPos.x)
                or (localPos.x - surfaceX)

            if depthIntoBody < -4 then return end

            local depthRange = 145 + damage * 95
            local depthFactor = 1 - math.Clamp(depthIntoBody / depthRange, 0, 1)

            local radiusY = 42 + damage * 42
            local radiusZ = 48 + damage * 38
            local dy = (localPos.y - hit.y) / radiusY
            local dz = (localPos.z - hit.z) / radiusZ
            local radial = 1 - math.Clamp(dy * dy + dz * dz, 0, 1)

            local influence = SmoothFalloff(radial) * SmoothFalloff(depthFactor)
            if influence <= 0 then return end

            local dentDepth = (10 + 34 * damage) * influence
            out.x = out.x + sign * dentDepth

            -- Pull material/attached equipment slightly towards the center of
            -- the impact, producing a crease instead of a flat translation.
            out.y = out.y + (hit.y - localPos.y) * 0.10 * damage * influence
            out.z = out.z + (hit.z - localPos.z) * 0.075 * damage * influence
        end

        local function side(zone, damage, sign)
            if damage <= 0.001 then return end

            local hit = state.hits[zone]
            local surfaceY = sign < 0 and state.maxs.y or state.mins.y
            local depthIntoBody = sign < 0
                and (surfaceY - localPos.y)
                or (localPos.y - surfaceY)

            if depthIntoBody < -4 then return end

            local depthRange = 78 + damage * 70
            local depthFactor = 1 - math.Clamp(depthIntoBody / depthRange, 0, 1)

            local radiusX = 78 + damage * 85
            local radiusZ = 45 + damage * 42
            local dx = (localPos.x - hit.x) / radiusX
            local dz = (localPos.z - hit.z) / radiusZ
            local radial = 1 - math.Clamp(dx * dx + dz * dz, 0, 1)

            local influence = SmoothFalloff(radial) * SmoothFalloff(depthFactor)
            if influence <= 0 then return end

            local dentDepth = (7 + 24 * damage) * influence
            out.y = out.y + sign * dentDepth
            out.x = out.x + (hit.x - localPos.x) * 0.075 * damage * influence
            out.z = out.z + (hit.z - localPos.z) * 0.065 * damage * influence
        end

        -- Sign is the inward direction.
        frontRear("front", state.front, -1)
        frontRear("rear", state.rear, 1)
        side("right", state.right, -1)
        side("left", state.left, 1)

        return out
    end

    local function DeformLocalPoint(localPos, state)
        local structurallyDeformed = state.affine * localPos
        return structurallyDeformed + LocalDentOffset(localPos, state)
    end

    local function DeformLocalAngle(localPos, localAng, state)
        local step = 6
        local p0 = DeformLocalPoint(localPos, state)
        local dx = DeformLocalPoint(localPos + localAng:Forward() * step, state) - p0
        local dy = DeformLocalPoint(localPos - localAng:Right() * step, state) - p0

        if dx:LengthSqr() < 0.0001 or dy:LengthSqr() < 0.0001 then
            return localAng
        end

        dx:Normalize()
        dy:Normalize()

        local up = dx:Cross(-dy)
        if up:LengthSqr() < 0.0001 then
            return localAng
        end

        up:Normalize()
        return dx:AngleEx(up)
    end

    local function LocalScaleAt(localPos, localAng, state)
        local step = 8
        local p0 = DeformLocalPoint(localPos, state)
        local px = DeformLocalPoint(localPos + localAng:Forward() * step, state)
        local py = DeformLocalPoint(localPos + localAng:Right() * step, state)
        local pz = DeformLocalPoint(localPos + localAng:Up() * step, state)

        return Vector(
            math.Clamp((px - p0):Length() / step, 0.72, 1.08),
            math.Clamp((py - p0):Length() / step, 0.72, 1.08),
            math.Clamp((pz - p0):Length() / step, 0.72, 1.08)
        )
    end

    ---------------------------------------------------------------------------
    -- Interactive controls
    --
    -- Metrostroi calculates panel aiming/clicks from ButtonMap every frame.
    -- Moving/rotating those panels from a third-party addon breaks interaction
    -- on several train classes because their own client code also updates the
    -- same data. Keep ButtonMap completely untouched.
    ---------------------------------------------------------------------------

    local function RestoreButtonMap(train)
        if not istable(train.ButtonMap) then return end

        if train.MEXDamageButtonMapOriginal then
            train.ButtonMap = train.MEXDamageButtonMapOriginal
            train.MEXDamageButtonMapOriginal = nil
        end

        train.MEXDamagePrivateButtonMap = nil
    end

    local function ApplyButtonMapDeformation(train, state)
        -- Intentionally disabled. Interactive panels must remain exactly where
        -- Metrostroi expects them so all switches, buttons and touchscreen
        -- controls keep working.
        RestoreButtonMap(train)
    end

    local function BuildInteractivePropSet(train)
        local set = {}

        if istable(train.ButtonMap) then
            for panelName, panel in pairs(train.ButtonMap) do
                if panelName ~= "BaseClass" and istable(panel) then
                    -- Some trains use ClientEnts named after the panel itself.
                    set[panelName] = true

                    if istable(panel.props) then
                        for _, propName in pairs(panel.props) do
                            if isstring(propName) then set[propName] = true end
                        end
                    end

                    if istable(panel.buttons) then
                        for _, button in pairs(panel.buttons) do
                            if istable(button) then
                                if isstring(button.PropName) then set[button.PropName] = true end
                                if isstring(button.ID) and string.sub(button.ID,1,1) ~= "!" then
                                    set[button.ID] = true
                                end

                                if istable(button.model) and isstring(button.model.name) then
                                    set[button.model.name] = true
                                end

                                if istable(button.lamp) and isstring(button.lamp.name) then
                                    set[button.lamp.name] = true
                                end
                            end
                        end
                    end
                end
            end
        end

        train.MEXDamageInteractiveProps = set
        return set
    end

    local function IsInteractiveProp(train, name)
        local set = train.MEXDamageInteractiveProps or BuildInteractivePropSet(train)
        return set[name] == true
    end

    ---------------------------------------------------------------------------
    -- ClientEnts: interior, panels, buttons, lamps, gauges, handles...
    ---------------------------------------------------------------------------

    local function ClearClientPropDeformation(train)
        if not istable(train.ClientEnts) then return end

        for _, prop in pairs(train.ClientEnts) do
            if not IsValid(prop) then continue end

            if prop.MEXDamageRenderOrigin then
                prop:SetRenderOrigin(nil)
                prop.MEXDamageRenderOrigin = nil
            end

            if prop.MEXDamageRenderAngles then
                prop:SetRenderAngles(nil)
                prop.MEXDamageRenderAngles = nil
            end

            if prop.MEXDamageMatrixApplied then
                prop:DisableMatrix("RenderMultiply")
                prop.MEXDamageMatrixApplied = nil
            end
        end
    end

    local function IsInteriorOrLargeClientProp(prop)
        if not IsValid(prop) then return false end

        local mins = prop:OBBMins()
        local maxs = prop:OBBMaxs()
        if not isvector(mins) or not isvector(maxs) then return false end

        local size = maxs - mins
        local model = string.lower(prop:GetModel() or "")

        local namedInterior =
            string.find(model, "interior", 1, true)
            or string.find(model, "salon", 1, true)
            or string.find(model, "cabin", 1, true)
            or string.find(model, "cabine", 1, true)
            or string.find(model, "panel", 1, true)

        return namedInterior
            or math.abs(size.x) >= 170
            or math.abs(size.y) >= 105
            or math.abs(size.z) >= 105
    end

    local function GetPropBaseLocalTransform(train, prop)
        -- Render origins/angles are drawing-only. The actual local transform
        -- remains the transform Metrostroi is animating.
        if prop:GetParent() == train then
            return prop:GetLocalPos(), prop:GetLocalAngles()
        end

        if prop.MEXDamageRenderOrigin then
            prop:SetRenderOrigin(nil)
            prop.MEXDamageRenderOrigin = nil
        end
        if prop.MEXDamageRenderAngles then
            prop:SetRenderAngles(nil)
            prop.MEXDamageRenderAngles = nil
        end

        local pos, ang = WorldToLocal(
            prop:GetPos(),
            prop:GetAngles(),
            train:GetPos(),
            train:GetAngles()
        )

        return pos, ang
    end

    local function EnsureBoneDentCallback(ent, train)
        if not IsValid(ent) or ent.MEXDamageBoneCallback then return end

        ent.MEXDamageBoneCallback = ent:AddCallback("BuildBonePositions", function(modelEnt, boneCount)
            if not IsValid(train) then return end
            local state = GetDamageState(train)
            if not state then return end
            if boneCount <= 1 then return end

            -- Bone 0 is normally the root. Moving it would just duplicate the
            -- whole-body RenderMultiply transform. Non-root bones can create
            -- genuine local deformation on models whose body/interior vertices
            -- are weighted to more than one bone.
            for bone = 1, boneCount - 1 do
                if modelEnt:GetBoneName(bone) == "__INVALIDBONE__" then continue end

                local matrix = modelEnt:GetBoneMatrix(bone)
                if not matrix then continue end

                local worldPos = matrix:GetTranslation()
                local localToTrain = train:WorldToLocal(worldPos)
                local dent = LocalDentOffset(localToTrain, state)

                if dent:LengthSqr() < 0.0025 then continue end

                matrix:SetTranslation(
                    train:LocalToWorld(localToTrain + dent)
                )

                modelEnt:SetBoneMatrix(bone, matrix)
            end
        end)
    end

    local function ApplyClientPropDeformation(train, state)
        if not istable(train.ClientEnts) then return end

        for name, prop in pairs(train.ClientEnts) do
            if not IsValid(prop) then continue end

            -- Never move a visual control away from the exact coordinates used
            -- by Metrostroi's ButtonMap hit testing. This includes panel models,
            -- switches, buttons, gauges, touchscreens and their generated props.
            if IsInteractiveProp(train, name) then
                if prop.MEXDamageRenderOrigin then
                    prop:SetRenderOrigin(nil)
                    prop.MEXDamageRenderOrigin = nil
                end
                if prop.MEXDamageRenderAngles then
                    prop:SetRenderAngles(nil)
                    prop.MEXDamageRenderAngles = nil
                end
                if prop.MEXDamageMatrixApplied then
                    prop:DisableMatrix("RenderMultiply")
                    prop.MEXDamageMatrixApplied = nil
                end
                continue
            end

            local basePos, baseAng = GetPropBaseLocalTransform(train, prop)
            local deformedPos = DeformLocalPoint(basePos, state)
            local deformedAng = DeformLocalAngle(basePos, baseAng, state)

            prop:SetRenderOrigin(train:LocalToWorld(deformedPos))
            prop:SetRenderAngles(train:LocalToWorldAngles(deformedAng))
            prop.MEXDamageRenderOrigin = true
            prop.MEXDamageRenderAngles = true

            if IsInteriorOrLargeClientProp(prop) then
                local localScale = LocalScaleAt(basePos, baseAng, state)
                local matrix = Matrix()
                matrix:Scale(localScale)
                prop:EnableMatrix("RenderMultiply", matrix)
                prop.MEXDamageMatrixApplied = true

                EnsureBoneDentCallback(prop, train)
            elseif prop.MEXDamageMatrixApplied then
                prop:DisableMatrix("RenderMultiply")
                prop.MEXDamageMatrixApplied = nil
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Main body
    ---------------------------------------------------------------------------

    local function EnsureTrainBoneDentCallback(train)
        if train.MEXDamageTrainBoneCallback then return end

        train.MEXDamageTrainBoneCallback = train:AddCallback("BuildBonePositions", function(ent, boneCount)
            local state = GetDamageState(ent)
            if not state or boneCount <= 1 then return end

            for bone = 1, boneCount - 1 do
                if ent:GetBoneName(bone) == "__INVALIDBONE__" then continue end

                local matrix = ent:GetBoneMatrix(bone)
                if not matrix then continue end

                local worldPos = matrix:GetTranslation()
                local localPos = ent:WorldToLocal(worldPos)
                local dent = LocalDentOffset(localPos, state)

                if dent:LengthSqr() < 0.0025 then continue end

                matrix:SetTranslation(ent:LocalToWorld(localPos + dent))
                ent:SetBoneMatrix(bone, matrix)
            end
        end)
    end

    local function ClearTrainDeformation(train)
        if train.MEXDamageMatrixApplied then
            train:DisableMatrix("RenderMultiply")
            train.MEXDamageMatrixApplied = nil
        end

        ClearClientPropDeformation(train)
        RestoreButtonMap(train)
    end

    local function ApplyVisualDeformation(train, state)
        if not state then
            ClearTrainDeformation(train)
            return
        end

        train:EnableMatrix("RenderMultiply", state.affine)
        train.MEXDamageMatrixApplied = true

        EnsureTrainBoneDentCallback(train)
        ApplyButtonMapDeformation(train, state)
        ApplyClientPropDeformation(train, state)
    end

    -- Run after Metrostroi's Think code has updated all animated ClientEnts.
    -- ButtonMap positions are changed before Metrostroi's next panel aiming pass,
    -- so rendered controls and clickable hitboxes stay in the same place.
    local nextDeformationUpdate = 0
    hook.Add("Think", "MEX.Damage.UpdateUnifiedDeformation", function()
        if CurTime() < nextDeformationUpdate then return end
        nextDeformationUpdate = CurTime() + 0.01

        for _, train in ipairs(ents.GetAll()) do
            if IsSubwayTrain(train) then
                ApplyVisualDeformation(train, GetDamageState(train))
            end
        end
    end)

    -- Reapply immediately before render because some train scripts reposition
    -- client props later in the frame (wagon numbers are one example).
    hook.Add("PreDrawOpaqueRenderables", "MEX.Damage.RenderAttachedParts", function()
        for _, train in ipairs(ents.GetAll()) do
            if not IsSubwayTrain(train) then continue end
            local state = GetDamageState(train)
            if state then
                ApplyClientPropDeformation(train, state)
            end
        end
    end)

    hook.Add("PreDrawTranslucentRenderables", "MEX.Damage.RenderAttachedTransparentParts", function()
        for _, train in ipairs(ents.GetAll()) do
            if not IsSubwayTrain(train) then continue end
            local state = GetDamageState(train)
            if state then
                ApplyClientPropDeformation(train, state)
            end
        end
    end)

    concommand.Add("mex_controls_restore", function()
        for _, train in ipairs(ents.GetAll()) do
            if IsSubwayTrain(train) then
                RestoreButtonMap(train)
                train.MEXDamageInteractiveProps = nil
                ClearClientPropDeformation(train)
            end
        end

        chat.AddText(Color(120,255,120), "[Metrostroi Expanded] Control panels restored.")
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

        if amount >= 0.18 then
            local dlight = DynamicLight(train:EntIndex())
            if dlight then
                dlight.pos = worldPos
                dlight.r = 255
                dlight.g = 150
                dlight.b = 70
                dlight.brightness = math.Clamp(amount * 3, 0.5, 2.5)
                dlight.Decay = 1600
                dlight.Size = math.Clamp(80 + amount * 120, 80, 200)
                dlight.DieTime = CurTime() + 0.08
            end
        end

        if amount >= 0.42 then
            local emitter = ParticleEmitter(worldPos)
            if emitter then
                for i = 1, math.floor(2 + amount * 4) do
                    local particle = emitter:Add("particle/particle_smokegrenade", worldPos)
                    if particle then
                        particle:SetVelocity(normal * math.Rand(8, 28) + VectorRand() * 8)
                        particle:SetDieTime(math.Rand(0.7, 1.5))
                        particle:SetStartAlpha(math.random(55, 90))
                        particle:SetEndAlpha(0)
                        particle:SetStartSize(math.Rand(4, 8))
                        particle:SetEndSize(math.Rand(15, 25))
                        particle:SetRoll(math.Rand(-180, 180))
                        particle:SetRollDelta(math.Rand(-0.5, 0.5))
                        particle:SetAirResistance(80)
                        particle:SetGravity(Vector(0, 0, math.Rand(4, 10)))
                    end
                end
                emitter:Finish()
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Debug
    ---------------------------------------------------------------------------

    local function HasAnyDamage(train)
        return train:GetNW2Float("MEX.Damage.overall", 0) > 0.001
    end

    hook.Add("PostDrawTranslucentRenderables", "MEX.Damage.DebugState", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:IsAdmin() then return end
        if not GetConVar("developer") or GetConVar("developer"):GetInt() < 2 then return end

        for _, train in ipairs(ents.GetAll()) do
            if IsSubwayTrain(train) and HasAnyDamage(train) then
                local pos = train:GetPos() + train:GetUp() * (train:OBBMaxs().z + 25)
                local ang = Angle(0, ply:EyeAngles().y - 90, 90)
                cam.Start3D2D(pos, ang, 0.1)
                    draw.SimpleTextOutlined(
                        string.format(
                            "F %.0f%%  R %.0f%%  L %.0f%%  P %.0f%%",
                            train:GetNW2Float("MEX.Damage.front", 0) * 100,
                            train:GetNW2Float("MEX.Damage.rear", 0) * 100,
                            train:GetNW2Float("MEX.Damage.left", 0) * 100,
                            train:GetNW2Float("MEX.Damage.right", 0) * 100
                        ),
                        "DermaDefaultBold",
                        0,
                        0,
                        Color(255, 220, 120),
                        TEXT_ALIGN_CENTER,
                        TEXT_ALIGN_CENTER,
                        1,
                        Color(0, 0, 0)
                    )
                cam.End3D2D()
            end
        end
    end)

    hook.Add("EntityRemoved", "MEX.Damage.CleanupClientState", function(ent)
        if not ent.MEXDamageMatrixApplied then return end
        if ent.DisableMatrix then
            ent:DisableMatrix("RenderMultiply")
        end
    end)
end
