-- Metrostroi Expanded - Track Builder Tool
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

TOOL.Category = "Metrostroi Expanded"
TOOL.Name = "#tool.mex_track_builder.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    gauge = "85.8",
    rail_width = "5.8",
    rail_height = "10",
    sleeper_spacing = "32",
    sleeper_length = "128",
    sleeper_width = "10",
    sleeper_height = "5",
    snap = "1",
    snap_distance = "32",
    snap_node_spacing = "192",
    show_snap_nodes = "1",
    auto_loop = "0",
    loop_min_radius = "3072",
    loop_max_grade = "4",
    network = "1",
    smooth = "1",
    curve_tension = "0.45",
    segment_length = "48",
    geometry_tolerance = "0.5",
    geometry_max_length = "192",
    fast_geometry = "1",
    tunnel_type = "none",
    tunnel_radius = "170",
    tunnel_width = "360",
    tunnel_height = "280",
    tunnel_wall = "12",
    use_track_model = "1",
    track_model = "models/metrostroi/tracks/railroad16.mdl",
}

if CLIENT then
    language.Add("tool.mex_track_builder.name", "Track Builder")
    language.Add("tool.mex_track_builder.desc", "Build smooth persistent Metrostroi-compatible track routes in-game")
    language.Add("tool.mex_track_builder.0", "LMB: add/snap point | RMB: finish | R: undo last step, select endpoint (saved routes supported)")

    -- TOOL.ClientConVar is persistent. Upgrade the former 80/100 SU defaults
    -- to the native 85.8 SU rail-centre spacing, keeping custom settings.
    timer.Simple(1, function()
        local key = "mex_track_builder_gauge_migrated_v4"
        if cookie.GetNumber(key, 0) ~= 0 then return end
        local cv = GetConVar("mex_track_builder_gauge")
        if not cv then return end
        local previousGauge = cv:GetFloat()
        if math.abs(previousGauge - 80) < 0.01
            or math.abs(previousGauge - 100) < 0.01
        then
            RunConsoleCommand("mex_track_builder_gauge", "85.8")
        end
        cookie.Set(key, "1")
    end)
end

