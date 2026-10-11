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

-- Native Source 2007/2013 Metrostroi models verified against the model
-- names and compiled studio headers of PhoenixBlack/Metrostroi. All original
-- straight tunnel modules advance along *local +Y*, from Y=0 to length.
-- The old heuristic used the bounding box's longest axis, which often chose
-- the wrong axis for short prefab pieces and silently fell back to boxes.
G.NativeTunnelModels = {
    none = {
        [1] = {[4096] = "railroad4096.mdl", [1024] = "railroad1024.mdl"},
    },
    round = {
        [1] = {[64] = "tunnel64.mdl", [256] = "tunnel256.mdl", [1024] = "tunnel1024.mdl"},
        [2] = {[1024] = "tunnel1024_double.mdl"},
    },
    rectangular = {
        [1] = {[64] = "tunnel64_rect.mdl", [256] = "tunnel256_rect.mdl",
               [1024] = "tunnel1024_rect.mdl"},
        [2] = {[1024] = "tunnel1024_double.mdl"},
    },
}
G.NativeTunnelModels.wide = {[2] = {[1024] = "tunnel1024_double.mdl"}}
G.NativeModelRoot = "models/metrostroi/tracks/"
G.NativeDoubleLateralCenter = -132 -- stock 1024_double MDL: X bounds [-408.3, 144.3]

function G.SelectNativeTunnel(tunnelType, trackCount, length)
    local byType = G.NativeTunnelModels[tunnelType]
    local choices = byType and byType[trackCount == 2 and 2 or 1]
    if not choices then return nil end
    for _, nominal in ipairs({4096, 1024, 256, 64}) do
        local fileName = choices[nominal]
        if fileName and math.abs(length - nominal) <= 1.0 then
            return G.NativeModelRoot .. fileName, nominal
        end
    end
    return nil
end

function G.SafeThirdRailSide(side)
    side = tostring(side or "outside")
    return (side == "left" or side == "right" or side == "both")
        and side or "outside"
end

-- Calculate how much shell is needed so a protective contact-rail cover
-- doesn't protrude THROUGH the bore at low installation height.
-- A perfect circular double-track bore needs to be very large; wide or
-- rectangular profiles are recommended for double-track construction.
function G.EffectiveBore(radius, width, trackCount, spacing, contactEnabled, contactOffset, contactHeight)
    local count = trackCount == 2 and 2 or 1
    local halfGap = count == 2 and spacing * 0.5 or 0
    local requiredOutside = halfGap + (contactEnabled and (contactOffset + 22) or 135)
    local minWidth = requiredOutside * 2
    width = math.max(width, minWidth)
    if count == 2 then radius = math.max(radius, halfGap + 135) end
    if contactEnabled then
        -- Cross-section is circle center (radius-55); ring meets guarded
        -- power rail around y=requiredOutside, z=(height+14).
        local q = 55 + contactHeight + 14
        radius = math.max(radius, (requiredOutside * requiredOutside + q * q) / (2 * q) + 10)
    end
    return radius, width
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
function G.PhysicsConvexes(length, gauge, railWidth, tunnelType, radius, width, height, wall,
                            trackCount, trackSpacing, thirdRail, thirdRailSide, thirdRailOffset, thirdRailHeight)
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
    radius, width = G.EffectiveBore(radius, width, trackCount, trackSpacing,
        thirdRail == true, tonumber(thirdRailOffset) or 112, tonumber(thirdRailHeight) or 20)

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

