-- Metrostroi Expanded - in-game track builder backend and track segment entity
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

if SERVER then
    AddCSLuaFile()
end

MEXTrackBuilder = MEXTrackBuilder or {}
local Builder = MEXTrackBuilder

local TRACK_CLASS = "mex_track_segment"
local DEFAULT_TRACK_MODEL = "models/metrostroi/tracks/railroad1024_plain.mdl"

local VALID_TRACK_MODELS = {
    ["models/metrostroi/tracks/railroad1024_plain.mdl"] = true,
    ["models/metrostroi/tracks/railroad1024.mdl"] = true,
    ["models/metrostroi/tracks/railroad1024_depot.mdl"] = true,
    ["models/metrostroi/tracks/railroad1024_station.mdl"] = true,
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
    if not SERVER then return end

    local length = math.max(self:GetNW2Float("MEXLength", 1), 1)
    local gauge = math.max(self:GetNW2Float("MEXGauge", 80), 8)
    local railWidth = math.max(self:GetNW2Float("MEXRailWidth", 4), 1)
    local railHeight = math.max(self:GetNW2Float("MEXRailHeight", 7), 1)
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
    local halfRail = railWidth * 0.5
    local railBottom = sleeperHeight
    local railTop = sleeperHeight + railHeight
    local leftY = gauge * 0.5
    local rightY = -gauge * 0.5

    local convexes = {
        BoxConvex(
            Vector(-halfLength, leftY - halfRail, railBottom),
            Vector(halfLength, leftY + halfRail, railTop)
        ),
        BoxConvex(
            Vector(-halfLength, rightY - halfRail, railBottom),
            Vector(halfLength, rightY + halfRail, railTop)
        ),
    }

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

        local railBottom = sleeperHeight
        local railTop = sleeperHeight + railHeight
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

    local function DrawMetrostroiModelClipped(self, length)
        local model = self:GetModel()
        if not isstring(model) or not string.StartWith(model, "models/metrostroi/tracks/") then
            return false
        end
        if not util.IsValidModel(model) then
            return false
        end

        local mins = self:OBBMins()
        local maxs = self:OBBMaxs()
        local modelLength = maxs.x - mins.x

        if modelLength < 64 then
            return false
        end

        local center = (mins + maxs) * 0.5
        local anchor = Vector(center.x, center.y, mins.z)
        local ang = self:GetAngles()
        local forward = ang:Forward()
        local right = ang:Right()
        local up = ang:Up()
        local drawOrigin = self:GetPos()
            - forward * anchor.x
            - right * anchor.y
            - up * anchor.z

        local halfLength = length * 0.5
        local oldClipping = render.EnableClipping(true)

        render.PushCustomClipPlane(
            forward,
            forward:Dot(self:GetPos() - forward * halfLength)
        )
        render.PushCustomClipPlane(
            -forward,
            (-forward):Dot(self:GetPos() + forward * halfLength)
        )

        self:SetRenderOrigin(drawOrigin)
        self:SetRenderAngles(ang)
        self:DrawModel()
        self:SetRenderOrigin(nil)
        self:SetRenderAngles(nil)

        render.PopCustomClipPlane()
        render.PopCustomClipPlane()
        render.EnableClipping(oldClipping)

        return true
    end

    function TrackEntity:Draw()
        local length = math.max(self:GetNW2Float("MEXLength", 1), 1)
        local gauge = math.max(self:GetNW2Float("MEXGauge", 80), 8)
        local railWidth = math.max(self:GetNW2Float("MEXRailWidth", 4), 1)
        local railHeight = math.max(self:GetNW2Float("MEXRailHeight", 7), 1)
        local sleeperSpacing = math.max(self:GetNW2Float("MEXSleeperSpacing", 32), 8)
        local sleeperLength = math.max(self:GetNW2Float("MEXSleeperLength", 128), gauge + 16)
        local sleeperWidth = math.max(self:GetNW2Float("MEXSleeperWidth", 10), 2)
        local sleeperHeight = math.max(self:GetNW2Float("MEXSleeperHeight", 5), 1)

        if self.SetRenderBounds then
            self:SetRenderBounds(
                Vector(-length * 0.5 - 24, -sleeperLength * 0.5 - 24, -16),
                Vector(length * 0.5 + 24, sleeperLength * 0.5 + 24, sleeperHeight + railHeight + 32)
            )
        end

        if self:GetNW2Bool("MEXUseTrackModel", true)
            and DrawMetrostroiModelClipped(self, length)
        then
            return
        end

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

if CLIENT then
    hook.Add("PostDrawTranslucentRenderables", "MEXTrackBuilderPreview", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:GetNW2Bool("MEXTrackBuilderActive", false) then return end

        local weapon = ply:GetActiveWeapon()
        if not IsValid(weapon) or weapon:GetClass() ~= "gmod_tool" then return end
        if weapon:GetMode() ~= "mex_track_builder" then return end

        local startPos = ply:GetNW2Vector("MEXTrackBuilderStart", vector_origin)
        if startPos == vector_origin then return end

        local tr = ply:GetEyeTrace()
        if not tr.Hit then return end

        render.SetColorMaterial()
        render.DrawLine(startPos, tr.HitPos, Color(80, 220, 100), true)
        render.DrawWireframeSphere(startPos, 5, 8, 8, Color(80, 220, 100), true)
        render.DrawWireframeSphere(tr.HitPos, 5, 8, 8, Color(255, 185, 60), true)
    end)

    return
end

Builder.Routes = Builder.Routes or {}
Builder.Active = Builder.Active or {}

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
        gauge = math.Clamp(tonumber(settings.gauge) or 80, 8, 200),
        rail_width = math.Clamp(tonumber(settings.rail_width) or 4, 1, 24),
        rail_height = math.Clamp(tonumber(settings.rail_height) or 7, 1, 32),
        sleeper_spacing = math.Clamp(tonumber(settings.sleeper_spacing) or 32, 8, 256),
        sleeper_length = math.Clamp(tonumber(settings.sleeper_length) or 128, 24, 256),
        sleeper_width = math.Clamp(tonumber(settings.sleeper_width) or 10, 2, 64),
        sleeper_height = math.Clamp(tonumber(settings.sleeper_height) or 5, 1, 32),
        smooth = settings.smooth ~= false and tonumber(settings.smooth or 1) ~= 0,
        curve_tension = math.Clamp(tonumber(settings.curve_tension) or 0.55, 0.05, 1.0),
        segment_length = math.Clamp(tonumber(settings.segment_length) or 192, 48, 512),
        use_track_model = settings.use_track_model ~= false and tonumber(settings.use_track_model or 1) ~= 0,
        track_model = SafeTrackModel(settings.track_model),
    }
