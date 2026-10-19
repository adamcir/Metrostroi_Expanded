-- Metrostroi Expanded | Station Builder tool
-- Copyright (C) 2026 Adam Cir / Adava Software | GPL-3.0
TOOL.Category="Metrostroi Expanded"
TOOL.Name="#tool.mex_station_builder.name"
TOOL.Command=nil
TOOL.ConfigName=""
TOOL.ClientConVar={
    layout="1", width="320", height="44", gap="100", spacing="480",
    ceiling="290", style="2", cladding="1", stairs="1", lights="1",
    name="Adamovske metro", accent="458965",
    rotation="0", fixed="0", length="1024"
}

if CLIENT then
    language.Add("tool.mex_station_builder.name","Station Builder")
    language.Add("tool.mex_station_builder.desc",
        "Build editable, walkable metro stations on original Metrostroi tracks")
    language.Add("tool.mex_station_builder.0",
        "LMB: set station start/end | RMB: edit aimed station or cancel | R: remove aimed station")
end
local function Options(tool)
    return {
        layout=tool:GetClientNumber("layout",1),
        width=tool:GetClientNumber("width",320),
        height=tool:GetClientNumber("height",44),
        gap=tool:GetClientNumber("gap",100),
        spacing=tool:GetClientNumber("spacing",480),
        ceiling=tool:GetClientNumber("ceiling",290),
        style=tool:GetClientNumber("style",2),
        cladding=tool:GetClientNumber("cladding",1),
        stairs=tool:GetClientNumber("stairs",1),
        lights=tool:GetClientNumber("lights",1),
        name=tool:GetClientInfo("name"),
        accent=tool:GetClientInfo("accent"),
        rotation=tool:GetClientNumber("rotation",0),
        fixed=tool:GetClientNumber("fixed",0),
        length=tool:GetClientNumber("length",1024),
    }
end
function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply=self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() or not MEXStationBuilder then
        return false
    end
    if not trace.Hit or trace.HitSky then return false end
    return MEXStationBuilder.Click(ply,trace.HitPos,Options(self))
end
function TOOL:RightClick(trace)
    if CLIENT then return true end
    local ply=self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() or not MEXStationBuilder then
        return false
    end
    if MEXStationBuilder.Drafts[ply] then
        return MEXStationBuilder.Cancel(ply)
    end
    if IsValid(trace.Entity) and trace.Entity:GetNW2Bool("MEXStationPart",false) then
        return MEXStationBuilder.Update(ply,trace.Entity,Options(self))
    end
    return false
end
function TOOL:Reload(trace)
    if CLIENT then return true end
    local ply=self:GetOwner()
    if not IsValid(ply) or not ply:IsAdmin() or not MEXStationBuilder then
        return false
    end
    if MEXStationBuilder.Drafts[ply] then
        return MEXStationBuilder.Cancel(ply)
    end
    return MEXStationBuilder.Remove(ply,trace.Entity)
