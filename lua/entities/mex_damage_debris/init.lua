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

        if isvector(mins) and isvector(maxs) and (maxs - mins):LengthSqr() > 1 then
            self:PhysicsInitBox(mins, maxs)
            phys = self:GetPhysicsObject()
        end
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
