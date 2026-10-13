-- Metrostroi Expanded - Track Builder Tool
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

TOOL.Category = "Metrostroi Expanded"
TOOL.Name = "#tool.mex_track_builder.name"
TOOL.Command = nil
TOOL.ConfigName = ""

-- Only options actually used by the native original-model editor.
TOOL.ClientConVar = {
    native_mode = "straight",
    native_tunnel = "round",
    native_tracks = "1",
    native_radius = "4096",
    native_junction = "",
    native_branch = "2",
    native_model = "",
}

if CLIENT then
    language.Add("tool.mex_track_builder.name", "Track Builder")
    language.Add("tool.mex_track_builder.desc", "Build using only original Metrostroi MDL modules")
    language.Add("tool.mex_track_builder.0",
        "LMB: start/place | RMB: finish | R: remove aimed module | Shift+R: undo last placement")
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if not MEXNativeTrack then return false end

    local aim = trace.Hit and not trace.HitSky and trace.HitPos
        or (ply:GetShootPos() + ply:GetAimVector() * 800)
    if MEXNativeTrack then return MEXNativeTrack.Add(ply, aim, {
            mode = self:GetClientInfo("native_mode"),
            tunnel = self:GetClientInfo("native_tunnel"),
            tracks = self:GetClientNumber("native_tracks", 1),
            radius = self:GetClientNumber("native_radius", 4096),
            junction = self:GetClientInfo("native_junction"),
            branch = self:GetClientNumber("native_branch", 2),
            native_model = self:GetClientInfo("native_model"),
        }) end
    return false

end

function TOOL:RightClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if not MEXNativeTrack then return false end

    if MEXNativeTrack then return MEXNativeTrack.Finish(ply) end
    return false

end

function TOOL:Reload(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if not MEXNativeTrack then return false end
    -- R removes exactly the module under the crosshair, not the last module
    -- of its route. Shift+R is the explicit undo construction shortcut.
    if ply:KeyDown(IN_SPEED) then
        return MEXNativeTrack.Undo(ply)
    end
    return MEXNativeTrack.RemoveAimedModule(ply, trace and trace.Entity)
end

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", {
        Text = "Metrostroi Expanded - Original Track Builder",
        Description = "Real Metrostroi MDLs and their compiled physics only. No procedural tracks or tunnel shells.",
    })
    panel:Help("LMB: set the first connector, then place original modules.")
    panel:Help("RMB: save construction. R: delete only the module under your crosshair.")
    panel:Help("Shift + R: undo the last unsaved module. The rest of the route stays.")
    panel:Help("Grey = pending model. Green = start node. Orange = end node.")
    panel:NumSlider("Outdoor rail model brightness", "mex_native_outdoor_brightness", 0.35, 1.5, 2)
    panel:CheckBox("Show measured rail centerline overlay",
        "mex_native_show_measured_path")
    panel:Help("Installed MDL catalog: choose any mounted Metrostroi or Track Pack rail model.")
    panel:Help("Track profiles use REAL measured rails. Unknown meshes are rejected, not approximated.")
    local catalog = panel:ComboBox("Exact installed original model", "mex_track_builder_native_model")
    local function RefreshCatalog()
        if not IsValid(catalog) then return end
        catalog:Clear()
        catalog:AddChoice("Automatic stock Metrostroi models", "")
        local entries = {}
        if MEXNativeTrack and MEXNativeTrack.ModelCatalog then
            for name, info in pairs(MEXNativeTrack.ModelCatalog) do
                entries[#entries + 1] = {name, info}
            end
        end
        table.sort(entries, function(a,b) return a[1] < b[1] end)
        for _, entry in ipairs(entries) do
            local info = entry[2]
            local label = "[" .. (info.kind or "?") .. "] " .. entry[1]
            catalog:AddChoice(label, entry[1])
        end
    end
    if MEXNativeTrack then MEXNativeTrack.RefreshCatalogUI = RefreshCatalog end
    RefreshCatalog()
    panel:TextEntry("Original model path (manual selection)",
        "mex_track_builder_native_model")
    panel:Button("Rescan mounted Metrostroi + Track Pack models",
        "mex_native_rescan_models")
    panel:Help("Third-party folders: server admin may add a scan root with mex_native_catalog_root models/<folder>.")
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
    panel:Button("Undo last unsaved module (Shift+R)", "mex_native_undo")
    panel:Button("Remove aimed single module (R)", "mex_native_remove_aimed")
    panel:Button("Cancel construction", "mex_native_cancel")
    panel:Button("Delete entire aimed route (advanced)", "mex_native_delete_aimed")
    panel:Button("Show original-model status", "mex_native_status")
    panel:Button("Realign older saved curve modules", "mex_native_realign_routes")
    panel:Button("Check installed original curve models", "mex_native_curve_assets")
    panel:Button("List available original junction models", "mex_native_list_junction_models")
end