end

local function PointTangent(points, index, tension)
    local count = #points
    if count < 2 then return vector_origin end

    if index <= 1 then
        return (points[2] - points[1]) * tension
    elseif index >= count then
        return (points[count] - points[count - 1]) * tension
    end

    local previous = points[index - 1]
    local current = points[index]
    local nextPoint = points[index + 1]
    local direction = nextPoint - previous
    local directionLength = direction:Length()

    if directionLength < 0.001 then
        return vector_origin
    end

    local localLength = math.min(
        current:Distance(previous),
        current:Distance(nextPoint)
    )

    return direction / directionLength * localLength * tension
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

function Builder.BuildSmoothPoints(controlPoints, settings)
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

        if not settings.smooth or #points < 3 then
            for step = 1, steps do
                output[#output + 1] = LerpVector(step / steps, a, b)
            end
        else
            local tangentA = PointTangent(points, i, settings.curve_tension)
            local tangentB = PointTangent(points, i + 1, settings.curve_tension)

            for step = 1, steps do
                local t = step / steps
                output[#output + 1] = HermitePoint(a, b, tangentA, tangentB, t)
            end
        end
    end

    return output
end

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

local function SpawnPolyline(points, settings, routeID)
    local entities = {}

    for i = 1, #points - 1 do
        local ent = SpawnSegment(points[i], points[i + 1], settings, routeID, i)
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

    RemoveEntities(active.entities)
    active.render_points = Builder.BuildSmoothPoints(active.points, active.settings)
    active.entities = SpawnPolyline(active.render_points, active.settings, 0)
end

function Builder.SaveLayout()
    EnsureDirectories()

    local payload = {
        version = 2,
        routes = Builder.Routes,
    }

    file.Write(LayoutPath(), util.TableToJSON(payload, true) or "{}")
end

function Builder.LoadLayout()
    Builder.Routes = {}

    if not file.Exists(LayoutPath(), "DATA") then return end

    local decoded = util.JSONToTable(file.Read(LayoutPath(), "DATA") or "")
    if not istable(decoded) or not istable(decoded.routes) then return end

    for _, routeEntry in ipairs(OrderedNumericValues(decoded.routes)) do
        local route = routeEntry.value
        if istable(route) and istable(route.points) then
            local points = {}
            for _, pointEntry in ipairs(OrderedNumericValues(route.points)) do
                local vec = NormalizeVector(pointEntry.value)
                if isvector(vec) then
                    points[#points + 1] = vec
                end
            end

            if #points >= 2 then
                Builder.Routes[#Builder.Routes + 1] = {
                    points = points,
                    settings = CopySettings(route.settings),
                    network = route.network ~= false,
                }
            end
        end
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
        local points = Builder.BuildSmoothPoints(route.points, settings)
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
    local zOffset = settings.sleeper_height + settings.rail_height
    local points = Builder.BuildSmoothPoints(route.points, settings)
    local result = {}

    for _, point in ipairs(points) do
        result[#result + 1] = point + Vector(0, 0, zOffset)
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
            local points = NetworkPoints(route)
            if #points >= 2 then
                maxPathID = maxPathID + 1
                merged[maxPathID] = points
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

function Builder.SnapPoint(pos, maxDistance)
    if not isvector(pos) then return pos end

    maxDistance = math.Clamp(tonumber(maxDistance) or 24, 1, 256)
    local best = pos
    local bestDistSqr = maxDistance * maxDistance

    local function CheckPoint(point)
        if not isvector(point) then return end

        local distSqr = pos:DistToSqr(point)
        if distSqr < bestDistSqr then
            best = point
            bestDistSqr = distSqr
        end
    end

    for _, route in ipairs(Builder.Routes) do
        if istable(route.points) and #route.points > 0 then
            CheckPoint(route.points[1])
            CheckPoint(route.points[#route.points])
        end
    end

    for _, active in pairs(Builder.Active) do
        if istable(active.points) and #active.points > 0 then
            CheckPoint(active.points[1])
            CheckPoint(active.points[#active.points])
        end
    end

    return best
end

function Builder.AddPoint(ply, pos, settings)
    if not IsValid(ply) or not ply:IsAdmin() or not isvector(pos) then return false end

    local active = Builder.Active[ply]
    if not active then
        active = {
            points = {pos},
            entities = {},
            render_points = {},
            settings = CopySettings(settings),
        }
        Builder.Active[ply] = active
        SetActiveStart(ply, pos)
        ply:ChatPrint("[MEX Track Builder] Start point set. Add control points; curves are smoothed automatically.")
        return true
    end

    local previous = active.points[#active.points]
    if previous:DistToSqr(pos) < 64 then
        return false
    end

    active.points[#active.points + 1] = pos
    RebuildActiveRoute(active)
    SetActiveStart(ply, pos)

    return true
end

function Builder.CancelRoute(ply, silent)
    local active = Builder.Active[ply]
    if not active then return false end

    RemoveEntities(active.entities)
    Builder.Active[ply] = nil
    SetActiveStart(ply, nil)

    if IsValid(ply) and not silent then
        ply:ChatPrint("[MEX Track Builder] Unfinished route cancelled.")
    end

    return true
end

function Builder.FinishRoute(ply, network)
    local active = Builder.Active[ply]
    if not active then return false end

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
        settings = CopySettings(active.settings),
        network = network ~= false,
    }

    Builder.Routes[#Builder.Routes + 1] = route
    local routeID = #Builder.Routes
    local smoothPoints = Builder.BuildSmoothPoints(route.points, route.settings)
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

concommand.Add("mex_track_builder_finish", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    Builder.FinishRoute(ply, ply:GetInfoNum("mex_track_builder_network", 1) > 0)
end)

concommand.Add("mex_track_builder_cancel", function(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    Builder.CancelRoute(ply)
end)

concommand.Add("mex_track_builder_rebuild", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    Builder.RebuildMetrostroiNetwork(IsValid(ply) and ply or nil)
end)
