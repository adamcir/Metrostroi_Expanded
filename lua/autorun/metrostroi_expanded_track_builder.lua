-- Metrostroi Expanded - in-game track builder backend and track segment entity
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("metrostroi_expanded/track_geometry.lua")
end

MEXTrackBuilder = MEXTrackBuilder or {}
local Builder = MEXTrackBuilder
include("metrostroi_expanded/track_geometry.lua")

local TRACK_CLASS = "mex_track_segment"
local DEFAULT_TRACK_MODEL = "models/metrostroi/tracks/railroad16.mdl"

-- Metrostroi sh_rerail.lua: TRACK_GAUGE=80 measures the CLEAR GAP between
-- the two inner rail faces. TRACK_WIDTH=5.8 is the rail head width. Therefore
-- the rail CENTRE-TO-CENTRE distance used by our twin convexes is 85.8 SU.
-- Use exactly the native railroad16.mdl track width, no artificial widening.
local METROSTROI_INNER_GAUGE = 80
local METROSTROI_RAIL_WIDTH = 5.8
local METROSTROI_RAIL_HEIGHT = 10
local DEFAULT_TRACK_GAUGE = METROSTROI_INNER_GAUGE + METROSTROI_RAIL_WIDTH
local METROSTROI_MODEL_GAUGE = DEFAULT_TRACK_GAUGE

-- Curved MEX track is built from Metrostroi's short 16-SU tile.
-- Long 1024/4096 models cannot bend and caused the huge rail "fan".
local VALID_TRACK_MODELS = {
    ["models/metrostroi/tracks/railroad16.mdl"] = true,
}

local function SafeTrackModel(model)
    model = tostring(model or "")
    if VALID_TRACK_MODELS[model] then
        return model
    end
    return DEFAULT_TRACK_MODEL
end

local TrackEntity = {}
TrackEntity.Type = "anim"
TrackEntity.Base = "base_anim"
TrackEntity.PrintName = "Metrostroi Expanded Track Segment"
TrackEntity.Spawnable = false
TrackEntity.AdminOnly = true
TrackEntity.RenderGroup = RENDERGROUP_OPAQUE

local function BoxConvex(mins, maxs)
    return {
        Vector(mins.x, mins.y, mins.z),
        Vector(mins.x, mins.y, maxs.z),
        Vector(mins.x, maxs.y, mins.z),
        Vector(mins.x, maxs.y, maxs.z),
        Vector(maxs.x, mins.y, mins.z),
        Vector(maxs.x, mins.y, maxs.z),
        Vector(maxs.x, maxs.y, mins.z),
        Vector(maxs.x, maxs.y, maxs.z),
    }
end

function TrackEntity:Initialize()
    -- Our procedural Draw() does not draw the backing 16-SU model. Source
    -- may still project a shadow from that hidden model for each rail entity.
    -- Explicitly disable it on both realms to prevent phantom shadow strips.
    if CLIENT then
        self:DrawShadow(false)
        return
    end
    self:DrawShadow(false)

    local length = math.max(self:GetNW2Float("MEXLength", 1), 1)
    local gauge = math.Clamp(self:GetNW2Float("MEXGauge", DEFAULT_TRACK_GAUGE), 8, 200)
    local railWidth = math.Clamp(self:GetNW2Float("MEXRailWidth", METROSTROI_RAIL_WIDTH), 1, 24)
    local railHeight = math.max(self:GetNW2Float("MEXRailHeight", METROSTROI_RAIL_HEIGHT), 1)
    local sleeperHeight = math.max(self:GetNW2Float("MEXSleeperHeight", 5), 1)
    local model = SafeTrackModel(self:GetNW2String("MEXTrackModel", DEFAULT_TRACK_MODEL))

    if util.IsValidModel(model) then
        self:SetModel(model)
    else
        self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
    end

    self:SetSolid(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)

    local halfLength = length * 0.5

    -- Do not derive this from the model OBB. railroad16.mdl contains more
    -- geometry than the running rail surface, so OBBMaxs().z is not the
    -- rerail height. Stock Metrostroi uses a 10-SU-high rail in sh_rerail.lua.
    local effectiveGauge = gauge
    local effectiveRailWidth = railWidth
    local railTop = METROSTROI_RAIL_HEIGHT
    local railBottom = 0
    local halfRail = effectiveRailWidth * 0.5

    self:SetNW2Float("MEXRailSurfaceOffset", railTop)
    self:SetNW2Float("MEXPhysicalGauge", effectiveGauge)
    self:SetNW2Float("MEXPhysicalRailWidth", effectiveRailWidth)

    local leftY = effectiveGauge * 0.5
    local rightY = -effectiveGauge * 0.5

    -- Only the two rail heads are solid. The previous implementation also
    -- created one wide rectangular collision bed under every segment. Subway
    -- bogeys hit that invisible bed before the wheels reached the rail model,
    -- which made trains visibly float above MEX track.
    -- One shared collision body per simplified chord; optional tunnel lining
    -- is hollow and keeps the rail running surface completely unobstructed.
    local convexes = Builder.Geometry.PhysicsConvexes(
        length, effectiveGauge, effectiveRailWidth,
        self:GetNW2String("MEXTunnelType", "none"),
        self:GetNW2Float("MEXTunnelRadius", 170),
        self:GetNW2Float("MEXTunnelWidth", 360),
        self:GetNW2Float("MEXTunnelHeight", 280),
        self:GetNW2Float("MEXTunnelWall", 12),
        self:GetNW2Int("MEXTrackCount", 1),
        self:GetNW2Float("MEXTrackSpacing", 240)
    )

    self:PhysicsInitMultiConvex(convexes)
    self:EnableCustomCollisions(true)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Sleep()
    end
end

if CLIENT then
    local fallbackRailMaterial = Material("metrostroi/metro_railroad_001")
    local fallbackSleeperMaterial = Material("models/props_c17/furniturefabric003a")

    local function RemoveModelPieces(self)
        if not istable(self.MEXModelPieces) then
            self.MEXModelPieces = {}
            return
        end

        for _, piece in ipairs(self.MEXModelPieces) do
            if IsValid(piece) then
                piece:Remove()
            end
        end

        self.MEXModelPieces = {}
    end

    local function DrawFallbackTrack(self, length, gauge, railWidth, railHeight, sleeperSpacing, sleeperLength, sleeperWidth, sleeperHeight)
        local halfLength = length * 0.5
        local ang = self:GetAngles()

        if not fallbackSleeperMaterial:IsError() then
            render.SetMaterial(fallbackSleeperMaterial)
        else
            render.SetColorMaterial()
        end

        local sleeperCount = math.Clamp(math.floor(length / sleeperSpacing) + 1, 2, 96)
        local step = sleeperCount > 1 and length / (sleeperCount - 1) or length

        for i = 0, sleeperCount - 1 do
            local x = -halfLength + step * i
            render.DrawBox(
                self:LocalToWorld(Vector(x, 0, sleeperHeight * 0.5)),
                ang,
                Vector(-sleeperWidth * 0.5, -sleeperLength * 0.5, -sleeperHeight * 0.5),
                Vector(sleeperWidth * 0.5, sleeperLength * 0.5, sleeperHeight * 0.5),
                color_white,
                true
            )
        end

        if not fallbackRailMaterial:IsError() then
            render.SetMaterial(fallbackRailMaterial)
        else
            render.SetColorMaterial()
        end

        local railTop = self:GetNW2Float(
            "MEXRailSurfaceOffset",
            METROSTROI_RAIL_HEIGHT
        )
        local railBottom = 0
        local halfRail = railWidth * 0.5

        render.DrawBox(
            self:GetPos(),
            ang,
            Vector(-halfLength, gauge * 0.5 - halfRail, railBottom),
            Vector(halfLength, gauge * 0.5 + halfRail, railTop),
            color_white,
            true
        )
        render.DrawBox(
            self:GetPos(),
            ang,
            Vector(-halfLength, -gauge * 0.5 - halfRail, railBottom),
            Vector(halfLength, -gauge * 0.5 + halfRail, railTop),
            color_white,
            true
        )
    end

    local function NewTrackPiece(model)
        local piece = ClientsideModel(model, RENDERGROUP_OPAQUE)
        if IsValid(piece) then
            piece:SetNoDraw(true)
            piece:SetParent(nil)
        end
        return piece
    end

    local function EnsureModelPieces(self, model, count)
        self.MEXModelPieces = self.MEXModelPieces or {}

        for i = 1, count do
            local piece = self.MEXModelPieces[i]
            if not IsValid(piece) or piece:GetModel() ~= model then
                if IsValid(piece) then
                    piece:Remove()
                end
                self.MEXModelPieces[i] = NewTrackPiece(model)
            end
        end

        for i = #self.MEXModelPieces, count + 1, -1 do
            local piece = self.MEXModelPieces[i]
            if IsValid(piece) then
                piece:Remove()
            end
            self.MEXModelPieces[i] = nil
        end
    end

    local function DrawMetrostroiTiles(self, length, model)
        if not util.IsValidModel(model) then
            RemoveModelPieces(self)
            return false
        end

        EnsureModelPieces(self, model, 1)
        local probe = self.MEXModelPieces and self.MEXModelPieces[1]
        if not IsValid(probe) then return false end

        local mins = probe:OBBMins()
        local maxs = probe:OBBMaxs()
        local size = maxs - mins

        -- railroad16 may be authored along local X or local Y. Pick the
        -- horizontal axis whose model extent is closest to the known 16-SU
        -- tile length instead of assuming the largest OBB axis is forward.
        local axisIsX = math.abs(size.x - 16) <= math.abs(size.y - 16)
        local tileLength = math.max(axisIsX and size.x or size.y, 4)

        -- The native model has an 80-SU inner gap, i.e. 85.8 SU between rail
        -- centres (sh_rerail.lua). Keep its native dimensions at the default.
        -- Scale only if a player deliberately selects a custom gauge; the
        -- model OBB also contains sleepers, so it cannot measure the gauge.
        local gauge = self:GetNW2Float("MEXPhysicalGauge", DEFAULT_TRACK_GAUGE)
        local lateralScale = gauge / METROSTROI_MODEL_GAUGE

        -- Full-size Metrostroi tiles are repeated. Their spacing is at most
        -- their real length, so adjacent pieces may overlap slightly but can
        -- never leave a visible gap.
        local count = math.Clamp(math.ceil(length / tileLength), 1, 96)
        EnsureModelPieces(self, model, count)

        local step = length / count
        local firstX = -length * 0.5 + step * 0.5
        local localCorrection = axisIsX and Angle(0, 0, 0) or Angle(0, -90, 0)
        local pieceAng = self:LocalToWorldAngles(localCorrection)
        local railSurface = self:GetNW2Float(
            "MEXRailSurfaceOffset",
            METROSTROI_RAIL_HEIGHT
        )

        for i = 1, count do
            local piece = self.MEXModelPieces[i]
            if IsValid(piece) then
                local pmins = piece:OBBMins()
                local pmaxs = piece:OBBMaxs()
                local center = (pmins + pmaxs) * 0.5

                -- Client-only scaling: the server's twin-rail convexes use
                -- the selected gauge and width, matching these visible rails.
                local matrix = Matrix()
                if axisIsX then
                    matrix:Scale(Vector(1, lateralScale, 1))
                else
                    matrix:Scale(Vector(lateralScale, 1, 1))
                end
                piece:EnableMatrix("RenderMultiply", matrix)

                -- The previous renderer placed MODEL BOTTOM at the spline
                -- plane. That assumes the model's height equals Metrostroi's
                -- 10-SU running surface, which is not guaranteed. Anchor the
                -- MODEL TOP to the exact physical/rerail rail surface instead.
                -- Thus what the wheel visually touches is the same Z used by
                -- collision and RerailGetTrackData.
                local anchor = Vector(
                    axisIsX and center.x or center.x * lateralScale,
                    axisIsX and center.y * lateralScale or center.y,
                    pmaxs.z
                )
                anchor:Rotate(pieceAng)

                local x = firstX + (i - 1) * step
                local target = self:LocalToWorld(
                    Vector(x, 0, railSurface)
                )

                piece:SetRenderOrigin(target - anchor)
                piece:SetRenderAngles(pieceAng)
                piece:DrawModel()
                piece:SetRenderOrigin(nil)
                piece:SetRenderAngles(nil)
            end
        end

        return true
    end

    function TrackEntity:OnRemove()
        RemoveModelPieces(self)
        Builder.Geometry.ClearClientMeshes(self)
    end

    function TrackEntity:Draw()
        if self:GetNW2Bool("MEXRigidSection", false)
            and Builder.Geometry.DrawPackModel(self) then
            return
        end
        if self:GetNW2Bool("MEXFastGeometry", true)
            or self:GetNW2Int("MEXTrackCount", 1) == 2 then
            Builder.Geometry.Draw(self)
            return
        end
        local length = math.max(self:GetNW2Float("MEXLength", 1), 1)
        local gauge = math.max(self:GetNW2Float("MEXPhysicalGauge", DEFAULT_TRACK_GAUGE), 8)
        local railWidth = math.max(self:GetNW2Float("MEXPhysicalRailWidth", METROSTROI_RAIL_WIDTH), 1)
        local railHeight = math.max(self:GetNW2Float("MEXRailHeight", METROSTROI_RAIL_HEIGHT), 1)
        local sleeperSpacing = math.max(self:GetNW2Float("MEXSleeperSpacing", 32), 8)
        local sleeperLength = math.max(self:GetNW2Float("MEXSleeperLength", 128), gauge + 16)
        local sleeperWidth = math.max(self:GetNW2Float("MEXSleeperWidth", 10), 2)
        local sleeperHeight = math.max(self:GetNW2Float("MEXSleeperHeight", 5), 1)
        local model = SafeTrackModel(self:GetNW2String("MEXTrackModel", DEFAULT_TRACK_MODEL))

        if self.SetRenderBounds then
            local scaledHalfWidth = sleeperLength * 0.5
                * math.max(1, gauge / METROSTROI_MODEL_GAUGE)
            local halfWidth = math.max(sleeperLength * 0.5, scaledHalfWidth, gauge * 0.5 + railWidth) + 32
            self:SetRenderBounds(
                Vector(-length * 0.5 - 32, -halfWidth, -16),
                Vector(length * 0.5 + 32, halfWidth, sleeperHeight + railHeight + 32)
            )
        end

        if self:GetNW2Bool("MEXUseTrackModel", true)
            and DrawMetrostroiTiles(self, length, model)
        then
            return
        end

        RemoveModelPieces(self)
        DrawFallbackTrack(
            self,
            length,
            gauge,
            railWidth,
            railHeight,
            sleeperSpacing,
            sleeperLength,
            sleeperWidth,
            sleeperHeight
        )
    end
