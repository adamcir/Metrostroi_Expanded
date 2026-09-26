ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Metrostroi Expanded Damage Debris"
ENT.Spawnable = false
ENT.AdminOnly = false

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "SourceTrain")
    self:NetworkVar("String", 0, "ComponentName")
end
