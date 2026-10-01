-- Metrostroi Expanded - in-game track builder backend and track segment entity
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

if SERVER then
    AddCSLuaFile()
end

MEXTrackBuilder = MEXTrackBuilder or {}
local Builder = MEXTrackBuilder

local TRACK_CLASS = "mex_track_segment"

local TrackEntity = {}
TrackEntity.Type = "anim"
TrackEntity.Base = "base_anim"
TrackEntity.PrintName = "Metrostroi Expanded Track Segment"
TrackEntity.Spawnable = false
TrackEntity.AdminOnly = true
TrackEntity.RenderGroup = RENDERGROUP_TRANSLUCENT

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
    local length = math.max(self:GetNW2Float("MEXLength", 1), 1)
    local gauge = math.max(self:GetNW2Float("MEXGauge", 80), 8)
    local railWidth = math.max(self:GetNW2Float("MEXRailWidth", 4), 1)
    local railHeight = math.max(self:GetNW2Float("MEXRailHeight", 7), 1)
    local sleeperHeight = math.max(self:GetNW2Float("MEXSleeperHeight", 5), 1)
    local sleeperLength = math.max(self:GetNW2Float("MEXSleeperLength", 128), gauge + 16)

    self:SetRenderBounds(
        Vector(-length * 0.5 - 8, -sleeperLength * 0.5 - 8, -8),
        Vector(length * 0.5 + 8, sleeperLength * 0.5 + 8, sleeperHeight + railHeight + 12)
    )

    if not SERVER then return end

    self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
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
    local railColor = Color(105, 108, 112)
    local sleeperColor = Color(93, 70, 47)

    function TrackEntity:Draw()
        self:DrawTranslucent()
    end

    function TrackEntity:DrawTranslucent()
        local length = math.max(self:GetNW2Float("MEXLength", 1), 1)
        local gauge = math.max(self:GetNW2Float("MEXGauge", 80), 8)
        local railWidth = math.max(self:GetNW2Float("MEXRailWidth", 4), 1)
        local railHeight = math.max(self:GetNW2Float("MEXRailHeight", 7), 1)
        local sleeperSpacing = math.max(self:GetNW2Float("MEXSleeperSpacing", 32), 8)
        local sleeperLength = math.max(self:GetNW2Float("MEXSleeperLength", 128), gauge + 16)
        local sleeperWidth = math.max(self:GetNW2Float("MEXSleeperWidth", 10), 2)
        local sleeperHeight = math.max(self:GetNW2Float("MEXSleeperHeight", 5), 1)
        local halfLength = length * 0.5
        local ang = self:GetAngles()

        self:SetRenderBounds(
            Vector(-halfLength - 8, -sleeperLength * 0.5 - 8, -8),
            Vector(halfLength + 8, sleeperLength * 0.5 + 8, sleeperHeight + railHeight + 12)
        )

        render.SetColorMaterial()

        local sleeperCount = math.Clamp(math.floor(length / sleeperSpacing) + 1, 2, 128)
        local step = sleeperCount > 1 and length / (sleeperCount - 1) or length

        for i = 0, sleeperCount - 1 do
            local x = -halfLength + step * i
            render.DrawBox(
                self:LocalToWorld(Vector(x, 0, sleeperHeight * 0.5)),
                ang,
                Vector(-sleeperWidth * 0.5, -sleeperLength * 0.5, -sleeperHeight * 0.5),
                Vector(sleeperWidth * 0.5, sleeperLength * 0.5, sleeperHeight * 0.5),
                sleeperColor,
                true
            )
        end

        local railBottom = sleeperHeight
        local railTop = sleeperHeight + railHeight
        local halfRail = railWidth * 0.5

        render.DrawBox(
            self:GetPos(),
            ang,
            Vector(-halfLength, gauge * 0.5 - halfRail, railBottom),
            Vector(halfLength, gauge * 0.5 + halfRail, railTop),
            railColor,
            true
        )
        render.DrawBox(
            self:GetPos(),
            ang,
            Vector(-halfLength, -gauge * 0.5 - halfRail, railBottom),
            Vector(halfLength, -gauge * 0.5 + halfRail, railTop),
            railColor,
            true
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
    }
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
    ent:SetNW2Int("MEXRouteID", routeID or 0)
    ent:SetNW2Int("MEXSegmentIndex", segmentIndex or 0)
    ent:Spawn()

    return ent
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

function Builder.SaveLayout()
    EnsureDirectories()

    local payload = {
        version = 1,
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
        for i = 1, #route.points - 1 do
            SpawnSegment(route.points[i], route.points[i + 1], settings, routeID, i)
        end
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
    local points = {}

    for _, point in ipairs(route.points or {}) do
        local vec = NormalizeVector(point)
        if isvector(vec) then
            points[#points + 1] = vec + Vector(0, 0, zOffset)
        end
    end

    return points
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
        notifyPly:ChatPrint("[MEX Track Builder] Track data saved. Reloading Metrostroi rail network...")
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

    for _, ent in ipairs(ents.FindByClass(TRACK_CLASS)) do
        if IsValid(ent) then
            local halfLength = ent:GetNW2Float("MEXLength", 0) * 0.5
            if halfLength > 0 then
                local endpoints = {
                    ent:LocalToWorld(Vector(-halfLength, 0, 0)),
                    ent:LocalToWorld(Vector(halfLength, 0, 0)),
                }

                for _, endpoint in ipairs(endpoints) do
                    local distSqr = pos:DistToSqr(endpoint)
                    if distSqr < bestDistSqr then
                        best = endpoint
                        bestDistSqr = distSqr
                    end
                end
            end
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
            settings = CopySettings(settings),
        }
        Builder.Active[ply] = active
        SetActiveStart(ply, pos)
        ply:ChatPrint("[MEX Track Builder] Start point set. Left click to add track segments; right click to finish.")
        return true
    end

    local previous = active.points[#active.points]
    if previous:DistToSqr(pos) < 16 then
        return false
    end

    local segment = SpawnSegment(previous, pos, active.settings, 0, #active.points)
    if not IsValid(segment) then return false end

    active.entities[#active.entities + 1] = segment
    active.points[#active.points + 1] = pos
    SetActiveStart(ply, pos)

    return true
end

function Builder.CancelRoute(ply, silent)
    local active = Builder.Active[ply]
    if not active then return false end

    for _, ent in ipairs(active.entities or {}) do
        if IsValid(ent) then ent:Remove() end
    end

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

    local route = {
        points = active.points,
        settings = active.settings,
        network = network ~= false,
    }
    Builder.Routes[#Builder.Routes + 1] = route
    local routeID = #Builder.Routes

    for index, ent in ipairs(active.entities or {}) do
        if IsValid(ent) then
            ent:SetNW2Int("MEXRouteID", routeID)
            ent:SetNW2Int("MEXSegmentIndex", index)
        end
    end

    Builder.Active[ply] = nil
    SetActiveStart(ply, nil)
    Builder.SaveLayout()

    if route.network then
        Builder.RebuildMetrostroiNetwork(ply)
    end

    if IsValid(ply) then
        ply:ChatPrint(string.format(
            "[MEX Track Builder] Route #%d saved (%d segments).",
            routeID,
            #route.points - 1
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