-- Railroad_001 and railroad_002 are texture ATLASES intended for compiled
-- Metrostroi models. Mapping the full atlas onto each primitive rail/tie was
-- responsible for bizarre bronze/striped segments in the screenshot. Keep
-- procedural parts consistently shaded; native MDLs retain their own atlases.
local railMaterial = SolidMaterial("mex_track_rail_steel_v8", {
    "models/props_c17/metalladder003",
    "models/props_wasteland/metal_tram001a",
    "vgui/white",
}, "[0.68 0.71 0.74]")
local sleeperMaterial = SolidMaterial("mex_track_tie_grease_v8", {
    "models/props_wasteland/wood_fence01a",
    "models/props_c17/furniturewood001a",
    "vgui/white",
}, "[0.39 0.38 0.37]")
-- tunnelwall_002 is a specialized model UV atlas (wood/plank-like patterns
-- when applied to a plain box). Use a proper tileable concrete surface instead.
local tunnelMaterial = SolidMaterial("mex_track_tunnel_wall_v8", {
    "metro/metroconcrete001",        -- original Metrostroi, repeatable concrete
    "metro/metroconcrete003",
    "models/props_c17/concretewall001a",
}, "[0.74 0.74 0.74]")
local tunnelSeamMaterial = SolidMaterial("mex_track_tunnel_seam_v8", {
    "metro/metroconcrete002",
    "models/props_c17/concretewall001a",
}, "[0.43 0.43 0.43]")
local tunnelFloorMaterial = SolidMaterial("mex_track_tunnel_floor_v8", {
    "models/props_wasteland/concretefloor010a",
    "metro/metroconcrete004",
    "metro/metroconcrete001",
}, "[0.48 0.46 0.43]")
local contactMaterial = SolidMaterial("mex_track_contact_metal_v9", {
    "models/props_c17/metalladder003",
    "vgui/white",
}, "[0.53 0.55 0.55]")
local contactCoverMaterial = SolidMaterial("mex_track_contact_yellow_v9", {
    "vgui/white",
}, "[0.78 0.61 0.21]")
local insulatorMaterial = SolidMaterial("mex_track_contact_insulator_v5", {
    "vgui/white",
}, "[0.46 0.35 0.23]")
local cableMaterial = SolidMaterial("mex_track_cable_matte_v8", {
    "vgui/white",
}, "[0.10 0.105 0.11]")
local cableBracketMaterial = SolidMaterial("mex_track_cable_bracket_v8", {
    "vgui/white",
}, "[0.25 0.25 0.26]")
local railClipMaterial = SolidMaterial("mex_track_rail_clips_v9", {
    "vgui/white",
}, "[0.26 0.27 0.29]")
local ceilingBeamMaterial = SolidMaterial("mex_track_ceiling_beam_v8", {
    "metro/metroconcrete001",
    "models/props_c17/concretewall001a",
}, "[0.57 0.56 0.55]")

-- Global visual toggle.  It never changes the saved route or collisions.
local cvDrawSleepers = CreateClientConVar(
    "mex_track_builder_draw_sleepers", "1", true, false,
    "Render procedural railway sleepers/ties"
)
local cvBrightNativeTunnels = CreateClientConVar(
    "mex_track_builder_native_tunnel_lighting", "1", true, false,
    "Keep installed tunnel MDLs lit on maps without baked tunnel lighting"
)

-- Correct per-FACE UV projection: the old x+z / y+z formula distorted
-- concrete on vertical walls into diagonal plank patterns. A wall tiles in
-- longitudinal (X) and vertical (Z), a ceiling/floor in X/Y, an end cap in
-- Y/Z. Coordinates are local Source units, so NO face is stretched to fit.
--
-- UV override is used only for circular lining: unfold theta around the
-- entire circumference to avoid discontinuities at every triangulated face.
local UV_TILE = 128
-- Set only while synchronously constructing one segment mesh. Client GLua
-- executes this sequentially; the offset is reset when generation finishes.
local activeUVStart = 0

local function AddQuad(vertices, a, b, c, d, doubleSided, suppliedUV)
    local normal = (b - a):Cross(c - a)
    if normal:LengthSqr() < 0.000001 then return end
    normal:Normalize()

    local ax, ay, az = math.abs(normal.x), math.abs(normal.y), math.abs(normal.z)
    local function UV(point)
        if ax >= ay and ax >= az then
            return point.y / UV_TILE, point.z / UV_TILE
        elseif ay >= az then
            return (point.x + activeUVStart) / UV_TILE, point.z / UV_TILE
        end
        return (point.x + activeUVStart) / UV_TILE, point.y / UV_TILE
    end

    local points = {a, b, c, d}
    local values = {}
    for i, p in ipairs(points) do
        local u, v
        if suppliedUV and suppliedUV[i] then
            u, v = suppliedUV[i][1], suppliedUV[i][2]
        else
            u, v = UV(p)
        end
        values[i] = {pos = p, u = u, v = v}
    end

    local function Add(i, n)
        local sample = values[i]
        vertices[#vertices + 1] = {
            pos = sample.pos, normal = n,
            u = sample.u, v = sample.v,
        }
    end

    Add(1, normal); Add(2, normal); Add(3, normal)
    Add(1, normal); Add(3, normal); Add(4, normal)
    if doubleSided then
        local reversed = -normal
        Add(3, reversed); Add(2, reversed); Add(1, reversed)
        Add(4, reversed); Add(3, reversed); Add(1, reversed)
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

