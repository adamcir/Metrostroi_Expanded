-- Metrostroi Expanded - original model catalog / track construction tool
-- Copyright (C) 2026 Adam Cir / Adava Software - GPL-3.0

TOOL.Category = "Metrostroi Expanded"
TOOL.Name = "#tool.mex_track_builder.name"
TOOL.Command = nil
TOOL.ConfigName = ""

-- No tunnel/curve/length presets: each placed piece is a selected
-- authentic mounted Metrostroi or Track Pack MDL.
TOOL.ClientConVar = {
    native_model = "",
    native_reverse = "0",
    native_branch = "2",
    native_grade = "0",
    native_pair = "0",
    native_split = "0",
    native_spacing = "264",
    native_lane = "0",
    station_layout = "0",
    station_offset = "160",
}

if CLIENT then
    language.Add("tool.mex_track_builder.name", "Track Builder [ALPHA]")
    language.Add("tool.mex_track_builder.desc",
        "Browse original Metrostroi / Track Pack model catalog")
    language.Add("tool.mex_track_builder.0",
        "LMB: start/place selected model | RMB: finish | R: remove aimed | Shift+R: undo")
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() or not MEXNativeTrack then return false end
    local aim = trace.Hit and not trace.HitSky and trace.HitPos
        or (ply:GetShootPos() + ply:GetAimVector() * 800)
    return MEXNativeTrack.Add(ply, aim, {
        native_model = self:GetClientInfo("native_model"),
        native_reverse = self:GetClientNumber("native_reverse", 0),
        branch = self:GetClientNumber("native_branch", 2),
        grade = self:GetClientNumber("native_grade", 0),
        native_pair = self:GetClientNumber("native_pair", 0),
        native_lane = self:GetClientNumber("native_lane", 0),
        station_layout = self:GetClientNumber("station_layout", 0),
        station_offset = self:GetClientNumber("station_offset", 160),
        native_split = self:GetClientNumber("native_split", 0),
        native_spacing = self:GetClientNumber("native_spacing", 264),
    })
end

function TOOL:RightClick()
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() or not MEXNativeTrack then return false end
    return MEXNativeTrack.Finish(ply)
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() or not MEXNativeTrack then return false end
    if ply:KeyDown(IN_SPEED) then return MEXNativeTrack.Undo(ply) end
    return MEXNativeTrack.RemoveAimedModule(ply, trace and trace.Entity)
end

