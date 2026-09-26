AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    if not util.IsValidModel(self:GetModel() or "") then
        self:Remove()
        return
    end

    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    -- Always use a centred physics box. Metrostroi ClientEnt models are often
    -- authored with their model origin far away from the visible geometry.
    -- Using the model's stock VPhysics hull would make the collision touch the
    -- floor while the visible detached part appears to hover in mid-air.
    local mins = self.MEXFallbackMins
    local maxs = self.MEXFallbackMaxs

    if not isvector(mins) or not isvector(maxs)
        or (maxs - mins):LengthSqr() <= 1
    then
        mins = self:OBBMins()
        maxs = self:OBBMaxs()
    end

    if not isvector(mins) or not isvector(maxs)
        or (maxs - mins):LengthSqr() <= 1
    then
        mins = Vector(-4, -4, -4)
        maxs = Vector(4, 4, 4)
    end

    local half = (maxs - mins) * 0.5

    -- Slightly shrink the collision box so decorative empty space in the model
    -- bounds cannot hold the visible part above the ground.
    half = half * 0.88
    half.x = math.max(math.abs(half.x), 1.5)
    half.y = math.max(math.abs(half.y), 1.5)
    half.z = math.max(math.abs(half.z), 1.5)

    self:PhysicsInitBox(-half, half)

    self:SetPlaybackRate(0)
    self:SetSequence(math.max(self:GetFrozenSequence(), 0))
    self:SetCycle(math.Clamp(self:GetFrozenCycle(), 0, 1))
    self:SetPoseParameter("position", self:GetFrozenPosePosition())

    local phys = self:GetPhysicsObject()

    if IsValid(phys) then
        phys:EnableGravity(true)
        phys:EnableMotion(true)
        phys:EnableDrag(true)
        phys:EnableCollisions(true)
        phys:Wake()
    else
        self:SetMoveType(MOVETYPE_NONE)
    end
end

function ENT:PhysgunPickup(ply)
    return true
end

function ENT:CanTool(ply, trace, tool)
    return true
end

hook.Add("PhysgunPickup", "MEX.DamageDebris.Physgun", function(ply, ent)
    if IsValid(ent) and ent:GetClass() == "mex_damage_debris" then
        return true
    end
end)

hook.Add("GravGunPickupAllowed", "MEX.DamageDebris.GravGun", function(ply, ent)
    if IsValid(ent) and ent:GetClass() == "mex_damage_debris" then
        return true
    end
end)