-- Five-sided dark rubber power/signal cable. It is true geometry, not
-- a stretched UV decal; its gentle sag follows global route distance so
-- neighboring independent track entities do not make the cable jump.
local function AddCable(vertices, xStart, xEnd, y, z, thickness, routePhase, phase)
    local count = math.max(1, math.ceil((xEnd - xStart) / 48))
    for j = 0, count - 1 do
        local a = xStart + (xEnd - xStart) * j / count
        local b = xStart + (xEnd - xStart) * (j + 1) / count
        local za = z + 2.2 * math.sin((a + routePhase) / 98 + phase)
        local zb = z + 2.2 * math.sin((b + routePhase) / 98 + phase)
        -- Low sidedness avoids expensive cylinder meshes.
        for side = 0, 4 do
            local phi0 = side * math.pi * 2 / 5
            local phi1 = (side + 1) * math.pi * 2 / 5
            local cy0, cz0 = math.cos(phi0) * thickness, math.sin(phi0) * thickness
            local cy1, cz1 = math.cos(phi1) * thickness, math.sin(phi1) * thickness
            AddQuad(vertices,
                Vector(a, y + cy0, za + cz0), Vector(b, y + cy0, zb + cz0),
                Vector(b, y + cy1, zb + cz1), Vector(a, y + cy1, za + cz1), true)
        end
    end
end

local function AddClassicTunnelDetails(ent, length, tunnelType, radius, width, height,
                                        cables, clamps, beams, wallSeams)
    if tunnelType == "none" then return end
    local half = length * 0.5
    local offset = ent:GetNW2Float("MEXUVStart", 0)
    local round = tunnelType == "round"
    local yc = width * 0.5
    local zCenter = radius - 55

    local function InnerSide(z)
        if not round then return yc - 4 end
        return math.sqrt(math.max(0, radius * radius - (z - zCenter) ^ 2)) - 5
    end

    -- Six cables at each side as seen in classic Metrostroi and Track Pack.
    -- Cable height stays above contact-rail cover and below roof.
    local highestCable = math.min(height - 55, 160)
    local lowestCable = 68
    if round then
        highestCable = math.min(zCenter + radius - 70, 156)
    end
    highestCable = math.max(highestCable, lowestCable + 35)
    for _, direction in ipairs({-1, 1}) do
        for strand = 0, 5 do
            local z = lowestCable + strand * (highestCable - lowestCable) / 5
            local y = direction * InnerSide(z)
            AddCable(cables, -half, half, y, z, 2.1, offset + half,
                     strand * 0.62 + (direction == 1 and 0.5 or 0))
        end
    end

    -- Brackets every 128SU, on an absolute route grid: no duplicated brackets
    -- at the beginning/end of adjacent mesh entities.
    local firstBracket = math.ceil((offset + 4) / 128)
    local lastBracket = math.floor((offset + length - 4) / 128)
    for idx = firstBracket, lastBracket do
        local x = idx * 128 - offset - half
        for _, direction in ipairs({-1, 1}) do
            local bottomZ, topZ = lowestCable - 9, highestCable + 8
            local y1 = direction * (InnerSide(highestCable) - 5)
            local y2 = direction * (InnerSide(lowestCable) + 7)
            AddBox(clamps, Vector(x - 2.5, math.min(y1, y2), bottomZ),
                           Vector(x + 2.5, math.max(y1, y2), topZ))
            for j = 0, 2 do
                local z = lowestCable + (j * 2 + 0.5) * (highestCable - lowestCable) / 5
                local y = direction * InnerSide(z)
                AddBox(clamps, Vector(x - 6, y - 5, z - 1.5),
                               Vector(x + 6, y + 5, z + 1.5))
            end
        end
    end

    -- Periodic concrete ceiling ribs in rectangular tunnels, as in the
    -- reference screenshot. No roof obstacles are added to train physics.
    if not round then
        local top = height - 12
        -- Shift by half a bay: otherwise beams fall exactly on 192-SU
        -- entity boundaries and BOTH neighboring chunks skip them.
        local beamPhase = 96
        for idx = math.ceil((offset + 8 - beamPhase) / 192),
                   math.floor((offset + length - 8 - beamPhase) / 192) do
            local x = idx * 192 + beamPhase - offset - half
            AddBox(beams,
                Vector(x - 6, -yc + 5, top - 15),
                Vector(x + 6, yc - 5, top))
        end
        -- Long, thin precast-wall panel joints. Kept shallow so the cables
        -- remain in front of the wall and no z-fighting occurs.
        for _, z in ipairs({56, 192}) do
            if z < height - 32 then
                AddBox(wallSeams,
                    Vector(-half, -yc + 1.5, z - 0.7),
                    Vector(half, -yc + 2.5, z + 0.7))
                AddBox(wallSeams,
                    Vector(-half, yc - 2.5, z - 0.7),
                    Vector(half, yc - 1.5, z + 0.7))
            end
        end
    end
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

