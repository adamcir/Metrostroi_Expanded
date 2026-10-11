-- Metrostroi Expanded - Track Builder Tool
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

TOOL.Category = "Metrostroi Expanded"
TOOL.Name = "#tool.mex_track_builder.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    snap = "1", snap_distance = "48", snap_node_spacing = "192",
    show_snap_nodes = "1", auto_loop = "0",
    loop_min_radius = "3072", loop_max_grade = "4",
    network = "1", smooth = "1", curve_tension = "0.45",
    segment_length = "48", geometry_tolerance = "0.5",
    geometry_max_length = "192", min_curve_radius = "3072",
    tunnel_type = "none", tunnel_radius = "170",
    tunnel_width = "360", tunnel_height = "280",
    tunnel_wall = "12", tunnel_style = "metrostroi",
    track_count = "1", track_spacing = "240",
    inherit_double_profile = "1",
    rigid_section = "0", rigid_length = "0",
}

if CLIENT then
    language.Add("tool.mex_track_builder.name", "Track Builder")
    language.Add("tool.mex_track_builder.desc", "Build smooth persistent Metrostroi-compatible track routes in-game")
    language.Add("tool.mex_track_builder.0", "LMB: add/snap point | RMB: finish | R: undo last step, select endpoint (saved routes supported)")

    -- Older installations kept the former fixed-prefab + rectangular
    -- tunnel defaults in archived client convars. Migrate just once so
    -- existing users do not start in an invisible rigid-prefab mode.
    timer.Simple(0, function()
        local key = "mex_track_builder_tiled_migrated_v1"
        if cookie.GetNumber(key, 0) ~= 0 then return end
        RunConsoleCommand("mex_track_builder_rigid_section", "0")
        RunConsoleCommand("mex_track_builder_rigid_length", "0")
        RunConsoleCommand("mex_track_builder_tunnel_type", "none")
        cookie.Set(key, "1")
    end)
end

local function ReadSettings(tool)
    return {
        smooth = tool:GetClientNumber("smooth", 1),
        curve_tension = tool:GetClientNumber("curve_tension", 0.45),
        segment_length = tool:GetClientNumber("segment_length", 48),
        geometry_tolerance = tool:GetClientNumber("geometry_tolerance", 0.5),
        geometry_max_length = tool:GetClientNumber("geometry_max_length", 192),
        min_curve_radius = tool:GetClientNumber("min_curve_radius", 3072),
        tunnel_type = tool:GetClientInfo("tunnel_type"),
        tunnel_radius = tool:GetClientNumber("tunnel_radius", 170),
        tunnel_width = tool:GetClientNumber("tunnel_width", 360),
        tunnel_height = tool:GetClientNumber("tunnel_height", 280),
        tunnel_wall = tool:GetClientNumber("tunnel_wall", 12),
        tunnel_style = tool:GetClientInfo("tunnel_style"),
        track_count = tool:GetClientNumber("track_count", 1),
        track_spacing = tool:GetClientNumber("track_spacing", 240),
        inherit_double_profile = tool:GetClientNumber("inherit_double_profile", 1),
        rigid_section = tool:GetClientNumber("rigid_section", 0),
        rigid_length = tool:GetClientNumber("rigid_length", 0),
    }
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    if not trace.Hit or trace.HitSky then return false end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if not MEXTrackBuilder then return false end

    local pos = trace.HitPos
    local anchor

    if self:GetClientNumber("snap", 1) > 0
        and MEXTrackBuilder.SnapPoint
    then
        pos, anchor = MEXTrackBuilder.SnapPoint(
            pos,
            -- End-node markers sit BETWEEN each pair of rails. Aiming at
            -- one rail is 42.9 SU off-center; allow sufficient tolerance for
            -- reliable double-to-double joins even with the old 32-SU config.
            self:GetClientNumber("track_count", 1) == 2
                and math.max(64, self:GetClientNumber("snap_distance", 32))
                or self:GetClientNumber("snap_distance", 32),
            self:GetClientNumber("snap_node_spacing", 192),
            ReadSettings(self)
        )
    end

    local ok

    if self:GetClientNumber("auto_loop", 0) > 0
        and not (MEXTrackBuilder.Active and MEXTrackBuilder.Active[ply])
    then
        if not MEXTrackBuilder.AutoLoopClick then return false end

        ok = MEXTrackBuilder.AutoLoopClick(
            ply,
            pos,
            anchor,
            ReadSettings(self),
            self:GetClientNumber("loop_min_radius", 3072),
            self:GetClientNumber("loop_max_grade", 4),
            self:GetClientNumber("network", 1) > 0
        )
    else
        if not MEXTrackBuilder.AddPoint then return false end

        ok = MEXTrackBuilder.AddPoint(
            ply,
            pos,
            ReadSettings(self),
            anchor
        )
    end

    if ok then
        ply:EmitSound("buttons/button15.wav", 55, 110, 0.35)
    end

    return ok
end

