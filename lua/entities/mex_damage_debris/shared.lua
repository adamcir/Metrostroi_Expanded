ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Metrostroi Expanded Damage Debris"
ENT.Spawnable = false
ENT.AdminOnly = false

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "SourceTrain")
    self:NetworkVar("String", 0, "ComponentName")
    self:NetworkVar("Vector", 0, "VisualCenter")
    self:NetworkVar("Int", 0, "FrozenSequence")
    self:NetworkVar("Float", 0, "FrozenCycle")
    self:NetworkVar("Float", 1, "FrozenPosePosition")
end