-- Manual diagnostics: tells the player which real compiled modules are
-- actually mounted, and why a section may still be procedural. No scanning
-- all addons or expensive model checks every frame.
concommand.Add("mex_track_builder_model_status", function()
    print("===== Metrostroi Expanded - real .mdl status =====")
    local ok, absent = 0, 0
    for kind, byCount in pairs(G.NativeTunnelModels) do
        for count, byLength in pairs(byCount) do
            for length, name in pairs(byLength) do
                local model = G.NativeModelRoot .. name
                local available = util.IsValidModel(model)
                print(string.format("  [%s] %s / %d track(s) / %d SU: %s",
                    available and "OK" or "MISSING", kind, count, length, model))
                if available then ok = ok + 1 else absent = absent + 1 end
            end
        end
    end
    local native, fallback = 0, 0
    for _, ent in ipairs(ents.FindByClass("mex_track_segment")) do
        local manual = ent:GetNW2String("MEXPackModel", "")
        local model = manual ~= "" and manual or
            G.SelectNativeTunnel(ent:GetNW2String("MEXTunnelType", "none"),
                                 ent:GetNW2Int("MEXTrackCount", 1),
                                 ent:GetNW2Float("MEXLength", 0))
        if model and util.IsValidModel(model) then
            native = native + 1
        else
            fallback = fallback + 1
        end
    end
    print(string.format("  %d native modules installed, %d missing; current route segments: %d candidate native / %d procedural",
        ok, absent, native, fallback))
    print("  Native models are exact-length stock units (64/256/1024 SU).")
    print("  On curves or nonstandard lengths, switch to model-piece placement or procedural fallback.")
    local player = LocalPlayer()
    if IsValid(player) then
        player:ChatPrint(string.format("[MEX] Stock tunnel models: %d OK / %d missing. See console for filenames.",ok,absent))
    end
end)

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
        activeUVStart = ent:GetNW2Float("MEXUVStart", 0) + length * 0.5
        ent.MEXContactMeshes = MakeContactMeshes(length, gauge, count, spacing,
                                                  enabled, side, offset, height)
        activeUVStart = 0
        ent.MEXContactKey = key
    end
    DrawMeshEntries(ent, ent.MEXContactMeshes)
end

