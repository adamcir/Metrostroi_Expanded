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
    min_curve_radius = "3072",
    experimental_native_curves = "1",
    fast_geometry = "1",
    tunnel_type = "rectangular",
    tunnel_radius = "170",
    tunnel_width = "360",
    tunnel_height = "280",
    tunnel_wall = "12",
    tunnel_style = "metrostroi",
    auto_native_models = "1",
    -- Original models contain their own conductor rail.
    stock_models_only = "1",
    use_track_model = "1",
    track_model = "models/metrostroi/tracks/railroad16.mdl",
    track_count = "1",
    track_spacing = "240",
    inherit_double_profile = "1",
    rigid_section = "1",
    rigid_length = "256",
    pack_model = "",
    pack_z_offset = "0",
    model_root = "models",
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
        min_curve_radius = tool:GetClientNumber("min_curve_radius", 3072),
        experimental_native_curves = tool:GetClientNumber("experimental_native_curves", 1),
        fast_geometry = tool:GetClientNumber("fast_geometry", 1),
        tunnel_type = tool:GetClientInfo("tunnel_type"),
        tunnel_radius = tool:GetClientNumber("tunnel_radius", 170),
        tunnel_width = tool:GetClientNumber("tunnel_width", 360),
        tunnel_height = tool:GetClientNumber("tunnel_height", 280),
        tunnel_wall = tool:GetClientNumber("tunnel_wall", 12),
        tunnel_style = tool:GetClientInfo("tunnel_style"),
        auto_native_models = tool:GetClientNumber("auto_native_models", 1),
        stock_models_only = tool:GetClientNumber("stock_models_only", 1),
        use_track_model = tool:GetClientNumber("use_track_model", 1),
        track_model = tool:GetClientInfo("track_model"),
        track_count = tool:GetClientNumber("track_count", 1),
        track_spacing = tool:GetClientNumber("track_spacing", 240),
        inherit_double_profile = tool:GetClientNumber("inherit_double_profile", 1),
        rigid_section = tool:GetClientNumber("rigid_section", 0),
        rigid_length = tool:GetClientNumber("rigid_length", 256),
        pack_model = tool:GetClientInfo("pack_model"),
        pack_z_offset = tool:GetClientNumber("pack_z_offset", 0),
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
    panel:Help("Advanced controls: geometry, snapping, model files and performance. Defaults are suitable for most routes.")

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

    panel:Help("Track layout / connections")
    local trackCount = panel:ComboBox("Track count", "mex_track_builder_track_count")
    trackCount:AddChoice("Single track", "1")
    trackCount:AddChoice("DOUBLE - two independent rail paths", "2")
    panel:NumSlider("DOUBLE track centre spacing (SU)", "mex_track_builder_track_spacing", 180, 400, 0)
    panel:CheckBox("Inherit connected DOUBLE tunnel profile", "mex_track_builder_inherit_double_profile")
    panel:Help("Snapping a new double tunnel to a double node inherits its track spacing and (by default) tunnel size/type, keeping the connection flush.")
    panel:Help("Each double-track tunnel has two separate nodes at each end AND along both rails. Clicking either node with Double selected snaps the entire next double tunnel to the same centerline.")
    panel:Help("Single selected + clicking a double node creates a single line attached to that lane. A full single/double transition is NOT yet generated.")

    panel:Help("Rigid straight section / station")
    panel:CheckBox("Rigid section (cannot curve)", "mex_track_builder_rigid_section")
    panel:NumSlider("Rigid section length (SU; 0 = click distance)", "mex_track_builder_rigid_length", 0, 1024, 0)
    panel:Help("A rigid route consists of exactly two endpoints. After second LMB, use RMB to finish. New sections can attach to either end without bending the saved station. Set length 64/256/1024 to match a Track Pack straight model.")

    panel:Help("Original Metrostroi and installed Track Pack models")
    local presets = panel:ComboBox("Verified Metrostroi prefabs (rigid)", "mex_track_builder_pack_model")
    presets:AddChoice("Automatic stock model (recommended)", "")
    presets:AddChoice("Round tunnel, 64 SU", "models/metrostroi/tracks/tunnel64.mdl")
    presets:AddChoice("Round tunnel, 256 SU", "models/metrostroi/tracks/tunnel256.mdl")
    presets:AddChoice("Round tunnel, 1024 SU", "models/metrostroi/tracks/tunnel1024.mdl")
    presets:AddChoice("Rectangular tunnel, 256 SU", "models/metrostroi/tracks/tunnel256_rect.mdl")
    presets:AddChoice("Rectangular tunnel, 1024 SU", "models/metrostroi/tracks/tunnel1024_rect.mdl")
    presets:AddChoice("Double tunnel, 1024 SU", "models/metrostroi/tracks/tunnel1024_double.mdl")
    panel:TextEntry("Custom Track Pack model path", "mex_track_builder_pack_model")
    panel:NumSlider("Pack MDL height adjustment (SU)", "mex_track_builder_pack_z_offset", -128, 128, 0)
    panel:TextEntry("Model scan root (GAME path)", "mex_track_builder_model_root")

    local foundModels = panel:ComboBox("Detected Track Pack models", "mex_track_builder_pack_model")
    local scanButton = vgui.Create("DButton", panel)
    scanButton:SetText("Scan installed rail / tunnel models")
    scanButton:SetTall(26)
    scanButton.DoClick = function()
        -- Scan only when requested. Searching every mounted .mdl per frame
        -- used to introduce huge lag on workshop-heavy installations.
        local rootCvar = GetConVar("mex_track_builder_model_root")
        local root = string.lower(rootCvar and rootCvar:GetString() or "models")
        root = string.gsub(root, "\\\\", "/")
        root = string.gsub(root, "/+$", "")
        if not string.match(root, "^models[%w_/%-]*$") then
            scanButton:SetText("Invalid model root (must start with models)")
            return
        end
        local queue = {root}
        local seen, found = {}, {}
        local visited = 0
        -- Never read outside the mounted GAME paths; includes Workshop addons.
        while #queue > 0 and visited < 500 and #found < 250 do
            local dir = table.remove(queue, 1)
            if not seen[dir] then
                seen[dir] = true
                visited = visited + 1
                local files, folders = file.Find(dir .. "/*", "GAME")
                for _, filename in ipairs(files or {}) do
                    local path = dir .. "/" .. filename
                    local lower = string.lower(path)
                    if string.EndsWith(lower, ".mdl")
                        and (string.find(lower, "rail", 1, true)
                        or string.find(lower, "metro", 1, true)
                        or string.find(lower, "tunnel", 1, true)
                        or string.find(lower, "arch", 1, true)
                        or string.find(lower, "_ns", 1, true)
                        or string.find(lower, "/rc", 1, true))
                        and util.IsValidModel(path)
                    then
                        found[#found + 1] = path
                        if #found >= 250 then break end
                    end
                end
                for _, folder in ipairs(folders or {}) do
                    local name = string.lower(folder)
                    local broad = dir == "models"
                    if not broad
                        or string.find(name, "metro", 1, true)
                        or string.find(name, "track", 1, true)
                        or string.find(name, "rail", 1, true)
                        or string.find(name, "tunnel", 1, true)
                        or string.find(name, "skay", 1, true)
                        or string.find(name, "alex", 1, true)
                    then
                        queue[#queue + 1] = dir .. "/" .. folder
                    end
                end
            end
        end
        table.sort(found)
        foundModels:Clear()
        for _, path in ipairs(found) do
            foundModels:AddChoice(path, path)
        end
        scanButton:SetText(string.format("Found %d models (%d folders scanned)", #found, visited))
        if #found == 0 then
            panel:Help("No matching models found. Set a more specific scan root, or paste the exact .mdl path from GMod's model browser.")
        end
    end
    panel:AddItem(scanButton)
    panel:Help("Track Pack Workshop 3536801478 is OPTIONAL and must be mounted. This uses actual files discovered in your installed GMod content; no fake model names are hardcoded. Non-rigid curves still use generated rails/tunnels.")
    panel:Help("A selected model must have approximately the same native length as the rigid section. Other models fall back to generated geometry; curved .mdl pieces are not stretched.")

    panel:Help("Classic Metrostroi tunnel")
    local style = panel:ComboBox("Tunnel appearance", "mex_track_builder_tunnel_style")
    style:AddChoice("Classic Metrostroi / Track Pack lining", "metrostroi")
    style:AddChoice("Basic geometry", "plain")
    panel:CheckBox("Use real Metrostroi models on exact straight sections", "mex_track_builder_auto_native_models")
    panel:CheckBox("Illuminate stock MDL tunnels on dark maps (client)", "mex_track_builder_native_tunnel_lighting")
    panel:Help("Classic prefers mounted original Metrostroi tunnel1024/256/64.mdl on exact straight sections. Curves use procedural tunnel geometry with correct repeating concrete and no stretched model texture atlases.")
    panel:Help("Rectangular / Wide classic tunnels include 12 signal cables, support clamps, precast wall seams and concrete ceiling ribs, matching the appearance of standard Metrostroi tunnels.")
    panel:Help("Running rails have a metal head/web/base with dark sleeper fasteners. Third-rail guard is yellow as on the original Metro. If content textures are absent, the mesh uses safe replacements.")

    panel:Help("Original Metrostroi models include their own third rail, sleepers and collision mesh. No duplicate contact rail is generated.")

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
    panel:Help("The shell follows the generated route. Double automatically widens the tunnel sufficiently for two running rails; a fitted Track Pack model replaces only the visible rigid section.")

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

-- The first screen should help players put REAL stock .mdl pieces in the
-- world, not bury key controls behind technical sliders.
function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", {
        Text = "Metrostroi Expanded - Track Builder",
        Description = "Build subway tunnels with real Metrostroi models. Connect the green endpoints to extend your network.",
    })

    panel:Help("1. TRACK AND TUNNEL")
    local profile = panel:ComboBox("Tunnel profile", "mex_track_builder_tunnel_type")
    profile:AddChoice("Rectangular - classic Metrostroi", "rectangular")
    profile:AddChoice("Round - bored tunnel", "round")
    profile:AddChoice("Wide - double-track tunnel", "wide")
    profile:AddChoice("Surface track - no tunnel", "none")

    local layout = panel:ComboBox("Track layout", "mex_track_builder_track_count")
    layout:AddChoice("Single track", "1")
    layout:AddChoice("Double track", "2")
    panel:CheckBox("Use original Metrostroi models", "mex_track_builder_auto_native_models")

    panel:Help("2. CONSTRUCTION METHOD")
    local mode = panel:ComboBox("Build mode", "mex_track_builder_rigid_section")
    mode:AddChoice("Fixed module (station / original prefab)", "1")
    mode:AddChoice("Flexible route (curves and slopes)", "0")
    local pieceLen = panel:ComboBox("Fixed module length", "mex_track_builder_rigid_length")
    pieceLen:AddChoice("64 Source units", "64")
    pieceLen:AddChoice("256 Source units", "256")
    pieceLen:AddChoice("1024 Source units", "1024")
    pieceLen:AddChoice("Custom click distance", "0")

    panel:CheckBox("EXPERIMENTAL: original Metrostroi curve models", "mex_track_builder_experimental_native_curves")
    panel:NumSlider("Minimum safe curve radius (SU)", "mex_track_builder_min_curve_radius", 1024, 8192, 0)
    panel:Help("Curves sharper than the minimum are REFUSED before spawning or saving. Double-track radius is checked on the inner track.")
    panel:Help("Original models only: match a 3072/4096/8192 SU right-hand turn. Unsupported bends are rejected, never replaced with a fake model.")
    panel:Help("Original compiled .mdl models and matching .phy collisions are lifted together by 5 SU. No separate third rail is generated.")

    panel:Help("3. ORIGINAL TRACK MODELS")
    panel:CheckBox("Original models ONLY (reject unsupported sections)", "mex_track_builder_stock_models_only")
    panel:Help("Default ON: No fake tunnel boxes or additional third rails are built. Unsupported curves and lengths are rejected with a useful message.")
    panel:Help("The stock .mdl provides the original third rail, and its .phy provides collision for rails, sleepers, lining and contact rail.")
    panel:CheckBox("Show attachment nodes", "mex_track_builder_show_snap_nodes")
    panel:CheckBox("Snap to existing track ends", "mex_track_builder_snap")
    panel:CheckBox("Register Metrostroi railway network", "mex_track_builder_network")
    panel:Button("Check installed original models", "mex_track_builder_model_status")
    panel:Help("Model status is printed to the game console. If an original asset is missing, fallback geometry is used.")

    panel:Help("4. BUILD")
    panel:Help("Left mouse: start / add point. Right mouse: finish. Reload (R): undo one step.")
    panel:Button("Finish route", "mex_track_builder_finish")
    panel:Button("Undo last step", "mex_track_builder_undo")
    panel:Button("Cancel construction", "mex_track_builder_cancel")
    panel:Button("Delete aimed route", "mex_track_builder_delete_aimed_route")

    local advanced = vgui.Create("DForm", panel)
    advanced:SetLabel("Advanced settings (models, snapping, geometry, performance)")
    BuildAdvancedPanel(advanced)
    advanced:SetExpanded(false)
    panel:AddItem(advanced)
end