if CLIENT then
    local currentBrowser

    -- Use the standard GMod Derma skin for the model catalog and toolgun UI.
    -- Only model-preview lighting and selected-model outline are customized.

    local function TrackName(info)
        return info.name or string.StripExtension(
            string.GetFileFromFilename(info.model or ""))
    end

    local function SetupModelView(view, model, focused)
        view:SetModel(model)
        if not IsValid(view.Entity) then return end
        local mn, mx = view.Entity:GetRenderBounds()
        local center = (mn + mx) * 0.5
        local extent = mx - mn
        local longest = math.max(extent.x, extent.y, extent.z, 1)
        -- Long tunnel models often look like a tiny dot if the camera
        -- frames their full 4096-SU hull. Zoom the detail preview toward
        -- the real rail model, keeping scroll-wheel zoom available.
        local distance = focused
            and math.Clamp(longest * 0.65, 115, 650)
            or math.Clamp(longest * 0.9, 110, 390)
        view:SetLookAt(center)
        view:SetCamPos(center + Vector(distance, -distance, distance * 0.67))
        view:SetFOV(focused and 47 or 51)
        view:SetAmbientLight(Color(205, 215, 225))
        view:SetDirectionalLight(BOX_TOP, Color(230, 230, 230))
        view:SetDirectionalLight(BOX_FRONT, Color(155, 155, 155))
        view.LayoutEntity = function() end
        -- Do not replace DModelPanel:Paint or call DrawModel directly:
        -- its native Paint establishes the 3-D camera, viewport and lighting.
    end

    local function OpenModelCatalog()
        if IsValid(currentBrowser) then
            currentBrowser:MakePopup()
            currentBrowser:MoveToFront()
            return
        end

        local frame = vgui.Create("DFrame")
        currentBrowser = frame
        frame:SetTitle("Metrostroi Expanded | Track Model Catalog [ALPHA]")
        frame:SetSize(math.min(ScrW() - 45, 1060), math.min(ScrH() - 45, 755))
        frame:SetMinWidth(640)
        frame:SetMinHeight(475)
        frame:SetSizable(true)
        frame:Center()
        frame:MakePopup()
        local header = vgui.Create("DPanel", frame)
        header:Dock(TOP)
        header:SetTall(74)
        header:DockPadding(9, 8, 9, 7)
        local search = vgui.Create("DTextEntry", header)
        search:Dock(TOP)
        search:SetTall(27)
        search:SetPlaceholderText("Search original tracks and tunnels...")
        local filterBar = vgui.Create("DPanel", header)
        filterBar:Dock(TOP)
        filterBar:SetTall(29)
        filterBar:DockMargin(0, 5, 0, 0)
        filterBar:SetPaintBackground(false)

        local kindFilter = vgui.Create("DComboBox", filterBar)
        kindFilter:Dock(LEFT)
        kindFilter:SetWide(180)
        local filters = {
            {"All track pieces", "all"},
            {"Straight", "straight"},
            {"Curves", "curve"},
            {"Double track", "double"},
            {"Uphill / downhill", "slope"},
            {"Turnouts / crossings", "junction"},
        }
        for _, f in ipairs(filters) do kindFilter:AddChoice(f[1], f[2]) end
        kindFilter:ChooseOptionID(1)

        local sourceFilter = vgui.Create("DComboBox", filterBar)
        sourceFilter:Dock(LEFT)
        sourceFilter:SetWide(140)
        sourceFilter:DockMargin(7, 0, 0, 0)
        sourceFilter:AddChoice("All sources", "all")
        sourceFilter:AddChoice("Metrostroi", "Metrostroi")
        sourceFilter:AddChoice("Track Pack", "Track Pack")
        sourceFilter:ChooseOptionID(1)

        local rescan = vgui.Create("DButton", filterBar)
        rescan:Dock(RIGHT)
        rescan:SetWide(118)
        rescan:SetText("Refresh models")
        rescan.DoClick = function()
            if MEXNativeTrack and MEXNativeTrack.RequestCatalogRescan then
                MEXNativeTrack.RequestCatalogRescan()
            end
        end

        local footer = vgui.Create("DPanel", frame)
        footer:Dock(BOTTOM)
        footer:SetTall(42)
        footer:DockPadding(10, 6, 10, 6)
        local useModel = vgui.Create("DButton", footer)
        useModel:Dock(RIGHT)
        useModel:SetWide(150)
        useModel:SetText("Use selected model")
        local countText = vgui.Create("DLabel", footer)
        countText:Dock(FILL)
        countText:SetContentAlignment(4)

        local details = vgui.Create("DPanel", frame)
        details:Dock(RIGHT)
        details:SetWide(300)
        details:DockMargin(7, 8, 10, 8)
        details:DockPadding(9, 9, 9, 9)
        local name = vgui.Create("DLabel", details)
        name:Dock(TOP)
        name:SetTall(34)
        name:SetFont("DermaLarge")
        name:SetText("Choose a track model")

        local viewportBackground = vgui.Create("DPanel", details)
        viewportBackground:Dock(TOP)
        viewportBackground:SetTall(275)
        viewportBackground:DockMargin(0, 4, 0, 7)
        local preview = vgui.Create("DModelPanel", viewportBackground)
        preview:Dock(FILL)
        preview:SetMouseInputEnabled(true)
        local zoom = 1
        local originCam = Vector(120, -120, 80)
        preview.OnMouseWheeled = function(self, delta)
            local center = self:GetLookAt() or vector_origin
            zoom = math.Clamp(zoom * (delta > 0 and 0.83 or 1.20), 0.15, 8)
            self:SetCamPos(center + originCam * zoom)
            return true
        end
        preview.OnMousePressed = function(self, code)
            if code == MOUSE_LEFT then
                self.DraggingX = gui.MouseX()
                self:MouseCapture(true)
            end
        end
        preview.OnCursorMoved = function(self)
            if not self.DraggingX or not IsValid(self.Entity) then return end
            local now = gui.MouseX()
            local oldAngles = self.Entity:GetAngles()
            self.Entity:SetAngles(Angle(oldAngles.p, oldAngles.y +
                (now - self.DraggingX) * 0.4, oldAngles.r))
            self.DraggingX = now
        end
        preview.OnMouseReleased = function(self)
            self.DraggingX = nil
            self:MouseCapture(false)
        end

        local modelPath = vgui.Create("DLabel", details)
        modelPath:Dock(TOP)
        modelPath:SetTall(73)
        modelPath:SetWrap(true)
        modelPath:SetText("Select a model to see its real 3-D geometry.")

        local attributes = vgui.Create("DLabel", details)
        attributes:Dock(TOP)
        attributes:SetTall(42)
        attributes:SetWrap(true)
        attributes:SetText("Original Metrostroi / Track Pack assets only.")

        -- Advanced port choice appears ONLY for actual junction model
        -- selections; ordinary track users do not see irrelevant controls.
        local junctionPort = vgui.Create("DComboBox", details)
        junctionPort:Dock(TOP)
        junctionPort:SetTall(27)
        junctionPort:DockMargin(0, 0, 0, 5)
        junctionPort:AddChoice("Main route (port 2)", "2")
        junctionPort:AddChoice("Diverging route (port 3)", "3")
        junctionPort:AddChoice("Crossing exit (port 4)", "4")
        junctionPort:ChooseOptionID(1)
        junctionPort:SetVisible(false)
        junctionPort.OnSelect = function(_, _, _, port)
            RunConsoleCommand("mex_track_builder_native_branch", tostring(port or "2"))
        end

        local hint = vgui.Create("DLabel", details)
        hint:Dock(TOP)
        hint:SetTall(60)
        hint:SetWrap(true)
        hint:SetText("Drag the model to rotate. Scroll over the preview to zoom.")

        local scroll = vgui.Create("DScrollPanel", frame)
        scroll:Dock(FILL)
        scroll:DockMargin(9, 8, 0, 8)
        local grid = vgui.Create("DIconLayout", scroll)
        grid:Dock(TOP)
        grid:DockMargin(8, 8, 8, 8)
        grid:SetSpaceX(7)
        grid:SetSpaceY(7)

        local selectedConvar = GetConVar("mex_track_builder_native_model")
        local selected = selectedConvar and selectedConvar:GetString() or ""
        local matches = {}
        local loaded = 0
        local kind = "all"
        local source = "all"
        local BATCH = 24

        local function SelectModel(info)
            if not IsValid(frame) then return end
            selected = info.model
            RunConsoleCommand("mex_track_builder_native_model", selected)
            if info.double or info.kind == "junction" then
                RunConsoleCommand("mex_track_builder_native_pair", "0")
            end
            name:SetText(info.name or "Original track")
            modelPath:SetText(info.model)
            attributes:SetText((info.source or "Original") .. "   •   "
                .. (info.double and "DOUBLE TRACK" or
                    string.upper(info.kind or "track")))
            junctionPort:SetVisible(info.kind == "junction")
            details:InvalidateLayout(true)
            local errorText = MEXNativeTrack and
                MEXNativeTrack.CatalogErrors and MEXNativeTrack.CatalogErrors[selected]
            hint:SetText(errorText and ("Rail-end calibration: " .. errorText)
                or (info.double and
                    "Double model: 4 measured ports. Select 2x singles to continue both lanes."
                    or "Actual original MDL. Single pieces can snap to either lane of a double. Scroll to zoom."))
            SetupModelView(preview, selected, true)
            local center = preview:GetLookAt() or vector_origin
            originCam = preview:GetCamPos() - center
            zoom = 1
            for _, tile in ipairs(grid:GetChildren()) do
                if IsValid(tile) then tile.Selected = tile.ModelPath == selected end
            end
        end

        local function AppendBatch()
            if not IsValid(frame) or loaded >= #matches then return end
            local upper = math.min(#matches, loaded + BATCH)
            for i = loaded + 1, upper do
                local info = matches[i]
                local tile = grid:Add("DPanel")
                tile:SetSize(126, 142)
                tile.ModelPath = info.model
                tile.Selected = info.model == selected
                tile.Paint = function(self, w, h)
                    -- GMod's default panel skin, plus a simple selection
                    -- outline rather than a custom dark/green theme.
                    derma.SkinHook("Paint", "Panel", self, w, h)
                    if self.Selected then
                        surface.SetDrawColor(65, 130, 200, 255)
                        surface.DrawOutlinedRect(0, 0, w, h, 2)
                    end
                end
                -- Create full 3-D thumbnails only when actually visible
                -- in the scroll viewport, releasing offscreen ClientsideModels
                -- to avoid accumulating thousands of expensive renders.
                tile.Think = function(self)
                    if (self.NextVisibilityTest or 0) > CurTime() then return end
                    self.NextVisibilityTest = CurTime() + 0.23
                    if not IsValid(scroll) then return end
                    local _, y = self:LocalToScreen(0, 0)
                    local _, viewportY = scroll:LocalToScreen(0, 0)
                    local visible = y + self:GetTall() >= viewportY - 160
                        and y < viewportY + scroll:GetTall() + 160
                    if visible and not IsValid(self.Thumbnail) then
                        local thumb = vgui.Create("DModelPanel", self)
                        self.Thumbnail = thumb
                        thumb:SetPos(3, 3)
                        thumb:SetSize(120, 108)
                        SetupModelView(thumb, info.model, false)
                        thumb:SetTooltip(info.model)
                        thumb.OnMousePressed = function() SelectModel(info) end
                    elseif not visible and IsValid(self.Thumbnail) then
                        self.Thumbnail:Remove()
                        self.Thumbnail = nil
                    end
                end
                local label = vgui.Create("DButton", tile)
                label:SetPos(3, 113)
                label:SetSize(120, 26)
                label:SetFont("DermaDefault")
                label:SetText(TrackName(info))
                label:SetTooltip(info.model)
                label.DoClick = function() SelectModel(info) end
            end
            loaded = upper
            grid:InvalidateLayout(true)
            grid:SizeToChildren(false, true)
            countText:SetText(string.format(
                "%d matching original railway models   •   %d loaded",
                #matches, loaded))
        end

        local function Refresh()
            if not IsValid(frame) then return end
            matches = {}
            local catalog = MEXNativeTrack and MEXNativeTrack.ModelCatalog or {}
            local query = string.Trim(string.lower(search:GetValue() or ""))
            for _, info in pairs(catalog) do
                local matchesKind = kind == "all"
                    or (kind == "double" and info.double)
                    or (kind == "slope" and info.kind == "slope")
                    or (kind ~= "double" and kind ~= "slope"
                        and info.kind == kind)
                if matchesKind and (source == "all" or info.source == source)
                    and (query == "" or info.model:find(query, 1, true)) then
                    matches[#matches + 1] = info
                end
            end
            table.sort(matches, function(a, b) return a.model < b.model end)
            loaded = 0
            grid:Clear()
            local bar = scroll:GetVBar()
            if IsValid(bar) then bar:SetScroll(0) end
            AppendBatch()
            if #matches == 0 then
                countText:SetText("No railway segments match these filters.")
            end
        end

        search.OnValueChange = Refresh
        kindFilter.OnSelect = function(_, _, _, value)
            kind = value or "all"
            Refresh()
        end
        sourceFilter.OnSelect = function(_, _, _, value)
            source = value or "all"
            Refresh()
        end
        useModel.DoClick = function()
            if selected ~= "" then frame:Close() end
        end
        frame.Think = function()
            if loaded == #matches then return end
            if (frame.NextBatchAt or 0) > CurTime() then return end
            local bar = scroll:GetVBar()
            if not IsValid(bar) then return end
            if bar:GetScroll() + scroll:GetTall()
                > grid:GetTall() - 230 then
                frame.NextBatchAt = CurTime() + 0.15
                AppendBatch()
            end
        end
        frame.OnClose = function()
            if MEXNativeTrack and MEXNativeTrack.RefreshCatalogUI == Refresh then
                MEXNativeTrack.RefreshCatalogUI = nil
            end
            currentBrowser = nil
        end
        if MEXNativeTrack then MEXNativeTrack.RefreshCatalogUI = Refresh end
        Refresh()
        local info = MEXNativeTrack and MEXNativeTrack.ModelCatalog[selected]
        if info then SelectModel(info) end
        if not MEXNativeTrack or not next(MEXNativeTrack.ModelCatalog or {}) then
            if MEXNativeTrack and MEXNativeTrack.RequestCatalogRescan then
                MEXNativeTrack.RequestCatalogRescan()
            end
        end
    end

    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", {
            Text = "Metrostroi Expanded | Track Builder [ALPHA]",
            Description = "Experimental original Metrostroi / Track Pack railway construction tool.",
        })
        panel:Help("ALPHA: experimental, unfinished and may contain bugs or affect performance.")
        local open = panel:Button("Open track model catalog")
        open.DoClick = OpenModelCatalog
        panel:TextEntry("Selected model", "mex_track_builder_native_model")
        panel:CheckBox("Reverse rail direction", "mex_track_builder_native_reverse")
        panel:Help("Station starter (rail geometry only)")
        local station = vgui.Create("DComboBox")
        station:SetTall(26)
        station:AddChoice("Ordinary railway", 0)
        station:AddChoice("Station start: platform left / rail right", 1)
        station:AddChoice("Station start: island / two separate rails", 2)
        station:AddChoice("Station start: platform right / rail left", 3)
        station:AddChoice("Station start: side platforms / two rails", 4)
        station:AddChoice("Station start: central rail / both platforms", 5)
        local stationCvar = GetConVar("mex_track_builder_station_layout")
        station:ChooseOptionID((stationCvar and stationCvar:GetInt() or 0) + 1)
        station.OnSelect = function(_, _, _, value)
            RunConsoleCommand("mex_track_builder_station_layout", tostring(value))
        end
        panel:AddItem(station)
        panel:NumSlider("Station edge to rail offset (SU)",
            "mex_track_builder_station_offset", 90, 480, 0)
        panel:Help("Click the desired station reference line. Single rails use an original MDL; island and side platforms start two separately rendered original single MDLs. Station structures are not generated.")
        panel:NumSlider("Track grade (+up / -down), degrees",
            "mex_track_builder_native_grade", -20, 20, 1)
        panel:CheckBox("2x single rails (connect both ends of a double track)",
            "mex_track_builder_native_pair")
        local lane = vgui.Create("DComboBox")
        lane:SetTall(25)
        lane:AddChoice("Double connector: automatic (aim at rail)", 0)
        lane:AddChoice("Double connector: rail A only", 1)
        lane:AddChoice("Double connector: rail B only", 2)
        local laneCvar = GetConVar("mex_track_builder_native_lane")
        lane:ChooseOptionID((laneCvar and laneCvar:GetInt() or 0) + 1)
        lane.OnSelect = function(_, _, _, value)
            RunConsoleCommand("mex_track_builder_native_lane", tostring(value))
        end
        panel:AddItem(lane)
        panel:CheckBox("Split paired curves outward (left + right)",
            "mex_track_builder_native_split")
        panel:NumSlider("2x spacing when starting a free route (SU)",
            "mex_track_builder_native_spacing", 180, 480, 0)
        panel:Help("Up/down: set positive or negative grade on a new route. Existing rail-end pitch is inherited.")
        panel:Help("For separate construction: turn 2x OFF, choose rail A or B, and finish each lane independently. For simultaneous twin track: enable 2x. Curve end ports follow the measured original rail paths.")
        panel:Help("Finish a 2x section before switching back to a single or double MDL.")
        panel:Help("LMB: start/place   RMB: finish   R: remove   Shift+R: undo")
        panel:CheckBox("Show measured rail path",
            "mex_native_show_measured_path")
        panel:Button("Finish", "mex_native_finish")
        panel:Button("Cancel", "mex_native_cancel")
    end
end