-- Track Pack provides *rigid compiled MDLs*. Draw exactly one installed model
-- on a straight two-point section, never stretch it along a spline and never
-- guess file paths. Curves continue to use our dynamic procedural geometry.
-- The selected MDL is only a visual skin: MEX's separate rail collision and
-- Metrostroi route graph remain authoritative.
-- IMPORTANT: Genuine Metrostroi models have a known native orientation.
-- Their track moves from local Y=0 to Y=64/256/1024, NOT centered around
-- the model origin. Draw by placing local Y=0 on the segment's first node.
-- This avoids the OBB-based axis guessing and mysterious missing models.
function G.DrawPackModel(ent)
    local length = ent:GetNW2Float("MEXLength", 0)
    local manual = ent:GetNW2String("MEXPackModel", "")
    local isRigid = ent:GetNW2Bool("MEXRigidSection", false)
    local allowAuto = ent:GetNW2Bool("MEXAutoNativeModels", true)
    local tunnelType = G.SafeTunnelType(ent:GetNW2String("MEXTunnelType", "none"))
    local trackCount = ent:GetNW2Int("MEXTrackCount", 1)
    local style = ent:GetNW2String("MEXTunnelStyle", "metrostroi")
    local modelName, nominalLength

    if manual ~= "" and isRigid then
        modelName = manual
    elseif allowAuto and style == "metrostroi" then
        modelName, nominalLength = G.SelectNativeTunnel(tunnelType, trackCount, length)
    end

    if not modelName then
        if IsValid(ent.MEXPackPiece) then ent.MEXPackPiece:Remove() end
        ent.MEXPackPiece, ent.MEXPackModel = nil, nil
        return false
    end

    local path = string.lower(modelName)
    -- Explicit selection of a stock prefab uses the same native +Y placement
    -- rules as the automatic preset. Do not misalign the double when selected
    -- through the dropdown.
    if not nominalLength then
        for _, byCount in pairs(G.NativeTunnelModels) do
            for _, bySize in pairs(byCount) do
                for nativeSize, fileName in pairs(bySize) do
                    if path == G.NativeModelRoot .. fileName then
                        nominalLength = nativeSize
                        break
                    end
                end
                if nominalLength then break end
            end
            if nominalLength then break end
        end
    end
    if not string.match(path, "^models/[%w_/%-%.]+%.mdl$") then return false end
    if trackCount == 2 and not (string.find(path, "double", 1, true)
        or string.find(path, "_ns", 1, true)
        or string.find(path, "2track", 1, true)) then
        return false
    end
    if not nominalLength and (string.find(path, "turn", 1, true)
        or string.find(path, "switch", 1, true)
        or string.find(path, "curve", 1, true)) then
        -- Curved prefabs require path/topology metadata; a straight physics
        -- segment must never masquerade as a curved model.
        return false
    end

    if ent.MEXPackValidityPath ~= modelName then
        ent.MEXPackValidityPath = modelName
        ent.MEXPackValidity = util.IsValidModel(modelName)
        if not ent.MEXPackValidity then
            G.MissingClientModels = G.MissingClientModels or {}
            if not G.MissingClientModels[modelName] then
                G.MissingClientModels[modelName] = true
                print("[MEX Track Builder] Missing installed native model: " .. modelName
                    .. " (using procedural fallback)")
            end
        end
    end
    if not ent.MEXPackValidity then return false end

    local cacheKey = modelName .. "/" .. math.Round(length, 1)
    if ent.MEXRejectedPackKey == cacheKey then return false end
    if ent.MEXPackModel ~= modelName or not IsValid(ent.MEXPackPiece) then
        if IsValid(ent.MEXPackPiece) then ent.MEXPackPiece:Remove() end
        local piece = ClientsideModel(modelName, RENDERGROUP_OPAQUE)
        if not IsValid(piece) then return false end
        piece:SetNoDraw(true)
        piece:DrawShadow(false)
        ent.MEXPackPiece, ent.MEXPackModel = piece, modelName
        ent.MEXLastRenderBounds = nil
    end

    local piece = ent.MEXPackPiece
    local mins, maxs = piece:OBBMins(), piece:OBBMaxs()
    local isOriginal = nominalLength ~= nil
    local nativeLength = maxs.y - mins.y
    local nativeOnY = isOriginal
    if not isOriginal then
        -- User-supplied Track Pack MDLs may use either X or Y. Detect using
        -- length, but never stretch an arbitrary prefab to make it fit.
        local xLength = maxs.x - mins.x
        if math.abs(xLength - length) < math.abs(nativeLength - length) then
            nativeLength, nativeOnY = xLength, false
        else
            nativeOnY = true
        end
    end
    if math.abs(nativeLength - length) > math.max(4, length * 0.03) then
        ent.MEXRejectedPackKey = cacheKey
        piece:Remove()
        ent.MEXPackPiece, ent.MEXPackModel = nil, nil
        if not ent.MEXPackSizeWarned then
            ent.MEXPackSizeWarned = true
            print("[MEX Track Builder] Native model size mismatch: " .. modelName
                .. " expected " .. math.Round(length, 1) ..
                " SU; model bounding length " .. math.Round(nativeLength, 1) .. " SU")
        end
        return false
    end
    ent.MEXRejectedPackKey = nil

    local angles = ent:GetAngles()
    local correction = nativeOnY and Angle(0, -90, 0) or Angle(0, 0, 0)
    local mdlAngles = ent:LocalToWorldAngles(correction)
    -- Native +Y (or user-supplied +X) starts at first route node. Source's
    -- model *origin* is at the start, not OBB centre. Native double has X
    -- bounds [-408,144] => offset its bore by 132 to center both tracks.
    local start = ent:GetPos() - angles:Forward() * (length * 0.5)
    local correctionX = isOriginal and trackCount == 2
        and -G.NativeDoubleLateralCenter or 0
    local lateral = Vector(correctionX, isOriginal and 0 or -mins.y, 0)
    lateral:Rotate(mdlAngles)
    local pos = start + lateral + angles:Up() * ent:GetNW2Float("MEXPackZOffset", 0)
    if not isOriginal and not nativeOnY then
        local axisOffset = Vector(-mins.x, -((mins.y + maxs.y) * 0.5), 0)
        axisOffset:Rotate(mdlAngles)
        pos = start + axisOffset + angles:Up() * ent:GetNW2Float("MEXPackZOffset", 0)
    end

    piece:SetRenderOrigin(pos)
    piece:SetRenderAngles(mdlAngles)
    if ent.SetRenderBounds and ent.MEXLastRenderBounds ~= modelName then
        local bound = math.max(1500, length + 512, (maxs - mins):Length() + 128)
        ent:SetRenderBounds(Vector(-bound, -bound, -bound),
                            Vector(bound, bound, bound))
        ent.MEXLastRenderBounds = modelName
    end
    local illuminate = cvBrightNativeTunnels and cvBrightNativeTunnels:GetBool()
    if illuminate then
        render.SuppressEngineLighting(true)
        render.SetColorModulation(0.67, 0.67, 0.67)
    end
    piece:DrawModel()
    if illuminate then
        render.SetColorModulation(1, 1, 1)
        render.SuppressEngineLighting(false)
    end
    piece:SetRenderOrigin(nil)
    piece:SetRenderAngles(nil)
    return true
