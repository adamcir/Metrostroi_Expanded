-- Metrostroi Expanded | Modular Station Builder
-- Copyright (C) 2026 Adam Cir / Adava Software | GPL-3.0
-- Saves real, walkable station architecture independently of track routes.
if SERVER then AddCSLuaFile() end

MEXStationBuilder = MEXStationBuilder or {}
local S = MEXStationBuilder
S.Stations = S.Stations or {}
S.Entities = S.Entities or {}
S.Drafts = S.Drafts or {}
S.NextID = S.NextID or 1

local GRID = 256
local MIN_LENGTH, MAX_LENGTH = 512, 4096
local STRUCTURAL_MODEL = "models/hunter/blocks/cube025x025x025.mdl"
local MATERIALS = {
    floor = "concrete/concretefloor001a",
    wall = "brick/brickwall003a",
    roof = "concrete/concretewall001a",
    clean = "models/debug/debugwhite",
}
local function Vec(v) return Vector(v[1] or 0, v[2] or 0, v[3] or 0) end
local function Arr(v) return {v.x, v.y, v.z} end
local function Forward(yaw) return Angle(0, yaw, 0):Forward() end
local function Right(yaw) local f=Forward(yaw) return Vector(f.y,-f.x,0) end
local function RoundLength(v)
    return math.Clamp(math.floor(math.abs(v)/GRID + 0.5)*GRID,
        MIN_LENGTH,MAX_LENGTH)
end
local function CleanString(str)
    str=tostring(str or "Adamovske metro"):gsub("[%c]"," ")
    return string.Trim(str):sub(1,64)
end
local function ValidColor(hex)
    if not isstring(hex) or not hex:match("^#?%x%x%x%x%x%x$") then
        return "458965"
    end
    return string.upper(hex:gsub("#",""))
end
local function HexColor(hex)
    hex=ValidColor(hex)
    return Color(tonumber(hex:sub(1,2),16),
        tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16))
end
local function ColorComponents(c)
    return Vector(c.r,c.g,c.b)
end

-- One small static collision/render entity per construction module. Never
-- scale a stock MDL's unreliable physics or build an invisible solid bed
-- through the tracks. Decorative pieces are deliberately non-solid.
local StationPart = {
    Type="anim", Base="base_anim",
    PrintName="MEX Station Module", Spawnable=false,
    RenderGroup=RENDERGROUP_OPAQUE
}
function StationPart:Initialize()
    if CLIENT then
        self:DrawShadow(false)
        return
    end
    self:SetModel(STRUCTURAL_MODEL)
    local mn=self:GetNW2Vector("MEXStMin",Vector(-16,-16,-4))
    local mx=self:GetNW2Vector("MEXStMax",Vector(16,16,4))
    if self:GetNW2Bool("MEXStSolid",true) then
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:PhysicsInitBox(mn,mx)
        local phys=self:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:Sleep()
        else
            self:Remove()
            return
        end
    else
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        self:SetNotSolid(true)
    end
    self:DrawShadow(false)