end
if CLIENT then
    local C_TITLE=Color(62,109,83)
    local C_TEXT=Color(227,234,234)
    local function Section(panel,text)
        local label=vgui.Create("DLabel",panel)
        label:Dock(TOP)
        label:DockMargin(0,13,0,5)
        label:SetTall(30)
        label:SetFont("DermaDefaultBold")
        label:SetTextColor(C_TEXT)
        label:SetText("  "..text)
        label.Paint=function(_,w,h)
            draw.RoundedBox(3,0,0,w,h,C_TITLE)
        end
        panel:AddItem(label)
    end
    local function Choices(panel,title,cvar,choices)
        local row=vgui.Create("DPanel")
        row:SetTall(53)
        row:SetPaintBackground(false)
        local name=vgui.Create("DLabel",row)
        name:Dock(TOP)
        name:SetTall(21)
        name:SetTextColor(C_TEXT)
        name:SetText(title)
        local combo=vgui.Create("DComboBox",row)
        combo:Dock(TOP)
        combo:SetTall(28)
        local cv=GetConVar("mex_station_builder_"..cvar)
        local selected=cv and cv:GetInt() or 1
        local choiceID=1
        for i,v in ipairs(choices) do
            combo:AddChoice(v[1],v[2])
            if v[2]==selected then choiceID=i end
        end
        combo:ChooseOptionID(choiceID)
        combo.OnSelect=function(_,_,_,value)
            RunConsoleCommand("mex_station_builder_"..cvar,tostring(value))
        end
        panel:AddItem(row)
    end
    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header",{
            Text="Metrostroi Expanded | Station Builder",
            Description="Build real walkable platforms, walls, roof, cladding, lighting, signs and stairs. Works alongside Track Builder."
        })
        panel:Help("LMB 1: choose starting point (snaps to existing rail). LMB 2: choose platform end. RMB on an existing station: apply new design. R: remove the whole station.")
        Section(panel,"1. STATION PLAN")
        panel:TextEntry("Station name","mex_station_builder_name")
        Choices(panel,"Platform arrangement","layout",{
            {"Left side platform (1 track)",1},
            {"Right side platform (1 track)",2},
            {"Island platform (2 tracks)",3},
            {"Two outer platforms (2 tracks)",4},
            {"Platforms on both sides (1 track)",5},
        })
        panel:NumSlider("Platform width (SU)","mex_station_builder_width",160,640,0)
        panel:NumSlider("Distance from rail to platform edge (SU)",
            "mex_station_builder_gap",85,180,0)
        panel:NumSlider("Two-track rail separation (SU)",
            "mex_station_builder_spacing",264,1000,0)
        panel:CheckBox("Use fixed station length (otherwise use two clicks)",
            "mex_station_builder_fixed")
        panel:NumSlider("Fixed station length (SU)",
            "mex_station_builder_length",512,4096,0)
        panel:NumSlider("Rotate from measured track heading (degrees)",
            "mex_station_builder_rotation",-180,180,0)
        Section(panel,"2. ARCHITECTURE")
        Choices(panel,"Architectural theme","style",{
            {"Classic concrete and tile",1},
            {"Modern clean station",2},
            {"Industrial brick station",3},
        })
        Choices(panel,"Wall cladding","cladding",{
            {"Light rectangular tiles",1},
            {"Concrete panels",2},
            {"Exposed brick",3},
        })
        panel:NumSlider("Platform top above railhead (SU)",
            "mex_station_builder_height",28,80,0)
        panel:NumSlider("Clear ceiling above platform (SU)",
            "mex_station_builder_ceiling",250,480,0)
        local label=vgui.Create("DLabel")
        label:SetText("Accent color (HEX)")
        label:SetTextColor(C_TEXT)
        label:SetTall(20)
        panel:AddItem(label)
        panel:TextEntry("RRGGBB / station stripe color",
            "mex_station_builder_accent")
        panel:CheckBox("Ceiling lamps with dynamic lighting",
            "mex_station_builder_lights")
        Section(panel,"3. ENTRANCES")
        Choices(panel,"Straight stairways and upper landings","stairs",{
            {"No stairs",0},
            {"Entrance stairs at start",1},
            {"Entrance stairs at end",2},
            {"Stairs at both ends",3},
        })
        panel:Help("Stairways are aligned to the platforms with 11-SU risers. They lead to raised landings; terrain connections can be finished with props or the map editor.")
        Section(panel,"4. BUILD / EDIT")
        panel:Help("Aim near a straight original rail for accurate direction and elevation. Two-track layouts use your selected midpoint between the two rails. Station Builder does not move, duplicate or replace the original Metrostroi rails.")
        panel:Help("Edit: adjust options above and RMB an existing station part. This regenerates the station in the same location and saves it for the current map.")
        panel:Help("Saved stations reload with the map and reappear after a map cleanup. Only admins can build, edit or remove stations.")
    end
end
