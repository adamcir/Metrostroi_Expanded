-- Metrostroi Expanded - Damage System
-- Simple directional crash damage and visual deformation for Metrostroi trains.
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

if SERVER then
    AddCSLuaFile()
end

MetrostroiExpandedDamage = MetrostroiExpandedDamage or {}
local MEXD = MetrostroiExpandedDamage

MEXD.Version = "0.2.0"

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
    local function GetDeformationTransform(train)
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
        local length = math.max(maxs.x - mins.x, 1)
        local width = math.max(maxs.y - mins.y, 1)
        local height = math.max(maxs.z - mins.z, 1)

        -- This is the same transform used by the carbody itself. Child/client
        -- props must use the same local-space mapping or they remain behind
        -- while the body gets compressed.
        local scale = Vector(
            1 - math.Clamp(0.075 * front + 0.075 * rear, 0, 0.14),
            1 - math.Clamp(0.10 * left + 0.10 * right, 0, 0.16),
            1 - math.Clamp(overall * 0.025, 0, 0.025)
        )

        local translate = Vector(
            (rear - front) * length * 0.0375,
            (left - right) * width * 0.05,
            -overall * height * 0.006
        )

        return {
            scale = scale,
            translate = translate,
            front = front,
            rear = rear,
            left = left,
            right = right,
            overall = overall,
        }
    end

    local function DeformLocalPosition(localPos, transform)
        return Vector(
            localPos.x * transform.scale.x + transform.translate.x,
            localPos.y * transform.scale.y + transform.translate.y,
            localPos.z * transform.scale.z + transform.translate.z
        )
    end

    local function ClearClientPropDeformation(train)
        if not istable(train.ClientEnts) then return end

        for _, prop in pairs(train.ClientEnts) do
            if IsValid(prop) then
                if prop.MEXDamageRenderOrigin then
                    prop:SetRenderOrigin(nil)
                    prop.MEXDamageRenderOrigin = nil
                end

                if prop.MEXDamageMatrixApplied then
                    prop:DisableMatrix("RenderMultiply")
                    prop.MEXDamageMatrixApplied = nil
                end
            end
        end
    end

    local function IsInteriorOrLargeClientProp(train, prop)
        if not IsValid(prop) then return false end

        local mins = prop:OBBMins()
        local maxs = prop:OBBMaxs()
        if not isvector(mins) or not isvector(maxs) then return false end

        local size = maxs - mins
        local model = string.lower(prop:GetModel() or "")

        -- Full salon/cab shells are commonly separate Metrostroi ClientEnts.
        -- Detect them by both geometry and conventional model naming.
        local namedInterior =
            string.find(model, "interior", 1, true)
            or string.find(model, "salon", 1, true)
            or string.find(model, "cabin", 1, true)
            or string.find(model, "cabine", 1, true)
            or string.find(model, "cab_", 1, true)

        local large =
            math.abs(size.x) >= 180
            or math.abs(size.y) >= 110
            or math.abs(size.z) >= 110

        if not large and not namedInterior then return false end

        -- RenderMultiply is in the prop's local axes. Use it only where those
        -- axes are close enough to the train axes; all other props still get
        -- their anchor point moved with the damaged structure.
        local forwardAlignment = math.abs(prop:GetForward():Dot(train:GetForward()))
        local rightAlignment = math.abs(prop:GetRight():Dot(train:GetRight()))

        return forwardAlignment >= 0.90 and rightAlignment >= 0.90
    end

    local function ApplyClientPropDeformation(train, transform)
        if not istable(train.ClientEnts) then return end

        for name, prop in pairs(train.ClientEnts) do
            if not IsValid(prop) then continue end

            -- ClientEnts include the salon/interior shell, cab equipment,
            -- panels, switches, gauges, lamps and buttons. Almost all standard
            -- Metrostroi ClientEnts are parented directly to the train.
            --
            -- IMPORTANT: SetRenderOrigin changes what GetPos() reports, so using
            -- GetPos() again on the next frame would recursively deform the
            -- already-deformed render position. GetLocalPos() remains the real
            -- attachment position maintained by Metrostroi and therefore gives
            -- us a stable, non-accumulating anchor for every frame.
            local baseLocalPos
            if prop:GetParent() == train then
                baseLocalPos = prop:GetLocalPos()
            else
                -- Fallback for third-party ClientEnts that are not parented to
                -- the train. Temporarily clear our render override before
                -- reading their real world position.
                if prop.MEXDamageRenderOrigin then
                    prop:SetRenderOrigin(nil)
                    prop.MEXDamageRenderOrigin = nil
                end
                baseLocalPos = train:WorldToLocal(prop:GetPos())
            end

            local deformedLocalPos = DeformLocalPosition(baseLocalPos, transform)
            local deformedWorldPos = train:LocalToWorld(deformedLocalPos)

            prop:SetRenderOrigin(deformedWorldPos)
            prop.MEXDamageRenderOrigin = true

            -- Keep rigid detail props (buttons, handles, gauges...) rigid, but
            -- move their attachment point with the same deformed panel/body.
            -- Their normal Metrostroi angles/animations remain untouched.

            -- Large salon/cab/interior shells are part of the structure and
            -- therefore receive the same compression as the outer carbody.
            if IsInteriorOrLargeClientProp(train, prop) then
                local matrix = Matrix()
                matrix:Scale(transform.scale)
                prop:EnableMatrix("RenderMultiply", matrix)
                prop.MEXDamageMatrixApplied = true
            elseif prop.MEXDamageMatrixApplied then
                prop:DisableMatrix("RenderMultiply")
                prop.MEXDamageMatrixApplied = nil
            end
        end
    end

    local function ApplyVisualDeformation(train, transform)
        if not transform then
            if train.MEXDamageMatrixApplied then
                train:DisableMatrix("RenderMultiply")
                train.MEXDamageMatrixApplied = nil
            end

            ClearClientPropDeformation(train)
            return
        end

        local matrix = Matrix()
        matrix:Scale(transform.scale)
        matrix:SetTranslation(transform.translate)

        train:EnableMatrix("RenderMultiply", matrix)
        train.MEXDamageMatrixApplied = true

        ApplyClientPropDeformation(train, transform)
    end

    -- Use render hooks rather than Think. Metrostroi may update panel/button,
    -- door and interior ClientEnt positions during Think; applying the damage
    -- mapping immediately before rendering keeps every visible child attached
    -- to the same deformed structure without fighting its animation code.
    hook.Add("PreDrawOpaqueRenderables", "MEX.Damage.UpdateVisualDeformation", function()
        for _, train in ipairs(ents.GetAll()) do
            if IsSubwayTrain(train) then
                ApplyVisualDeformation(train, GetDeformationTransform(train))
            end
        end
    end)

    hook.Add("PreDrawTranslucentRenderables", "MEX.Damage.UpdateTransparentClientProps", function()
        -- Some Metrostroi client props are rendered in translucent groups.
        -- Reapply the same origins so those props stay attached as well.
        for _, train in ipairs(ents.GetAll()) do
            if IsSubwayTrain(train) then
                local transform = GetDeformationTransform(train)
                if transform then
                    ApplyClientPropDeformation(train, transform)
                end
            end
        end
    end)

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

    hook.Add("EntityRemoved", "MEX.Damage.ClearRemovedTrainClientProps", function(ent)
        if not ent.MEXDamageMatrixApplied then return end
        if ent.DisableMatrix then
            ent:DisableMatrix("RenderMultiply")
        end
    end)
end
