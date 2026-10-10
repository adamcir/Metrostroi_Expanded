-- Metrostroi Expanded - shared fast track/tunnel geometry (one cached IMesh per material)
-- Copyright (C) 2026 Adam Cir / Adava Software - GPL-3.0
-- Included by metrostroi_expanded_track_builder.lua on both realms.
local Builder = MEXTrackBuilder
Builder.Geometry = Builder.Geometry or {}
local G = Builder.Geometry

G.TunnelTypes = {
    none = true,
    round = true,
    rectangular = true,
    wide = true,
}

function G.SafeTunnelType(name)
    name = tostring(name or "none")
    return G.TunnelTypes[name] and name or "none"
end

local function BoxConvex(mins, maxs)
    return {
        Vector(mins.x, mins.y, mins.z), Vector(mins.x, mins.y, maxs.z),
        Vector(mins.x, maxs.y, mins.z), Vector(mins.x, maxs.y, maxs.z),
        Vector(maxs.x, mins.y, mins.z), Vector(maxs.x, mins.y, maxs.z),
        Vector(maxs.x, maxs.y, mins.z), Vector(maxs.x, maxs.y, maxs.z),
    }
end

-- A static rail entity has two narrow collision hulls, never a wide invisible
-- bed that catches the train bogeys. Extend ends slightly to bridge tiny gaps
-- between adjacent chords (the former end-to-end butt joint caused bumps).
function G.PhysicsConvexes(length, gauge, railWidth, tunnelType, radius, width, height, wall)
    local half = length * 0.5 + 0.6
    local halfRail = railWidth * 0.5
    local convexes = {
        BoxConvex(Vector(-half, gauge * 0.5 - halfRail, 0),
                  Vector( half, gauge * 0.5 + halfRail, 10)),
        BoxConvex(Vector(-half, -gauge * 0.5 - halfRail, 0),
                  Vector( half, -gauge * 0.5 + halfRail, 10)),
    }
    tunnelType = G.SafeTunnelType(tunnelType)
    if tunnelType == "none" then return convexes end

    radius = math.Clamp(tonumber(radius) or 170, 140, 320)
    width = math.Clamp(tonumber(width) or 360, 300, 640)
    height = math.Clamp(tonumber(height) or 280, 230, 480)
    wall = math.Clamp(tonumber(wall) or 12, 6, 32)

    if tunnelType == "round" then
        local zCenter = radius - 55 -- tunnel invert is 55 SU BELOW the rail base
        -- 12 convex rings, not per-triangle physics. The floor is below the
        -- running rails, giving Metrostroi bogeys and wheels free clearance.
        local sides = 12
        for i = 0, sides - 1 do
            local a = i * math.pi * 2 / sides
            local b = (i + 1) * math.pi * 2 / sides
            local points = {}
            for _, x in ipairs({-half, half}) do
                for _, r in ipairs({radius, radius + wall}) do
                    points[#points + 1] = Vector(x, math.cos(a) * r, zCenter + math.sin(a) * r)
                    points[#points + 1] = Vector(x, math.cos(b) * r, zCenter + math.sin(b) * r)
                end
            end
            convexes[#convexes + 1] = points
        end
    else
        if tunnelType == "wide" then width = math.max(width, 460) end
        local y = width * 0.5
        local bottom = -55
        -- Walls, roof, and invert as separate convex solids: NEVER a filled box.
        convexes[#convexes + 1] = BoxConvex(Vector(-half, -y - wall, bottom), Vector(half, -y, height))
        convexes[#convexes + 1] = BoxConvex(Vector(-half, y, bottom), Vector(half, y + wall, height))
        convexes[#convexes + 1] = BoxConvex(Vector(-half, -y - wall, height), Vector(half, y + wall, height + wall))
        convexes[#convexes + 1] = BoxConvex(Vector(-half, -y - wall, bottom - wall), Vector(half, y + wall, bottom))
    end
    return convexes
end

if not CLIENT then return end

local railMaterial = Material("metrostroi/metro_railroad_001")
if railMaterial:IsError() then railMaterial = Material("models/props_c17/metalladder003") end
local sleeperMaterial = Material("models/props_c17/furniturefabric003a")
local tunnelMaterial = Material("models/props_wasteland/concretefloor010a")
if tunnelMaterial:IsError() then tunnelMaterial = Material("models/props_c17/concretewall001a") end

local function AddQuad(vertices, a, b, c, d, doubleSided)
    local normal = (b - a):Cross(c - a)
    if normal:LengthSqr() < 0.000001 then return end
    normal:Normalize()

    local function Add(p, n)
        vertices[#vertices + 1] = {
            pos = p, normal = n,
            u = p.x / 128 + p.z / 256, v = p.y / 128 + p.z / 128,
        }
    end
    Add(a, normal); Add(b, normal); Add(c, normal)
    Add(a, normal); Add(c, normal); Add(d, normal)
    if doubleSided then
        local reversed = -normal
        Add(c, reversed); Add(b, reversed); Add(a, reversed)
        Add(d, reversed); Add(c, reversed); Add(a, reversed)
    end
end

local function AddBox(vertices, min, max)
    local a = Vector(min.x, min.y, min.z)
    local b = Vector(max.x, min.y, min.z)
    local c = Vector(max.x, max.y, min.z)
    local d = Vector(min.x, max.y, min.z)
    local e = Vector(min.x, min.y, max.z)
    local f = Vector(max.x, min.y, max.z)
    local g = Vector(max.x, max.y, max.z)
    local h = Vector(min.x, max.y, max.z)
    AddQuad(vertices, a, d, c, b) -- bottom
    AddQuad(vertices, e, f, g, h) -- top
    AddQuad(vertices, a, b, f, e) -- near
    AddQuad(vertices, d, h, g, c) -- far
    AddQuad(vertices, a, e, h, d) -- left cap
    AddQuad(vertices, b, c, g, f) -- right cap
end

local function MakeMesh(vertices)
    if #vertices < 3 then return nil end
    local output = Mesh()
    output:BuildFromTriangles(vertices)
    return output
end

function G.ClearClientMeshes(ent)
    if not ent.MEXFastMeshes then return end
    for _, entry in ipairs(ent.MEXFastMeshes) do
        if entry.mesh and entry.mesh:IsValid() then entry.mesh:Destroy() end
    end
    ent.MEXFastMeshes = nil
    ent.MEXFastKey = nil
end

local function CreateMeshes(ent, length, gauge, railWidth, sleeperSpacing,
                            sleeperLength, sleeperWidth, sleeperHeight,
                            tunnelType, radius, width, height, wall)
    local rails, sleepers, tunnel = {}, {}, {}
    local half = length * 0.5
    for _, y in ipairs({-gauge * 0.5, gauge * 0.5}) do
        AddBox(rails,
            Vector(-half - 0.3, y - railWidth * 0.5, 0),
            Vector(half + 0.3, y + railWidth * 0.5, 10))
    end

    local ties = math.max(1, math.ceil(length / sleeperSpacing))
    for i = 0, ties do
        local x = -half + i * length / ties
        AddBox(sleepers,
            Vector(x - sleeperWidth * 0.5, -sleeperLength * 0.5, -sleeperHeight),
            Vector(x + sleeperWidth * 0.5, sleeperLength * 0.5, 0))
    end

    if tunnelType == "round" then
        local zCenter = radius - 55
        -- Both sides of the lining are visible (viewed from inside/outside).
        for i = 0, 31 do
            local a = i * math.pi * 2 / 32
            local b = (i + 1) * math.pi * 2 / 32
            local y1, z1 = math.cos(a) * radius, zCenter + math.sin(a) * radius
            local y2, z2 = math.cos(b) * radius, zCenter + math.sin(b) * radius
            local yo1, zo1 = math.cos(a) * (radius + wall), zCenter + math.sin(a) * (radius + wall)
            local yo2, zo2 = math.cos(b) * (radius + wall), zCenter + math.sin(b) * (radius + wall)
            AddQuad(tunnel,
                Vector(-half - 0.5, y1, z1), Vector(half + 0.5, y1, z1),
                Vector(half + 0.5, y2, z2), Vector(-half - 0.5, y2, z2), true)
            AddQuad(tunnel,
                Vector(-half - 0.5, yo2, zo2), Vector(half + 0.5, yo2, zo2),
                Vector(half + 0.5, yo1, zo1), Vector(-half - 0.5, yo1, zo1), true)
        end
    elseif tunnelType ~= "none" then
        if tunnelType == "wide" then width = math.max(width, 460) end
        local y, bottom = width * 0.5, -55
        AddBox(tunnel, Vector(-half, -y - wall, bottom), Vector(half, -y, height))
        AddBox(tunnel, Vector(-half, y, bottom), Vector(half, y + wall, height))
        AddBox(tunnel, Vector(-half, -y - wall, height), Vector(half, y + wall, height + wall))
        AddBox(tunnel, Vector(-half, -y - wall, bottom - wall), Vector(half, y + wall, bottom))
    end

    local meshes = {}
    local function Keep(vertices, mat)
        local result = MakeMesh(vertices)
        if result then meshes[#meshes + 1] = {mesh = result, material = mat} end
    end
    Keep(rails, railMaterial)
    Keep(sleepers, sleeperMaterial)
    Keep(tunnel, tunnelMaterial)
    return meshes
end

function G.Draw(ent)
    local length = math.max(ent:GetNW2Float("MEXLength", 1), 1)
    local gauge = math.max(ent:GetNW2Float("MEXPhysicalGauge", 85.8), 8)
    local rw = math.max(ent:GetNW2Float("MEXPhysicalRailWidth", 5.8), 1)
    local spacing = math.max(ent:GetNW2Float("MEXSleeperSpacing", 32), 8)
    local sl = math.max(ent:GetNW2Float("MEXSleeperLength", 128), gauge + 12)
    local sw = math.max(ent:GetNW2Float("MEXSleeperWidth", 10), 2)
    local sh = math.max(ent:GetNW2Float("MEXSleeperHeight", 5), 1)
    local tunnelType = G.SafeTunnelType(ent:GetNW2String("MEXTunnelType", "none"))
    local radius = math.Clamp(ent:GetNW2Float("MEXTunnelRadius", 170), 140, 320)
    local width = math.Clamp(ent:GetNW2Float("MEXTunnelWidth", 360), 300, 640)
    local height = math.Clamp(ent:GetNW2Float("MEXTunnelHeight", 280), 230, 480)
    local wall = math.Clamp(ent:GetNW2Float("MEXTunnelWall", 12), 6, 32)
    -- Rebuild only when networked geometry SETTINGS change, never every frame.
    local key = string.format("%.2f/%.2f/%.2f/%.2f/%.2f/%.2f/%.2f/%s/%.2f/%.2f/%.2f/%.2f",
        length, gauge, rw, spacing, sl, sw, sh, tunnelType, radius, width, height, wall)
    if ent.MEXFastKey ~= key then
        G.ClearClientMeshes(ent)
        ent.MEXFastMeshes = CreateMeshes(ent, length, gauge, rw, spacing, sl, sw, sh,
                                         tunnelType, radius, width, height, wall)
        ent.MEXFastKey = key
        local halfWidth = tunnelType == "round" and radius + wall
            or (tunnelType ~= "none" and math.max(width, tunnelType == "wide" and 460 or 0) * 0.5 + wall)
            or math.max(sl * 0.5, gauge * 0.5 + rw)
        local roof = tunnelType == "round" and (2 * radius - 55 + wall)
            or (tunnelType ~= "none" and height + wall)
            or 24
        ent:SetRenderBounds(Vector(-length * 0.5 - 16, -halfWidth - 16, -72),
                            Vector(length * 0.5 + 16, halfWidth + 16, roof + 16))
    end

    if not ent.MEXFastMeshes then return end
    local matrix = Matrix()
    matrix:SetTranslation(ent:GetPos())
    matrix:SetAngles(ent:GetAngles())
    cam.PushModelMatrix(matrix)
    for _, entry in ipairs(ent.MEXFastMeshes) do
        render.SetMaterial(entry.material)
        entry.mesh:Draw()
    end
    cam.PopModelMatrix()
end
