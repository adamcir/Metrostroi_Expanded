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
}

if CLIENT then
    language.Add("tool.mex_track_builder.name", "Track Builder")
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
    local function TitleFor(info)
        local name = info.name or string.GetFileFromFilename(info.model or "")
        return name ~= "" and name or "Original model"
    end

    local function OpenModelCatalog()
        if IsValid(currentBrowser) then
            currentBrowser:MakePopup()
            currentBrowser:MoveToFront()
            return
        end
        local frame = vgui.Create("DFrame")
        currentBrowser = frame
        frame:SetTitle("Metrostroi Expanded | Original Model Catalog")
        frame:SetSize(math.min(ScrW() - 50, 1030), math.min(ScrH() - 60, 745))
        frame:SetMinWidth(550)
        frame:SetMinHeight(430)
        frame:SetSizable(true)
        frame:Center()
        frame:MakePopup()

        local header = vgui.Create("DPanel", frame)
        header:Dock(TOP)
        header:SetTall(70)
        header:DockPadding(8, 7, 8, 7)
        local search = vgui.Create("DTextEntry", header)
        search:Dock(TOP)
        search:SetTall(28)
        search:SetPlaceholderText("Search original model names and paths...")
        local filters = vgui.Create("DPanel", header)
        filters:Dock(TOP)
        filters:SetTall(28)
        filters:DockMargin(0, 6, 0, 0)
        filters:SetPaintBackground(false)
        local categories = vgui.Create("DComboBox", filters)
        categories:Dock(LEFT)
        categories:SetWide(175)
        for _, item in ipairs({
            {"All models", "all"}, {"Straight tracks / tunnels", "straight"},
            {"Curved tracks", "curve"}, {"Junctions / crossings", "junction"},
            {"Other models", "other"},
        }) do
            categories:AddChoice(item[1], item[2])
        end
        categories:ChooseOptionID(1)
        local sources = vgui.Create("DComboBox", filters)
        sources:Dock(LEFT)
        sources:SetWide(155)
        sources:DockMargin(6, 0, 0, 0)
        sources:AddChoice("All installed packs", "all")
        sources:AddChoice("Metrostroi", "Metrostroi")
        sources:AddChoice("Track Pack", "Track Pack")
        sources:ChooseOptionID(1)
        local rescan = vgui.Create("DButton", filters)
        rescan:Dock(RIGHT)
        rescan:SetWide(136)
        rescan:SetText("Rescan mounted MDLs")
        rescan.DoClick = function()
            RunConsoleCommand("mex_native_rescan_models")
        end

        local footer = vgui.Create("DPanel", frame)
        footer:Dock(BOTTOM)
        footer:SetTall(38)
        footer:DockPadding(7, 5, 7, 5)
        local choose = vgui.Create("DButton", footer)
        choose:Dock(RIGHT)
        choose:SetWide(156)
        choose:SetText("USE SELECTED MODEL")
        local pageForward = vgui.Create("DButton", footer)
        pageForward:Dock(LEFT)
        pageForward:SetWide(68)
        pageForward:SetText("Next >")
        local pageBack = vgui.Create("DButton", footer)
        pageBack:Dock(LEFT)
        pageBack:SetWide(68)
        pageBack:SetText("< Prev")
        pageBack:DockMargin(0, 0, 5, 0)
        local pageText = vgui.Create("DLabel", footer)
        pageText:Dock(FILL)
        pageText:SetContentAlignment(5)
        pageText:SetTextColor(Color(225, 225, 225))

        local preview = vgui.Create("DPanel", frame)
        preview:Dock(RIGHT)
        preview:SetWide(300)
        preview:DockMargin(7, 7, 8, 7)
        preview:DockPadding(7, 7, 7, 7)
        local modelPreview = vgui.Create("DModelPanel", preview)
        modelPreview:Dock(TOP)
        modelPreview:SetTall(240)
        modelPreview:SetFOV(38)
        modelPreview.LayoutEntity = function() end
        local nameText = vgui.Create("DLabel", preview)
        nameText:Dock(TOP)
        nameText:SetTall(46)
        nameText:SetWrap(true)
        nameText:SetContentAlignment(7)
        nameText:SetTextColor(Color(240, 240, 240))
        local pathText = vgui.Create("DLabel", preview)
        pathText:Dock(TOP)
        pathText:SetTall(86)
        pathText:SetWrap(true)
        pathText:SetContentAlignment(7)
        pathText:SetTextColor(Color(190, 215, 240))
        local categoryText = vgui.Create("DLabel", preview)
        categoryText:Dock(TOP)
        categoryText:SetTall(60)
        categoryText:SetWrap(true)
        categoryText:SetContentAlignment(7)
        categoryText:SetTextColor(Color(230, 220, 180))
        local noteText = vgui.Create("DLabel", preview)
        noteText:Dock(FILL)
        noteText:SetWrap(true)
        noteText:SetContentAlignment(7)
        noteText:SetTextColor(Color(210, 210, 210))

        local scroll = vgui.Create("DScrollPanel", frame)
        scroll:Dock(FILL)
        scroll:DockMargin(8, 7, 0, 7)
        local icons = vgui.Create("DIconLayout", scroll)
        icons:Dock(TOP)
        icons:SetSpaceX(8)
        icons:SetSpaceY(8)

        local page = 1
        local pageSize = 30
        local selected = GetConVar("mex_track_builder_native_model")
        local selectedModel = selected and selected:GetString() or ""
        local matched = {}
        local currentCategory, currentSource = "all", "all"

        local function ApplySelection(model)
            if model == "" then return end
            selectedModel = model
            RunConsoleCommand("mex_track_builder_native_model", model)
            local info = MEXNativeTrack and MEXNativeTrack.ModelCatalog[model] or nil
            if not info then return end
            nameText:SetText(TitleFor(info))
            pathText:SetText(model)
            categoryText:SetText((info.source or "Original model") ..
                "   /   " .. string.upper(info.kind or "other"))
            noteText:SetText(info.kind == "junction"
                and "Junctions require real, calibrated switch/crossing ports. Unknown rail branches are never guessed."
                or info.kind == "other"
                and "This original model appears in the catalog, but Track Builder cannot treat a non-track prop as rails."
                or "Track-end and curve geometry are measured from the original MDL. Unreadable rail geometry is rejected without a synthetic replacement.")
            modelPreview:SetModel(model)
            if IsValid(modelPreview.Entity) then
                local ent = modelPreview.Entity
                local mn, mx = ent:GetRenderBounds()
                local size = mx - mn
                local maxDim = math.max(size.x, size.y, size.z, 1)
                modelPreview:SetLookAt((mn + mx) * 0.5)
                modelPreview:SetCamPos(Vector(maxDim * 1.5,
                    -maxDim * 1.5, maxDim * 0.9))
            end
        end

        local function Refresh()
            if not IsValid(frame) then return end
            matched = {}
            local catalog = MEXNativeTrack and MEXNativeTrack.ModelCatalog or {}
            local term = string.Trim(string.lower(search:GetValue() or ""))
            for path, info in pairs(catalog) do
                local kind = info.kind or "other"
                if (currentCategory == "all" or kind == currentCategory)
                    and (currentSource == "all" or info.source == currentSource)
                    and (term == "" or string.find(string.lower(path), term, 1, true)) then
                    matched[#matched + 1] = info
                end
            end
            table.sort(matched, function(a, b) return a.model < b.model end)
            local maxPage = math.max(1, math.ceil(#matched / pageSize))
            page = math.Clamp(page, 1, maxPage)
            icons:Clear()
            for i = (page - 1) * pageSize + 1,
                math.min(page * pageSize, #matched) do
                local info = matched[i]
                local icon = icons:Add("SpawnIcon")
                icon:SetSize(100, 100)
                icon:SetModel(info.model)
                icon:SetTooltip(info.model)
                icon.DoClick = function()
                    ApplySelection(info.model)
                end
                icon.DoDoubleClick = function()
                    ApplySelection(info.model)
                    frame:Close()
                end
            end
            icons:InvalidateLayout(true)
            icons:SizeToChildren(false, true)
            pageBack:SetEnabled(page > 1)
            pageForward:SetEnabled(page < maxPage)
            pageText:SetText(string.format("%d models  |  Page %d / %d",
                #matched, page, maxPage))
            if #matched == 0 then
                pageText:SetText("No matching MDLs. Rescan or check installed Track Pack.")
            end
        end

        search.OnValueChange = function()
            page = 1
            Refresh()
        end
        categories.OnSelect = function(_, _, _, data)
            currentCategory = data or "all"
            page = 1
            Refresh()
        end
        sources.OnSelect = function(_, _, _, data)
            currentSource = data or "all"
            page = 1
            Refresh()
        end
        pageBack.DoClick = function() page = math.max(1, page - 1); Refresh() end
        pageForward.DoClick = function() page = page + 1; Refresh() end
        choose.DoClick = function()
            if selectedModel ~= "" then
                RunConsoleCommand("mex_track_builder_native_model", selectedModel)
                frame:Close()
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
        if selectedModel ~= "" and MEXNativeTrack
            and MEXNativeTrack.ModelCatalog[selectedModel] then
            ApplySelection(selectedModel)
        else
            nameText:SetText("Select an original MDL")
            pathText:SetText("Browse all mounted Metrostroi and Track Pack models.")
            categoryText:SetText("No automatic model presets.")
            noteText:SetText("Click any icon to inspect its real model. Click again to choose a different piece.")
        end
        if not MEXNativeTrack or not next(MEXNativeTrack.ModelCatalog or {}) then
            RunConsoleCommand("mex_native_rescan_models")
        end
    end

    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", {
            Text = "Metrostroi Expanded - Model Catalog",
            Description = "Only original installed MDL models. No preset tunnel types, radii or generated replacement tracks.",
        })
        local pick = panel:Button("OPEN ORIGINAL MODEL CATALOG")
        pick.DoClick = OpenModelCatalog
        local activePath = panel:TextEntry("Selected original model",
            "mex_track_builder_native_model")
        activePath:SetPlaceholderText("Choose a model from the catalog...")
        panel:CheckBox("Reverse model direction (use other rail end)",
            "mex_track_builder_native_reverse")
        local junction = panel:ComboBox("Junction output port (registered models)",
            "mex_track_builder_native_branch")
        junction:AddChoice("Port 2 - main", "2")
        junction:AddChoice("Port 3 - diverging", "3")
        junction:AddChoice("Port 4 - crossing", "4")
        panel:Help("LMB: set start, then place selected MDL.")
        panel:Help("RMB: save | R: remove aimed model | Shift+R: undo last.")
        panel:Help("Green / orange crossbars = actual rail-end connectors.")
        panel:CheckBox("Show measured rail centerline overlay",
            "mex_native_show_measured_path")
        panel:NumSlider("Outdoor original-model brightness",
            "mex_native_outdoor_brightness", 0.35, 1.5, 2)
        panel:Button("Finish route", "mex_native_finish")
        panel:Button("Undo last module", "mex_native_undo")
        panel:Button("Remove aimed module", "mex_native_remove_aimed")
        panel:Button("Cancel construction", "mex_native_cancel")
        panel:Button("Rescan model catalog", "mex_native_rescan_models")
        panel:Help("Unknown Track Pack rail meshes need measured original ports. Use mex_native_model_info models/...mdl to inspect.")
    end
end
