include("shared.lua")

ENT.AutomaticFrameAdvance = false

local function RotatedLocalOffset(ang, v)
    return
        ang:Forward() * v.x
        + ang:Right() * v.y
        + ang:Up() * v.z
end

function ENT:Draw()
    -- The physics entity lives at the visible geometry centre, while the MDL
    -- still expects its original model-space origin. Shift only rendering back
    -- by that model-space centre. Physics/Physgun therefore operate exactly
    -- where the detached part is visible.
    local center = self:GetVisualCenter()
    local renderOrigin = self:GetPos() - RotatedLocalOffset(
        self:GetAngles(),
        center
    )

    self:SetPlaybackRate(0)
    self:SetSequence(math.max(self:GetFrozenSequence(), 0))
    self:SetCycle(math.Clamp(self:GetFrozenCycle(), 0, 1))
    self:SetPoseParameter("position", self:GetFrozenPosePosition())

    self:SetRenderOrigin(renderOrigin)
    self:SetRenderAngles(self:GetAngles())
    self:DrawModel()
    self:SetRenderOrigin(nil)
    self:SetRenderAngles(nil)
end