local function ReadSettings(tool)
    return {
        gauge = tool:GetClientNumber("gauge", 85.8),
        rail_width = tool:GetClientNumber("rail_width", 5.8),
        rail_height = tool:GetClientNumber("rail_height", 10),
        sleeper_spacing = tool:GetClientNumber("sleeper_spacing", 32),
        sleeper_length = tool:GetClientNumber("sleeper_length", 128),
        sleeper_width = tool:GetClientNumber("sleeper_width", 10),
        sleeper_height = tool:GetClientNumber("sleeper_height", 5),
        smooth = tool:GetClientNumber("smooth", 1),
        curve_tension = tool:GetClientNumber("curve_tension", 0.45),
        segment_length = tool:GetClientNumber("segment_length", 48),
        geometry_tolerance = tool:GetClientNumber("geometry_tolerance", 0.5),
        geometry_max_length = tool:GetClientNumber("geometry_max_length", 192),
        fast_geometry = tool:GetClientNumber("fast_geometry", 1),
        tunnel_type = tool:GetClientInfo("tunnel_type"),
        tunnel_radius = tool:GetClientNumber("tunnel_radius", 170),
        tunnel_width = tool:GetClientNumber("tunnel_width", 360),
        tunnel_height = tool:GetClientNumber("tunnel_height", 280),
        tunnel_wall = tool:GetClientNumber("tunnel_wall", 12),
        use_track_model = tool:GetClientNumber("use_track_model", 1),
        track_model = tool:GetClientInfo("track_model"),
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
            self:GetClientNumber("snap_distance", 32),
            self:GetClientNumber("snap_node_spacing", 192)
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

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", {
        Text = "Metrostroi Expanded - Track Builder",
        Description = "Place control points instead of hard track corners. MEX builds a smooth curve through them and writes the same smooth path into Metrostroi's track_<map>.txt network.",
    })

    panel:Help("Controls")
    panel:Help("Normal mode: LMB places control points; RMB finishes the route.")
    panel:Help("Auto Loop mode: first LMB marks the start, second LMB marks the end and immediately creates a safe loop.")
    panel:Help("RMB cancels a waiting Auto Loop start.")
    panel:Help("R / Reload: undo just ONE step, then the previous track endpoint is automatically selected for the next LMB. On a saved route, aim at its rail and press R to reopen and shorten it; further R presses step backward.")
    panel:Help("R never deletes a whole route at once. To remove an entire saved route, use the separate Delete aimed route button below.")

    panel:CheckBox("Smooth curves", "mex_track_builder_smooth")
    panel:NumSlider("Curve tension", "mex_track_builder_curve_tension", 0.1, 0.85, 2)
    panel:NumSlider("Smooth spline sampling (SU)", "mex_track_builder_segment_length", 16, 256, 0)
    panel:Help("The Metrostroi track graph remains densely sampled even if the physical geometry is optimized.")
    panel:CheckBox("FAST static rail meshes (recommended)", "mex_track_builder_fast_geometry")
    panel:CheckBox("Show sleepers / ties (client visual)", "mex_track_builder_draw_sleepers")
    panel:Help("If you still see a dark strip along surface track, temporarily disable sleepers to isolate the cause. This affects graphics only.")
    panel:NumSlider("Maximum physical chord length (SU)", "mex_track_builder_geometry_max_length", 64, 256, 0)
    panel:NumSlider("Maximum spline deviation (SU)", "mex_track_builder_geometry_tolerance", 0.1, 2, 2)
    panel:Help("Fewer physics bodies and cached GPU meshes reduce severe FPS drops and train judder. Keep tolerance near 0.5 SU for curves.")
    panel:CheckBox("Use legacy Metrostroi track model (if FAST disabled)", "mex_track_builder_use_track_model")
    panel:Help("Legacy mode repeats railroad16.mdl every 16 SU; this can be extremely slow on long lines.")

    panel:Help("Tunnel construction")
    local tunnel = panel:ComboBox("Tunnel type", "mex_track_builder_tunnel_type")
    tunnel:AddChoice("None - surface rails", "none")
    tunnel:AddChoice("Round - bored metro tunnel", "round")
    tunnel:AddChoice("Rectangular - cut and cover", "rectangular")
    tunnel:AddChoice("Wide - double-track-size profile", "wide")
    panel:NumSlider("Round internal radius (SU)", "mex_track_builder_tunnel_radius", 140, 320, 0)
    panel:NumSlider("Rectangular internal width (SU)", "mex_track_builder_tunnel_width", 300, 640, 0)
    panel:NumSlider("Rectangular internal height (SU)", "mex_track_builder_tunnel_height", 230, 480, 0)
    panel:NumSlider("Lining thickness (SU)", "mex_track_builder_tunnel_wall", 6, 32, 0)
    panel:Help("Tunnel is generated with the rails on the same route. The lining has a hollow collision shape, not a solid block. Wide mode is a wider SINGLE-track tube in this first version.")

    panel:NumSlider("Track gauge - rail centres (SU)", "mex_track_builder_gauge", 60, 120, 1)
    panel:NumSlider("Fallback rail width", "mex_track_builder_rail_width", 1, 12, 1)
    panel:Help("Correct Metrostroi spacing: 80 SU between the inner rail faces + 5.8 SU rail-head width = 85.8 SU from centre to centre. The default matches the 81-717 bogey and the native railroad16.mdl model.")
    panel:NumSlider("Fallback rail height", "mex_track_builder_rail_height", 1, 16, 1)
    panel:NumSlider("Fallback sleeper spacing", "mex_track_builder_sleeper_spacing", 12, 96, 0)
    panel:NumSlider("Fallback sleeper length", "mex_track_builder_sleeper_length", 80, 180, 0)
    panel:NumSlider("Fallback sleeper width", "mex_track_builder_sleeper_width", 4, 24, 1)
    panel:NumSlider("Fallback sleeper height", "mex_track_builder_sleeper_height", 1, 12, 1)

    panel:CheckBox("Show track attachment points", "mex_track_builder_show_snap_nodes")
    panel:CheckBox("Snap to track attachment points", "mex_track_builder_snap")
    panel:NumSlider("Attachment point spacing", "mex_track_builder_snap_node_spacing", 64, 512, 0)
    panel:NumSlider("Snap distance", "mex_track_builder_snap_distance", 4, 128, 0)
    panel:Help("Green points are route ends; blue points are reusable attachment points along the track. Their short line shows the tangent direction used for a smooth connection.")

    panel:CheckBox("AUTO LOOP - create a safe circle with two clicks", "mex_track_builder_auto_loop")
    panel:NumSlider("Auto Loop minimum radius (SU)", "mex_track_builder_loop_min_radius", 1024, 8192, 0)
    panel:NumSlider("Auto Loop maximum grade (%)", "mex_track_builder_loop_max_grade", 1, 8, 1)
    panel:Help("Auto Loop chooses the circle side that best matches snapped track tangents, uses the long circular arc, and enlarges the loop when needed to respect the requested radius/grade.")

    panel:CheckBox("Add route to Metrostroi rail network", "mex_track_builder_network")

    panel:Help("Fast mode uses one cached procedural GPU mesh per material and static rail collisions. It does not spam hundreds of 16-SU ClientsideModels.")
    panel:Help("Disable fast mode only to compare with the older detailed railroad16.mdl renderer.")
    panel:Help("At 85.8 SU, native Metrostroi tiles are not stretched. Only change this if you use custom rolling stock with a different wheel spacing.")

    panel:Button("Undo last step (R)", "mex_track_builder_undo")
    panel:Button("Finish current route", "mex_track_builder_finish")
    panel:Button("Cancel drawing / stop editing", "mex_track_builder_cancel")
    panel:Button("Delete aimed route (entire route)", "mex_track_builder_delete_aimed_route")
    panel:Button("Apply selected gauge to saved routes", "mex_track_builder_apply_gauge")
    panel:Help("Apply gauge to saved routes without deleting them. Previous default 80/100-SU layouts migrate automatically to 85.8 SU when reloaded.")
    panel:Button("Rebuild Metrostroi network", "mex_track_builder_rebuild")
    panel:Button("Rerail aimed Metrostroi train", "metrostroi_rerail")
    panel:Help("The normal Metrostroi rerailer and train spawner now also recognize saved MEX Track Builder rails.")
end
