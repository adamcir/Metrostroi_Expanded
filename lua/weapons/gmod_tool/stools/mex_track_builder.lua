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
    native = "1", native_mode = "straight", native_tunnel = "round",
    native_tracks = "1", native_radius = "4096",
    native_junction = "", native_branch = "2",
}

if CLIENT then
    language.Add("tool.mex_track_builder.name", "Track Builder")
    language.Add("tool.mex_track_builder.desc", "Build using only original Metrostroi MDL modules")
    language.Add("tool.mex_track_builder.0", "LMB: set start / place original module | RMB: finish | R: undo last module")

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

    if MEXNativeTrack then return MEXNativeTrack.Add(ply, trace.HitPos, {
            mode = self:GetClientInfo("native_mode"),
            tunnel = self:GetClientInfo("native_tunnel"),
            tracks = self:GetClientNumber("native_tracks", 1),
            radius = self:GetClientNumber("native_radius", 4096),
            junction = self:GetClientInfo("native_junction"),
            branch = self:GetClientNumber("native_branch", 2),
        }) end
    return false

end

function TOOL:RightClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if not MEXTrackBuilder then return false end

    if MEXNativeTrack then return MEXNativeTrack.Finish(ply) end
    return false

end

function TOOL:Reload(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if MEXNativeTrack then return MEXNativeTrack.Undo(ply, trace and trace.Entity) end
    return false

end

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", {
        Text = "Metrostroi Expanded - Original Track Builder",
        Description = "Real Metrostroi MDLs and their compiled physics only. No procedural tracks or tunnel shells.",
    })
    panel:Help("LMB: select start, then build | RMB: save | R: undo one module")
    panel:Help("The grey translucent model is always a preview. Green and orange spheres are the start/end connectors.")
    local tunnel = panel:ComboBox("Original model family", "mex_track_builder_native_tunnel")
    tunnel:AddChoice("Round tunnel", "round")
    tunnel:AddChoice("Rectangular tunnel", "rectangular")
    tunnel:AddChoice("Wide double tunnel", "wide")
    tunnel:AddChoice("Surface track", "none")
    local tracks = panel:ComboBox("Track layout", "mex_track_builder_native_tracks")
    tracks:AddChoice("Single track", "1")
    tracks:AddChoice("Double track", "2")
    local mode = panel:ComboBox("Module / junction", "mex_track_builder_native_mode")
    mode:AddChoice("Straight - automatically combine original lengths", "straight")
    mode:AddChoice("Curve left - original segment", "curve_left")
    mode:AddChoice("Curve right - original segment", "curve_right")
    mode:AddChoice("Turnout - calibrated original model", "switch")
    mode:AddChoice("Rail crossing - calibrated original model", "crossing")
    local radius = panel:ComboBox("Original curve radius", "mex_track_builder_native_radius")
    radius:AddChoice("3072 SU", "3072")
    radius:AddChoice("4096 SU", "4096")
    radius:AddChoice("8192 SU", "8192")
    local installed = panel:ComboBox("Calibrated original junction", "mex_track_builder_native_junction")
    if MEXNativeTrack and MEXNativeTrack.Junctions then
        local ids = {}
        for id in pairs(MEXNativeTrack.Junctions) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do installed:AddChoice(id, id) end
    end
    panel:TextEntry("Junction profile ID (manual entry)", "mex_track_builder_native_junction")
    local branch = panel:ComboBox("Junction exit", "mex_track_builder_native_branch")
    branch:AddChoice("Port 2 - straight / main", "2")
    branch:AddChoice("Port 3 - diverging", "3")
    branch:AddChoice("Port 4 - crossing exit", "4")
    panel:Help("Turnouts and crossings require a registered original MDL and measured connector coordinates; unsafe or missing models cannot be placed.")
    panel:Help("Use server command mex_native_register_junction for custom installed Metrostroi Track Pack junctions.")
    panel:Button("Finish route", "mex_native_finish")
    panel:Button("Undo last module", "mex_native_undo")
    panel:Button("Cancel construction", "mex_native_cancel")
    panel:Button("Delete aimed saved route", "mex_native_delete_aimed")
    panel:Button("Show original-model status", "mex_native_status")
    panel:Button("List available original junction models", "mex_native_list_junction_models")
end
