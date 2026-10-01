-- Metrostroi Expanded - Track Builder Tool
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

TOOL.Category = "Metrostroi Expanded"
TOOL.Name = "#tool.mex_track_builder.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    gauge = "80",
    rail_width = "4",
    rail_height = "7",
    sleeper_spacing = "32",
    sleeper_length = "128",
    sleeper_width = "10",
    sleeper_height = "5",
    snap = "1",
    snap_distance = "24",
    network = "1",
    smooth = "1",
    curve_tension = "0.45",
    segment_length = "48",
    use_track_model = "1",
    track_model = "models/metrostroi/tracks/railroad16.mdl",
}

if CLIENT then
    language.Add("tool.mex_track_builder.name", "Track Builder")
    language.Add("tool.mex_track_builder.desc", "Build smooth persistent Metrostroi-compatible track routes in-game")
    language.Add("tool.mex_track_builder.0", "LMB: add control point | RMB: finish route | Reload: delete aimed route or cancel")
end

local function ReadSettings(tool)
    return {
        gauge = tool:GetClientNumber("gauge", 80),
        rail_width = tool:GetClientNumber("rail_width", 4),
        rail_height = tool:GetClientNumber("rail_height", 7),
        sleeper_spacing = tool:GetClientNumber("sleeper_spacing", 32),
        sleeper_length = tool:GetClientNumber("sleeper_length", 128),
        sleeper_width = tool:GetClientNumber("sleeper_width", 10),
        sleeper_height = tool:GetClientNumber("sleeper_height", 5),
        smooth = tool:GetClientNumber("smooth", 1),
        curve_tension = tool:GetClientNumber("curve_tension", 0.45),
        segment_length = tool:GetClientNumber("segment_length", 48),
        use_track_model = tool:GetClientNumber("use_track_model", 1),
        track_model = tool:GetClientInfo("track_model"),
    }
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    if not trace.Hit or trace.HitSky then return false end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if not MEXTrackBuilder or not MEXTrackBuilder.AddPoint then return false end

    local pos = trace.HitPos
    if self:GetClientNumber("snap", 1) > 0 and MEXTrackBuilder.SnapPoint then
        pos = MEXTrackBuilder.SnapPoint(
            pos,
            self:GetClientNumber("snap_distance", 24)
        )
    end

    local ok = MEXTrackBuilder.AddPoint(ply, pos, ReadSettings(self))
    if ok then
        ply:EmitSound("buttons/button15.wav", 55, 110, 0.35)
    end

    return ok
end

function TOOL:RightClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if not MEXTrackBuilder or not MEXTrackBuilder.FinishRoute then return false end

    local ok = MEXTrackBuilder.FinishRoute(
        ply,
        self:GetClientNumber("network", 1) > 0
    )

    if ok then
        ply:EmitSound("buttons/button14.wav", 60, 105, 0.45)
    end

    return ok
end

function TOOL:Reload(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if not MEXTrackBuilder then return false end

    local ent = trace.Entity
    if IsValid(ent) and ent:GetClass() == "mex_track_segment" then
        local routeID = ent:GetNW2Int("MEXRouteID", 0)
        if routeID > 0 and MEXTrackBuilder.RemoveRoute then
            return MEXTrackBuilder.RemoveRoute(routeID, ply)
        end
    end

    if MEXTrackBuilder.CancelRoute then
        return MEXTrackBuilder.CancelRoute(ply)
    end

    return false
end

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", {
        Text = "Metrostroi Expanded - Track Builder",
        Description = "Place control points instead of hard track corners. MEX builds a smooth curve through them and writes the same smooth path into Metrostroi's track_<map>.txt network.",
    })

    panel:Help("Controls")
    panel:Help("LMB: place the first point and then additional control points.")
    panel:Help("RMB: finish and save the route.")
    panel:Help("Reload on a MEX track: remove the whole saved route.")
    panel:Help("Reload elsewhere: cancel the unfinished route.")

    panel:CheckBox("Smooth curves", "mex_track_builder_smooth")
    panel:NumSlider("Curve tension", "mex_track_builder_curve_tension", 0.1, 0.85, 2)
    panel:NumSlider("Smooth piece length", "mex_track_builder_segment_length", 16, 256, 0)
    panel:Help("Smaller = smoother curve. Default 48 SU; use 24-32 for tight bends.")

    panel:CheckBox("Use Metrostroi track model", "mex_track_builder_use_track_model")
    panel:Help("Smooth track uses the real Metrostroi railroad16.mdl tile. Long 1024-SU models are intentionally not used on curves.")

    panel:NumSlider("Track gauge (Source units)", "mex_track_builder_gauge", 40, 120, 1)
    panel:NumSlider("Fallback rail width", "mex_track_builder_rail_width", 1, 12, 1)
    panel:NumSlider("Fallback rail height", "mex_track_builder_rail_height", 1, 16, 1)
    panel:NumSlider("Fallback sleeper spacing", "mex_track_builder_sleeper_spacing", 12, 96, 0)
    panel:NumSlider("Fallback sleeper length", "mex_track_builder_sleeper_length", 80, 180, 0)
    panel:NumSlider("Fallback sleeper width", "mex_track_builder_sleeper_width", 4, 24, 1)
    panel:NumSlider("Fallback sleeper height", "mex_track_builder_sleeper_height", 1, 12, 1)

    panel:CheckBox("Snap to existing MEX track endpoints", "mex_track_builder_snap")
    panel:NumSlider("Endpoint snap distance", "mex_track_builder_snap_distance", 2, 96, 0)
    panel:CheckBox("Add route to Metrostroi rail network", "mex_track_builder_network")

    panel:Help("railroad16.mdl is repeated along the spline, so track pieces keep their normal proportions without the long-model fan effect.")
    panel:Help("If a selected Metrostroi model is missing, the tool falls back to procedural rails using Metrostroi materials.")
    panel:Help("The default gauge 80 SU is close to 1520 mm in Metrostroi scale.")

    panel:Button("Finish current route", "mex_track_builder_finish")
    panel:Button("Cancel unfinished route", "mex_track_builder_cancel")
    panel:Button("Rebuild Metrostroi network", "mex_track_builder_rebuild")
end