end
if CLIENT then
    local materialCache={}
    local function CachedMaterial(path)
        if not materialCache[path] then
            materialCache[path]=Material(path)
        end
        return materialCache[path]
    end
    function StationPart:Draw()
        local mn=self:GetNW2Vector("MEXStMin",Vector(-16,-16,-4))
        local mx=self:GetNW2Vector("MEXStMax",Vector(16,16,4))
        if not self.MEXStBoundsReady then
            self:SetRenderBounds(mn-Vector(4,4,4),mx+Vector(4,4,4))
            self.MEXStBoundsReady=true
        end
        local tint=self:GetNW2Vector("MEXStColor",Vector(255,255,255))
        local c=Color(math.Clamp(tint.x,0,255),
            math.Clamp(tint.y,0,255),math.Clamp(tint.z,0,255))
        local material=self:GetNW2String("MEXStMaterial",MATERIALS.clean)
        render.SetMaterial(CachedMaterial(material))
        render.DrawBox(self:GetPos(),self:GetAngles(),mn,mx,c,true)
        local kind=self:GetNW2String("MEXStKind","")
        if kind=="light" then
            local l=DynamicLight(self:EntIndex())
            if l then
                l.pos=self:GetPos()-Vector(0,0,14)
                l.r,l.g,l.b=c.r,c.g,c.b
                l.brightness=1.3
                l.Size=340
                l.Decay=1000
                l.DieTime=CurTime()+0.13
            end
        elseif kind=="sign" then
            local name=self:GetNW2String("MEXStLabel","")
            if name~="" then
                local center=self:GetPos()
                local yaw=self:GetAngles().y
                local w=math.abs(mx.y-mn.y)
                local size=math.Clamp(200/math.max(#name,12),8,17)
                for _,side in ipairs({-1,1}) do
                    local face=Angle(0,yaw+(side==1 and 90 or -90),90)
                    local p=center+Forward(yaw)*side*7
                    cam.Start3D2D(p,face,0.18)
                        draw.SimpleText(name,"DermaLarge",0,0,
                            Color(255,255,255),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                    cam.End3D2D()
                end
            end
        end
    end
end
scripted_ents.Register(StationPart,"mex_station_piece")

local function Template(settings)
    settings=settings or {}
    local layout=math.Clamp(math.floor(tonumber(settings.layout) or 1),1,5)
    return {
        layout=layout,
        width=math.Clamp(math.floor(tonumber(settings.width) or 320),160,640),
        height=math.Clamp(math.floor(tonumber(settings.height) or 44),28,80),
        gap=math.Clamp(math.floor(tonumber(settings.gap) or 100),85,180),
        spacing=math.Clamp(math.floor(tonumber(settings.spacing) or 480),264,1000),
        ceiling=math.Clamp(math.floor(tonumber(settings.ceiling) or 290),250,480),
        style=math.Clamp(math.floor(tonumber(settings.style) or 1),1,3),
        cladding=math.Clamp(math.floor(tonumber(settings.cladding) or 1),1,3),
        stairs=math.Clamp(math.floor(tonumber(settings.stairs) or 0),0,3),
        lights=settings.lights~=false and tonumber(settings.lights)~=0,
        name=CleanString(settings.name),
        accent=ValidColor(settings.accent),
    }
end

local function Layout(cfg)
    local w,g,d=cfg.width,cfg.gap,cfg.spacing
    local platforms={}
    local function add(center,width)
        platforms[#platforms+1]={center=center,width=width}
    end
    if cfg.layout==1 then
        add(-(g+w*0.5),w)
    elseif cfg.layout==2 then
        add(g+w*0.5,w)
    elseif cfg.layout==3 then
        -- The platform must actually fit between the specified rails.
        if d-2*g < 160 then
            return nil,"Island platform needs more spacing between the two rails."
        end
        add(0,math.min(w,d-2*g))
    elseif cfg.layout==4 then
        add(-(d*0.5+g+w*0.5),w)
        add(d*0.5+g+w*0.5,w)
    elseif cfg.layout==5 then
        add(-(g+w*0.5),w)
        add(g+w*0.5,w)
    end
    local left,right=math.huge,-math.huge
    for _,platform in ipairs(platforms) do
        left=math.min(left,platform.center-platform.width*0.5)
        right=math.max(right,platform.center+platform.width*0.5)
    end
    if cfg.layout==3 or cfg.layout==4 then
        left=math.min(left,-d*0.5-125)
        right=math.max(right,d*0.5+125)
    else
        left=math.min(left,-125)
        right=math.max(right,125)
    end
    return platforms,left-28,right+28
end

-- All station components are compact boxes in station-local coordinates.
-- X follows the track, Y points to track right, Z measures rail-base level.
-- Railhead is +10 SU on original Metrostroi track modules.
local function BuildModules(cfg)
    local platforms,lateralMin,lateralMax=Layout(cfg)
    if not platforms then return nil,lateralMin end
    local pieces={}
    local total=cfg.length/GRID
    local deck=10+cfg.height
    local roof=deck+cfg.ceiling
    local accent=HexColor(cfg.accent)
    local trim=Color(accent.r,accent.g,accent.b)
    local classic=cfg.style==1
    local industrial=cfg.style==3
    local floorMat=classic and MATERIALS.floor or MATERIALS.clean
    local wallMat=cfg.cladding==3 and MATERIALS.wall or
        (cfg.cladding==2 and MATERIALS.roof or MATERIALS.clean)
    local roofMat=industrial and MATERIALS.wall or MATERIALS.roof
    local floorTint=classic and Color(198,192,171)
        or (industrial and Color(115,120,124) or Color(218,219,215))
    local wallTint=classic and Color(218,211,190)
        or (industrial and Color(138,145,146) or Color(230,233,230))
    local roofTint=classic and Color(181,180,171)
        or (industrial and Color(110,117,119) or Color(214,219,218))
    local function add(x,y,z,l,w,h,material,color,solid,kind,label)
        pieces[#pieces+1]={
            x=x,y=y,z=z,
            mn={-l/2,-w/2,-h/2},mx={l/2,w/2,h/2},
            material=material or MATERIALS.clean,
            rgb={color.r,color.g,color.b},
            solid=solid~=false,kind=kind or "",label=label or "",
        }
    end
    for i=1,total do
        local x=(i-0.5)*GRID
        for _,platform in ipairs(platforms) do
            local center,w=platform.center,platform.width
            add(x,center,deck-12,GRID,w,24,floorMat,floorTint,true)
            -- Two tactile edges make platforms immediately legible.
            for _,side in ipairs({-1,1}) do
                local edge=center+side*(w/2-9)
                add(x,edge,deck+1,GRID-2,18,2,
                    MATERIALS.clean,Color(244,186,54),false)
                local inner=center+side*(w/2-25)
                add(x,inner,deck+1,GRID-2,5,2,
                    MATERIALS.clean,trim,false)
            end
            if i%2==1 then
                -- Pillars stand within the platform, never on running rails.
                local py=center
                add(x,py,(deck+roof)/2,26,26,roof-deck-22,
                    wallMat,wallTint,true)
                add(x,py,deck+12,38,38,16,MATERIALS.clean,trim,false)
                add(x,py,roof-15,38,38,16,MATERIALS.clean,trim,false)
            end
            -- Furnishing modules stand away from the track-facing edges.
            if i%4==0 and w>=240 then
                local by=center
                add(x+28,by,deck+20,98,35,12,
                    MATERIALS.clean,Color(81,92,90),true)
                add(x+28,by-18,deck+43,98,9,42,
                    MATERIALS.clean,Color(74,85,83),true)
                for _,dx in ipairs({-30,30}) do
                    add(x+28+dx,by,deck+8,9,26,16,
                        MATERIALS.clean,Color(85,85,82),true)
                end
            end
            if cfg.lights then
                add(x,center,roof-17,88,30,6,
                    MATERIALS.clean,Color(255,241,200),false,"light")
            end
            if i%3==2 then
                add(x,center,roof-63,12,140,31,MATERIALS.clean,
                    Color(30,55,45),false,"sign",cfg.name)
            end
        end
        local corridorW=lateralMax-lateralMin
        local corridorCenter=(lateralMax+lateralMin)/2
        -- Continuous concrete vault; NO floor is created across the tracks.
        add(x,corridorCenter,roof+9,GRID,corridorW,18,
            roofMat,roofTint,true)
        for _,side in ipairs({lateralMin,lateralMax}) do
            add(x,side,(deck+roof)/2,GRID,20,roof-deck,
                wallMat,wallTint,true)
            add(x,side-(side>0 and 1 or -1)*11,
                deck+37,GRID-2,3,14,MATERIALS.clean,trim,false)
            if cfg.cladding==1 then
                -- Render decorative tile grout on the interior wall face.
                -- Thin non-solid strips do not introduce track collisions.
                local inside=side-(side>0 and 1 or -1)*11.6
                for k=1,3 do
                    add(x-GRID/2+k*64,inside,
                        (deck+roof)/2,2,1,roof-deck-4,
                        MATERIALS.clean,Color(150,154,149),false)
                end
                for z=deck+82,roof-10,80 do
                    add(x,inside,z,GRID-2,1,2,
                        MATERIALS.clean,Color(150,154,149),false)
                end
            end
            if i%2==0 then
                add(x,side-(side>0 and 1 or -1)*12,
                    roof-76,110,3,62,MATERIALS.clean,
                    Color(235,235,224),false)
            end
        end
        add(x,corridorCenter,roof-4,18,corridorW,22,
            MATERIALS.clean,roofTint,true)
    end

    -- Straight, climbable staircase *outside* either end of the platform.
    -- Steps rise by 11 SU (below Source step-height limits), 24 SU tread.
    if cfg.stairs~=0 then
        for _,platform in ipairs(platforms) do
            for _,atEnd in ipairs({false,true}) do
                if (cfg.stairs==1 and not atEnd) or
                    (cfg.stairs==2 and atEnd) or cfg.stairs==3 then
                    local outward=atEnd and 1 or -1
                    local baseX=atEnd and cfg.length or 0
                    local stairW=math.min(platform.width-65,170)
                    for step=1,12 do
                        local sx=baseX+outward*(step-0.5)*24
                        local level=deck+step*11
                        add(sx,platform.center,level-5,24,stairW,10,
                            floorMat,floorTint,true)
                        for _,side in ipairs({-1,1}) do
                            add(sx,platform.center+side*(stairW/2+9),
                                level+30,24,12,80,
                                wallMat,wallTint,true)
                        end
                    end
                    add(baseX+outward*(12*24+48),platform.center,
                        deck+12*11-9,96,stairW+30,18,
                        floorMat,floorTint,true)
                end
            end
        end
    end
    -- Prevent a malicious combination from exhausting entity limits.
    if #pieces>800 then return nil,"Station layout exceeds module safety limit." end
    return pieces
end

if CLIENT then
    local startTime=0
    hook.Add("PostDrawTranslucentRenderables","MEXStationBuilderPreview",function(_,sky)
        if sky then return end
        local ply=LocalPlayer()
        if not IsValid(ply) or not ply:GetNW2Bool("MEXStDraft",false) then return end
        local weapon=ply:GetActiveWeapon()
        if not IsValid(weapon) or weapon:GetClass()~="gmod_tool"
            or weapon:GetMode()~="mex_station_builder" then return end
        local yaw=ply:GetNW2Float("MEXStDraftYaw",0)
        local start=ply:GetNW2Vector("MEXStDraftPos",vector_origin)
        local tr=ply:GetEyeTrace()
        local delta=(tr.HitPos-start):Dot(Forward(yaw))
        local fixed=GetConVar("mex_station_builder_fixed")
        local desired=GetConVar("mex_station_builder_length")
        local length=fixed and fixed:GetBool() and
            RoundLength(desired and desired:GetFloat() or 1024)
            or RoundLength(delta)
        local center=start+Forward(yaw)*(length/2)
        local settings={
            width=GetConVar("mex_station_builder_width"):GetFloat(),
            gap=GetConVar("mex_station_builder_gap"):GetFloat(),
            spacing=GetConVar("mex_station_builder_spacing"):GetFloat(),
            layout=GetConVar("mex_station_builder_layout"):GetInt(),
            height=GetConVar("mex_station_builder_height"):GetFloat(),
            ceiling=GetConVar("mex_station_builder_ceiling"):GetFloat(),
        }
        local c=Template(settings)
        local platforms,left,right=Layout(c)
        if not platforms then return end
        render.SetColorMaterial()
        local ang=Angle(0,yaw,0)
        local deck=10+c.height
        for _,p in ipairs(platforms) do
            render.DrawWireframeBox(center+Right(yaw)*p.center+
                Vector(0,0,deck-12),ang,
                Vector(-length/2,-p.width/2,-12),
                Vector(length/2,p.width/2,12),
                Color(58,230,140),true)
        end
        render.DrawWireframeBox(center+Right(yaw)*((left+right)/2)+
            Vector(0,0,deck+c.ceiling),ang,
            Vector(-length/2,-(right-left)/2,-2),
            Vector(length/2,(right-left)/2,2),
            Color(90,180,245),true)
        render.DrawLine(start,start+Forward(yaw)*length,
            Color(255,201,56),true)
    end)
    return
end

local FILE="metrostroi_expanded/stations_"..game.GetMap()..".json"
local function Notice(ply,message)
    if IsValid(ply) then ply:ChatPrint("[MEX Station Builder] "..message) end
    print("[MEX Station Builder] "..message)
end

local function Clear(id)
    for _,ent in ipairs(S.Entities[id] or {}) do
        if IsValid(ent) then ent:Remove() end
    end
    S.Entities[id]=nil
end
local function Spawn(id,cfg)
    local specs,err=BuildModules(cfg)
    if not specs then return false,err end
    local result={}
    local yaw=cfg.yaw
    local origin=Vec(cfg.origin)
    local f,r=Forward(yaw),Right(yaw)
    for _,spec in ipairs(specs) do
        local ent=ents.Create("mex_station_piece")
        if not IsValid(ent) then
            for _,p in ipairs(result) do if IsValid(p) then p:Remove() end end
            return false,"Could not spawn a station construction module."
        end
        ent:SetPos(origin+f*spec.x+r*spec.y+Vector(0,0,spec.z))
        ent:SetAngles(Angle(0,yaw,0))
        ent:SetNW2Vector("MEXStMin",Vec(spec.mn))
        ent:SetNW2Vector("MEXStMax",Vec(spec.mx))
        ent:SetNW2Vector("MEXStColor",Vec(spec.rgb))
        ent:SetNW2Bool("MEXStSolid",spec.solid)
        ent:SetNW2String("MEXStMaterial",spec.material)
        ent:SetNW2String("MEXStKind",spec.kind)
        ent:SetNW2String("MEXStLabel",spec.label)
        ent:SetNW2Int("MEXStationID",id)
        ent:SetNW2Bool("MEXStationPart",true)
        ent:Spawn()
        if not IsValid(ent) then
            for _,p in ipairs(result) do if IsValid(p) then p:Remove() end end
            return false,"Station module physics could not be initialized."
        end
        ent:Activate()
        result[#result+1]=ent
    end
    return result
end
local function Save()
    file.CreateDir("metrostroi_expanded")
    local list={}
    for id,cfg in pairs(S.Stations) do
        list[#list+1]={id=id,config=cfg}
    end
    table.sort(list,function(a,b) return a.id<b.id end)
    file.Write(FILE,util.TableToJSON({version=1,stations=list},true) or "{}")
end
local function Restore()
    for id in pairs(S.Entities) do Clear(id) end
    S.Stations={}
    S.NextID=1
    local data=util.JSONToTable(file.Read(FILE,"DATA") or "{}") or {}
    for _,row in ipairs(data.stations or {}) do
        if istable(row) and istable(row.config) and istable(row.config.origin) then
            local id=math.floor(tonumber(row.id) or 0)
            local cfg=Template(row.config)
            cfg.origin=row.config.origin
            cfg.yaw=tonumber(row.config.yaw) or 0
            cfg.length=RoundLength(row.config.length or 1024)
            if id>0 and id<100000 and not S.Stations[id] then
                local entities,err=Spawn(id,cfg)
                if entities then
                    S.Stations[id],S.Entities[id]=cfg,entities
                    S.NextID=math.max(S.NextID,id+1)
                else
                    print("[MEX Station Builder] Could not load #"..id..": "..tostring(err))
                end
            end
        end
    end
end
hook.Add("InitPostEntity","MEXStationsLoad",function() timer.Simple(0,Restore) end)
hook.Add("PostCleanupMap","MEXStationsRestore",function()
    timer.Simple(0.1,Restore)
end)
hook.Add("PlayerDisconnected","MEXStationsDiscardDraft",function(ply)
    S.Drafts[ply]=nil
end)

-- Snap direction to *authentic Metrostroi rail geometry*. Snap the start
-- position for single-line layouts; island/twin layouts use the midpoint
-- deliberately chosen by the player, only inheriting the rail heading/Z.
local function SnapRail(pos,keepLateral)
    local N=MEXNativeTrack
    if not N or not N.Routes or not N.ModulePaths then return pos,nil end
    local best,score=nil,200*200
    -- Loop the saved track geometry, not entity pivot distances: large
    -- curved/straight MDLs can have their pivots >500 SU from either end.
    for _,route in pairs(N.Routes) do
        for _,part in ipairs(route.parts or {}) do
            if part then
                for _,path in ipairs(N.ModulePaths(part)) do
                    for j=2,#path do
                        local a,b=path[j-1],path[j]
                        local dx,dy=b.x-a.x,b.y-a.y
                        local d=dx*dx+dy*dy
                        if d>4 then
                            local t=math.Clamp(((pos.x-a.x)*dx+
                                (pos.y-a.y)*dy)/d,0,1)
                            local p=a+(b-a)*t
                            local err=(Vector(p.x,p.y,0)-
                                Vector(pos.x,pos.y,0)):LengthSqr()
                            if err<score then
                                score=err
                                best={pos=p,yaw=math.deg(math.atan2(dy,dx))}
                            end
                        end
                    end
                end
            end
        end
    end
    if not best then return pos,nil end
    if keepLateral then
        return Vector(pos.x,pos.y,best.pos.z),best.yaw
    end
    return best.pos,best.yaw
end

local function DraftSync(ply,draft)
    ply:SetNW2Bool("MEXStDraft",draft~=nil)
    if draft then
        ply:SetNW2Vector("MEXStDraftPos",draft.start)
        ply:SetNW2Float("MEXStDraftYaw",draft.yaw)
    end
end
function S.Cancel(ply)
    if not S.Drafts[ply] then return false end
    S.Drafts[ply]=nil
    DraftSync(ply,nil)
    Notice(ply,"Station placement cancelled.")
    return true
end
local function MakeConfig(ply,settings)
    local cfg=Template(settings)
    local platform,err=Layout(cfg)
    if not platform then return nil,err end
    return cfg
end
function S.Click(ply,aim,settings)
    if not IsValid(ply) or not ply:IsAdmin() or not isvector(aim) then return false end
    local cfg,err=MakeConfig(ply,settings)
    if not cfg then Notice(ply,err);return false end
    local draft=S.Drafts[ply]
    if not draft then
        -- Respect the user's orientation unless a real rail path is nearby.
        local preserve=cfg.layout==3 or cfg.layout==4
        local start,yaw=SnapRail(aim,preserve)
        yaw=yaw or ply:EyeAngles().y
        yaw=yaw+math.Clamp(tonumber(settings.rotation) or 0,-180,180)
        draft={start=start,yaw=yaw}
        S.Drafts[ply]=draft
        DraftSync(ply,draft)
        Notice(ply,"Start set. Aim along the platform and LMB to build; RMB cancels.")
        return true
    end
    local distance=(aim-draft.start):Dot(Forward(draft.yaw))
    local length=(tonumber(settings.fixed) or 0)==1
        and RoundLength(settings.length or 1024) or RoundLength(distance)
    local origin=draft.start
    local yaw=draft.yaw
    if distance<0 and tonumber(settings.fixed)~=1 then
        yaw=(yaw+180)%360
    end
    cfg.origin=Arr(origin)
    cfg.yaw=yaw
    cfg.length=length
    local id=S.NextID
    local created,reason=Spawn(id,cfg)
    if not created then Notice(ply,reason);return false end
    S.Stations[id]=cfg
    S.Entities[id]=created
    S.NextID=id+1
    S.Drafts[ply]=nil
    DraftSync(ply,nil)
    Save()
    Notice(ply,string.format("Station #%d saved: %s, %d SU, %d modules.",
        id,cfg.name,cfg.length,#created))
    return true
end
function S.Update(ply,entity,settings)
    if not IsValid(ply) or not ply:IsAdmin() or not IsValid(entity)
        or not entity:GetNW2Bool("MEXStationPart",false) then return false end
    local id=entity:GetNW2Int("MEXStationID",0)
    local previous=S.Stations[id]
    if not previous then return false end
    local cfg,err=MakeConfig(ply,settings)
    if not cfg then Notice(ply,err);return false end
    cfg.origin=table.Copy(previous.origin)
    cfg.yaw=previous.yaw
    cfg.length=previous.length
    -- Validate and build replacement BEFORE destroying the prior station.
    local replacements,reason=Spawn(id,cfg)
    if not replacements then Notice(ply,reason);return false end
    Clear(id)
    S.Stations[id],S.Entities[id]=cfg,replacements
    Save()
    Notice(ply,"Station #"..id.." updated. Position and length preserved.")
    return true
end
function S.Remove(ply,entity)
    if not IsValid(ply) or not ply:IsAdmin() or not IsValid(entity)
        or not entity:GetNW2Bool("MEXStationPart",false) then return false end
    local id=entity:GetNW2Int("MEXStationID",0)
    if not S.Stations[id] then return false end
    Clear(id)
    S.Stations[id]=nil
    Save()
    Notice(ply,"Station #"..id.." removed.")
    return true
end
