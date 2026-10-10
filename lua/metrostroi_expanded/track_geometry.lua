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

function G.SafeThirdRailSide(side)
    side = tostring(side or "outside")
    return (side == "left" or side == "right" or side == "both")
        and side or "outside"
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
function G.PhysicsConvexes(length, gauge, railWidth, tunnelType, radius, width, height, wall, trackCount, trackSpacing)
    local half = length * 0.5 + 0.6
    local halfRail = railWidth * 0.5
    trackCount = trackCount == 2 and 2 or 1
    trackSpacing = math.Clamp(tonumber(trackSpacing) or 240, 180, 400)
    local convexes = {}
    for lane = 1, trackCount do
        local middle = trackCount == 2 and (lane == 1 and -trackSpacing * 0.5 or trackSpacing * 0.5) or 0
        for _, railY in ipairs({middle + gauge * 0.5, middle - gauge * 0.5}) do
            convexes[#convexes + 1] = BoxConvex(
                Vector(-half, railY - halfRail, 0),
                Vector( half, railY + halfRail, 10)
            )
        end
    end
    tunnelType = G.SafeTunnelType(tunnelType)
    if tunnelType == "none" then return convexes end

    radius = math.Clamp(tonumber(radius) or 170, 140, 320)
    width = math.Clamp(tonumber(width) or 360, 300, 640)
    height = math.Clamp(tonumber(height) or 280, 230, 480)
    wall = math.Clamp(tonumber(wall) or 12, 6, 32)

    if tunnelType == "round" then
        -- A double-track bore must clear both cars.
        if trackCount == 2 then radius = math.max(radius, trackSpacing * 0.5 + 135) end
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
        if trackCount == 2 then width = math.max(width, trackSpacing + 270) end
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

