-- Metrostroi Expanded | Station Builder tool
-- Copyright (C) 2026 Adam Cir / Adava Software | GPL-3.0
TOOL.Category="Metrostroi Expanded"
TOOL.Name="#tool.mex_station_builder.name"
TOOL.Command=nil
TOOL.ConfigName=""
TOOL.ClientConVar={
    layout="1", width="320", height="44", gap="100", spacing="480",
    ceiling="290", style="2", cladding="1", stairs="0", lights="1",
    name="Adamovske metro", accent="458965",
    rotation="0", fixed="0", length="1024"
}

if CLIENT then
    language.Add("tool.mex_station_builder.name","Station Builder [ALPHA]")
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
    -- Use the default Garry's Mod Derma toolgun panel skin. No custom
    -- backgrounds, hard-coded bright text, or colored category headers.
    local function Section(panel,title)
        panel:Help(string.upper(title))
    end

    local function Choices(panel,title,cvar,choices)
        -- Native ComboBox appearance, as used in other GMod tools.
        panel:Help(title)
        local combo=vgui.Create("DComboBox")
        combo:SetTall(24)
        local convarName="mex_station_builder_"..cvar
        local cv=GetConVar(convarName)
        local selected=cv and cv:GetInt() or 1
        local choiceID=1
        for i,option in ipairs(choices) do
            combo:AddChoice(option[1],option[2])
            if option[2]==selected then choiceID=i end
        end
        combo:ChooseOptionID(choiceID)
        combo.OnSelect=function(_,_,_,value)
            if value~=nil then
                RunConsoleCommand(convarName,tostring(value))
            end
        end
        panel:AddItem(combo)
    end

    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header",{
            Text="Metrostroi Expanded | Station Builder [ALPHA]",
            Description="Experimental: create walkable metro platforms, walls, roofing, cladding, signs and stairs using standard GMod tools."
        })
        panel:Help("ALPHA: unfinished and may contain bugs or affect performance.")
        panel:Help("LMB 1: choose starting point (snaps to existing rail). LMB 2: choose platform end. RMB on an existing station: apply new design. R: remove the whole station.")

        Section(panel,"1. Station plan")
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

        Section(panel,"2. Architecture")
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
        panel:TextEntry("Accent color (HEX RRGGBB)",
            "mex_station_builder_accent")
        panel:CheckBox("Ceiling lamps with dynamic lighting",
            "mex_station_builder_lights")

        Section(panel,"3. Entrances")
        Choices(panel,"Straight stairways and upper landings","stairs",{
            {"No stairs",0},
            {"Entrance stairs at start",1},
            {"Entrance stairs at end",2},
            {"Stairs at both ends",3},
        })
        panel:Help("Stairways are aligned to platforms with 11-SU risers. They lead to upper landings; connect terrain with props or the map editor.")

        Section(panel,"4. Build / edit")
        panel:Help("Aim near a straight original rail for accurate direction and elevation. Two-track layouts use the selected midpoint between rails; original Metrostroi rails are not moved.")
        panel:Help("Edit: change settings above, then RMB on a station part to regenerate the station in place.")
        panel:Help("Stations reload with the map and survive cleanup. Only admins can build, edit or remove stations.")
    end
end
