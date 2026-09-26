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

    self:PhysicsInit(SOLID_VPHYSICS)
    local phys = self:GetPhysicsObject()

    if not IsValid(phys) then
        local mins = self.MEXFallbackMins
        local maxs = self.MEXFallbackMaxs

        if not isvector(mins) or not isvector(maxs) then
            mins = self:OBBMins()
            maxs = self:OBBMaxs()
        end

        if not isvector(mins) or not isvector(maxs)
            or (maxs - mins):LengthSqr() <= 1
        then
            mins = Vector(-4, -4, -4)
            maxs = Vector(4, 4, 4)
        end

        self:PhysicsInitBox(mins, maxs)
        phys = self:GetPhysicsObject()
    end

    if IsValid(phys) then
        phys:EnableMotion(true)
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