-- The stock Metrostroi/Track Pack textures are REAL content paths (see
-- models/metrostroi_tunnels/*.vmt in original Metrostroi).  Build our own
-- visible UnlitGeneric materials from installed VTFs: imported VertexLitGeneric
-- VMTs can become pitch-black on night/unlit construction maps, and missing
-- workshop textures previously caused pink checkerboard sleepers/rails.
-- We NEVER distribute the original artists' files or assume they are mounted.
local function ExistingTexture(paths)
    for _, path in ipairs(paths) do
        if file.Exists("materials/" .. path .. ".vtf", "GAME") then
            return path
        end
    end
    return "vgui/white" -- engine built-in, not a missing-file texture
end

local function SolidMaterial(name, texturePaths, tint)
    local texture = ExistingTexture(texturePaths)
    local mat = CreateMaterial(name, "UnlitGeneric", {
        ["$basetexture"] = texture,
        ["$color2"] = tint,
        ["$nocull"] = "0",
    })
    if mat and not mat:IsError() then return mat end
    return Material("models/debug/debugwhite")
end

local railMaterial = SolidMaterial("mex_track_rail_metro_v3", {
    "models/metrostroi_tunnels/railroad_001",
    "metrostroi/metro_railroad_001",
}, "[0.75 0.75 0.75]")
local sleeperMaterial = SolidMaterial("mex_track_tie_metro_v3", {
    "models/metrostroi_tunnels/railroad_002",
    "models/metrostroi_tunnels/railroad_001b",
}, "[0.58 0.58 0.58]")
local tunnelMaterial = SolidMaterial("mex_track_tunnel_metro_v3", {
    "models/metrostroi_tunnels/tunnelwall_002",
    "models/metrostroi_tunnels/tunnelwall_001",
    "metro/metroconcrete001",
}, "[0.60 0.60 0.60]")
local tunnelSeamMaterial = SolidMaterial("mex_track_tunnel_ring_v3", {
    "models/metrostroi_tunnels/tunnelwall_003",
    "models/metrostroi_tunnels/tunnelwall_001",
}, "[0.42 0.42 0.42]")
local tunnelFloorMaterial = SolidMaterial("mex_track_tunnel_floor_v3", {
    "models/metrostroi_tunnels/tunnelfloor_001",
    "models/metrostroi_tunnels/tunnelfloor_002",
}, "[0.40 0.40 0.40]")
local contactMaterial = SolidMaterial("mex_track_contact_metro_v3", {
    "metrostroi/metro_contactrail_001",
    "models/metrostroi_tunnels/railroad_001",
}, "[0.80 0.72 0.59]")
local contactCoverMaterial = SolidMaterial("mex_track_contact_cover_v3", {
    "models/metrostroi_tunnels/railroad_006c",
    "models/metrostroi_tunnels/railroad_001b",
}, "[0.30 0.30 0.28]")
local insulatorMaterial = SolidMaterial("mex_track_contact_insulator_v3", {
    "models/metrostroi_tunnels/railroad_008",
}, "[0.52 0.47 0.34]")

-- Global visual toggle.  It never changes the saved route or collisions.
local cvDrawSleepers = CreateClientConVar(
    "mex_track_builder_draw_sleepers", "1", true, false,
    "Render procedural railway sleepers/ties"
)

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
    if IsValid(ent.MEXPackPiece) then ent.MEXPackPiece:Remove() end
    ent.MEXPackPiece = nil
    ent.MEXPackModel = nil
    if ent.MEXContactMeshes then
        for _, entry in ipairs(ent.MEXContactMeshes) do
            if entry.mesh then entry.mesh:Destroy() end
        end
    end
    ent.MEXContactMeshes, ent.MEXContactKey = nil, nil
    if not ent.MEXFastMeshes then return end
    for _, entry in ipairs(ent.MEXFastMeshes) do
        if entry.mesh and entry.mesh:IsValid() then entry.mesh:Destroy() end
    end
    ent.MEXFastMeshes = nil
    ent.MEXFastKey = nil
end

-- Contact rail is always a SEPARATE asset from the running rails/tunnel
-- (including the official Track Pack). It does not add bogey collisions.
local function ContactRailVertices(length, gauge, trackCount, trackSpacing, enabled, side, offset, height)
    local bar, cover, insulators = {}, {}, {}
    if not enabled then return bar, cover, insulators end
    local half = length * 0.5
    side = G.SafeThirdRailSide(side)
    for lane = 1, trackCount do
        local center = trackCount == 2 and (lane == 1 and -trackSpacing * 0.5 or trackSpacing * 0.5) or 0
        local sides = {}
        if side == "both" then
            sides = {-1, 1}
        elseif side == "left" then
            sides = {1}
        elseif side == "right" then
            sides = {-1}
        elseif trackCount == 2 then
            sides = {lane == 1 and -1 or 1} -- exterior edge of each track
        else
            sides = {-1} -- right side of single line
        end
        for _, direction in ipairs(sides) do
            -- Offset is from TRACK center, not from tunnel center.
            local y = center + direction * offset
            local bottom = height - 4
            AddBox(bar,
                Vector(-half - 0.3, y - 4.2, bottom),
                Vector( half + 0.3, y + 4.2, height + 4))
            -- A covered contact rail with dark top/lateral protection and
            -- visible supporting ceramic/insulating feet.
            AddBox(cover,
                Vector(-half, y - 11, height + 11),
                Vector( half, y + 11, height + 14))
            AddBox(cover,
                Vector(-half, y + direction * 8 - 1.5, height + 5),
                Vector( half, y + direction * 8 + 1.5, height + 12))
            local supports = math.max(1, math.ceil(length / 128))
            for i = 0, supports - 1 do
                local x = -half + (i + 0.5) * (length / supports)
                AddBox(insulators,
                    Vector(x - 7, y - 8, 1.5),
                    Vector(x + 7, y + 8, height - 4))
                AddBox(insulators,
                    Vector(x - 9, y - 13, 0.8),
                    Vector(x + 9, y + 13, 3.8))
            end
        end
    end
    return bar, cover, insulators
end

local function MakeContactMeshes(length, gauge, count, spacing, enabled, side, offset, height)
    local rail, cover, insulators = ContactRailVertices(
        length, gauge, count, spacing, enabled, side, offset, height)
    local results = {}
    for _, item in ipairs({
        {rail, contactMaterial},
        {cover, contactCoverMaterial},
        {insulators, insulatorMaterial}
    }) do
        local result = MakeMesh(item[1])
        if result then results[#results + 1] = {mesh = result, material = item[2]} end
    end
    return results
end

local function DrawMeshEntries(ent, entries)
    if not entries then return end
    local matrix = Matrix()
    matrix:SetTranslation(ent:GetPos())
    matrix:SetAngles(ent:GetAngles())
    cam.PushModelMatrix(matrix)
    for _, entry in ipairs(entries) do
        if not entry.sleepers or not cvDrawSleepers or cvDrawSleepers:GetBool() then
            render.SetMaterial(entry.material)
            entry.mesh:Draw()
        end
    end
    cam.PopModelMatrix()
end

function G.DrawContactRailOnly(ent)
    local enabled = ent:GetNW2Bool("MEXThirdRail", true)
    if not enabled then return end
    local length = math.max(ent:GetNW2Float("MEXLength", 1), 1)
    local gauge = ent:GetNW2Float("MEXPhysicalGauge", 85.8)
    local count = ent:GetNW2Int("MEXTrackCount", 1) == 2 and 2 or 1
    local spacing = ent:GetNW2Float("MEXTrackSpacing", 240)
    local side = G.SafeThirdRailSide(ent:GetNW2String("MEXThirdRailSide", "outside"))
    local offset = ent:GetNW2Float("MEXThirdRailOffset", 112)
    local height = ent:GetNW2Float("MEXThirdRailHeight", 20)
    local key = string.format("%.1f/%.1f/%d/%.1f/%s/%.1f/%.1f",
        length, gauge, count, spacing, side, offset, height)
    if ent.MEXContactKey ~= key then
        if ent.MEXContactMeshes then
            for _, entry in ipairs(ent.MEXContactMeshes) do entry.mesh:Destroy() end
        end
        ent.MEXContactMeshes = MakeContactMeshes(length, gauge, count, spacing,
                                                  enabled, side, offset, height)
        ent.MEXContactKey = key
    end
    DrawMeshEntries(ent, ent.MEXContactMeshes)
end

-- Track Pack provides *rigid compiled MDLs*. Draw exactly one installed model
-- on a straight two-point section, never stretch it along a spline and never
-- guess file paths. Curves continue to use our dynamic procedural geometry.
-- The selected MDL is only a visual skin: MEX's separate rail collision and
-- Metrostroi route graph remain authoritative.
function G.DrawPackModel(ent)
    local requested = ent:GetNW2String("MEXPackModel", "")
    -- Original Metrostroi has concrete tunnel256/tunnel64/tunnel1024 MDLs.
    -- Prefer those automatically on straight RIGID sections of matching
    -- length. User-selected genuine Track Pack MDLs always take precedence.
    if requested == "" and ent:GetNW2String("MEXTunnelStyle", "metrostroi") == "metrostroi" then
        local typeName = ent:GetNW2String("MEXTunnelType", "none")
        local count = ent:GetNW2Int("MEXTrackCount", 1)
        local len = ent:GetNW2Float("MEXLength", 0)
        local prefix = "models/metrostroi/tracks/"
        local suffix = ""
        if typeName == "rectangular" then suffix = "_rect" end
        local name
        if count == 2 then
            if math.abs(len - 1024) < 8 and typeName ~= "none" then
                name = "tunnel1024_double.mdl"
            end
        elseif typeName ~= "none" then
            if math.abs(len - 64) < 8 then name = "tunnel64" .. suffix .. ".mdl" end
            if math.abs(len - 256) < 8 then name = "tunnel256" .. suffix .. ".mdl" end
            if math.abs(len - 1024) < 8 then name = "tunnel1024" .. suffix .. ".mdl" end
        end
        if name then requested = prefix .. name end
    end
    if requested == "" or not ent:GetNW2Bool("MEXRigidSection", false) then
        if IsValid(ent.MEXPackPiece) then ent.MEXPackPiece:Remove() end
        ent.MEXPackPiece, ent.MEXPackModel = nil, nil
        return false
    end
    local path = string.lower(requested)
    if not string.match(path, "^models/[%w_/%-%.]+%.mdl$") then return false end
    -- Loading/validating a compiled model is expensive; do it once per path,
    -- not once per frame for every fixed station.
    if ent.MEXPackValidityPath ~= requested then
        ent.MEXPackValidityPath = requested
        ent.MEXPackValidity = util.IsValidModel(requested)
    end
    if not ent.MEXPackValidity then return false end
    local count = ent:GetNW2Int("MEXTrackCount", 1)
    if count == 2 and not (string.find(path, "_ns", 1, true)
        or string.find(path, "double", 1, true)
        or string.find(path, "2track", 1, true)
        or string.find(path, "2_track", 1, true))
    then
        return false
    end
    -- Non-straight pre-bent kit pieces cannot replace a straight physics
    -- chord; never make those models act like rails they do not represent.
    if string.find(path, "curve", 1, true) or string.find(path, "turnout", 1, true)
        or string.find(path, "switch", 1, true) then
        return false
    end

    if ent.MEXPackModel ~= requested or not IsValid(ent.MEXPackPiece) then
        if IsValid(ent.MEXPackPiece) then ent.MEXPackPiece:Remove() end
        local piece = ClientsideModel(requested, RENDERGROUP_OPAQUE)
        if not IsValid(piece) then
            ent.MEXPackModel = nil
            return false
        end
        piece:SetNoDraw(true)
        piece:DrawShadow(false)
        ent.MEXPackPiece, ent.MEXPackModel = piece, requested
    end

    local piece = ent.MEXPackPiece
    local mins, maxs = piece:OBBMins(), piece:OBBMaxs()
    local size = maxs - mins
    local length = ent:GetNW2Float("MEXLength", 1)
    local isX = math.abs(size.x - length) <= math.abs(size.y - length)
    local nativeLength = isX and size.x or size.y
    -- A 1024-SU prefab cannot be placed on a 256-SU route. Fallback to MEX
    -- generated graphics rather than silently stretching/misaligning it.
    if math.abs(nativeLength - length) > math.max(8, length * 0.06) then
        return false
    end
    local correction = isX and Angle(0, 0, 0) or Angle(0, -90, 0)
    local ang = ent:LocalToWorldAngles(correction)
    local center = (mins + maxs) * 0.5
    local pivot = Vector(center.x, center.y, 0)
    pivot:Rotate(ang)
    local target = ent:GetPos() + ent:GetAngles():Up() * ent:GetNW2Float("MEXPackZOffset", 0)
    piece:SetRenderOrigin(target - pivot)
    piece:SetRenderAngles(ang)
    -- The imported prefab can be wider/taller than the invisible track tile.
    if ent.SetRenderBounds then
        local halfSize = math.max(size.x, size.y, size.z, length) + 48
        ent:SetRenderBounds(Vector(-halfSize, -halfSize, -halfSize),
                            Vector(halfSize, halfSize, halfSize))
    end
    piece:DrawModel()
    piece:SetRenderOrigin(nil)
    piece:SetRenderAngles(nil)
    return true
end

local function CreateMeshes(ent, length, gauge, railWidth, sleeperSpacing,
                            sleeperLength, sleeperWidth, sleeperHeight,
                            tunnelType, radius, width, height, wall, trackCount, trackSpacing)
    local rails, sleepers, tunnel = {}, {}, {}
    local ballast, rings, walkway = {}, {}, {}
    local thirdRail = ent:GetNW2Bool("MEXThirdRail", true)
    local contactSide = G.SafeThirdRailSide(ent:GetNW2String("MEXThirdRailSide", "outside"))
    local contactOffset = ent:GetNW2Float("MEXThirdRailOffset", 112)
    local contactHeight = ent:GetNW2Float("MEXThirdRailHeight", 20)
    local tunnelStyle = ent:GetNW2String("MEXTunnelStyle", "metrostroi")
    local half = length * 0.5
    trackCount = trackCount == 2 and 2 or 1
    trackSpacing = math.Clamp(tonumber(trackSpacing) or 240, 180, 400)
    for lane = 1, trackCount do
        local middle = trackCount == 2 and (lane == 1 and -trackSpacing * 0.5 or trackSpacing * 0.5) or 0
        for _, y in ipairs({middle - gauge * 0.5, middle + gauge * 0.5}) do
            AddBox(rails,
                Vector(-half - 0.3, y - railWidth * 0.5, 0),
                Vector(half + 0.3, y + railWidth * 0.5, 10))
        end
    end

    -- The previous mesh put every sleeper between -sleeperHeight and z=0.
    -- The flatgrass terrain is also at z=0: the top surfaces were co-planar
    -- with the BSP floor and z-fought, creating a long dark "shadow" band.
    -- Match the old fallback renderer instead: sleepers stand ABOVE z=0,
    -- while their tops remain below the 10-SU physical rail-running surface.
    local sleeperBase = 0.15
    local sleeperTop = math.min(sleeperBase + sleeperHeight, 8.5)

    -- Center ties within every section, never on section endpoints. Formerly
    -- each adjacent entity drew a second tie at the same joint, creating more
    -- overlap artifacts (especially on curves).
    local ties = math.max(1, math.ceil(length / sleeperSpacing))
    local step = length / ties
    for i = 0, ties - 1 do
        local x = -half + (i + 0.5) * step
        for lane = 1, trackCount do
            local middle = trackCount == 2 and (lane == 1 and -trackSpacing * 0.5 or trackSpacing * 0.5) or 0
            AddBox(sleepers,
                Vector(x - sleeperWidth * 0.5, middle - sleeperLength * 0.5, sleeperBase),
                Vector(x + sleeperWidth * 0.5, middle + sleeperLength * 0.5, sleeperTop))
        end
    end

    if tunnelType ~= "none" and trackCount == 2 then
        if tunnelType == "round" then
            radius = math.max(radius, trackSpacing * 0.5 + 135)
        else
            width = math.max(width, trackSpacing + 270)
        end
    end
    if tunnelType ~= "none" then
        -- The ordinary map terrain at z=0 used to be visible through the bore.
        -- A concrete/ballast deck at z=1.2 occludes the grass without raising
        -- the Metrostroi running rails (top=10) or bogey physics.
        local floorHalf = tunnelType == "round" and radius * 0.69
            or math.max(width * 0.5, trackCount == 2 and trackSpacing * 0.5 + 105 or 120)
        AddBox(ballast, Vector(-half, -floorHalf, -2),
                        Vector( half, floorHalf, 1.1))
        if tunnelStyle == "metrostroi" then
            local sideReach = tunnelType == "round" and radius * 0.78
                or math.max(120, width * 0.5 - 24)
            for _, direction in ipairs({-1, 1}) do
                local inner = sideReach - 22
                local y1, y2 = math.min(inner * direction, sideReach * direction),
                               math.max(inner * direction, sideReach * direction)
                AddBox(walkway, Vector(-half, y1, 1.1),
                                Vector( half, y2, 11))
            end
        end
    end

    if tunnelType == "round" then
        if trackCount == 2 then radius = math.max(radius, trackSpacing * 0.5 + 135) end
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
            if tunnelStyle == "metrostroi" then
                -- Slender concrete tubbing seam rings, every ~128 Source units.
                local ringCount = math.max(1, math.ceil(length / 128))
                for j = 0, ringCount do
                    local x = -half + j * length / ringCount
                    AddQuad(rings,
                        Vector(x - 1.4, y1 * 0.996, z1 * 0.996 + zCenter * 0.004),
                        Vector(x + 1.4, y1 * 0.996, z1 * 0.996 + zCenter * 0.004),
                        Vector(x + 1.4, y2 * 0.996, z2 * 0.996 + zCenter * 0.004),
                        Vector(x - 1.4, y2 * 0.996, z2 * 0.996 + zCenter * 0.004), true)
                end
            end
        end
    elseif tunnelType ~= "none" then
        if trackCount == 2 then width = math.max(width, trackSpacing + 270) end
        if tunnelType == "wide" then width = math.max(width, 460) end
        local y, bottom = width * 0.5, -55
        AddBox(tunnel, Vector(-half, -y - wall, bottom), Vector(half, -y, height))
        AddBox(tunnel, Vector(-half, y, bottom), Vector(half, y + wall, height))
        AddBox(tunnel, Vector(-half, -y - wall, height), Vector(half, y + wall, height + wall))
        AddBox(tunnel, Vector(-half, -y - wall, bottom - wall), Vector(half, y + wall, bottom))
        if tunnelStyle == "metrostroi" then
            local count = math.max(1, math.ceil(length / 128))
            for j = 0, count do
                local x = -half + j * length / count
                AddBox(rings, Vector(x - 1.3, -y + 1, 1),
                              Vector(x + 1.3, -y + 3.5, height))
                AddBox(rings, Vector(x - 1.3, y - 3.5, 1),
                              Vector(x + 1.3, y - 1, height))
                AddBox(rings, Vector(x - 1.3, -y, height - 3.5),
                              Vector(x + 1.3, y, height - 1))
            end
        end
    end

    local contact, cover, insulators = ContactRailVertices(
        length, gauge, trackCount, trackSpacing, thirdRail,
        contactSide, contactOffset, contactHeight)

    local meshes = {}
    local function Keep(vertices, mat)
        local result = MakeMesh(vertices)
        if result then meshes[#meshes + 1] = {mesh = result, material = mat} end
    end
    Keep(rails, railMaterial)
    -- Separate mesh makes the diagnostic toggle free of regeneration.
    local sleeperMesh = MakeMesh(sleepers)
    if sleeperMesh then
        meshes[#meshes + 1] = {mesh = sleeperMesh, material = sleeperMaterial, sleepers = true}
    end
    Keep(tunnel, tunnelStyle == "metrostroi" and tunnelMaterial or tunnelFloorMaterial)
    Keep(ballast, tunnelFloorMaterial)
    Keep(walkway, tunnelFloorMaterial)
    Keep(rings, tunnelSeamMaterial)
    Keep(contact, contactMaterial)
    Keep(cover, contactCoverMaterial)
    Keep(insulators, insulatorMaterial)
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
    local trackCount = ent:GetNW2Int("MEXTrackCount", 1) == 2 and 2 or 1
    local trackSpacing = math.Clamp(ent:GetNW2Float("MEXTrackSpacing", 240), 180, 400)
    local doubleBore = trackCount == 2
    local tunnelStyle = ent:GetNW2String("MEXTunnelStyle", "metrostroi")
    local thirdRail = ent:GetNW2Bool("MEXThirdRail", true)
    local contactSide = G.SafeThirdRailSide(ent:GetNW2String("MEXThirdRailSide", "outside"))
    local contactOffset = ent:GetNW2Float("MEXThirdRailOffset", 112)
    local contactHeight = ent:GetNW2Float("MEXThirdRailHeight", 20)
    if doubleBore then
        if tunnelType == "round" then radius = math.max(radius, trackSpacing * 0.5 + 135) end
        if tunnelType ~= "none" and tunnelType ~= "round" then width = math.max(width, trackSpacing + 270) end
    end
    -- Rebuild only when networked geometry SETTINGS change, never every frame.
    local key = string.format(
        "metro-lining-v4/%d/%.2f/%.2f/%.2f/%.2f/%.2f/%.2f/%.2f/%.2f/%s/%s/%.2f/%.2f/%.2f/%.2f/%d/%s/%.2f/%.2f",
        trackCount, trackSpacing, length, gauge, rw, spacing, sl, sw, sh,
        tunnelType, tunnelStyle, radius, width, height, wall,
        thirdRail and 1 or 0, contactSide, contactOffset, contactHeight)
    if ent.MEXFastKey ~= key then
        G.ClearClientMeshes(ent)
        ent.MEXFastMeshes = CreateMeshes(ent, length, gauge, rw, spacing, sl, sw, sh,
                                         tunnelType, radius, width, height, wall, trackCount, trackSpacing)
        ent.MEXFastKey = key
        local halfWidth = tunnelType == "round" and radius + wall
            or (tunnelType ~= "none" and math.max(width, tunnelType == "wide" and 460 or 0) * 0.5 + wall)
            or math.max(sl * 0.5 + (doubleBore and trackSpacing * 0.5 or 0), gauge * 0.5 + rw + (doubleBore and trackSpacing * 0.5 or 0))
        local roof = tunnelType == "round" and (2 * radius - 55 + wall)
            or (tunnelType ~= "none" and height + wall)
            or 24
        -- Older GMod branches/models may not expose this method here.
        if ent.SetRenderBounds then
            ent:SetRenderBounds(Vector(-length * 0.5 - 16, -halfWidth - 16, -72),
                                Vector(length * 0.5 + 16, halfWidth + 16, roof + 16))
        end
    end

    if not ent.MEXFastMeshes then return end
    local matrix = Matrix()
    matrix:SetTranslation(ent:GetPos())
    matrix:SetAngles(ent:GetAngles())
    cam.PushModelMatrix(matrix)
    local drawSleepers = not cvDrawSleepers or cvDrawSleepers:GetBool()
    for _, entry in ipairs(ent.MEXFastMeshes) do
        if not entry.sleepers or drawSleepers then
            render.SetMaterial(entry.material)
            entry.mesh:Draw()
        end
    end
    cam.PopModelMatrix()
end