function TOOL:RightClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if not MEXTrackBuilder then return false end

    if self:GetClientNumber("auto_loop", 0) > 0
        and not (MEXTrackBuilder.Active and MEXTrackBuilder.Active[ply])
    then
        if MEXTrackBuilder.CancelAutoLoop then
            return MEXTrackBuilder.CancelAutoLoop(ply)
        end
        return false
    end

    if not MEXTrackBuilder.FinishRoute then return false end

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
    if not MEXTrackBuilder or not MEXTrackBuilder.UndoLastPoint then return false end

    -- If a route is currently being drawn/edited, R undoes its last
    -- control point regardless of where the player is looking.
    -- Otherwise choose the aimed saved MEX route; if none is aimed,
    -- UndoLastPoint falls back to the most recently completed route.
    local routeID
    local ent = trace and trace.Entity
    if IsValid(ent) and ent:GetClass() == "mex_track_segment" then
        local id = ent:GetNW2Int("MEXRouteID", 0)
        if id > 0 then routeID = id end
    end

    local ok = MEXTrackBuilder.UndoLastPoint(ply, routeID)
    if ok then
        ply:EmitSound("buttons/button14.wav", 55, 110, 0.35)
    end
    return ok
end

local function BuildAdvancedPanel(panel)
    panel:Help("The builder uses original Metrostroi railroad16.mdl tiles.")
    panel:Help("All bends and straight sections share the same renderer and collision.")
    panel:CheckBox("Smooth curves", "mex_track_builder_smooth")
    panel:NumSlider("Curve tension", "mex_track_builder_curve_tension", 0.05, 0.85, 2)
    panel:NumSlider("Spline sample length (SU)", "mex_track_builder_segment_length", 16, 128, 0)
    panel:NumSlider("Maximum collision chord length (SU)", "mex_track_builder_geometry_max_length", 64, 256, 0)
    panel:NumSlider("Maximum chord deviation (SU)", "mex_track_builder_geometry_tolerance", 0.1, 2, 2)
    panel:Help("Short chords produce smooth curves without a solid track bed.")
    panel:CheckBox("Rigid straight section", "mex_track_builder_rigid_section")
    panel:NumSlider("Fixed straight length (0 = click distance)", "mex_track_builder_rigid_length", 0, 1024, 0)
    panel:CheckBox("Show attachment points", "mex_track_builder_show_snap_nodes")
    panel:CheckBox("Snap to existing track", "mex_track_builder_snap")
    panel:NumSlider("Snap distance", "mex_track_builder_snap_distance", 8, 128, 0)
    panel:NumSlider("Attachment spacing", "mex_track_builder_snap_node_spacing", 64, 512, 0)
    panel:NumSlider("Double-track center spacing", "mex_track_builder_track_spacing", 180, 400, 0)
    panel:CheckBox("Inherit connected double-track profile", "mex_track_builder_inherit_double_profile")
    panel:Help("Optional generated tunnel SHELL - original rails are never replaced.")
    local tunnel = panel:ComboBox("Tunnel type", "mex_track_builder_tunnel_type")
    tunnel:AddChoice("None (surface rails)", "none")
    tunnel:AddChoice("Round", "round")
    tunnel:AddChoice("Rectangular", "rectangular")
    tunnel:AddChoice("Wide", "wide")
    panel:NumSlider("Round inner radius", "mex_track_builder_tunnel_radius", 140, 320, 0)
    panel:NumSlider("Tunnel inside width", "mex_track_builder_tunnel_width", 300, 640, 0)
    panel:NumSlider("Tunnel inside height", "mex_track_builder_tunnel_height", 230, 480, 0)
    panel:NumSlider("Wall thickness", "mex_track_builder_tunnel_wall", 6, 32, 0)
    panel:CheckBox("Auto loop: create a safe circle", "mex_track_builder_auto_loop")
    panel:NumSlider("Auto loop minimum radius", "mex_track_builder_loop_min_radius", 1024, 8192, 0)
    panel:NumSlider("Auto loop maximum grade (%)", "mex_track_builder_loop_max_grade", 1, 8, 1)
end

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", {
        Text = "Metrostroi Expanded - Track Builder",
        Description = "Draw connected routes with original Metrostroi railroad16.mdl rails.",
    })
    panel:Help("LMB: add/attach point   RMB: finish   R: undo one step")
    panel:Help("Sharp curves are rejected. No long prefabricated rail models are required.")
    local layout = panel:ComboBox("Tracks", "mex_track_builder_track_count")
    layout:AddChoice("Single track", "1")
    layout:AddChoice("Double track", "2")
    panel:CheckBox("Smooth curves", "mex_track_builder_smooth")
    panel:NumSlider("Minimum safe curve radius", "mex_track_builder_min_curve_radius", 1024, 8192, 0)
    panel:CheckBox("Snap to track ends", "mex_track_builder_snap")
    panel:CheckBox("Show attachment points", "mex_track_builder_show_snap_nodes")
    panel:CheckBox("Add Metrostroi rail network", "mex_track_builder_network")
    local advanced = vgui.Create("DForm", panel)
    advanced:SetLabel("Advanced routing, tunnel and loop settings")
    BuildAdvancedPanel(advanced)
    advanced:SetExpanded(false)
    panel:AddItem(advanced)
    panel:Button("Finish route", "mex_track_builder_finish")
    panel:Button("Undo last step", "mex_track_builder_undo")
    panel:Button("Cancel construction", "mex_track_builder_cancel")
    panel:Button("Delete aimed route", "mex_track_builder_delete_aimed_route")
    panel:Button("Rebuild Metrostroi network", "mex_track_builder_rebuild")
    panel:Button("Check original track model", "mex_track_builder_model_status")
    panel:Button("Check track collisions", "mex_track_builder_collision_status")
end