end

scripted_ents.Register(TrackEntity, TRACK_CLASS)

-- Build reusable attachment nodes from the actually spawned smooth track.
-- Both server-side snapping and the client visualization use this exact
-- geometry, so the point the player sees is the point the new track uses.
local function CollectTrackSnapNodes(spacing)
    spacing = math.Clamp(tonumber(spacing) or 192, 32, 1024)
    local routes = {}
    for _, ent in ipairs(ents.FindByClass(TRACK_CLASS)) do
        if IsValid(ent) then
            local id = ent:GetNW2Int("MEXRouteID", 0)
            local index = ent:GetNW2Int("MEXSegmentIndex", 0)
            if id > 0 and index > 0 then
                routes[id] = routes[id] or {}
                routes[id][#routes[id] + 1] = {ent = ent, index = index}
            end
        end
    end

    local nodes, seen = {}, {}
    local function AddNodes(center, dir, ent, routeID, kind)
        if not isvector(center) or not isvector(dir) or dir:LengthSqr() < 0.000001 then return end
        dir = dir:GetNormalized()
        local right = dir:Cross(Vector(0, 0, 1))
        if right:LengthSqr() < 0.001 then right = ent:GetAngles():Right() end
        right:Normalize()
        local count = ent:GetNW2Int("MEXTrackCount", 1) == 2 and 2 or 1
        local distance = ent:GetNW2Float("MEXTrackSpacing", 240)
        for lane = 1, count do
            local offset = count == 2 and (lane == 1 and -distance * 0.5 or distance * 0.5) or 0
            local point = center + right * offset
            -- Uniqueness is PER LANE, not per tunnel center. Double-track
            -- layouts must expose both their separate attachment points.
            local key = string.format("%d:%d:%d:%d:%d", routeID, lane,
                math.Round(point.x), math.Round(point.y), math.Round(point.z))
            local previous = seen[key]
            if previous then
                if kind == "start" or kind == "end" then previous.kind = kind end
            else
                local node = {
                    pos = point,
                    center_pos = center,
                    dir = dir,
                    route_id = routeID,
                    kind = kind or "mid",
                    track_count = count,
                    track_spacing = distance,
                    lane = lane,
                }
                nodes[#nodes + 1] = node
                seen[key] = node
            end
        end
    end

    for routeID, pieces in pairs(routes) do
        table.sort(pieces, function(a, b) return a.index < b.index end)
        local first = pieces[1] and pieces[1].ent
        local last = pieces[#pieces] and pieces[#pieces].ent
        if IsValid(first) and IsValid(last) then
            local firstLen = first:GetNW2Float("MEXLength", 0)
            local firstDir = first:GetAngles():Forward():GetNormalized()
            AddNodes(first:GetPos() - firstDir * firstLen * 0.5, firstDir, first, routeID, "start")
            local untilNext = spacing
            for pieceIndex, entry in ipairs(pieces) do
                local ent = entry.ent
                if IsValid(ent) then
                    local length = math.max(ent:GetNW2Float("MEXLength", 0), 0)
                    local dir = ent:GetAngles():Forward():GetNormalized()
                    local segStart = ent:GetPos() - dir * length * 0.5
                    local cursor = 0
                    while length > 0 and cursor + untilNext <= length do
                        cursor = cursor + untilNext
                        local tangent = dir
                        if cursor >= length - 0.5 and pieces[pieceIndex + 1] then
                            local nextEnt = pieces[pieceIndex + 1].ent
                            if IsValid(nextEnt) then
                                local blended = dir + nextEnt:GetAngles():Forward():GetNormalized()
                                if blended:LengthSqr() > 0.00001 then tangent = blended:GetNormalized() end
                            end
                        end
                        AddNodes(segStart + dir * cursor, tangent, ent, routeID, "mid")
                        untilNext = spacing
                    end
                    untilNext = untilNext - (length - cursor)
                    if untilNext <= 0.001 then untilNext = spacing end
                end
            end
            local lastLen = last:GetNW2Float("MEXLength", 0)
            local lastDir = last:GetAngles():Forward():GetNormalized()
            AddNodes(last:GetPos() + lastDir * lastLen * 0.5, lastDir, last, routeID, "end")
        end
    end
    return nodes
end

if CLIENT then
    local snapCache = {}
    local nextSnapCache = 0

    local function TrackBuilderSelected()
        local ply = LocalPlayer()
        if not IsValid(ply) then return false end

        local weapon = ply:GetActiveWeapon()
        return IsValid(weapon)
            and weapon:GetClass() == "gmod_tool"
            and weapon:GetMode() == "mex_track_builder"
    end

    hook.Add("PostDrawTranslucentRenderables", "MEXTrackBuilderPreview", function()
        if not TrackBuilderSelected() then return end

        local ply = LocalPlayer()
        local tr = ply:GetEyeTrace()

        local showNodes = GetConVar("mex_track_builder_show_snap_nodes")
        local spacingCvar = GetConVar("mex_track_builder_snap_node_spacing")
        local distanceCvar = GetConVar("mex_track_builder_snap_distance")

        if showNodes and showNodes:GetBool() then
            if CurTime() >= nextSnapCache then
                snapCache = CollectTrackSnapNodes(
                    spacingCvar and spacingCvar:GetFloat() or 192
                )
                nextSnapCache = CurTime() + 0.2
            end

            local snapDistance = distanceCvar and distanceCvar:GetFloat() or 24
            local nearest
            local nearestDist = snapDistance * snapDistance

            if tr.Hit then
                for _, node in ipairs(snapCache) do
                    local dist = tr.HitPos:DistToSqr(node.pos)
                    if dist <= nearestDist then
                        nearestDist = dist
                        nearest = node
                    end
                end
            end

            render.SetColorMaterial()

            for _, node in ipairs(snapCache) do
                if ply:GetPos():DistToSqr(node.pos) <= 5000 * 5000 then
                    local selected = node == nearest
                    local color

                    if selected then
                        color = Color(255, 190, 40)
                    elseif node.kind == "start" or node.kind == "end" then
                        color = Color(80, 255, 100)
                    else
                        color = Color(70, 190, 255)
                    end

                    render.DrawWireframeSphere(
                        node.pos,
                        selected and 8 or 5,
                        8,
                        8,
                        color,
                        true
                    )
                    render.DrawLine(
                        node.pos - node.dir * 12,
                        node.pos + node.dir * 12,
                        color,
                        true
                    )
                end
            end
        end

        if ply:GetNW2Bool("MEXTrackBuilderLoopActive", false) then
            local loopStart = ply:GetNW2Vector(
                "MEXTrackBuilderLoopStart",
                vector_origin
            )

            if loopStart ~= vector_origin then
                render.SetColorMaterial()
                render.DrawWireframeSphere(
                    loopStart,
                    10,
                    12,
                    12,
                    Color(255, 80, 220),
                    true
                )

                if tr.Hit then
                    render.DrawLine(
                        loopStart,
                        tr.HitPos,
                        Color(255, 80, 220),
                        true
                    )
                end
            end
        end

        if not ply:GetNW2Bool("MEXTrackBuilderActive", false) then return end

        local startPos = ply:GetNW2Vector("MEXTrackBuilderStart", vector_origin)
        if startPos == vector_origin or not tr.Hit then return end

        render.SetColorMaterial()
        render.DrawLine(startPos, tr.HitPos, Color(80, 220, 100), true)
        render.DrawWireframeSphere(startPos, 5, 8, 8, Color(80, 220, 100), true)
        render.DrawWireframeSphere(tr.HitPos, 5, 8, 8, Color(255, 185, 60), true)
    end)

    return
end

Builder.Routes = Builder.Routes or {}
Builder.Active = Builder.Active or {}
Builder.LoopStart = Builder.LoopStart or {}
Builder.LastRoute = Builder.LastRoute or {}

local DATA_DIR = "metrostroi_expanded"
local NETWORK_DIR = "metrostroi_data"

local function LayoutPath()
    return string.format("%s/tracks_%s.txt", DATA_DIR, game.GetMap())
end

local function BaseTrackPath()
    return string.format("%s/base_track_%s.txt", DATA_DIR, game.GetMap())
end

local function MetrostroiTrackPath()
    return string.format("%s/track_%s.txt", NETWORK_DIR, game.GetMap())
end

local function MetrostroiDefaultTrackPath()
    return string.format("metrostroi_data/track_%s.lua", game.GetMap())
end

local function EnsureDirectories()
    if not file.Exists(DATA_DIR, "DATA") then
        file.CreateDir(DATA_DIR)
    end
    if not file.Exists(NETWORK_DIR, "DATA") then
        file.CreateDir(NETWORK_DIR)
    end
end

local function NormalizeVector(value)
    if isvector(value) then return value end

    if isstring(value) then
        local x, y, z = string.match(
            value,
            "^%[?%s*([%+%-]?[%d%.eE]+)%s+([%+%-]?[%d%.eE]+)%s+([%+%-]?[%d%.eE]+)%s*%]?$"
        )
        if x and y and z then
            return Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
        end
        return nil
    end

    if not istable(value) then return nil end

    return Vector(
        tonumber(value.x or value[1] or value["1"]) or 0,
        tonumber(value.y or value[2] or value["2"]) or 0,
        tonumber(value.z or value[3] or value["3"]) or 0
    )
end

local function OrderedNumericValues(tbl)
    local entries = {}
    for key, value in pairs(tbl or {}) do
        local numericKey = tonumber(key)
        if numericKey then
            entries[#entries + 1] = {key = numericKey, value = value}
        end
    end

    table.sort(entries, function(a, b)
        return a.key < b.key
    end)

    return entries
end

local function CopySettings(settings)
    settings = settings or {}
    return {
        gauge = math.Clamp(tonumber(settings.gauge) or DEFAULT_TRACK_GAUGE, 8, 200),
        rail_width = math.Clamp(tonumber(settings.rail_width) or METROSTROI_RAIL_WIDTH, 1, 24),
        rail_height = math.Clamp(tonumber(settings.rail_height) or METROSTROI_RAIL_HEIGHT, 1, 32),
        sleeper_spacing = math.Clamp(tonumber(settings.sleeper_spacing) or 32, 8, 256),
        sleeper_length = math.Clamp(tonumber(settings.sleeper_length) or 128, 24, 256),
        sleeper_width = math.Clamp(tonumber(settings.sleeper_width) or 10, 2, 64),
        sleeper_height = math.Clamp(tonumber(settings.sleeper_height) or 5, 1, 32),
        smooth = settings.smooth ~= false and tonumber(settings.smooth or 1) ~= 0,
        curve_tension = math.Clamp(tonumber(settings.curve_tension) or 0.45, 0.05, 0.85),
        segment_length = math.Clamp(tonumber(settings.segment_length) or 48, 16, 256),
        use_track_model = settings.use_track_model ~= false and tonumber(settings.use_track_model or 1) ~= 0,
        track_model = SafeTrackModel(settings.track_model),
        fast_geometry = settings.fast_geometry ~= false and tonumber(settings.fast_geometry or 1) ~= 0,
        -- Tunnel construction is part of the route and survives save/load.
        tunnel_type = Builder.Geometry.SafeTunnelType(settings.tunnel_type),
        tunnel_radius = math.Clamp(tonumber(settings.tunnel_radius) or 170, 140, 320),
        tunnel_width = math.Clamp(tonumber(settings.tunnel_width) or 360, 300, 640),
        tunnel_height = math.Clamp(tonumber(settings.tunnel_height) or 280, 230, 480),
        tunnel_wall = math.Clamp(tonumber(settings.tunnel_wall) or 12, 6, 32),
        -- Keep a high-resolution Metrostroi rail graph, but use fewer
        -- physical entities on long straight and gently curved sections.
        geometry_tolerance = math.Clamp(tonumber(settings.geometry_tolerance) or 0.5, 0.1, 2),
        geometry_max_length = math.Clamp(tonumber(settings.geometry_max_length) or 192, 64, 256),
        track_count = tonumber(settings.track_count) == 2 and 2 or 1,
        track_spacing = math.Clamp(tonumber(settings.track_spacing) or 240, 180, 400),
        rigid_section = settings.rigid_section == true or tonumber(settings.rigid_section or 0) == 1,
        rigid_length = math.Clamp(tonumber(settings.rigid_length) or 0, 0, 1024),
        pack_model = string.sub(tostring(settings.pack_model or ""), 1, 240),
        pack_z_offset = math.Clamp(tonumber(settings.pack_z_offset) or 0, -128, 128),
    }
end

local function AnchorDirection(anchor)
    if not istable(anchor) then return nil end

    local dir = NormalizeVector(anchor.dir)
    if not isvector(dir) or dir:LengthSqr() <= 0.000001 then
        return nil
    end

    return dir:GetNormalized()
end

local function PointTangent(points, index, tension, anchors)
    local count = #points
    if count < 2 then return vector_origin end

    local current = points[index]
    local direction
    local localLength

    if index <= 1 then
        direction = points[2] - current
        localLength = direction:Length()
    elseif index >= count then
        direction = current - points[count - 1]
        localLength = direction:Length()
    else
        local previous = points[index - 1]
        local nextPoint = points[index + 1]
        direction = nextPoint - previous
        localLength = math.min(
            current:Distance(previous),
            current:Distance(nextPoint)
        )
    end

    if not isvector(direction) or direction:LengthSqr() <= 0.000001 then
        return vector_origin
    end

    local anchorDir = AnchorDirection(anchors and anchors[index])
    if anchorDir then
        if anchorDir:Dot(direction) < 0 then
            anchorDir = -anchorDir
        end

        return anchorDir * math.max(localLength, 1) * tension
    end

    return direction:GetNormalized() * math.max(localLength, 1) * tension
end

local function HermitePoint(p0, p1, m0, m1, t)
    local t2 = t * t
    local t3 = t2 * t
    local h00 = 2 * t3 - 3 * t2 + 1
    local h10 = t3 - 2 * t2 + t
    local h01 = -2 * t3 + 3 * t2
    local h11 = t3 - t2

    return p0 * h00
        + m0 * h10
        + p1 * h01
        + m1 * h11
end

function Builder.BuildSmoothPoints(controlPoints, settings, anchors)
    settings = CopySettings(settings)

    local points = {}
    for _, value in ipairs(controlPoints or {}) do
        local point = NormalizeVector(value)
        if isvector(point) then
            points[#points + 1] = point
        end
    end

    if #points < 2 then
        return points
    end

    local output = {points[1]}

    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        local directLength = a:Distance(b)
        local steps = math.max(1, math.ceil(directLength / settings.segment_length))

        if not settings.smooth or settings.rigid_section then
            for step = 1, steps do
                output[#output + 1] = LerpVector(step / steps, a, b)
            end
        else
            local tangentA = PointTangent(
                points,
                i,
                settings.curve_tension,
                anchors
            )
            local tangentB = PointTangent(
                points,
                i + 1,
                settings.curve_tension,
                anchors
            )

            for step = 1, steps do
                local t = step / steps
                output[#output + 1] = HermitePoint(a, b, tangentA, tangentB, t)
            end
        end
    end

    return output
end

local function ReadPointArray(tbl)
    local result = {}

    for _, entry in ipairs(OrderedNumericValues(tbl or {})) do
        local point = NormalizeVector(entry.value)
        if isvector(point) then
            result[#result + 1] = point
        end
    end

    return result
end

local function ReadAnchors(tbl)
    local result = {}

    for key, value in pairs(tbl or {}) do
        local index = tonumber(key)
        if index and istable(value) then
            local dir = NormalizeVector(value.dir)
            if isvector(dir) and dir:LengthSqr() > 0.000001 then
                result[index] = {
                    dir = dir:GetNormalized(),
                }
            end
        end
    end

    return result
end

local function RouteRenderPoints(route)
    if not istable(route) then return {} end

    local generated = ReadPointArray(route.generated_points)
    if #generated >= 2 then
        return generated
    end

    return Builder.BuildSmoothPoints(
        route.points or {},
        route.settings,
        route.anchors
    )
end

Builder.GetRouteRenderPoints = RouteRenderPoints

local function SpawnSegment(a, b, settings, routeID, segmentIndex)
    if not isvector(a) or not isvector(b) then return nil end

    local delta = b - a
    local length = delta:Length()
    if length < 2 then return nil end

    settings = CopySettings(settings)

    local ent = ents.Create(TRACK_CLASS)
    if not IsValid(ent) then return nil end

    ent:SetPos((a + b) * 0.5)
    ent:SetAngles(delta:Angle())
    ent:SetNW2Float("MEXLength", length)
    ent:SetNW2Float("MEXGauge", settings.gauge)
    ent:SetNW2Float("MEXRailWidth", settings.rail_width)
    ent:SetNW2Float("MEXRailHeight", settings.rail_height)
    ent:SetNW2Float("MEXSleeperSpacing", settings.sleeper_spacing)
    ent:SetNW2Float("MEXSleeperLength", settings.sleeper_length)
    ent:SetNW2Float("MEXSleeperWidth", settings.sleeper_width)
    ent:SetNW2Float("MEXSleeperHeight", settings.sleeper_height)
    ent:SetNW2String("MEXTrackModel", settings.track_model)
    ent:SetNW2Bool("MEXUseTrackModel", settings.use_track_model)
    ent:SetNW2Bool("MEXFastGeometry", settings.fast_geometry)
    ent:SetNW2String("MEXTunnelType", settings.tunnel_type)
    ent:SetNW2Float("MEXTunnelRadius", settings.tunnel_radius)
    ent:SetNW2Float("MEXTunnelWidth", settings.tunnel_width)
    ent:SetNW2Float("MEXTunnelHeight", settings.tunnel_height)
    ent:SetNW2Float("MEXTunnelWall", settings.tunnel_wall)
    ent:SetNW2Int("MEXTrackCount", settings.track_count)
    ent:SetNW2Float("MEXTrackSpacing", settings.track_spacing)
    ent:SetNW2Bool("MEXRigidSection", settings.rigid_section)
    -- Only mounted models with real model metadata are accepted.
    local packModel = settings.pack_model
    if not settings.rigid_section
        or not string.match(packModel, "^models/[%w_/%-%.]+%.mdl$")
        or not util.IsValidModel(packModel)
    then
        packModel = ""
    end
    ent:SetNW2String("MEXPackModel", packModel)
    ent:SetNW2Float("MEXPackZOffset", settings.pack_z_offset)
    ent:SetNW2Int("MEXRouteID", routeID or 0)
    ent:SetNW2Int("MEXSegmentIndex", segmentIndex or 0)
    ent:Spawn()

    return ent
end

local function RemoveEntities(entities)
    for _, ent in ipairs(entities or {}) do
        if IsValid(ent) then
            ent:Remove()
        end
    end
end

-- Approximate the dense spline by long, low-error collision/render chords.
-- The original dense points are left unchanged for Metrostroi's rail network.
-- An individual static physics entity per 48 SU was the major cause of frame
-- spikes and unstable wheel contacts on long manually built routes.
function Builder.BuildGeometryPoints(points, settings)
    settings = CopySettings(settings)
    if settings.rigid_section then
        return #points >= 2 and {points[1], points[#points]} or points
    end
    if #points < 3 then return points end
    local result = {points[1]}
    local i = 1
    local maxLength = settings.geometry_max_length
    local maxErrorSqr = settings.geometry_tolerance * settings.geometry_tolerance
    while i < #points do
        local lastGood = i + 1
        local accumulated = 0
        for j = i + 1, #points do
            accumulated = accumulated + points[j]:Distance(points[j - 1])
            if accumulated > maxLength and j > i + 1 then break end
            local from, to = points[i], points[j]
            local delta = to - from
            local lengthSqr = delta:LengthSqr()
            if lengthSqr < 0.00001 then break end
            local accurate = true
            for k = i + 1, j - 1 do
                local fraction = math.Clamp((points[k] - from):Dot(delta) / lengthSqr, 0, 1)
                local projection = from + delta * fraction
                if projection:DistToSqr(points[k]) > maxErrorSqr then
                    accurate = false
                    break
                end
            end
            if not accurate then break end
            lastGood = j
        end
        result[#result + 1] = points[lastGood]
        i = lastGood
    end
    return result
end

local function SpawnPolyline(points, settings, routeID)
    local entities = {}
    -- Physical route is intentionally simpler than the fine-grained rail graph.
    local geometryPoints = Builder.BuildGeometryPoints(points, settings)

    for i = 1, #geometryPoints - 1 do
        local ent = SpawnSegment(geometryPoints[i], geometryPoints[i + 1], settings, routeID, i)
        if IsValid(ent) then
            entities[#entities + 1] = ent
        end
    end

    return entities
end

local function SetActiveStart(ply, pos)
    if not IsValid(ply) then return end

    if isvector(pos) then
        ply:SetNW2Bool("MEXTrackBuilderActive", true)
        ply:SetNW2Vector("MEXTrackBuilderStart", pos)
    else
        ply:SetNW2Bool("MEXTrackBuilderActive", false)
        ply:SetNW2Vector("MEXTrackBuilderStart", vector_origin)
    end
end

local function RebuildActiveRoute(active)
    if not active then return end

    active.render_points = Builder.BuildSmoothPoints(
        active.points,
        active.settings,
        active.anchors
    )

    -- Editing an already saved track after R must keep its route ID and
    -- update the saved geometry/network, not create a second overlapping
    -- route or turn the entire surviving track into a disposable preview.
    if active.edit_route then
        local routeID
        for id, route in ipairs(Builder.Routes) do
            if route == active.edit_route then
                routeID = id
                break
            end
        end
        if not routeID then return end

        local route = active.edit_route
        route.points = active.points
        route.anchors = active.anchors
        route.settings = CopySettings(active.settings)
        route.generated_points = nil
        route.kind = nil

        for _, ent in ipairs(ents.FindByClass(TRACK_CLASS)) do
            if IsValid(ent) and ent:GetNW2Int("MEXRouteID", 0) == routeID then
                ent:Remove()
            end
        end
        SpawnPolyline(active.render_points, route.settings, routeID)
        Builder.SaveLayout()
        if route.network then
            Builder.RebuildMetrostroiNetwork()
        end
        return
    end

    RemoveEntities(active.entities)
    active.entities = SpawnPolyline(active.render_points, active.settings, 0)
end

function Builder.SaveLayout()
    EnsureDirectories()

    local payload = {
        version = 4,
        routes = Builder.Routes,
    }

    file.Write(LayoutPath(), util.TableToJSON(payload, true) or "{}")
end

function Builder.LoadLayout()
    Builder.Routes = {}

    if not file.Exists(LayoutPath(), "DATA") then return end

    local decoded = util.JSONToTable(file.Read(LayoutPath(), "DATA") or "")
    if not istable(decoded) or not istable(decoded.routes) then return end

    local previousVersion = tonumber(decoded.version) or 1
    local migrated = false

    for _, routeEntry in ipairs(OrderedNumericValues(decoded.routes)) do
        local route = routeEntry.value

        if istable(route) then
            local points = ReadPointArray(route.points)
            local generated = ReadPointArray(route.generated_points)

            if #points >= 2 or #generated >= 2 then
                local settings = CopySettings(route.settings)
                -- Previously saved defaults used 80 SU (v1/v2), then an
                -- overly wide 100 SU (v3). Bring both to the real Metrostroi
                -- rail-centre distance, while preserving custom gauges.
                local oldDefaultGauge = previousVersion < 3 and 80 or 100
                if previousVersion < 4
                    and math.abs(settings.gauge - oldDefaultGauge) < 0.01
                then
                    settings.gauge = DEFAULT_TRACK_GAUGE
                    migrated = true
                end
                Builder.Routes[#Builder.Routes + 1] = {
                    points = points,
                    generated_points = #generated >= 2 and generated or nil,
                    anchors = ReadAnchors(route.anchors),
                    settings = settings,
                    network = route.network ~= false,
                    kind = isstring(route.kind) and route.kind or nil,
                }
            end
        end
    end

    if migrated then
        Builder.SaveLayout()
    end
end

function Builder.RespawnAll()
    for _, ent in ipairs(ents.FindByClass(TRACK_CLASS)) do
        if IsValid(ent) and ent:GetNW2Int("MEXRouteID", 0) > 0 then
            ent:Remove()
        end
    end

    for routeID, route in ipairs(Builder.Routes) do
        local settings = CopySettings(route.settings)
        local points = RouteRenderPoints(route)
        SpawnPolyline(points, settings, routeID)
    end
end

local function RuntimeTrackFallback()
    local result = {}
    if not Metrostroi or not istable(Metrostroi.Paths) then return result end

    for _, pathEntry in ipairs(OrderedNumericValues(Metrostroi.Paths)) do
        local path = pathEntry.value
        local points = {}
        if istable(path) then
            for _, nodeEntry in ipairs(OrderedNumericValues(path)) do
                local node = nodeEntry.value
                if istable(node) and isvector(node.pos) then
                    points[#points + 1] = node.pos
                end
            end
        end
        if #points >= 2 then
            result[pathEntry.key] = points
        end
    end

    return result
end

local function ReadJSONTrack(path, realm)
    if not file.Exists(path, realm) then return nil end
    local decoded = util.JSONToTable(file.Read(path, realm) or "")
    if not istable(decoded) then return nil end
    return decoded
end

function Builder.EnsureBaseTrack()
    EnsureDirectories()

    local cached = ReadJSONTrack(BaseTrackPath(), "DATA")
    if istable(cached) then return cached end

    local base = ReadJSONTrack(MetrostroiTrackPath(), "DATA")
        or ReadJSONTrack(MetrostroiDefaultTrackPath(), "LUA")
        or RuntimeTrackFallback()

    file.Write(BaseTrackPath(), util.TableToJSON(base, true) or "[]")
    return base
end

local function NetworkPoints(route)
    local settings = CopySettings(route.settings)
    local points = RouteRenderPoints(route)
    local result = {}
    if #points < 2 then return result end
    local tracks = settings.track_count
    for lane = 1, tracks do
        local path = {}
        local sideways = tracks == 2 and (lane == 1 and -settings.track_spacing * 0.5 or settings.track_spacing * 0.5) or 0
        for i, point in ipairs(points) do
            local previous = points[math.max(1, i - 1)]
            local following = points[math.min(#points, i + 1)]
            local tangent = following - previous
            if tangent:LengthSqr() < 0.00001 then tangent = Vector(1, 0, 0) end
            tangent:Normalize()
            local right = tangent:Cross(Vector(0, 0, 1))
            if right:LengthSqr() < 0.001 then right = Vector(0, -1, 0) end
            right:Normalize()
            path[#path + 1] = point + right * sideways + Vector(0, 0, METROSTROI_RAIL_HEIGHT)
        end
        result[#result + 1] = path
    end
    return result
end

function Builder.RebuildMetrostroiNetwork(notifyPly)
    EnsureDirectories()

    local base = Builder.EnsureBaseTrack()
    local merged = {}
    local maxPathID = 0

    for key, path in pairs(base or {}) do
        local numericKey = tonumber(key)
        if numericKey then
            merged[numericKey] = path
            maxPathID = math.max(maxPathID, numericKey)
        else
            merged[key] = path
        end
    end

    for _, route in ipairs(Builder.Routes) do
        if route.network ~= false then
            for _, points in ipairs(NetworkPoints(route)) do
                if #points >= 2 then
                    maxPathID = maxPathID + 1
                    merged[maxPathID] = points
                end
            end
        end
    end

    file.Write(MetrostroiTrackPath(), util.TableToJSON(merged, true) or "[]")

    if IsValid(notifyPly) then
        notifyPly:ChatPrint("[MEX Track Builder] Smooth track data saved. Reloading Metrostroi rail network...")
    end

    if Metrostroi and isfunction(Metrostroi.Load) then
        timer.Create("MEXTrackBuilderReloadNetwork", 0.15, 1, function()
            if Metrostroi and isfunction(Metrostroi.Load) then
                Metrostroi.Load(game.GetMap(), true)
            end
        end)
    elseif IsValid(notifyPly) then
        notifyPly:ChatPrint("[MEX Track Builder] Metrostroi.Load is unavailable; data was saved for the next map load.")
    end
end

function Builder.SnapPoint(pos, maxDistance, spacing, settings)
    if not isvector(pos) then return pos, nil end

    maxDistance = math.Clamp(tonumber(maxDistance) or 24, 1, 256)

    local best
    local bestDistSqr = maxDistance * maxDistance

    local wantDouble = istable(settings) and tonumber(settings.track_count) == 2
    for _, node in ipairs(CollectTrackSnapNodes(spacing)) do
        local distSqr = pos:DistToSqr(node.pos)

        if (not wantDouble or node.track_count == 2) and distSqr < bestDistSqr then
            best = node
            bestDistSqr = distSqr
        end
    end

    if best then
        -- For DOUBLE, clicking either of its two rail nodes snaps the new
        -- tunnel CENTERLINE. For SINGLE, the same click targets that one lane.
        return wantDouble and best.center_pos or best.pos, best
    end

    return pos, nil
end

function Builder.AddPoint(ply, pos, settings, anchor)
    if not IsValid(ply) or not ply:IsAdmin() or not isvector(pos) then return false end

    local active = Builder.Active[ply]
    if not active then
        local newSettings = CopySettings(settings)
        if istable(anchor) and newSettings.track_count == 2 and anchor.track_count == 2 then
            newSettings.track_spacing = anchor.track_spacing
        end
        active = {
            points = {pos},
            anchors = {},
            entities = {},
            render_points = {},
            settings = newSettings,
        }

        if istable(anchor) and isvector(anchor.dir) then
            active.anchors[1] = {
                dir = anchor.dir:GetNormalized(),
            }
        end
        Builder.Active[ply] = active
        SetActiveStart(ply, pos)
        ply:ChatPrint("[MEX Track Builder] Start point set. Add control points; curves are smoothed automatically.")
        return true
    end

    if active.settings.rigid_section and #active.points >= 2 then
        ply:ChatPrint("[MEX Track Builder] Rigid station section has two endpoints. RMB saves it; start a new route to continue.")
        return false
    end

    -- A rigid station is one perfectly straight structural element. A fixed
    -- length is optional; snapping to an existing endpoint takes priority.
    local previous = active.points[#active.points]
    if active.settings.rigid_section
        and active.settings.rigid_length > 0
        and #active.points == 1
        and not (istable(anchor) and anchor.kind == "end")
    then
        local delta = pos - previous
        if delta:LengthSqr() > 0.0001 then
            local dir = delta:GetNormalized()
            local locked = AnchorDirection(active.anchors[1])
            if locked and math.abs(locked:Dot(dir)) > 0.7 then
                if locked:Dot(dir) < 0 then locked = -locked end
                dir = locked
            end
            pos = previous + dir * active.settings.rigid_length
        end
    end

    if active.settings.track_count == 2 and istable(anchor) and anchor.track_count == 2
        and math.abs(active.settings.track_spacing - anchor.track_spacing) > 0.1 then
        ply:ChatPrint("[MEX Track Builder] Double-track spacing mismatch. Start a new route at matching spacing.")
        return false
    end

    if previous:DistToSqr(pos) < 64 then
        return false
    end

    active.points[#active.points + 1] = pos

    if istable(anchor) and isvector(anchor.dir) then
        active.anchors[#active.points] = {
            dir = anchor.dir:GetNormalized(),
        }
    end

    RebuildActiveRoute(active)
    SetActiveStart(ply, pos)

    return true
end

local PI = math.pi
local TWO_PI = PI * 2

local function Atan2(y, x)
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + PI
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - PI
    elseif x == 0 and y > 0 then
        return PI * 0.5
    elseif x == 0 and y < 0 then
        return -PI * 0.5
    end

    return 0
end

local function PositiveAngle(angle)
    while angle < 0 do
        angle = angle + TWO_PI
    end
    while angle >= TWO_PI do
        angle = angle - TWO_PI
    end
    return angle
end

local function OrientedDirection(dir, fallback)
    dir = NormalizeVector(dir)

    if not isvector(dir) or dir:LengthSqr() <= 0.000001 then
        if isvector(fallback) and fallback:LengthSqr() > 0.000001 then
            return fallback:GetNormalized()
        end
        return Vector(1, 0, 0)
    end

    dir = dir:GetNormalized()

    if isvector(fallback)
        and fallback:LengthSqr() > 0.000001
        and dir:Dot(fallback) < 0
    then
        dir = -dir
    end

    return dir
end

local function HermiteSegment(p0, p1, dir0, dir1, steps, handle)
    steps = math.max(math.floor(steps or 2), 2)
    handle = math.max(tonumber(handle) or p0:Distance(p1) * 0.75, 1)

    local m0 = OrientedDirection(dir0, p1 - p0) * handle
    local m1 = OrientedDirection(dir1, p1 - p0) * handle
    local result = {}

    for i = 0, steps do
        result[#result + 1] = HermitePoint(
            p0,
            p1,
            m0,
            m1,
            i / steps
        )
    end

    return result
end

local function EstimateMinRadius(points)
    local best = math.huge

    for i = 2, #points - 1 do
        local p0 = points[i - 1]
        local p1 = points[i]
        local p2 = points[i + 1]

        local a = p0:Distance(p1)
        local b = p1:Distance(p2)
        local c = p2:Distance(p0)
        local cross = (p1 - p0):Cross(p2 - p0):Length()

        if a > 0.001
            and b > 0.001
            and c > 0.001
            and cross > 0.001
        then
            local radius = (a * b * c) / (2 * cross)
            best = math.min(best, radius)
        end
    end

    return best
end

local function EstimateMaxGrade(points)
    local maxGrade = 0

    for i = 1, #points - 1 do
        local delta = points[i + 1] - points[i]
        local horizontal = math.sqrt(delta.x * delta.x + delta.y * delta.y)

        if horizontal > 0.001 then
            maxGrade = math.max(
                maxGrade,
                math.abs(delta.z) / horizontal * 100
            )
        end
    end

    return maxGrade
end

local function LoopCandidate(startPos, endPos, startAnchor, endAnchor, radius, settings, center)
    local startAngle = Atan2(
        startPos.y - center.y,
        startPos.x - center.x
    )
    local endAngle = Atan2(
        endPos.y - center.y,
        endPos.x - center.x
    )

    local positiveSweep = PositiveAngle(endAngle - startAngle)
    local sweep

    -- The long arc is the actual loop. The short arc would merely connect
    -- the two selected points with an ordinary bend.
    if positiveSweep > PI then
        sweep = positiveSweep
    else
        sweep = positiveSweep - TWO_PI
    end

    local sign = sweep >= 0 and 1 or -1

    local function CircleTangent(angle)
        return Vector(
            -math.sin(angle) * sign,
            math.cos(angle) * sign,
            0
        )
    end

    local score = 0

    local startDir = AnchorDirection(startAnchor)
    if startDir then
        score = score + math.abs(
            startDir:Dot(CircleTangent(startAngle))
        )
    else
        score = score + 0.5
    end

    local endDir = AnchorDirection(endAnchor)
    if endDir then
        score = score + math.abs(
            endDir:Dot(CircleTangent(endAngle))
        )
    else
        score = score + 0.5
    end

    local arcLength = math.abs(sweep) * radius
    local stepLength = math.Clamp(
        tonumber(settings.segment_length) or 48,
        16,
        96
    )
    local steps = math.Clamp(
        math.ceil(arcLength / stepLength),
        24,
        1024
    )

    local raw = {}

    for i = 0, steps do
        local t = i / steps
        local angle = startAngle + sweep * t

        raw[#raw + 1] = Vector(
            center.x + math.cos(angle) * radius,
            center.y + math.sin(angle) * radius,
            Lerp(t, startPos.z, endPos.z)
        )
    end

    raw[1] = startPos
    raw[#raw] = endPos

    -- Blend the circle tangentially into snapped existing track. This avoids
    -- a visible kink even though a generic pair of selected points does not
    -- mathematically define a circle with both required endpoint tangents.
    local transitionDistance = math.min(
        radius * 0.30,
        math.max(256, radius * 0.18)
    )
    local transitionSteps = math.Clamp(
        math.ceil(transitionDistance / stepLength),
        3,
        math.floor((#raw - 3) / 4)
    )

    if transitionSteps >= 3 and #raw >= transitionSteps * 2 + 5 then
        local startJoinIndex = 1 + transitionSteps
        local endJoinIndex = #raw - transitionSteps

        local startJoin = raw[startJoinIndex]
        local endJoin = raw[endJoinIndex]

        local startCircleDir = (
            raw[startJoinIndex + 1]
            - raw[startJoinIndex - 1]
        ):GetNormalized()

        local endCircleDir = (
            raw[endJoinIndex + 1]
            - raw[endJoinIndex - 1]
        ):GetNormalized()

        local chosenStartDir = startDir
            and OrientedDirection(startDir, startJoin - startPos)
            or (startJoin - startPos):GetNormalized()

        local chosenEndDir = endDir
            and OrientedDirection(endDir, endPos - endJoin)
            or (endPos - endJoin):GetNormalized()

        local startBlend = HermiteSegment(
            startPos,
            startJoin,
            chosenStartDir,
            startCircleDir,
            transitionSteps,
            math.max(startPos:Distance(startJoin) * 0.85, 64)
        )

        local endBlend = HermiteSegment(
            endJoin,
            endPos,
            endCircleDir,
            chosenEndDir,
            transitionSteps,
            math.max(endJoin:Distance(endPos) * 0.85, 64)
        )

        local blended = {}

        for i = 1, #startBlend - 1 do
            blended[#blended + 1] = startBlend[i]
        end

        for i = startJoinIndex, endJoinIndex do
            blended[#blended + 1] = raw[i]
        end

        for i = 2, #endBlend do
            blended[#blended + 1] = endBlend[i]
        end

        raw = blended
    end

    return {
        points = raw,
        score = score,
        radius = radius,
        min_radius = EstimateMinRadius(raw),
        max_grade = EstimateMaxGrade(raw),
    }
end

function Builder.BuildSafeLoop(startInfo, endInfo, settings, minRadius, maxGrade)
    if not istable(startInfo) or not istable(endInfo) then return nil end

    local startPos = NormalizeVector(startInfo.pos)
    local endPos = NormalizeVector(endInfo.pos)

    if not isvector(startPos) or not isvector(endPos) then return nil end

    local chord = Vector(
        endPos.x - startPos.x,
        endPos.y - startPos.y,
        0
    )
    local chordLength = chord:Length()

    if chordLength < 32 then
        return nil, "Start and end are too close."
    end

    settings = CopySettings(settings)
    minRadius = math.Clamp(tonumber(minRadius) or 3072, 512, 16384)
    maxGrade = math.Clamp(tonumber(maxGrade) or 4, 0.5, 12)

    local radius = math.max(
        minRadius,
        chordLength * 0.505
    )

    local best
    local lastBest

    for _ = 1, 7 do
        local midpoint = (startPos + endPos) * 0.5
        local perpendicular = Vector(
            -chord.y / chordLength,
            chord.x / chordLength,
            0
        )

        local halfChord = chordLength * 0.5
        local offset = math.sqrt(
            math.max(radius * radius - halfChord * halfChord, 0)
        )

        local centerA = midpoint + perpendicular * offset
        local centerB = midpoint - perpendicular * offset

        local candidateA = LoopCandidate(
            startPos,
            endPos,
            startInfo.anchor,
            endInfo.anchor,
            radius,
            settings,
            centerA
        )

        local candidateB = LoopCandidate(
            startPos,
            endPos,
            startInfo.anchor,
            endInfo.anchor,
            radius,
            settings,
            centerB
        )

        if candidateA.score >= candidateB.score then
            best = candidateA
        else
            best = candidateB
        end

        lastBest = best

        local radiusSafe = best.min_radius == math.huge
            or best.min_radius >= minRadius * 0.90
        local gradeSafe = best.max_grade <= maxGrade

        if radiusSafe and gradeSafe then
            return best
        end

        radius = radius * 1.25
    end

    return lastBest
end

function Builder.CancelAutoLoop(ply, silent)
    if not Builder.LoopStart[ply] then return false end

    Builder.LoopStart[ply] = nil

    if IsValid(ply) then
        ply:SetNW2Bool("MEXTrackBuilderLoopActive", false)
        ply:SetNW2Vector("MEXTrackBuilderLoopStart", vector_origin)

        if not silent then
            ply:ChatPrint("[MEX Track Builder] Auto loop start cancelled.")
        end
    end

    return true
end

function Builder.AutoLoopClick(
    ply,
    pos,
    anchor,
    settings,
    minRadius,
    maxGrade,
    network
)
    if not IsValid(ply)
        or not ply:IsAdmin()
        or not isvector(pos)
    then
        return false
    end

    local start = Builder.LoopStart[ply]

    if not start then
        Builder.CancelRoute(ply, true)

        Builder.LoopStart[ply] = {
            pos = pos,
            anchor = anchor,
            settings = CopySettings(settings),
        }

        ply:SetNW2Bool("MEXTrackBuilderLoopActive", true)
        ply:SetNW2Vector("MEXTrackBuilderLoopStart", pos)
        ply:ChatPrint(
            "[MEX Track Builder] Auto loop start selected. "
            .. "Click the end point; the safest large-radius loop will be generated."
        )

        return true
    end

    local result, reason = Builder.BuildSafeLoop(
        start,
        {
            pos = pos,
            anchor = anchor,
        },
        start.settings,
        minRadius,
        maxGrade
    )

    if not result or not istable(result.points) or #result.points < 3 then
        if isstring(reason) then
            ply:ChatPrint("[MEX Track Builder] " .. reason)
        end
        return false
    end

    local route = {
        points = {
            start.pos,
            pos,
        },
        anchors = {
            [1] = istable(start.anchor)
                and isvector(start.anchor.dir)
                and {dir = start.anchor.dir:GetNormalized()}
                or nil,
            [2] = istable(anchor)
                and isvector(anchor.dir)
                and {dir = anchor.dir:GetNormalized()}
                or nil,
        },
        generated_points = result.points,
        settings = CopySettings(start.settings),
        network = network ~= false,
        kind = "auto_loop",
    }

    Builder.Routes[#Builder.Routes + 1] = route
    Builder.LastRoute[ply] = route
    local routeID = #Builder.Routes

    SpawnPolyline(
        route.generated_points,
        route.settings,
        routeID
    )

    Builder.LoopStart[ply] = nil
    ply:SetNW2Bool("MEXTrackBuilderLoopActive", false)
    ply:SetNW2Vector("MEXTrackBuilderLoopStart", vector_origin)

    Builder.SaveLayout()

    if route.network then
        Builder.RebuildMetrostroiNetwork(ply)
    end

    ply:ChatPrint(string.format(
        "[MEX Track Builder] Auto loop #%d created. Radius %.0f SU, measured minimum %.0f SU, max grade %.2f%%.",
        routeID,
        result.radius,
        result.min_radius == math.huge and result.radius or result.min_radius,
        result.max_grade
    ))

    return true
end


function Builder.CancelRoute(ply, silent)
    local active = Builder.Active[ply]
    if not active then return false end

    -- An edited, already saved route is kept. Cancel only exits edit mode;
    -- do not erase the existing track that R stepped back into.
    if not active.edit_route then
        RemoveEntities(active.entities)
    end
    Builder.Active[ply] = nil
    SetActiveStart(ply, nil)

    if IsValid(ply) and not silent then
        ply:ChatPrint(active.edit_route
            and "[MEX Track Builder] Editing stopped; saved track kept."
            or "[MEX Track Builder] Unfinished route cancelled.")
    end

    return true
end

function Builder.FinishRoute(ply, network)
    local active = Builder.Active[ply]
    if not active then return false end

    -- Undoing a saved route puts its endpoint back into edit mode. Adding
    -- points edits that same route in place; RMB only finishes the edit.
    if active.edit_route and #active.points >= 2 then
        Builder.Active[ply] = nil
        SetActiveStart(ply, nil)
        if IsValid(ply) then
            ply:ChatPrint("[MEX Track Builder] Saved route editing finished.")
        end
        return true
    end

    if #active.points < 2 then
        Builder.CancelRoute(ply, true)
        if IsValid(ply) then
            ply:ChatPrint("[MEX Track Builder] Route needs at least one segment.")
        end
        return false
    end

    RemoveEntities(active.entities)

    local route = {
        points = active.points,
        anchors = active.anchors,
        settings = CopySettings(active.settings),
        network = network ~= false,
    }

    Builder.Routes[#Builder.Routes + 1] = route
    Builder.LastRoute[ply] = route
    local routeID = #Builder.Routes
    local smoothPoints = RouteRenderPoints(route)
    SpawnPolyline(smoothPoints, route.settings, routeID)

    Builder.Active[ply] = nil
    SetActiveStart(ply, nil)
    Builder.SaveLayout()

    if route.network then
        Builder.RebuildMetrostroiNetwork(ply)
    end

    if IsValid(ply) then
        ply:ChatPrint(string.format(
            "[MEX Track Builder] Route #%d saved (%d control points, %d smooth pieces).",
            routeID,
            #route.points,
            math.max(#smoothPoints - 1, 0)
        ))
    end

    return true
end

-- R (tool Reload) undoes exactly one construction step. For an active route
-- this is its last control point. For a saved route we reopen the selected
-- (or most recently finished) route, remove one step and leave its surviving
-- endpoint selected so the next left click continues from there.
function Builder.UndoLastPoint(ply, routeID)
    if not IsValid(ply) or not ply:IsAdmin() then return false end

    if Builder.LoopStart[ply] then
        return Builder.CancelAutoLoop(ply)
    end

    local active = Builder.Active[ply]
    if not active then
        local route = Builder.Routes[tonumber(routeID) or 0]
        if not route then
            local previous = Builder.LastRoute[ply]
            for _, saved in ipairs(Builder.Routes) do
                if saved == previous then
                    route = saved
                    break
                end
            end
        end

        if not route then
            ply:ChatPrint("[MEX Track Builder] Nothing to undo. Aim at a saved MEX rail or place a point.")
            return false
        end

        local generated = ReadPointArray(route.generated_points)
        local fromLoop = #generated >= 2
        local points = fromLoop and generated or ReadPointArray(route.points)
        if #points < 2 then return false end

        local settings = CopySettings(route.settings)
        if fromLoop then
            -- Auto Loop was created in one action. Its generated track
            -- consists of short pieces; make these editable steps, keeping
            -- the original loop shape instead of deleting the whole loop.
            settings.smooth = false
        end

        active = {
            points = points,
            anchors = fromLoop and {} or ReadAnchors(route.anchors),
            entities = {},
            render_points = {},
            settings = settings,
            edit_route = route,
        }
        Builder.Active[ply] = active
        Builder.LastRoute[ply] = route
    end

    local previousCount = #active.points
    if previousCount <= 1 then
        Builder.CancelRoute(ply, true)
        ply:ChatPrint("[MEX Track Builder] Starting point undone; route is no longer active.")
        return true
    end

    table.remove(active.points, previousCount)
    active.anchors[previousCount] = nil

    if active.edit_route and #active.points < 2 then
        -- One saved segment has been undone. Preserve its start point as
        -- an active drawing anchor, but remove that now-empty saved route.
        for id, route in ipairs(Builder.Routes) do
            if route == active.edit_route then
                table.remove(Builder.Routes, id)
                break
            end
        end
        Builder.LastRoute[ply] = nil
        active.edit_route = nil
        Builder.SaveLayout()
        Builder.RespawnAll()
        Builder.RebuildMetrostroiNetwork()
    else
        RebuildActiveRoute(active)
    end

    SetActiveStart(ply, active.points[#active.points])
    ply:ChatPrint(string.format(
        "[MEX Track Builder] Undid 1 step. Endpoint selected (%d point(s) remain); LMB continues track.",
        #active.points
    ))
    return true
end

-- --------------------------------------------------------------------------
-- Metrostroi rerailer support for runtime-built MEX rails
-- --------------------------------------------------------------------------
-- The stock Metrostroi rerailer intentionally traces MASK_NPCWORLDSTATIC.
-- MEX rails are scripted entities, not BSP/world geometry, so the stock
-- getTrackData() cannot ever see them. These helpers reproduce the track data
-- Metrostroi expects directly from our generated rail segments.

local DEFAULT_BOGEY_OFFSET = 31

local function OrientTrackData(data, roughForward)
    if not istable(data) then return nil end
    if not isvector(data.forward) or not isvector(data.up) then return nil end

    local forward = data.forward:GetNormalized()
    local up = data.up:GetNormalized()

    if isvector(roughForward)
        and roughForward:LengthSqr() > 0.000001
        and forward:Dot(roughForward) < 0
    then
        forward = -forward
    end

    local right = forward:Cross(up)
    if right:LengthSqr() <= 0.000001 then
        return nil
    end
    right:Normalize()

    return {
        forward = forward,
        right = right,
        up = up,
        centerpos = data.centerpos,
        entity = data.entity,
        route_id = data.route_id,
    }
end

function Builder.GetMEXTrackData(pos, roughForward, maxDistance, routeID)
    if not isvector(pos) then return nil end

    maxDistance = math.Clamp(tonumber(maxDistance) or 768, 64, 4096)
    routeID = tonumber(routeID)

    local maxDistanceSqr = maxDistance * maxDistance
    local best
    local bestScore = math.huge
    local roughDir = isvector(roughForward)
        and roughForward:LengthSqr() > 0.000001
        and roughForward:GetNormalized()
        or nil

    -- Spatial query instead of scanning EVERY generated rail in the map on
    -- every Metrostroi rail lookup. Add half a maximum chord for its origin.
    for _, ent in ipairs(ents.FindInSphere(pos, maxDistance + 520)) do
        local entRouteID = IsValid(ent)
            and ent:GetNW2Int("MEXRouteID", 0)
            or 0

        if IsValid(ent)
            and ent:GetClass() == TRACK_CLASS
            and entRouteID > 0
            and (not routeID or entRouteID == routeID)
        then
            local length = math.max(
                ent:GetNW2Float("MEXLength", 0),
                0
            )

            if length > 1 then
                local forward = ent:GetAngles():Forward():GetNormalized()
                local up = ent:GetAngles():Up():GetNormalized()
                local right = forward:Cross(up)

                if right:LengthSqr() > 0.000001 then
                    right:Normalize()

                    local relative = pos - ent:GetPos()
                    local along = math.Clamp(
                        relative:Dot(forward),
                        -length * 0.5,
                        length * 0.5
                    )

                    local basePos = ent:GetPos() + forward * along
                    local railTop = ent:GetNW2Float(
                        "MEXRailSurfaceOffset",
                        0
                    )

                    if railTop <= 0 then
                        railTop = METROSTROI_RAIL_HEIGHT
                    end

                    local count = ent:GetNW2Int("MEXTrackCount", 1) == 2 and 2 or 1
                    local laneGap = ent:GetNW2Float("MEXTrackSpacing", 240)
                    local alignment = 1
                    if roughDir then alignment = math.abs(forward:Dot(roughDir)) end

                    for lane = 1, count do
                        local side = count == 2 and (lane == 1 and -laneGap * 0.5 or laneGap * 0.5) or 0
                        local centerpos = basePos + up * railTop + right * side
                        local offset = pos - centerpos
                        local sideways = math.abs(offset:Dot(right))
                        local vertical = math.abs(offset:Dot(up))
                        local distance = offset:LengthSqr()
                        if sideways <= 220
                            and vertical <= maxDistance
                            and distance <= maxDistanceSqr
                            and alignment >= 0.30
                        then
                            local score = distance + (1 - alignment) * 96 * 96
                            if score < bestScore then
                                bestScore = score
                                best = {
                                    forward = forward, right = right, up = up,
                                    centerpos = centerpos, entity = ent,
                                    route_id = entRouteID, lane = lane,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return OrientTrackData(best, roughForward)
end

local function ValidPhysics(ent)
    if not IsValid(ent) then return nil end
    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return nil end
    return phys
end

local function StopPhysics(ent)
    local phys = ValidPhysics(ent)
    if not phys then return end

    phys:SetVelocity(vector_origin)
    phys:AddAngleVelocity(-phys:GetAngleVelocity())
    phys:EnableMotion(false)
end

local function BeginRerailMove(entities)
    local saved = {}

    for _, ent in ipairs(entities or {}) do
        if IsValid(ent) and not saved[ent] then
            local phys = ValidPhysics(ent)

            saved[ent] = {
                solid = ent:GetSolid(),
                motion = phys and phys:IsMotionEnabled() or nil,
            }

            ent:SetSolid(SOLID_NONE)

            if phys then
                phys:SetVelocity(vector_origin)
                phys:AddAngleVelocity(-phys:GetAngleVelocity())
                phys:EnableMotion(false)
            end
        end
    end

    return saved
end

local function FinishRerailMove(saved, timerName)
    timer.Create(timerName, 0.8, 1, function()
        for ent, state in pairs(saved or {}) do
            if IsValid(ent) then
                ent:SetSolid(state.solid or SOLID_VPHYSICS)

                local phys = ValidPhysics(ent)
                if phys then
                    phys:SetVelocity(vector_origin)
                    phys:AddAngleVelocity(-phys:GetAngleVelocity())
                    phys:EnableMotion(state.motion ~= false)
                    phys:Wake()
                end
            end
        end
    end)
end

local function TrainRerailEntities(train)
    local list = {}

    local function Add(ent)
        if IsValid(ent) then
            list[#list + 1] = ent
        end
    end

    Add(train)
    Add(train.FrontBogey)
    Add(train.RearBogey)
    Add(train.FrontCouple)
    Add(train.RearCouple)

    if IsValid(train.FrontBogey) then
        Add(train.FrontBogey.Wheels)
    end
    if IsValid(train.RearBogey) then
        Add(train.RearBogey.Wheels)
    end

    return list
end

local function BogeyLocalPosition(train, bogey)
    if not IsValid(train) or not IsValid(bogey) then
        return vector_origin
    end

    if isvector(bogey.SpawnPos) then
        return bogey.SpawnPos
    end

    return train:WorldToLocal(bogey:GetPos())
end

local function BogeyLocalAngle(train, bogey)
    if IsValid(bogey) and isangle(bogey.SpawnAng) then
        return bogey.SpawnAng
    end

    if IsValid(train) and IsValid(bogey) then
        return train:WorldToLocalAngles(bogey:GetAngles())
    end

    return angle_zero
end

local function AlignDataForward(data, direction)
    if not istable(data) then return nil end

    if isvector(direction)
        and direction:LengthSqr() > 0.000001
        and data.forward:Dot(direction) < 0
    then
        data.forward = -data.forward
        data.right = -data.right
    end

    return data
end

local function ResetBogeyWheelsToBogey(bogey)
    if not IsValid(bogey) or not IsValid(bogey.Wheels) then return end

    local wheels = bogey.Wheels
    local types = bogey.Types
    local typ = istable(types) and types[bogey.BogeyType or "717"] or nil

    if istable(typ) then
        local localPos = isvector(typ[2]) and typ[2] or vector_origin
        local localAng = isangle(typ[3]) and typ[3] or angle_zero

        wheels:SetPos(bogey:LocalToWorld(localPos))
        wheels:SetAngles(bogey:LocalToWorldAngles(localAng))
    end

    StopPhysics(wheels)
end

function Builder.RerailBogeyOnMEX(bogey)
    if not IsValid(bogey) then return false end

    local data = Builder.GetMEXTrackData(
        bogey:GetPos(),
        bogey:GetAngles():Forward(),
        1024
    )
    if not data then return false end

    local wheels = bogey.Wheels
    local saved = BeginRerailMove({
        bogey,
        wheels,
    })

    local offset = tonumber(bogey.BogeyOffset) or DEFAULT_BOGEY_OFFSET

    bogey:SetPos(data.centerpos + data.up * offset)
    bogey:SetAngles(data.forward:Angle())
    StopPhysics(bogey)
    ResetBogeyWheelsToBogey(bogey)

    FinishRerailMove(
        saved,
        "mex_track_rerail_bogey_" .. bogey:EntIndex()
    )

    return true
end

function Builder.RerailTrainOnMEX(train, forcedRouteID)
    if not IsValid(train)
        or train.SubwayTrain == nil
        or train.NoPhysics
        or not IsValid(train.FrontBogey)
        or not IsValid(train.RearBogey)
        or not ValidPhysics(train)
    then
        return false
    end

    local currentForward = train:GetAngles():Forward()
    local trackData = Builder.GetMEXTrackData(
        train:GetPos(),
        currentForward,
        1400,
        forcedRouteID
    )
    if not trackData then return false end

    AlignDataForward(trackData, currentForward)

    local routeID = trackData.route_id
    local initialAng = trackData.forward:Angle()
    initialAng.r = 0

    local frontLocal = isvector(train.FrontBogey.SpawnPos)
        and train.FrontBogey.SpawnPos
        or train:WorldToLocal(train.FrontBogey:GetPos())

    local rearLocal = isvector(train.RearBogey.SpawnPos)
        and train.RearBogey.SpawnPos
        or train:WorldToLocal(train.RearBogey:GetPos())

    -- First estimate both bogey locations using only the horizontal local
    -- offset from the car center. We intentionally ignore the local Z here;
    -- track data returns the rail running surface and BogeyOffset adds the
    -- correct bogey-origin height afterwards.
    local frontGuessOffset = Vector(
        frontLocal.x,
        frontLocal.y,
        0
    )
    frontGuessOffset:Rotate(initialAng)

    local rearGuessOffset = Vector(
        rearLocal.x,
        rearLocal.y,
        0
    )
    rearGuessOffset:Rotate(initialAng)

    local frontGuess = trackData.centerpos + frontGuessOffset
    local rearGuess = trackData.centerpos + rearGuessOffset

    local frontData = Builder.GetMEXTrackData(
        frontGuess,
        trackData.forward,
        900,
        routeID
    )

    local rearData = Builder.GetMEXTrackData(
        rearGuess,
        trackData.forward,
        900,
        routeID
    )

    if not frontData or not rearData then
        return false
    end

    AlignDataForward(frontData, trackData.forward)
    AlignDataForward(rearData, trackData.forward)

    local frontBogeyOffset = tonumber(train.FrontBogey.BogeyOffset)
        or DEFAULT_BOGEY_OFFSET
    local rearBogeyOffset = tonumber(train.RearBogey.BogeyOffset)
        or frontBogeyOffset

    local targetFront = frontData.centerpos
        + frontData.up * frontBogeyOffset

    local targetRear = rearData.centerpos
        + rearData.up * rearBogeyOffset

    -- A railway vehicle is one rigid car body between two constrained bogeys.
    -- Therefore the body orientation is the chord between both required bogey
    -- positions. No roll is introduced because MEX track currently has no
    -- cant/banking.
    local bodyForward = targetFront - targetRear

    if bodyForward:LengthSqr() <= 0.000001 then
        bodyForward = trackData.forward
    else
        bodyForward:Normalize()
    end

    if bodyForward:Dot(currentForward) < 0 then
        bodyForward = -bodyForward
    end

    local bodyAng = bodyForward:Angle()
    bodyAng.r = 0

    -- Fit the original bogey SpawnPos pair to the two desired rail positions.
    -- We map their LOCAL midpoint to the TARGET midpoint. This preserves every
    -- train class' real suspension/body geometry instead of inventing another
    -- body->bogey offset.
    local spawnMid = (frontLocal + rearLocal) * 0.5
    local targetMid = (targetFront + targetRear) * 0.5

    local trainPos = LocalToWorld(
        -spawnMid,
        bodyAng,
        targetMid,
        bodyAng
    )

    local saved = BeginRerailMove(
        TrainRerailEntities(train)
    )

    train:SetAngles(bodyAng)
    train:SetPos(trainPos)

    -- CRITICAL: never force constrained bogeys onto independent world
    -- positions. That stretches the Axis constraints and, when physics is
    -- restored, the train jumps/tilts. Keep the exact original rigid
    -- relationship to the car body, just like stock Metrostroi does.
    train.FrontBogey:SetPos(
        train:LocalToWorld(frontLocal)
    )
    train.RearBogey:SetPos(
        train:LocalToWorld(rearLocal)
    )

    local frontSpawnAng = isangle(train.FrontBogey.SpawnAng)
        and train.FrontBogey.SpawnAng
        or angle_zero

    local rearSpawnAng = isangle(train.RearBogey.SpawnAng)
        and train.RearBogey.SpawnAng
        or angle_zero

    train.FrontBogey:SetAngles(
        train:LocalToWorldAngles(frontSpawnAng)
    )
    train.RearBogey:SetAngles(
        train:LocalToWorldAngles(rearSpawnAng)
    )

    if IsValid(train.FrontCouple)
        and isvector(train.FrontCouple.SpawnPos)
        and isangle(train.FrontCouple.SpawnAng)
    then
        train.FrontCouple:SetPos(
            train:LocalToWorld(train.FrontCouple.SpawnPos)
        )
        train.FrontCouple:SetAngles(
            train:LocalToWorldAngles(train.FrontCouple.SpawnAng)
        )
    end

    if IsValid(train.RearCouple)
        and isvector(train.RearCouple.SpawnPos)
        and isangle(train.RearCouple.SpawnAng)
    then
        train.RearCouple:SetPos(
            train:LocalToWorld(train.RearCouple.SpawnPos)
        )
        train.RearCouple:SetAngles(
            train:LocalToWorldAngles(train.RearCouple.SpawnAng)
        )
    end

    ResetBogeyWheelsToBogey(train.FrontBogey)
    ResetBogeyWheelsToBogey(train.RearBogey)

    StopPhysics(train)
    StopPhysics(train.FrontBogey)
    StopPhysics(train.RearBogey)

    -- Give Source physics one tick while everything is non-solid and frozen,
    -- then re-assert the rigid spawn geometry. This prevents old constraint
    -- error accumulated before rerailing from kicking the wagon sideways.
    timer.Simple(0, function()
        if not IsValid(train)
            or not IsValid(train.FrontBogey)
            or not IsValid(train.RearBogey)
        then
            return
        end

        train:SetAngles(bodyAng)
        train:SetPos(trainPos)

        train.FrontBogey:SetPos(
            train:LocalToWorld(frontLocal)
        )
        train.RearBogey:SetPos(
            train:LocalToWorld(rearLocal)
        )

        train.FrontBogey:SetAngles(
            train:LocalToWorldAngles(frontSpawnAng)
        )
        train.RearBogey:SetAngles(
            train:LocalToWorldAngles(rearSpawnAng)
        )

        ResetBogeyWheelsToBogey(train.FrontBogey)
        ResetBogeyWheelsToBogey(train.RearBogey)

        StopPhysics(train)
        StopPhysics(train.FrontBogey)
        StopPhysics(train.RearBogey)
    end)

    FinishRerailMove(
        saved,
        "mex_track_rerail_train_" .. train:EntIndex()
    )

    return true
end

function Builder.InstallRerailSupport()
    if not Metrostroi
        or not isfunction(Metrostroi.RerailTrain)
        or not isfunction(Metrostroi.RerailBogey)
        or not isfunction(Metrostroi.RerailGetTrackData)
    then
        return false
    end

    -- Preserve the real Metrostroi implementations even across Lua refreshes.
    Metrostroi.MEXOriginalRerailTrain =
        Metrostroi.MEXOriginalRerailTrain
        or Metrostroi.RerailTrain
    Metrostroi.MEXOriginalRerailBogey =
        Metrostroi.MEXOriginalRerailBogey
        or Metrostroi.RerailBogey
    Metrostroi.MEXOriginalRerailGetTrackData =
        Metrostroi.MEXOriginalRerailGetTrackData
        or Metrostroi.RerailGetTrackData

    if Metrostroi.MEXTrackBuilderRerailVersion == 7 then
        return true
    end

    local originalTrain = Metrostroi.MEXOriginalRerailTrain
    local originalBogey = Metrostroi.MEXOriginalRerailBogey
    local originalTrackData = Metrostroi.MEXOriginalRerailGetTrackData

    Metrostroi.RerailGetTrackData = function(pos, forward)
        -- When the player is directly aiming at a MEX rail, use its exact
        -- tangent instead of letting the stock world-only trace accidentally
        -- lock onto the floor below it.
        local closeMEX = Builder.GetMEXTrackData(
            pos,
            forward,
            96
        )
        if closeMEX then return closeMEX end

        local normal = originalTrackData(pos, forward)
        if normal then return normal end

        return Builder.GetMEXTrackData(
            pos,
            forward,
            1024
        ) or false
    end

    Metrostroi.RerailBogey = function(bogey)
        if IsValid(bogey) then
            local closeMEX = Builder.GetMEXTrackData(
                bogey:GetPos(),
                bogey:GetAngles():Forward(),
                256
            )
            if closeMEX
                and Builder.RerailBogeyOnMEX(bogey)
            then
                return true
            end
        end

        if originalBogey(bogey) then
            return true
        end

        return Builder.RerailBogeyOnMEX(bogey)
    end

    Metrostroi.RerailTrain = function(train)
        if IsValid(train) then
            local closeMEX = Builder.GetMEXTrackData(
                train:GetPos(),
                train:GetAngles():Forward(),
                256
            )

            if closeMEX
                and Builder.RerailTrainOnMEX(
                    train,
                    closeMEX.route_id
                )
            then
                return true
            end
        end

        if originalTrain(train) then
            return true
        end

        return Builder.RerailTrainOnMEX(train)
    end

    Metrostroi.MEXTrackBuilderRerailVersion = 7
    print(
        "[Metrostroi Expanded] Track Builder rerail support installed"
    )

    return true
end

hook.Add("Think", "MEXTrackBuilderInstallRerailSupport", function()
    if Builder.InstallRerailSupport() then
        hook.Remove(
            "Think",
            "MEXTrackBuilderInstallRerailSupport"
        )
    end
end)


function Builder.ApplyGaugeToRoutes(gauge, ply)
    gauge = math.Clamp(tonumber(gauge) or DEFAULT_TRACK_GAUGE, 40, 160)
    local changed = 0

    for _, route in ipairs(Builder.Routes) do
        route.settings = CopySettings(route.settings)
        if math.abs(route.settings.gauge - gauge) > 0.01 then
            route.settings.gauge = gauge
            changed = changed + 1
        end
    end

    if changed > 0 then
        Builder.SaveLayout()
        Builder.RespawnAll()
    end

    if IsValid(ply) then
        ply:ChatPrint(string.format(
            "[MEX Track Builder] Gauge: %.1f SU. Updated %d saved route(s).",
            gauge, changed
        ))
    end
    return changed
end

function Builder.RemoveRoute(routeID, ply)
    routeID = math.floor(tonumber(routeID) or 0)
    if routeID < 1 or not Builder.Routes[routeID] then return false end

    table.remove(Builder.Routes, routeID)
    Builder.SaveLayout()
    Builder.RespawnAll()
    Builder.RebuildMetrostroiNetwork(ply)

    if IsValid(ply) then
        ply:ChatPrint(string.format("[MEX Track Builder] Route #%d removed.", routeID))
    end

    return true
end

hook.Add("PlayerDisconnected", "MEXTrackBuilderPlayerDisconnected", function(ply)
    Builder.CancelRoute(ply, true)
    Builder.CancelAutoLoop(ply, true)
    Builder.LastRoute[ply] = nil
end)

hook.Add("PostCleanupMap", "MEXTrackBuilderRespawn", function()
    timer.Simple(0.25, function()
        Builder.RespawnAll()
    end)
end)

hook.Add("InitPostEntity", "MEXTrackBuilderLoad", function()
    timer.Simple(0.5, function()
        Builder.LoadLayout()
        Builder.RespawnAll()

        if #Builder.Routes > 0 then
            timer.Simple(2.0, function()
                Builder.RebuildMetrostroiNetwork()
            end)
        end
    end)
end)

-- Removing a whole saved route is deliberately separate from Undo (R).
concommand.Add("mex_track_builder_delete_aimed_route", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local tr = ply:GetEyeTrace()
    local ent = tr and tr.Entity
    if not IsValid(ent) or ent:GetClass() ~= TRACK_CLASS then
        ply:ChatPrint("[MEX Track Builder] Aim at a saved MEX rail to delete its entire route.")
        return
    end
    local routeID = ent:GetNW2Int("MEXRouteID", 0)
    if routeID <= 0 then
        ply:ChatPrint("[MEX Track Builder] Finish this unfinished route first, or press R to undo.")
        return
    end

    local active = Builder.Active[ply]
    if active and active.edit_route == Builder.Routes[routeID] then
        Builder.CancelRoute(ply, true)
    end
    Builder.RemoveRoute(routeID, ply)
end)

concommand.Add("mex_track_builder_undo", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local tr = ply:GetEyeTrace()
    local ent = tr and tr.Entity
    local routeID
    if IsValid(ent) and ent:GetClass() == TRACK_CLASS then
        local id = ent:GetNW2Int("MEXRouteID", 0)
        if id > 0 then routeID = id end
    end
    Builder.UndoLastPoint(ply, routeID)
end)

concommand.Add("mex_track_builder_finish", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    Builder.FinishRoute(ply, ply:GetInfoNum("mex_track_builder_network", 1) > 0)
end)

concommand.Add("mex_track_builder_cancel", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    if not Builder.CancelAutoLoop(ply) then
        Builder.CancelRoute(ply)
    end
end)

concommand.Add("mex_track_builder_cancel_loop", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    Builder.CancelAutoLoop(ply)
end)

concommand.Add("mex_track_builder_apply_gauge", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    Builder.ApplyGaugeToRoutes(ply:GetInfoNum("mex_track_builder_gauge", DEFAULT_TRACK_GAUGE), ply)
end)

concommand.Add("mex_track_builder_rebuild", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    Builder.RebuildMetrostroiNetwork(IsValid(ply) and ply or nil)
end)