end


local function CreateMeshes(ent, length, gauge, railWidth, sleeperSpacing,
                            sleeperLength, sleeperWidth, sleeperHeight,
                            tunnelType, radius, width, height, wall, trackCount, trackSpacing)
    local rails, sleepers, tunnel = {}, {}, {}
    local railClips = {}
    local ballast, rings, walkway = {}, {}, {}
    local cables, clamps, beams, wallSeams = {}, {}, {}, {}
    local thirdRail = ent:GetNW2Bool("MEXThirdRail", true)
    local contactSide = G.SafeThirdRailSide(ent:GetNW2String("MEXThirdRailSide", "outside"))
    local contactOffset = ent:GetNW2Float("MEXThirdRailOffset", 112)
    local contactHeight = ent:GetNW2Float("MEXThirdRailHeight", 20)
    local tunnelStyle = ent:GetNW2String("MEXTunnelStyle", "metrostroi")
    local half = length * 0.5
    activeUVStart = ent:GetNW2Float("MEXUVStart", 0) + half
    trackCount = trackCount == 2 and 2 or 1
    trackSpacing = math.Clamp(tonumber(trackSpacing) or 240, 180, 400)
    for lane = 1, trackCount do
        local middle = trackCount == 2 and (lane == 1 and -trackSpacing * 0.5 or trackSpacing * 0.5) or 0
        for _, y in ipairs({middle - gauge * 0.5, middle + gauge * 0.5}) do
            -- Three-layer steel rail profile: broad base, slender web and
            -- running head exactly at z=10 SU (Metrostroi rerail height).
            -- Physics remains the old narrow continuous rail collision hull.
            AddBox(rails,
                Vector(-half - 0.35, y - railWidth * 0.88, 5.1),
                Vector(half + 0.35, y + railWidth * 0.88, 6.5))
            AddBox(rails,
                Vector(-half - 0.35, y - 1.7, 6.4),
                Vector(half + 0.35, y + 1.7, 8.9))
            AddBox(rails,
                Vector(-half - 0.35, y - railWidth * 0.5, 8.7),
                Vector(half + 0.35, y + railWidth * 0.5, 10))
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
            -- Lightweight dark clips at each running rail/sleeper crossing.
            for _, railY in ipairs({middle - gauge * 0.5, middle + gauge * 0.5}) do
                for _, side in ipairs({-1, 1}) do
                    local boltY = railY + side * (railWidth * 0.5 + 2.5)
                    AddBox(railClips,
                        Vector(x - 3.1, boltY - 1.9, sleeperTop),
                        Vector(x + 3.1, boltY + 1.9, sleeperTop + 1.8))
                end
            end
        end
    end

    if tunnelType ~= "none" then
        radius, width = G.EffectiveBore(radius, width, trackCount, trackSpacing,
            thirdRail, contactOffset, contactHeight)
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
        local zCenter = radius - 55
        -- Both sides of the lining are visible (viewed from inside/outside).
        for i = 0, 31 do
            local a = i * math.pi * 2 / 32
            local b = (i + 1) * math.pi * 2 / 32
            local y1, z1 = math.cos(a) * radius, zCenter + math.sin(a) * radius
            local y2, z2 = math.cos(b) * radius, zCenter + math.sin(b) * radius
            local yo1, zo1 = math.cos(a) * (radius + wall), zCenter + math.sin(a) * (radius + wall)
            local yo2, zo2 = math.cos(b) * (radius + wall), zCenter + math.sin(b) * (radius + wall)
            -- Continuous cylindrical UVs: U is tunnel length, V is true
            -- perimeter distance rather than mixed Y/Z projections.
            local u0 = (-half - 0.5 + activeUVStart) / UV_TILE
            local u1 = (half + 0.5 + activeUVStart) / UV_TILE
            local v1, v2 = a * radius / UV_TILE, b * radius / UV_TILE
            local vo1, vo2 = a * (radius + wall) / UV_TILE, b * (radius + wall) / UV_TILE
            AddQuad(tunnel,
                Vector(-half - 0.5, y1, z1), Vector(half + 0.5, y1, z1),
                Vector(half + 0.5, y2, z2), Vector(-half - 0.5, y2, z2), true,
                {{u0, v1}, {u1, v1}, {u1, v2}, {u0, v2}})
            AddQuad(tunnel,
                Vector(-half - 0.5, yo2, zo2), Vector(half + 0.5, yo2, zo2),
                Vector(half + 0.5, yo1, zo1), Vector(-half - 0.5, yo1, zo1), true,
                {{u0, vo2}, {u1, vo2}, {u1, vo1}, {u0, vo1}})
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

    if tunnelStyle == "metrostroi" and tunnelType ~= "none" then
        AddClassicTunnelDetails(ent, length, tunnelType, radius, width, height,
                                cables, clamps, beams, wallSeams)
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
    Keep(railClips, railClipMaterial)
    -- Separate mesh makes the diagnostic toggle free of regeneration.
    local sleeperMesh = MakeMesh(sleepers)
    if sleeperMesh then
        meshes[#meshes + 1] = {mesh = sleeperMesh, material = sleeperMaterial, sleepers = true}
    end
    Keep(tunnel, tunnelStyle == "metrostroi" and tunnelMaterial or tunnelFloorMaterial)
    Keep(ballast, tunnelFloorMaterial)
    Keep(walkway, tunnelFloorMaterial)
    Keep(rings, tunnelSeamMaterial)
    Keep(cables, cableMaterial)
    Keep(clamps, cableBracketMaterial)
    Keep(beams, ceilingBeamMaterial)
    Keep(wallSeams, tunnelSeamMaterial)
    Keep(contact, contactMaterial)
    Keep(cover, contactCoverMaterial)
    Keep(insulators, insulatorMaterial)
    activeUVStart = 0
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
    if tunnelType ~= "none" then
        radius, width = G.EffectiveBore(radius, width, trackCount, trackSpacing,
            thirdRail, contactOffset, contactHeight)
    end
    -- Rebuild only when networked geometry SETTINGS change, never every frame.
    local uvStart = ent:GetNW2Float("MEXUVStart", 0)
    local key = string.format(
        "metro-classic-rails-v9/%d/%.2f/%.2f/%.2f/%.2f/%.2f/%.2f/%.2f/%.2f/%s/%s/%.2f/%.2f/%.2f/%.2f/%d/%s/%.2f/%.2f/%.2f",
        trackCount, trackSpacing, length, gauge, rw, spacing, sl, sw, sh,
        tunnelType, tunnelStyle, radius, width, height, wall,
        thirdRail and 1 or 0, contactSide, contactOffset, contactHeight,
        uvStart)
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
