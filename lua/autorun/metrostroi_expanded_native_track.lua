-- Metrostroi Expanded - native original-model construction
-- Copyright (C) 2026 Adam Cir / Adava Software - GPL-3.0
-- No generated rail/tunnel geometry or substituted collision bodies.
if SERVER then AddCSLuaFile() end

MEXNativeTrack = MEXNativeTrack or {}
local N = MEXNativeTrack
local ROOT = "models/metrostroi/tracks/"
if CLIENT then
    CreateClientConVar("mex_native_show_measured_path", "1", true, false,
        "Draw measured original MDL rail-centerline only when using Track Builder")
end
-- Track-placement points sit at the original MDL's baseline, whereas a
-- visible/snap marker belongs at the running rail surface. Never feed that
-- display-only Z offset into another module's origin (it would stair-step).
local RAIL_SURFACE_OFFSET = 10
local MODEL_LIFT = 5
local RAIL_MARKER_OFFSET = Vector(0, 0, RAIL_SURFACE_OFFSET)
local function RenderPort(base)
    return base + RAIL_MARKER_OFFSET
end
-- No prefab/tunnel/radius choices: each model is selected from the
-- installed original MDL catalog. The historic per-model measurements below
-- are retained strictly for safe migration of pre-catalog saved routes.
N.Junctions = N.Junctions or {}
-- Scans mounted Metrostroi and Track Pack MDLs, and measures the real rail
-- centerline of each user-selected model (never substitutes custom meshes).
include("metrostroi_expanded/native_model_catalog.lua")
N.ServerNativeProfiles = N.ServerNativeProfiles or {}
N.CatalogErrors = N.CatalogErrors or {}

-- A native scripted static prop uses the original MDL for BOTH rendering
-- and its compiled .phy. PhysicsInitStatic supports static-prop models that
-- prop_physics may reject; no custom convex hulls are synthesized.
local NativePiece = {
    Type = "anim", Base = "base_anim",
    PrintName = "MEX Original Metrostroi Module",
    Spawnable = false, AdminOnly = true, RenderGroup = RENDERGROUP_OPAQUE,
}
function NativePiece:Initialize()
    if CLIENT then return end
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_VPHYSICS)
    local ok = self:PhysicsInitStatic(SOLID_VPHYSICS)
    if not ok and self.MEXNativePart and N.NativeRailConvexes then
        -- Real original MDL, collision strips reconstructed from its
        -- measured railheads ONLY when the Workshop model has no .phy.
        local hulls = N.NativeRailConvexes(self.MEXNativePart)
        if hulls and #hulls > 0 then
            ok = self:PhysicsInitMultiConvex(hulls, "metal")
            if ok then
                self:SetSolid(SOLID_VPHYSICS)
                self:EnableCustomCollisions(true)
                self.MEXNativeCollisionFallback = true
            end
        end
    end
    if not ok then
        ErrorNoHalt("[MEX Native Track] No original .phy or measured rail geometry: " ..
            self:GetModel() .. "\\n")
    end
    self:SetUseType(SIMPLE_USE)
    -- Original Source-engine entity shadows, not a flat fullbright tint.
    self:DrawShadow(true)
end

-- Rail models are ordinary lit studio entities. Do NOT suppress Source
-- lighting or inject constant model lights: that made tunnel tracks glow
-- and prevented them becoming dark at night or under a tunnel ceiling.
--
-- One engine lighting probe is sampled ABOVE the rail surface, not at the
-- model pivot buried in flatgrass/terrain. An infrequent upward trace adds
-- modest occlusion for *runtime* tunnel roofs, whose shadows are not baked
-- into the underlying BSP lightmaps. Floor/terrain BELOW the start point
-- is deliberately excluded; no fake ground shadow meshes are generated.
-- The engine lighting probe is 74 SU above the track. Check for a
-- ceiling from ~56 SU above the railhead so LOW roofs are not missed,
-- while remaining safely clear of the ground and sleeper collision.
local ROOF_TRACE_HEIGHT = -18
local ROOF_TRACE_RANGE = 2048
local function TrackSkyOcclusion(ent, probe)
    local sample = probe + Vector(0, 0, ROOF_TRACE_HEIGHT)
    local excludeSelf = ent:GetNW2Bool("MEXNativeSurface", false)
    local mask = MASK_OPAQUE or MASK_SOLID
    local filter = excludeSelf and ent or nil
    local hit = util.TraceLine({
        start = sample,
        endpos = sample + Vector(0, 0, ROOF_TRACE_RANGE),
        mask = mask,
        filter = filter,
    })
    if not hit then return 1 end
    if hit.StartSolid then
        -- If the probe happens to sit inside concrete/PHY, do not mistake
        -- the map floor for an overhead roof. Reprobe higher up.
        local higher = sample + Vector(0, 0, 48)
        hit = util.TraceLine({
            start = higher,
            endpos = higher + Vector(0, 0, ROOF_TRACE_RANGE),
            mask = mask,
            filter = filter,
        })
        if not hit then return 1 end
        if hit.StartSolid then
            -- Both probes are inside a solid above the rail. This is
            -- genuinely buried/covered track, NOT a sunlit ground-level
            -- section. Treat it as dark rather than accidentally fullbright.
            return excludeSelf and 0.40 or 0.64
        end
    end
    if not hit.Hit or hit.HitSky then return 1 end
    -- Stronger under-roof rail dimming, gentler on a complete tunnel MDL
    -- because its roof/exterior are part of the same rendered mesh.
    return excludeSelf and 0.40 or 0.64
end

function NativePiece:Draw()
    local sample = self:GetNW2Vector("MEXNativeLightProbe",
        self:GetPos() + Vector(0, 0, 70))
    if self.MEXNextCoverCheck == nil or CurTime() >= self.MEXNextCoverCheck then
        self.MEXNextCoverCheck = CurTime() + 1.35 +
            (self:EntIndex() % 9) * 0.085
        self.MEXCoverShade = TrackSkyOcclusion(self, sample)
    end
    -- Preserve any upstream renderer modulation and leave the lighting
    -- state exactly as it was for other addons/models.
    local red, green, blue = render.GetColorModulation()
    local shade = self.MEXCoverShade or 1
    render.SetLightingOrigin(sample)
    render.SetColorModulation(red * shade, green * shade, blue * shade)
    self:DrawModel()
    render.SetColorModulation(red, green, blue)
    render.SetLightingOrigin(vector_origin)
end

function NativePiece:Use(activator)
    if SERVER and N.ToggleSwitch then N.ToggleSwitch(activator, self) end
end
scripted_ents.Register(NativePiece, "mex_native_track_piece")
local function V(t) return Vector(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0) end
local function P(v) return {v.x, v.y, v.z} end
local function Direction(yaw) return Angle(0, yaw, 0):Forward() end
local function Right(yaw) local f = Direction(yaw) return Vector(f.y, -f.x, 0) end
local function ModelAngles(yaw) return Angle(0, yaw - 90, 0) end
local modelCache = {}
local function ValidModel(model)
    if not isstring(model) or
        (not string.StartWith(string.lower(model), ROOT) and
            not N.ModelCatalog[string.lower(model)]) then return false end
    local cached = modelCache[model]
    if cached and cached.expiry > CurTime() then return cached.valid end
    local valid = util.IsValidModel(model)
    modelCache[model] = {valid = valid, expiry = CurTime() + 30}
    return valid
end
local function Placement(start, yaw, model, length, kind, turn, radius, sweep)
    local ang = ModelAngles(yaw)
    local origin = start + Vector(0, 0, MODEL_LIFT)
    if kind == "double" then
        -- Calibrated original double-tunnel X center is -132 SU.
        origin = origin + ang:Forward() * 132
    end
    return {
        model = model, pos = P(origin), ang = {ang.p, ang.y, ang.r},
        start = P(start), yaw = yaw, length = length,
        lane = kind, turn = turn or 0, radius = radius or 0, sweep = sweep or 0,
    }
end

-- Measured directly from the *running-rail mesh* (railroad_001b)
-- in the original PhoenixBlack/Metrostroi MDL/VVD files. The "turn1"
-- models are TRANSITION curves, not constant-radius circular pieces.
-- They start tangent along model +Y but end with a much SMALLER tangent
-- sweep than 90/3, 90/4 or 90/8. Using circles with the nominal radius
-- made the next piece start hundreds of SU away from the actual rail.
-- Endpoints below are midpoints of the two LAST rail-end mesh vertices.
local STOCK_CURVE_PORTS = {
    [ROOT .. "tunnel3072_turn1.mdl"] = {
        x = -297.195, y = 1623.610, sweep = 24.494,
        track = {0, -1.6, -6.1, -12.9, -24, -39.6, -58.7,
            -75.1, -102.2, -135.6, -173.2, -215.4, -259.2},
    },
    [ROOT .. "tunnel3072_rect_turn1.mdl"] = {
        x = -326.2, y = 1612.0, sweep = 24.49,
        track = {0, -4.2, -11.3, -21.3, -33.6, -48.9, -69.5,
            -95.6, -122.3, -157.9, -195.3, -240.2, -291.4},
    },
    [ROOT .. "tunnel4096_turn1.mdl"] = {
        x = -205.630, y = 1644.390, sweep = 16.300,
        track = {0, -1.3, -4.6, -9.6, -17.7, -28.9, -40.2,
            -54.3, -73.3, -96.6, -122.6, -152.6, -181.3},
    },
    [ROOT .. "tunnel8192_turn1.mdl"] = {
        x = -89.665, y = 1658.955, sweep = 6.830,
        track = {0, -0.8, -2.4, -4.9, -8.7, -13.1, -19.3,
            -25.8, -34.5, -44.9, -54.4, -67.6, -79.4},
    },
    -- Double "turn1" models have a DIFFERENT local pivot from the
    -- double STRAIGHT tunnel prefab: their two rail centers start at
    -- X=+128 and X=-136 (center X=-4), not X=0 and X=-264.
    -- Last-rail coordinates are from the original double VVD mesh.
    [ROOT .. "tunnel4096_double_turn1.mdl"] = {
        entryX = -4, x = -213.6, y = 1642.2, sweep = 16.30,
        track = {-4, -5.0, -8.3, -13.6, -21.1, -31.5, -45.0,
            -58.7, -76.6, -99.4, -122.9, -152.6, -184.0},
    },
    [ROOT .. "tunnel8192_double_turn1.mdl"] = {
        entryX = -4, x = -98.2, y = 1657.9, sweep = 6.83,
        track = {-4, -4.5, -6.1, -8.8, -12.3, -16.7, -22.9,
            -30.1, -37.9, -47.6, -58.9, -69.8, -83.7},
    },
}
-- X samples in the stock mesh above are at Y=0,128,...1536.
-- Explicit final endpoints are exact rail-end cross-section centers.
-- Calibrate attachment ports from the railhead vertices of the exact
-- installed original MDL, NOT from the tunnel shell's OBB or a nominal R
-- circle. This handles different Workshop revisions of original turn1
-- models. No geometry is generated: vertices are inspected only to locate
-- the existing authored track end faces.
local curveMeshCache = {}
-- The server owns the exact curved-rail port measurements. A client may
-- load a different LOD/material set; never independently move its ghost.
N.ServerCurveProfiles = N.ServerCurveProfiles or {}
local function DetectCurveRailMesh(model, fallback)
    if not util.GetModelMeshes then return nil end
    local ok, meshes = pcall(util.GetModelMeshes, model, 0)
    if not ok or not istable(meshes) then return nil end
    local selected = {}
    local lowY, highY = math.huge, -math.huge
    for _, meshData in ipairs(meshes) do
        local material = string.lower(tostring(meshData.material or ""))
        -- The stock railhead material was used to measure the original
        -- turn1 profiles. Do not include sleeper, tunnel wall or third-rail
        -- meshes, which have different local offsets and endpoints.
        if string.find(material, "railroad_001b", 1, true) then
            local vertices = meshData.verticies or meshData.triangles or {}
            selected[#selected + 1] = vertices
            for _, vertex in ipairs(vertices) do
                local pos = vertex.pos
                if isvector(pos) then
                    lowY = math.min(lowY, pos.y)
                    highY = math.max(highY, pos.y)
                end
            end
        end
    end
    if #selected == 0 or highY - lowY < 1024
        or highY - lowY > 2048 then return nil end
    -- Average BOTH running railhead strips at regular original-model
    -- intervals. The midpoint of those rails is the true track center.
    local span = highY - lowY
    local samples = {}
    for i = 0, 12 do
        samples[#samples + 1] = {x = 0, y = lowY + span * i / 12,
            count = 0}
    end
    for _, vertices in ipairs(selected) do
        for _, vertex in ipairs(vertices) do
            local pos = vertex.pos
            if isvector(pos) then
                local t = (pos.y - lowY) / span * 12
                local index = math.Clamp(math.floor(t + 0.5) + 1, 1, 13)
                local sample = samples[index]
                if math.abs(pos.y - sample.y) < 20 then
                    sample.x = sample.x + pos.x
                    sample.count = sample.count + 1
                end
            end
        end
    end
    local valid = {}
    for _, sample in ipairs(samples) do
        if sample.count >= 4 then
            valid[#valid + 1] = {x = sample.x / sample.count,
                y = sample.y}
        end
    end
    if #valid < 6 then return nil end
    local first, last = valid[1], valid[#valid]
    -- End caps must be represented. Otherwise intermediate strips would be
    -- mistaken for connector faces and shift the next section into a gap.
    if first.y - lowY > 24 or highY - last.y > 24 then return nil end
    -- Guard against measuring the outside third rail, sleeve, or any
    -- mismatched Workshop material. A 30-90 SU "successful" measurement
    -- is WORSE than the calibrated stock rail-head ports: it is exactly
    -- the gap visible between two original curved sections.
    if math.abs(first.x - (fallback.entryX or 0)) > 16
        or math.abs(first.y - (fallback.entryY or 0)) > 16
        or math.abs(last.x - fallback.x) > 16
        or math.abs(last.y - fallback.y) > 16 then return nil end
    local preceding = valid[#valid - 1]
    local dx = last.x - preceding.x
    local dy = last.y - preceding.y
    local angle = math.deg(math.atan2(-dx, dy))
    if angle < 0 or angle > 45
        or math.abs(angle - fallback.sweep) > 3 then
        angle = fallback.sweep
    end
    return {
        entryX = first.x, entryY = first.y,
        x = last.x, y = last.y, sweep = angle,
        samples = valid,
    }
end

local function StockCurveProfile(model)
    model = string.lower(tostring(model or ""))
    local fallback = STOCK_CURVE_PORTS[model]
    if not fallback then return nil end
    if CLIENT then
        -- Until the first server synchronization arrives the immutable
        -- stock table is preferred to a locally guessed mesh measurement.
        return N.ServerCurveProfiles[model] or fallback
    end
    if curveMeshCache[model] == nil then
        curveMeshCache[model] = DetectCurveRailMesh(model, fallback) or false
    end
    return curveMeshCache[model] or fallback
end
local function RotateLocal(localPoint, angle)
    local out = Vector(localPoint.x, localPoint.y, localPoint.z)
    out:Rotate(angle)
    return out
end
local function StockCurveWorldPart(start, yaw, model, turn, radius, lane)
    local profile = StockCurveProfile(model)
    if not profile then return nil end
    local left = turn == -1
    local localStart = Vector(profile.entryX or 0, profile.entryY or 0, 0)
    local localEnd = Vector(profile.x, profile.y, 0)
    local sweep = profile.sweep
    -- The measured original track mesh bends toward local negative X.
    -- Start tangent is local +Y, end tangent is yaw + sweep.
    -- Reverse traversal must face opposite the authored end tangent;
    -- therefore its model yaw is yaw - sweep + 180, NOT yaw + sweep + 180.
    local poseYaw = left and yaw or (yaw - sweep + 180)
    local ang = ModelAngles(poseYaw)
    -- Use the ACTUAL authored local rail ports on BOTH ends. "turn1" is a
    -- transition module with a ~1600 SU advance; its end is NOT at
    -- (R*(1-cos(90/parts)), R*sin(90/parts)).
    local authoredEntry = left and localStart or localEnd
    local authoredExit = left and localEnd or localStart
    local modelBase = start - RotateLocal(authoredEntry, ang)
    local finish = modelBase + RotateLocal(authoredExit, ang)
    local mdlOrigin = modelBase + Vector(0, 0, MODEL_LIFT)
    return {
        model = model, pos = P(mdlOrigin), ang = {ang.p, ang.y, ang.r},
        start = P(start), finish = P(finish), yaw = yaw,
        length = localStart:Distance(localEnd),
        lane = lane, turn = turn, radius = radius, sweep = sweep,
        calibrated = true,
    }, finish, yaw + (left and sweep or -sweep)
end
-- Migrate old saved native turn1 modules in-place. Their MDL position is
-- authoritative: update ONLY the start/end rail ports using the visible
-- mesh, without moving/rotating an existing saved original model.
function N.RecalibrateCurvePart(part)
    if not istable(part) or part.junction or part.nativeModel
        or not part.turn or part.turn == 0 then return false end
    local profile = StockCurveProfile(part.model)
    if not profile or not istable(part.pos) or not istable(part.ang) then
        return false
    end
    local ang = Angle(part.ang[1], part.ang[2], part.ang[3])
    local pivot = V(part.pos) - Vector(0, 0, MODEL_LIFT)
    local portA = pivot + RotateLocal(
        Vector(profile.entryX or 0, profile.entryY or 0, 0), ang)
    local portB = pivot + RotateLocal(Vector(profile.x, profile.y, 0), ang)
    if part.turn == -1 then
        part.start, part.finish = P(portA), P(portB)
        part.yaw = part.ang[2] + 90
    else
        part.start, part.finish = P(portB), P(portA)
        part.yaw = part.ang[2] + 90 + profile.sweep + 180
    end
    part.sweep = profile.sweep
    part.length = portA:Distance(portB)
    part.calibrated = true
    return true
end

-- Any original mounted Metrostroi/Track Pack piece can be selected by its
-- full MDL name. Unlike fixed stock profiles, its endpoints and curvature
-- are derived from the pair of real running rails on that exact model.
local function GenericProfile(model)
    model = string.lower(tostring(model or ""))
    if CLIENT then
        local data = N.ServerNativeProfiles[model]
        if data then return data end
        if N.CatalogErrors[model] then return nil, N.CatalogErrors[model] end
        if not N.NextNativeProfileRequest or CurTime() >= N.NextNativeProfileRequest then
            N.NextNativeProfileRequest = CurTime() + 2.5
            net.Start("MEXNativeRequestProfile")
            net.WriteString(model)
            net.SendToServer()
        end
        return nil, "Waiting for server rail-end calibration."
    end
    local measured, err = N.AnalyzeNativeModel(model)
    local original = STOCK_CURVE_PORTS[model]
    if measured and original
        and measured.method ~= "registered original rail centerline" then
        local expectedX = original.entryX or 0
        local expectedY = original.entryY or 0
        -- Original straight-line sleeper/third-rail meshes must never be
        -- mistaken for the running railheads of a 1600-SU turn1 transition.
        if measured.axis ~= 2
            or math.abs(measured.entry[1] - expectedX) > 24
            or math.abs(measured.entry[2] - expectedY) > 24
            or math.abs(measured.finish[1] - original.x) > 24
            or math.abs(measured.finish[2] - original.y) > 24 then
            return nil, "Measured MDL railheads disagree with calibrated Metrostroi curve."
        end
    end
    if not measured and original then
        -- A few stock Metrostroi MDLs do not expose readable railhead
        -- submeshes on dedicated servers. Their measured historical
        -- per-model seam coordinates are retained as a compatibility
        -- profile, NOT as a new-construction model/radius preset.
        local pts = {{original.entryX or 0, original.entryY or 0, 0}}
        for i = 2, #(original.track or {}) do
            pts[#pts + 1] = {original.track[i], (i - 1) * 128, 0}
        end
        pts[#pts + 1] = {original.x, original.y, 0}
        return {
            model = model,
            entry = pts[1], finish = pts[#pts],
            points = pts,
            entryYaw = 90, exitYaw = 90 + original.sweep,
            deltaYaw = original.sweep, curved = true,
            length = math.sqrt(original.x * original.x +
                original.y * original.y),
            method = "model-specific historical measured rail ports",
        }
    end
    return measured, err
end
local function GradeBetween(first, second)
    local z = second.z - first.z
    local planar = math.sqrt((second.x - first.x)^2 +
        (second.y - first.y)^2)
    return math.deg(math.atan2(z, math.max(0.001, planar)))
end
local function HeadingBetween(first, second)
    return math.deg(math.atan2(second.y - first.y,
        second.x - first.x))
end
local function WorldRailPoint(position, angle, point)
    return position + RotateLocal(
        Vector(point[1], point[2], point[3]), angle)
end
local function GenericOriginalPart(start, yaw, model, settings)
    model = string.lower(tostring(model))
    local profile, err = GenericProfile(model)
    if not profile then return nil, err end
    if not istable(profile.points) or #profile.points < 2
        or not istable(profile.entry) or not istable(profile.finish) then
        return nil, "Original MDL does not have validated rail-end geometry."
    end
    local points = profile.points
    local reverse = tonumber(settings.native_reverse) == 1
    local beginPort = reverse and profile.finish or profile.entry
    local endPort = reverse and profile.entry or profile.finish
    local initialNext = reverse and points[#points - 1] or points[2]
    local heading = reverse and (profile.exitYaw + 180)
        or profile.entryYaw
    -- Grade is an elevation angle, positive when rails rise along travel.
    -- Roll the entire ORIGINAL MDL about the world-sideways axis. Neither
    -- its geometry nor its two pairs of rails are bent or generated.
    local beginVector = Vector(beginPort[1], beginPort[2], beginPort[3])
    local nextVector = Vector(initialNext[1], initialNext[2], initialNext[3])
    local localGrade = GradeBetween(beginVector, nextVector)
    local targetGrade = math.Clamp(tonumber(settings.start_grade)
        or tonumber(settings.grade) or 0, -20, 20)
    local angle = Angle(0, yaw - heading, 0)
    angle:RotateAroundAxis(Right(yaw), targetGrade - localGrade)
    local origin = RenderPort(start) - RotateLocal(beginVector, angle)
    local railEnd = WorldRailPoint(origin, angle, endPort)
    local finish = railEnd - RAIL_MARKER_OFFSET
    local finalIndex = reverse and 2 or (#points - 1)
    local lastBefore = WorldRailPoint(origin, angle, points[finalIndex])
    local finalYaw = HeadingBetween(lastBefore, railEnd)
    local finalGrade = GradeBetween(lastBefore, railEnd)
    local part = {
        model = model, pos = P(origin),
        ang = {angle.p, angle.y, angle.r},
        start = P(start), finish = P(finish),
        yaw = yaw, endYaw = finalYaw,
        pitch = targetGrade, endPitch = finalGrade,
        length = profile.length,
        lane = profile.double and "double" or "single",
        turn = profile.curved and
            (math.AngleDifference(finalYaw, yaw) > 0 and -1 or 1) or 0,
        sweep = math.abs(math.AngleDifference(finalYaw, yaw)),
        radius = 0,
        nativeModel = true, reverse = reverse,
        nativePoints = points,
        nativeLanePoints = profile.lanePoints,
        calibrated = true,
    }
    return part, finish, finalYaw, finalGrade
end


-- Collision fallback uses the selected original MDL's LOCAL rail path, not
-- its OBB or a wide support bed. There are two narrow, separate rail strips.
function N.NativeRailConvexes(part)
    if not part.nativeModel then return nil end
    local paths = part.lane == "double" and part.nativeLanePoints
        or {part.nativePoints}
    if not istable(paths) then return nil end
    local hulls = {}
    local function addRails(a, b)
        local delta = b - a
        local flat = Vector(delta.x, delta.y, 0)
        if flat:LengthSqr() < 4 then return end
        flat:Normalize()
        local across = Vector(flat.y, -flat.x, 0)
        for _, side in ipairs({-1, 1}) do
            local offset = across * (side * 42.9)
            local p, q = a + offset, b + offset
            local width = across * 2.9
            local hull = {}
            for _, point in ipairs({p - width, p + width, q - width, q + width}) do
                hull[#hull + 1] = point + Vector(0, 0, -8)
                hull[#hull + 1] = point + Vector(0, 0, 2)
            end
            hulls[#hulls + 1] = hull
        end
    end
    for _, path in ipairs(paths) do
        if not istable(path) or #path < 2 then return nil end
        local stride = math.max(1, math.ceil((#path - 1) / 24))
        for i = 1, #path - 1, stride do
            addRails(V(path[i]), V(path[math.min(#path, i + stride)]))
        end
    end
    return #hulls > 0 and hulls or nil
end

-- Generate a strict sequence of original-size stock modules. There is no
-- arbitrary deformation, scaling, procedural tunnel or geometry fallback.
-- Only a model selected from the actual installed catalog can be placed.
-- Legacy prefab radius/family lists remain readable for old saves, but
-- are NEVER consulted by new construction.
function N.Candidate(start, yaw, aimed, settings)
    settings = settings or {}
    local result = {parts = {}, pos = start, yaw = yaw}
    local selected = string.lower(string.Trim(tostring(settings.native_model or "")))
    if selected == "" then
        return nil, "Select an original MDL from the Model Catalog first."
    end
    local info = N.ModelCatalog[selected]
    if not info then
        return nil, "Original MDL not installed in the mounted model catalog: " .. selected
    end
    if not ValidModel(selected) then
        return nil, "Original model is unavailable: " .. selected
    end

    -- Registered real junctions can also be selected directly from the
    -- catalog. Their topology comes from measured multi-port profiles,
    -- never fabricated by overlapping two regular rails.
    local profile
    for id, junction in pairs(N.Junctions) do
        if junction.model == selected
            or (junction.variants and
                (junction.variants["2"] == selected or
                    junction.variants["3"] == selected)) then
            profile = junction
            break
        end
    end
    if profile then
        if tonumber(settings.native_reverse) == 1 then
            return nil, "Reversing a junction requires separately surveyed port directions."
        end
        local branch = math.Clamp(math.floor(tonumber(settings.branch) or 2),
            2, #profile.ports)
        local validExit = false
        for _, link in ipairs(profile.paths) do
            if (link[1] == 1 and link[2] == branch)
                or (link[2] == 1 and link[1] == branch) then
                validExit = true
                break
            end
        end
        if not validExit then
            return nil, "Selected original junction has no rail connection to output port " .. branch
        end
        if profile.kind == "switch" and branch ~= 2 and not profile.variants then
            return nil, "This original turnout needs calibrated main/diverging PHY models."
        end
        local model = profile.variants
            and profile.variants[tostring(branch)] or profile.model
        if model ~= selected then
            return nil, "Choose the original junction MDL matching selected output port."
        end
        local ang = ModelAngles(yaw)
        local reference = V(profile.ports[1])
        reference:Rotate(ang)
        local origin = start - reference + Vector(0, 0, MODEL_LIFT)
        local port = V(profile.ports[branch])
        port:Rotate(ang)
        result.pos = origin + port - Vector(0, 0, MODEL_LIFT)
        result.yaw = yaw + (tonumber(profile.ports[branch][4]) or 0)
        result.parts[1] = {
            model = model, pos = P(origin), ang = {ang.p, ang.y, ang.r},
            start = P(start), yaw = yaw, length = 0,
            lane = "single", junction = profile.id, branch = branch,
        }
        return result
    end
    if info.kind == "junction" then
        return nil, "Original turnout/crossing needs measured 3- or 4-port junction registration."
    end
    -- 2x = two UNCHANGED single MDLs. On a curve, Split flips the
    -- traversal of the second authentic curve so both lines can branch.
    if tonumber(settings.native_pair) == 1 then
        if info.double or info.kind == "junction" then
            return nil, "2x Single mode requires a single-track MDL."
        end
        local ends = settings.pair_ends
        if not istable(ends) or #ends ~= 2 then
            local spacing = math.Clamp(tonumber(settings.native_spacing) or 264, 180, 480)
            ends = {
                {pos = start - Right(yaw) * spacing * 0.5, yaw = yaw,
                    pitch = tonumber(settings.start_grade) or tonumber(settings.grade) or 0},
                {pos = start + Right(yaw) * spacing * 0.5, yaw = yaw,
                    pitch = tonumber(settings.start_grade) or tonumber(settings.grade) or 0},
            }
        end
        result.pairEnds = {}
        for lane = 1, 2 do
            local entry = ends[lane]
            if not entry or not isvector(entry.pos) then
                return nil, "2x rail endpoints unavailable; restart at a double rail end."
            end
            local reverse = tonumber(settings.native_reverse) or 0
            if tonumber(settings.native_split) == 1 and info.kind == "curve"
                and lane == 2 then reverse = reverse == 1 and 0 or 1 end
            local part, exit, heading, grade = GenericOriginalPart(
                entry.pos, entry.yaw, selected,
                {native_reverse = reverse, start_grade = entry.pitch or 0})
            if not part then return nil, exit end
            part.pairLane = lane
            result.parts[#result.parts + 1] = part
            result.pairEnds[lane] = {pos = exit, yaw = heading, pitch = grade}
        end
        result.pos = (result.pairEnds[1].pos + result.pairEnds[2].pos) * 0.5
        result.yaw = result.pairEnds[1].yaw
        result.pitch = result.pairEnds[1].pitch
        return result
    end
    if settings.pair_ends then
        return nil, "Finish the 2x section before changing to another track mode."
    end
    local part, finish, exitYaw, exitGrade = GenericOriginalPart(
        start, yaw, selected, settings)
    if not part then return nil, finish end
    result.parts[1] = part
    result.pos, result.yaw, result.pitch = finish, exitYaw, exitGrade
    return result
end

local function PortKey(pos)
    return string.format("%d:%d:%d", math.Round(pos.x), math.Round(pos.y), math.Round(pos.z))
end
function N.ModulePorts(part)
    if not part.junction then
        local a, b = V(part.start), part.finish and V(part.finish)
            or (V(part.start) + Direction(part.yaw) * part.length)
        local endYaw = part.endYaw or
            (part.yaw - (part.turn or 0) * (part.sweep or 0))
        local lanes = part.lane == "double" and 2 or 1
        if part.nativeModel and lanes == 2 and istable(part.nativeLanePoints)
            and #part.nativeLanePoints == 2 then
            local ports = {}
            local angle = Angle(part.ang[1], part.ang[2], part.ang[3])
            local origin = V(part.pos)
            for lane = 1, 2 do
                local samples = part.nativeLanePoints[lane]
                if istable(samples) and #samples >= 2 then
                    local entry = part.reverse and samples[#samples] or samples[1]
                    local exit = part.reverse and samples[1] or samples[#samples]
                    local after = part.reverse and samples[#samples - 1] or samples[2]
                    local before = part.reverse and samples[2] or samples[#samples - 1]
                    local entryPos = WorldRailPoint(origin, angle, entry)
                    local exitPos = WorldRailPoint(origin, angle, exit)
                    local afterPos = WorldRailPoint(origin, angle, after)
                    local beforePos = WorldRailPoint(origin, angle, before)
                    ports[#ports + 1] = {
                        pos = entryPos, center = a,
                        yaw = HeadingBetween(afterPos, entryPos),
                        pitch = -GradeBetween(entryPos, afterPos),
                        lanes = 2, start = true,
                    }
                    ports[#ports + 1] = {
                        pos = exitPos, center = b,
                        yaw = HeadingBetween(beforePos, exitPos),
                        pitch = GradeBetween(beforePos, exitPos),
                        lanes = 2, start = false,
                    }
                end
            end
            -- Existing native API expects first two ports to be start and
            -- next two to be end, one authentic measured rail per lane.
            if #ports == 4 then
                return {ports[1], ports[3], ports[2], ports[4]}
            end
            return {}
        end
        if lanes == 1 then
            return {
                {pos = RenderPort(a), center = a, yaw = part.yaw + 180,
                    pitch = -(part.pitch or 0), lanes = 1, start = true},
                {pos = RenderPort(b), center = b, yaw = endYaw,
                    pitch = part.endPitch or 0, lanes = 1, start = false}
            }
        end
        local ports = {}
        for lane = 1, 2 do
            local offset = lane == 1 and -132 or 132
            ports[#ports + 1] = {
                pos = RenderPort(a + Right(part.yaw) * offset),
                center = a, yaw = part.yaw + 180,
                pitch = -(part.pitch or 0), lanes = 2, start = true,
            }
        end
        for lane = 1, 2 do
            local offset = lane == 1 and -132 or 132
            ports[#ports + 1] = {
                pos = RenderPort(b + Right(endYaw) * offset),
                center = b, yaw = endYaw,
                pitch = part.endPitch or 0, lanes = 2, start = false,
            }
        end
        return ports
    end
    local spec = N.Junctions[part.junction]
    if not spec then return {} end
    local ports = {}
    local ang = Angle(part.ang[1], part.ang[2], part.ang[3])
    for i, data in ipairs(spec.ports) do
        local pos = V(data)
        pos:Rotate(ang)
        local yaw = (part.yaw + (tonumber(data[4]) or 0))
        local base = V(part.pos) - Vector(0, 0, MODEL_LIFT) + pos
        ports[i] = {pos = RenderPort(base), center = base, yaw = yaw,
            lanes = part.lane == "double" and 2 or 1, start = i == 1}
    end
    return ports
end

function N.ModulePaths(part)
    if not part.junction then
        local nodes = {}
        if part.nativeModel and istable(part.nativePoints)
            and #part.nativePoints >= 2 then
            local angle = Angle(part.ang[1], part.ang[2], part.ang[3])
            local original = V(part.pos)
            local points = part.nativePoints
            if part.reverse then
                for j = #points, 1, -1 do
                    local item = points[j]
                    nodes[#nodes + 1] = original + RotateLocal(
                        Vector(item[1], item[2], item[3]), angle)
                        - RAIL_MARKER_OFFSET
                end
            else
                for _, item in ipairs(points) do
                    nodes[#nodes + 1] = original + RotateLocal(
                        Vector(item[1], item[2], item[3]), angle)
                        - RAIL_MARKER_OFFSET
                end
            end
            if part.lane == "double" then
                if not istable(part.nativeLanePoints)
                    or #part.nativeLanePoints ~= 2 then
                    return {} -- Never invent a double-track centerline.
                end
                local lanes = {{}, {}}
                local transform = function(p)
                    return original + RotateLocal(
                        Vector(p[1], p[2], p[3]), angle)
                        - RAIL_MARKER_OFFSET
                end
                for lane = 1, 2 do
                    local source = part.nativeLanePoints[lane]
                    if not istable(source) or #source < 2 then return {} end
                    if part.reverse then
                        for k = #source, 1, -1 do
                            lanes[lane][#lanes[lane] + 1] = transform(source[k])
                        end
                    else
                        for _, p in ipairs(source) do
                            lanes[lane][#lanes[lane] + 1] = transform(p)
                        end
                    end
                end
                return lanes
            end
            return {nodes}
        end
        if not part.turn or part.turn == 0 then
            local steps = math.max(1, math.ceil(part.length / 64))
            for i = 0, steps do
                nodes[#nodes + 1] = V(part.start) + Direction(part.yaw) * (part.length * i / steps)
            end
        else
            -- The original "turn1" models are eased transition track. Their
            -- measured running-rail centerlines are NOT nominal circles.
            -- Transform the exact model-local rail path. For right curves
            -- traverse its mesh in reverse instead of drawing a false arc.
            local profile = StockCurveProfile(part.model)
            if profile then
                local ang = Angle(part.ang[1], part.ang[2], part.ang[3])
                local authoredOrigin = V(part.pos) - Vector(0, 0, MODEL_LIFT)
                local points = {}
                if profile.samples then
                    for _, sample in ipairs(profile.samples) do
                        points[#points + 1] = sample
                    end
                else
                    points[1] = {x = profile.entryX or 0, y = profile.entryY or 0}
                    for i = 2, #profile.track do
                        points[#points + 1] = {x = profile.track[i],
                            y = (i - 1) * 128}
                    end
                    points[#points + 1] = {x = profile.x, y = profile.y}
                end
                if part.turn == 1 then
                    local rev = {}
                    for i = #points, 1, -1 do rev[#rev + 1] = points[i] end
                    points = rev
                end
                for _, point in ipairs(points) do
                    nodes[#nodes + 1] = authoredOrigin +
                        RotateLocal(Vector(point.x, point.y, 0), ang)
                end
            else
                local sweep = math.rad(part.sweep)
                local steps = math.max(2, math.ceil(part.radius * sweep / 64))
                for step = 0, steps do
                    local q = sweep * step / steps
                    nodes[#nodes + 1] = V(part.start)
                        + Direction(part.yaw) * (part.radius * math.sin(q))
                        + Right(part.yaw) * (part.turn *
                            part.radius * (1 - math.cos(q)))
                end
            end
        end
        if part.lane ~= "double" then return {nodes} end
        -- Original double-tunnel track centers are 264 SU apart, not one
        -- imaginary rail line along the structural center of the tunnel.
        local paths = {{}, {}}
        for i, pos in ipairs(nodes) do
            local prev = nodes[math.max(1, i-1)]
            local nextPos = nodes[math.min(#nodes, i+1)]
            local tangent = (nextPos - prev):GetNormalized()
            local right = Vector(tangent.y, -tangent.x, 0)
            for lane = 1, 2 do
                paths[lane][i] = pos + right * (lane == 1 and -132 or 132)
            end
        end
        return paths
    end
    local spec = N.Junctions[part.junction]
    if not spec then return {} end
    local ports = N.ModulePorts(part)
    local paths = {}
    for _, link in ipairs(spec.paths) do
        -- A real switch presents exactly one traversable branch at a time;
        -- crossing pairs remain independently traversable simultaneously.
        if spec.kind ~= "switch" or (link[1] == 1 and link[2] == (part.branch or 2))
            or (link[2] == 1 and link[1] == (part.branch or 2)) then
            local a, b = ports[link[1]], ports[link[2]]
            if a and b then
                local path = {a.center or a.pos}
                local ang = Angle(part.ang[1], part.ang[2], part.ang[3])
                for _, waypoint in ipairs(link.via or {}) do
                    local worldOffset = V(waypoint)
                    worldOffset:Rotate(ang)
                    path[#path + 1] = V(part.pos) - Vector(0, 0, MODEL_LIFT) + worldOffset
                end
                path[#path + 1] = b.center or b.pos
                paths[#paths + 1] = path
            end
        end
    end
    return paths
end

-- Identify the exact preview module under the crosshair. Preview props are
-- deliberately non-solid so a player/train can pass through; Source's normal
-- eye trace therefore cannot hit them. Ray-test their REAL stock model OBBs.
function N.FindAimedPreview(ply)
    if not IsValid(ply) then return nil end
    local origin = ply:GetShootPos()
    local ray = ply:GetAimVector() * 8192
    local list
    if CLIENT then
        list = ents.FindByClass("prop_dynamic_override")
    else
        local state = N.Active and N.Active[ply]
        list = state and state.preview or {}
    end
    local selected, nearest = nil, ray:LengthSqr()
    for _, ent in ipairs(list) do
        if IsValid(ent) and ent:GetNW2Bool("MEXNativePreview", false)
            and ent:GetNW2Entity("MEXNativePreviewOwner") == ply then
            local hit = util.IntersectRayWithOBB(
                origin, ray, ent:GetPos(), ent:GetAngles(),
                ent:OBBMins(), ent:OBBMaxs()
            )
            if isvector(hit) then
                local distance = origin:DistToSqr(hit)
                if distance < nearest then
                    nearest, selected = distance, ent
                end
            end
        end
    end
    return selected, nearest
end

function N.GetAimedModule(ply, traced)
    if not IsValid(ply) then return nil end
    local saved = IsValid(traced) and traced:GetNW2Bool("MEXNativeModule", false)
        and traced or nil
    local ghost, ghostDist = N.FindAimedPreview(ply)
    if not IsValid(ghost) then return saved end
    if not IsValid(saved) then return ghost end
    if ghostDist < ply:GetShootPos():DistToSqr(ply:GetEyeTrace().HitPos) then
        return ghost
    end
    return saved
end

-- A curved MDL has a huge collision hull. Hitting its MIDDLE must not
-- snap to a faraway end or to a joint that is already occupied. Only the
-- physical rail-end nodes can be used to start a new segment.
function N.PortOccupied(owner, marker)
    for _, candidate in ipairs(ents.FindByClass("mex_native_track_piece")) do
        if IsValid(candidate) and candidate ~= owner
            and candidate:GetNW2Bool("MEXNativeModule", false) then
            for i = 1, candidate:GetNW2Int("MEXNativePorts", 0) do
                local other = candidate:GetNW2Vector("MEXNativePort" .. i, vector_origin)
                if other ~= vector_origin and other:DistToSqr(marker) < 12 * 12 then
                    return true
                end
            end
        end
    end
    return false
end


-- The double MDL publishes four MEASURED endpoints: start L/R and end L/R.
-- Single rails join one lane; paired singles use both free ports at one end.
function N.PairedAnchors(ent, index)
    if not IsValid(ent) or ent:GetNW2Int("MEXNativePorts", 0) ~= 4
        or ent:GetNW2String("MEXNativeJunctionID", "") ~= "" then return nil end
    local first = index <= 2 and 1 or 3
    local pair = {}
    for i = first, first + 1 do
        local point = ent:GetNW2Vector("MEXNativePort" .. i, vector_origin)
        if point == vector_origin or N.PortOccupied(ent, point) then return nil end
        pair[#pair + 1] = {
            pos = point - RAIL_MARKER_OFFSET,
            yaw = ent:GetNW2Float("MEXNativePortYaw" .. i, 0),
            pitch = ent:GetNW2Float("MEXNativePortPitch" .. i, 0),
        }
    end
    local right = Right(pair[1].yaw)
    if pair[1].pos:Dot(right) > pair[2].pos:Dot(right) then
        pair[1], pair[2] = pair[2], pair[1]
    end
    return pair
end

function N.AdaptAnchor(node, wanted)
    if not node then return nil end
    local anchor = table.Copy(node)
    if anchor.lanes == 2 then
        if wanted == 1 then
            -- Never attach a single rail to the fictitious tunnel midpoint.
            anchor.center = anchor.pos - RAIL_MARKER_OFFSET
            anchor.lanes = 1
        else
            anchor.pair_ends = N.PairedAnchors(anchor.ent, anchor.index)
            if not anchor.pair_ends then return nil end
        end
    elseif wanted == 2 then
        return nil
    end
    return anchor
end

function N.PortFromAimedEntity(trace, tracks, eye, aimDir)
    local ent = trace and trace.Entity
    if not IsValid(ent) or not ent:GetNW2Bool("MEXNativeModule", false) then
        return nil
    end
    local wanted = tonumber(tracks) == 2 and 2 or 1
    local num = ent:GetNW2Int("MEXNativePorts", 0)
    local double = num == 4 and ent:GetNW2String("MEXNativeJunctionID", "") == ""
    if wanted == 2 and not double then return nil end
    local best, score = nil, math.huge
    for i = 1, num do
        local point = ent:GetNW2Vector("MEXNativePort" .. i, vector_origin)
        if point ~= vector_origin and not N.PortOccupied(ent, point) then
            local hitDist = isvector(trace.HitPos) and trace.HitPos:DistToSqr(point)
                or math.huge
            local miss = math.huge
            if isvector(eye) and isvector(aimDir) then
                local along = (point - eye):Dot(aimDir)
                if along > 0 and along < 8192 then
                    miss = point:DistToSqr(eye + aimDir * along)
                end
            end
            -- No "closest end of any track you clicked" behavior: on a
            -- 1664-SU turn that chooses an endpoint hundreds of units away.
            if hitDist < 90 * 90 or miss < 28 * 28 then
                local d = math.min(hitDist, miss)
                if d < score then
                    score = d
                    best = {
                        pos = point,
                        center = ent:GetNW2Vector("MEXNativePortCenter" .. i,
                            point - RAIL_MARKER_OFFSET),
                        yaw = ent:GetNW2Float("MEXNativePortYaw" .. i, 0),
                        pitch = ent:GetNW2Float("MEXNativePortPitch" .. i, 0),
                        start = ent:GetNW2Bool("MEXNativePortStart" .. i, false),
                        lanes = wanted,
                        ent = ent, index = i,
                    }
                end
            end
        end
    end
    return N.AdaptAnchor(best, wanted)
end


if CLIENT then
    local ghosts = {}
    local grey = Color(207, 207, 207, 160)
    local function DrawGhost(part, index, warn)
        local ghost = ghosts[index]
        if not IsValid(ghost) or ghost:GetModel() ~= part.model then
            if IsValid(ghost) then ghost:Remove() end
            ghost = ClientsideModel(part.model, RENDERGROUP_TRANSLUCENT)
            ghosts[index] = ghost
            if not IsValid(ghost) then return end
            ghost:SetNoDraw(true)
            ghost:SetRenderMode(RENDERMODE_TRANSCOLOR)
        end
        ghost:SetPos(V(part.pos))
        ghost:SetAngles(Angle(part.ang[1], part.ang[2], part.ang[3]))
        ghost:SetColor(warn and Color(220, 80, 80, 125) or grey)
        local start = part.start and V(part.start) or V(part.pos)
        local finish = part.finish and V(part.finish) or start
        local sample = (start + finish) * 0.5 + Vector(0, 0, 74)
        local r, g, b = render.GetColorModulation()
        render.SetLightingOrigin(sample)
        render.SetBlend(0.57)
        render.SetColorModulation(r * (warn and 1 or 0.95),
            g * (warn and 0.45 or 0.95),
            b * (warn and 0.45 or 0.95))
        -- Preview is translucent, but shares ordinary Source lighting
        -- with a committed model. No artificial fullbright illumination.
        ghost:SetupBones()
        ghost:DrawModel()
        render.SetBlend(1)
        render.SetColorModulation(r, g, b)
        render.SetLightingOrigin(vector_origin)
    end
    local nodes, nextNodesRefresh = {}, 0
    local function CollectVisibleEndpoints()
        if CurTime() < nextNodesRefresh then return nodes end
        nextNodesRefresh = CurTime() + 0.3
        local all, counts = {}, {}
        for _, ent in ipairs(ents.FindByClass("mex_native_track_piece")) do
            if IsValid(ent) and ent:GetNW2Bool("MEXNativeModule", false) then
                for j = 1, ent:GetNW2Int("MEXNativePorts", 0) do
                    local pos = ent:GetNW2Vector("MEXNativePort" .. j, vector_origin)
                    if pos ~= vector_origin then
                        local key = PortKey(pos)
                        counts[key] = (counts[key] or 0) + 1
                        local double = ent:GetNW2Int("MEXNativePorts", 0) == 4
                            and ent:GetNW2String("MEXNativeJunctionID", "") == ""
                        all[#all + 1] = {
                            pos = pos, key = key,
                            center = ent:GetNW2Vector("MEXNativePortCenter" .. j,
                                pos - RAIL_MARKER_OFFSET),
                            lanes = double and 2 or 1,
                            yaw = ent:GetNW2Float("MEXNativePortYaw" .. j, 0),
                            pitch = ent:GetNW2Float("MEXNativePortPitch" .. j, 0),
                            ent = ent, index = j,
                            start = ent:GetNW2Bool("MEXNativePortStart" .. j,
                                double and j <= 2 or (not double and j == 1))
                        }
                    end
                end
            end
        end
        nodes = {}
        -- All modules use original MDL coordinates. End caps separated by
        -- fractions of a unit (or an older saved route's tiny offset) must
        -- count as ONE joined node, not two fake "free" control points.
        -- Never hide a real open rail end unless another module is within
        -- 12 SU of the same rail center.
        for index, node in ipairs(all) do
            local joined = false
            for j, other in ipairs(all) do
                if j ~= index and node.pos:DistToSqr(other.pos) <= 12 * 12 then
                    joined = true
                    break
                end
            end
            if not joined then nodes[#nodes + 1] = node end
        end
        return nodes
    end
    -- Same free-node ray/hit selection used by the server. Snapping the
    -- preview only after LMB made a curve jump from the grass onto the rail;
    -- now its grey MDL is already aligned BEFORE the user places anything.
    local function ClientAimedFreePort(aim, eye, ray, tracks)
        local byRay, rayError = nil, 28 * 28
        local byHit, hitError = nil, 72 * 72
        local required = tonumber(tracks) == 2 and 2 or 1
        for _, node in ipairs(CollectVisibleEndpoints()) do
            if node.lanes == required or (node.lanes == 2 and required == 1) then
                local distance = aim:DistToSqr(node.pos)
                if distance < hitError then
                    byHit, hitError = node, distance
                end
                local along = (node.pos - eye):Dot(ray)
                if along >= 0 and along <= 8192 then
                    local miss = node.pos:DistToSqr(eye + ray * along)
                    if miss < rayError then
                        byRay, rayError = node, miss
                    end
                end
            end
        end
        return N.AdaptAnchor(byRay or byHit, required)
    end

    local function Tool()
        local ply = LocalPlayer()
        if not IsValid(ply) then return nil end
        local weapon = ply:GetActiveWeapon()
        if not IsValid(weapon) or weapon:GetClass() ~= "gmod_tool"
            or weapon:GetMode() ~= "mex_track_builder" then return nil end
        return weapon:GetToolObject()
    end
    hook.Add("PostDrawTranslucentRenderables", "MEXNativeTrackAlwaysGhost", function(_, skybox)
        if skybox then return end
        local tool = Tool()
        if not tool then return end
        local ply = LocalPlayer()
        local tr = ply:GetEyeTrace()
        local aim = tr.Hit and not tr.HitSky and tr.HitPos
            or (ply:GetShootPos() + ply:GetAimVector() * 800)
        local active = ply:GetNW2Bool("MEXNativeActive", false)
        local selectedName = string.lower(tool:GetClientInfo("native_model"))
        local info = N.ModelCatalog[selectedName]
        local settings = {
            native_model = selectedName,
            native_reverse = tool:GetClientNumber("native_reverse", 0),
            branch = tool:GetClientNumber("native_branch", 2),
            grade = tool:GetClientNumber("native_grade", 0),
            native_pair = tool:GetClientNumber("native_pair", 0),
            native_split = tool:GetClientNumber("native_split", 0),
            native_spacing = tool:GetClientNumber("native_spacing", 264),
            tracks = ((info and info.double) or
                tool:GetClientNumber("native_pair", 0) == 1) and 2 or 1,
            start_grade = active
                and ply:GetNW2Float("MEXNativePitch", 0) or nil,
        }
        if active and ply:GetNW2Bool("MEXNativePairActive", false) then
            settings.pair_ends = {}
            for i = 1, 2 do
                settings.pair_ends[i] = {
                    pos = ply:GetNW2Vector("MEXNativePairPos" .. i, vector_origin),
                    yaw = ply:GetNW2Float("MEXNativePairYaw" .. i, 0),
                    pitch = ply:GetNW2Float("MEXNativePairPitch" .. i, 0),
                }
            end
        end
        local anchor = nil
        if not active then
            anchor = N.PortFromAimedEntity(tr, settings.tracks,
                ply:GetShootPos(), ply:GetAimVector())
                or ClientAimedFreePort(aim, ply:GetShootPos(),
                    ply:GetAimVector(), settings.tracks)
        end
        local origin = active and ply:GetNW2Vector("MEXNativeEnd", aim)
            or (anchor and anchor.center or aim)
        local yaw = active and ply:GetNW2Float("MEXNativeYaw", 0)
            or (anchor and anchor.yaw or ply:EyeAngles().y)
        if not active and anchor then
            settings.start_grade = anchor.pitch or 0
        end
        local aimedNative = IsValid(tr.Entity)
            and tr.Entity:GetNW2Bool("MEXNativeModule", false)
        local invalidMidRail = not active and aimedNative and not anchor
        local candidate, errorText
        if invalidMidRail then
            errorText = "Aim at a FREE rail-end connector, not the middle of an existing curve."
        else
            candidate, errorText = N.Candidate(origin, yaw, aim, settings)
        end
        N.PreviewError = candidate and nil or errorText
        if candidate and #candidate.parts > 0 then
            for i, part in ipairs(candidate.parts) do
                if i <= 64 then DrawGhost(part, i, false) end
            end
            render.SetColorMaterial()
            -- Show attachment markers at the ACTUAL final rail surface and
            -- independently at both lanes of double-track original modules.
            -- Do not render green/orange spheres at the ground-level origin.
            local firstPorts = N.ModulePorts(candidate.parts[1])
            local lastPorts = N.ModulePorts(candidate.parts[#candidate.parts])
            for _, port in ipairs(firstPorts) do
                if port.start then
                    render.DrawWireframeSphere(port.pos, 9, 10, 10,
                        Color(55, 245, 120), true)
                end
            end
            for _, port in ipairs(lastPorts) do
                if port.start == false then
                    render.DrawWireframeSphere(port.pos, 9, 10, 10,
                        Color(255, 185, 70), true)
                end
            end
            -- Cyan segments visualize the surveyed REAL MDL rail centerline.
            -- This is editor-only overlay, not a generated replacement rail.
            local showPath = GetConVar("mex_native_show_measured_path")
            if showPath and showPath:GetBool() then
                for _, part in ipairs(candidate.parts) do
                    if part.nativeModel then
                        local paths = N.ModulePaths(part)
                        for _, path in ipairs(paths) do
                            for j = 2, #path do
                                render.DrawLine(RenderPort(path[j - 1]),
                                    RenderPort(path[j]),
                                    Color(35, 240, 245, 220), true)
                            end
                        end
                    end
                end
            end

        end
        render.SetColorMaterial()
        local eye, aimDir = ply:GetShootPos(), ply:GetAimVector()
        local trDistance = tr.Hit and not tr.HitSky
            and eye:Distance(tr.HitPos) or 8192
        local highlighted, nearestRayMiss = nil, 28 * 28
        local endpoints = CollectVisibleEndpoints()
        for _, node in ipairs(endpoints) do
            local distanceAlong = (node.pos - eye):Dot(aimDir)
            -- A long curved section may block the trace against its OWN
            -- collision wall before the cursor reaches the endpoint.
            -- Snap markers follow the view ray, not the earlier wall hit.
            if distanceAlong > 0 and distanceAlong < 8192 then
                local miss = node.pos:DistToSqr(eye + aimDir * distanceAlong)
                if miss < nearestRayMiss then
                    highlighted, nearestRayMiss = node, miss
                end
            end
        end
        for _, node in ipairs(endpoints) do
            if ply:GetPos():DistToSqr(node.pos) < 5000 * 5000 then
                local selected = node == highlighted
                local c = selected and Color(255, 225, 55)
                    or (node.start and Color(60, 245, 110)
                        or Color(255, 175, 65))
                render.DrawWireframeSphere(node.pos, selected and 12 or 8,
                    9, 9, c, true)
                -- The crossbar is the FULL rail gauge at the model's physical
                -- start/end face. It lets the player see a real attachment
                -- plane, instead of a floating control point in the grass.
                local across = Right(node.yaw) * (85.8 * 0.5)
                render.DrawLine(node.pos - across, node.pos + across, c, true)
            end
        end
        if active then
            render.DrawWireframeSphere(RenderPort(origin), 9, 9, 9,
                Color(60, 245, 110), true)
        end
    end)
    -- The tool shows exactly what R will delete before the key is pressed.
    -- Keep the target marked even when preview modules have no collisions.
    hook.Add("PreDrawHalos", "MEXNativeTrackAimedModuleHalo", function()
        if not Tool() then return end
        local ply = LocalPlayer()
        local tr = ply:GetEyeTrace()
        local selected = N.GetAimedModule(ply, tr and tr.Entity)
        if IsValid(selected) then
            halo.Add({selected}, Color(255, 95, 65), 2, 2, 1, true, true)
        end
    end)
    hook.Add("HUDPaint", "MEXNativeTrackHelp", function()
        if not Tool() then return end
        local ply = LocalPlayer()
        local tr = ply:GetEyeTrace()
        local selected = N.GetAimedModule(ply, tr and tr.Entity)
        local y = ScrH() * 0.78
        local help = "LMB  Start / Place   |   RMB  Save   |   R  Remove aimed   |   Shift+R  Undo last"
        draw.SimpleTextOutlined(help, "DermaDefaultBold", ScrW() * 0.5, y,
            Color(235, 235, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
            1, Color(0, 0, 0, 220))
        if IsValid(selected) then
            local ghost = selected:GetNW2Bool("MEXNativePreview", false)
            local index = ghost and selected:GetNW2Int("MEXNativePreviewIndex", 0)
                or selected:GetNW2Int("MEXNativeIndex", 0)
            local kind = ghost and "UNSAVED" or "SAVED"
            local caption = string.format("R  REMOVE THIS %s MODULE #%d ONLY", kind, index)
            draw.SimpleTextOutlined(caption, "DermaDefaultBold", ScrW() * 0.5, y + 20,
                Color(255, 140, 95), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
                1, Color(0, 0, 0, 220))
        end
    end)
    hook.Add("HUDPaint", "MEXNativeTrackPreviewWarning", function()
        if not Tool() or not N.PreviewError then return end
        draw.SimpleTextOutlined(
            "Cannot place original model: " .. N.PreviewError,
            "DermaDefaultBold", ScrW() * 0.5, ScrH() * 0.72,
            Color(255, 160, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
            1, Color(0, 0, 0, 220)
        )
    end)
    hook.Add("ShutDown", "MEXNativeGhostCleanup", function()
        for _, ghost in pairs(ghosts) do if IsValid(ghost) then ghost:Remove() end end
    end)
    function N.RequestCatalogRescan()
        net.Start("MEXNativeCatalogRescan")
        net.SendToServer()
    end
    -- Compatibility diagnostic: read the real mounted catalog, never old
    -- hardcoded curve-radius prefab tables.
    concommand.Add("mex_native_curve_assets", function()
        local names = {}
        for name, info in pairs(N.ModelCatalog or {}) do
            if info.kind == "curve" then names[#names + 1] = name end
        end
        table.sort(names)
        print("[MEX Native Track] Mounted original curved MDL models:")
        for _, name in ipairs(names) do print("  " .. name) end
        chat.AddText(Color(230, 230, 230),
            "[MEX Track Builder] " .. #names ..
            " named curve models in catalog. See console for filenames.")
    end)
    net.Receive("MEXNativeCatalogChunk", function()
        local page, pages = net.ReadUInt(16), net.ReadUInt(16)
        local items = util.JSONToTable(net.ReadString() or "{}") or {}
        if page == 1 then
            N.ModelCatalog = {}
            N.ServerNativeProfiles = {}
            N.CatalogErrors = {}
        end
        if not istable(items) then return end
        for _, item in ipairs(items) do
            if isstring(item.model) and isstring(item.kind)
                and string.StartWith(item.model, "models/") then
                N.ModelCatalog[item.model] = item
            end
        end
        if page == pages and N.RefreshCatalogUI then N.RefreshCatalogUI() end
    end)
    net.Receive("MEXNativeSingleProfile", function()
        local data = util.JSONToTable(net.ReadString() or "{}") or {}
        local model = tostring(data.model or "")
        if not string.StartWith(model, "models/") then return end
        if istable(data.profile) and istable(data.profile.points) then
            N.ServerNativeProfiles[model] = data.profile
            N.CatalogErrors[model] = nil
        else
            N.CatalogErrors[model] = tostring(data.error or "Model is not a verifiable rail segment.")
        end
    end)
    net.Receive("MEXNativeCurveProfiles", function()
        local profiles = util.JSONToTable(net.ReadString() or "") or {}
        if not istable(profiles) then return end
        local validated = {}
        for model, profile in pairs(profiles) do
            if STOCK_CURVE_PORTS[model] and istable(profile)
                and tonumber(profile.x) and tonumber(profile.y)
                and tonumber(profile.sweep) then
                validated[model] = profile
            end
        end
        N.ServerCurveProfiles = validated
    end)
    net.Receive("MEXNativeJunctionProfiles", function()
        local decoded = util.JSONToTable(net.ReadString() or "") or {}
        if istable(decoded) then N.Junctions = decoded end
    end)
    return
end

util.AddNetworkString("MEXNativeJunctionProfiles")
util.AddNetworkString("MEXNativeCurveProfiles")
util.AddNetworkString("MEXNativeCatalogChunk")
util.AddNetworkString("MEXNativeRequestProfile")
util.AddNetworkString("MEXNativeSingleProfile")
util.AddNetworkString("MEXNativeCatalogRescan")
N.Active = N.Active or {}
N.Routes = N.Routes or {}
N.Props = N.Props or {}

local FILE = "metrostroi_expanded/native_tracks_" .. game.GetMap() .. ".json"
local JUNCTION_FILE = "metrostroi_expanded/native_junctions.json"
local function SendProfiles(ply)
    net.Start("MEXNativeJunctionProfiles")
    net.WriteString(util.TableToJSON(N.Junctions) or "{}")
    if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end
local function SendCurveProfiles(ply)
    local profiles = {}
    for model in pairs(STOCK_CURVE_PORTS) do
        if ValidModel(model) then
            profiles[model] = StockCurveProfile(model)
        end
    end
    net.Start("MEXNativeCurveProfiles")
    net.WriteString(util.TableToJSON(profiles) or "{}")
    if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end
local function SendMountedCatalog(ply)
    local results = N.ModelCatalog
    if not results or not next(results) then results = N.ScanModelCatalog() end
    local list = {}
    for _, data in pairs(results or {}) do list[#list + 1] = data end
    table.sort(list, function(a,b) return a.model < b.model end)
    local pageSize = 65
    local pageCount = math.max(1, math.ceil(#list / pageSize))
    for page = 1, pageCount do
        local group = {}
        for i = (page - 1) * pageSize + 1,
                math.min(#list, page * pageSize) do
            group[#group + 1] = list[i]
        end
        net.Start("MEXNativeCatalogChunk")
        net.WriteUInt(page, 16)
        net.WriteUInt(pageCount, 16)
        net.WriteString(util.TableToJSON(group) or "[]")
        if IsValid(ply) then net.Send(ply) else net.Broadcast() end
    end
end
net.Receive("MEXNativeRequestProfile", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    if (ply.MEXNativeLastProfileRequest or 0) > CurTime() then return end
    ply.MEXNativeLastProfileRequest = CurTime() + 0.5
    local model = string.lower(net.ReadString() or "")
    -- Only original installed model paths from the catalog can be analyzed.
    if not N.ModelCatalog[model] then return end
    local info = N.ModelCatalog[model]
    local profile, err
    if info.kind == "junction" then
        err = "Original junctions need measured multi-port switch/crossing topology."
    else
        -- Reply with the exact SAME verified profile used by the server
        -- placement code; never give the client an unchecked mesh estimate.
        profile, err = GenericProfile(model)
    end
    net.Start("MEXNativeSingleProfile")
    net.WriteString(util.TableToJSON({
        model = model, profile = profile, error = err,
    }) or "{}")
    net.Send(ply)
end)
net.Receive("MEXNativeCatalogRescan", function(_, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    if (ply.MEXNativeCatalogNext or 0) > CurTime() then return end
    ply.MEXNativeCatalogNext = CurTime() + 10
    N.ModelCatalog = {}
    N.MeshProfiles = {}
    N.ScanModelCatalog()
    SendMountedCatalog(ply)
end)
concommand.Add("mex_native_rescan_models", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    N.ModelCatalog = {}
    N.MeshProfiles = {}
    local models = N.ScanModelCatalog()
    SendMountedCatalog(ply)
    print("[MEX Native Track] Discovered " .. table.Count(models) ..
        " original mounted Metrostroi / Track Pack rail model candidates.")
end)
concommand.Add("mex_native_catalog_root", function(ply, _, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local root = string.lower(tostring(args[1] or ""))
    if not string.StartWith(root, "models/") or root:find("%.%.", 1, true)
        or root:find("[%*%%]") or #root > 150 then
        print("[MEX Native Track] Usage: mex_native_catalog_root models/<your_TrackPack_folder>")
        return
    end
    local filePath = "metrostroi_expanded/native_catalog_roots.json"
    local roots = util.JSONToTable(file.Read(filePath, "DATA") or "[]") or {}
    if not table.HasValue(roots, root) then roots[#roots+1] = root end
    file.CreateDir("metrostroi_expanded")
    file.Write(filePath, util.TableToJSON(roots,true) or "[]")
    N.ModelCatalog = {}
    SendMountedCatalog(ply)
end)

local function Save()
    file.CreateDir("metrostroi_expanded")
    file.Write(FILE, util.TableToJSON({version = 2, routes = N.Routes}, true) or "{}")
end
local function ValidProfile(profile)
    if not istable(profile) or not isstring(profile.id) or not isstring(profile.model)
        or not string.StartWith(profile.model, ROOT)
        or (profile.kind ~= "switch" and profile.kind ~= "crossing")
        or not istable(profile.ports) or not istable(profile.paths) then return false end
    if #profile.ports ~= (profile.kind == "switch" and 3 or 4) then return false end
    if profile.variants then
        if profile.kind ~= "switch" or not istable(profile.variants)
            or not isstring(profile.variants["2"])
            or not isstring(profile.variants["3"]) then return false end
        if not string.StartWith(profile.variants["2"], ROOT)
            or not string.StartWith(profile.variants["3"], ROOT) then return false end
    end
    for _, port in ipairs(profile.ports) do
        if not istable(port) or #port < 4 then return false end
        for j = 1, 4 do if not tonumber(port[j]) then return false end end
    end
    for _, link in ipairs(profile.paths) do
        if not istable(link) or not profile.ports[tonumber(link[1]) or 0]
            or not profile.ports[tonumber(link[2]) or 0] then return false end
        if link.via then
            if not istable(link.via) then return false end
            for _, waypoint in ipairs(link.via) do
                if not istable(waypoint) or #waypoint < 3 then return false end
                for i = 1, 3 do if not tonumber(waypoint[i]) then return false end end
            end
        end
    end
    if profile.kind == "switch" then
        local hasMain, hasDiverge = false, false
        for _, link in ipairs(profile.paths) do
            if (link[1] == 1 and link[2] == 2) or (link[1] == 2 and link[2] == 1) then
                hasMain = true
            end
            if (link[1] == 1 and link[2] == 3) or (link[1] == 3 and link[2] == 1) then
                hasDiverge = true
            end
        end
        if not hasMain or not hasDiverge then return false end
    elseif profile.kind == "crossing" then
        -- Genuine diamond crossings must consist of exactly two independent
        -- rails: four unique outer ports, used once each, no fake junction.
        if #profile.paths ~= 2 then return false end
        local seenPorts = {}
        for _, link in ipairs(profile.paths) do
            for _, portIndex in ipairs(link) do
                if seenPorts[portIndex] or portIndex < 1 or portIndex > 4 then
                    return false
                end
                seenPorts[portIndex] = true
            end
        end
        for i = 1, 4 do if not seenPorts[i] then return false end end
    end
    return true
end

local function SyncState(ply)
    local state = N.Active[ply]
    ply:SetNW2Bool("MEXNativeActive", state ~= nil)
    ply:SetNW2Vector("MEXNativeEnd", state and state.pos or vector_origin)
    ply:SetNW2Float("MEXNativeYaw", state and state.yaw or 0)
    ply:SetNW2Float("MEXNativePitch", state and state.pitch or 0)
    local pair = state and state.pairEnds
    ply:SetNW2Bool("MEXNativePairActive", pair ~= nil)
    for i = 1, 2 do
        local node = pair and pair[i]
        ply:SetNW2Vector("MEXNativePairPos" .. i, node and node.pos or vector_origin)
        ply:SetNW2Float("MEXNativePairYaw" .. i, node and node.yaw or 0)
        ply:SetNW2Float("MEXNativePairPitch" .. i, node and node.pitch or 0)
    end
end
local function CollectPorts()
    local nodes, count = {}, {}
    for _, route in ipairs(N.Routes) do
        for partIndex, part in ipairs(route.parts or {}) do
            for portIndex, port in ipairs(N.ModulePorts(part)) do
                local entity = N.Props[route.id] and N.Props[route.id][partIndex]
                local key = PortKey(port.pos)
                count[key] = (count[key] or 0) + 1
                nodes[#nodes + 1] = {pos = port.pos, center = port.center,
                    yaw = port.yaw, pitch = port.pitch, lanes = port.lanes,
                    ent = entity, index = portIndex, key = key}
            end
        end
    end
    return nodes, count
end
-- When the crosshair hits an ORIGINAL MDL, use the exact saved rail
-- attachment metadata from that entity instead of the point on its wall,
-- sleepers or collision surface. This works at ANY distance along a curve.
-- Both server placement and client ghost rendering call the same function.

function N.FindPort(pos, distance, tracks, eye, aimDir, traceDistance)
    local best, bestDist = nil, (distance or 72)^2
    local nodes = CollectPorts()
    -- Screen-center targeting is much more intuitive than asking players
    -- to shoot the map surface exactly behind a floating connector marker.
    local rayBest, rayDist = nil, 28 * 28
    for index, node in ipairs(nodes) do
        local occupied = false
        for j, other in ipairs(nodes) do
            if j ~= index and node.pos:DistToSqr(other.pos) <= 12 * 12 then
                occupied = true
                break
            end
        end
        if not occupied
            and (not tracks or node.lanes == (tonumber(tracks) == 2 and 2 or 1)
                or (tonumber(tracks) ~= 2 and node.lanes == 2)) then
            local d = pos:DistToSqr(node.pos)
            if d < bestDist then best, bestDist = node, d end
            if isvector(eye) and isvector(aimDir) then
                local along = (node.pos - eye):Dot(aimDir)
                if along >= 0 and along <= 8192 then
                    local miss = node.pos:DistToSqr(eye + aimDir * along)
                    if miss < rayDist then rayBest, rayDist = node, miss end
                end
            end
        end
    end
    return N.AdaptAnchor(rayBest or best, tonumber(tracks) == 2 and 2 or 1)
end

local function SpawnRoute(route, ghost)
    local new = {}
    for _, part in ipairs(route.parts) do
        if not ValidModel(part.model) then
            for _, ent in ipairs(new) do if IsValid(ent) then ent:Remove() end end
            return nil, "Missing original model: " .. tostring(part.model)
        end
        local ent = ents.Create("mex_native_track_piece")
        if not IsValid(ent) then
            for _, prev in ipairs(new) do if IsValid(prev) then prev:Remove() end end
            return nil, "Failed to create original model prop."
        end
        ent:SetModel(part.model)
        ent.MEXNativePart = part
        ent:SetPos(V(part.pos))
        ent:SetAngles(Angle(part.ang[1], part.ang[2], part.ang[3]))
        ent:Spawn()
        ent:Activate()
        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then
            ent:Remove()
            for _, prev in ipairs(new) do if IsValid(prev) then prev:Remove() end end
            return nil, "Original MDL has no usable .phy and its rails could not be reconstructed: " .. part.model
        end
        phys:EnableMotion(false)
        phys:Sleep()
        ent:SetNW2Bool("MEXNativeModule", true)
        local lowerModel = string.lower(part.model)
        local enclosedModel = lowerModel:find("tunnel", 1, true) ~= nil
            or lowerModel:find("station", 1, true) ~= nil
            or lowerModel:find("arch", 1, true) ~= nil
        -- Separate/above-ground rails should never be mistaken for a
        -- tunnel roof, even if their model is in a non-Metrostroi folder.
        ent:SetNW2Bool("MEXNativeSurface", not enclosedModel)
        -- Real ambient-light sampling point: halfway along the AUTHORED
        -- rail centerline, safely above the map ground, never inside grass.
        local railPaths = N.ModulePaths(part)
        local railPath = railPaths and railPaths[1]
        local lightBase
        if railPath and #railPath >= 2 then
            lightBase = railPath[math.ceil(#railPath * 0.5)]
        else
            lightBase = part.start and V(part.start) or ent:GetPos()
        end
        ent:SetNW2Vector("MEXNativeLightProbe",
            lightBase + Vector(0, 0, 74))
        ent:SetNW2Int("MEXNativeRoute", route.id or 0)
        ent:SetNW2Int("MEXNativeIndex", #new + 1)
    local ports = N.ModulePorts(part)
        local portCount = #ports
        for portIndex = 1, math.min(portCount, 4) do
            local port = ports[portIndex]
            ent:SetNW2Vector("MEXNativePort" .. portIndex, port.pos)
            ent:SetNW2Vector("MEXNativePortCenter" .. portIndex,
                port.center or (port.pos - RAIL_MARKER_OFFSET))
            ent:SetNW2Float("MEXNativePortYaw" .. portIndex, port.yaw or 0)
            ent:SetNW2Float("MEXNativePortPitch" .. portIndex,
                port.pitch or 0)
            ent:SetNW2Bool("MEXNativePortStart" .. portIndex, port.start == true)
        end
        ent:SetNW2Int("MEXNativePorts", portCount)
        if part.junction then
            ent:SetNW2String("MEXNativeJunctionID", part.junction)
            ent:SetNW2Int("MEXNativeBranch", part.branch or 2)
        end
        ent:DrawShadow(true)
        new[#new + 1] = ent
    end
    return new
end
-- Reject an ordinary rail-line intersection. The only way to build a
-- valid at-grade diamond or turnout is a registered original junction MDL.
-- An end-to-end join is allowed; grade-separated routes are independent.
local function SegmentsCross(a, b, c, d, aStart, aEnd, cStart, cEnd)
    local ab, cd = b - a, d - c
    local cross = ab.x * cd.y - ab.y * cd.x
    if math.abs(cross) < 0.0001 then return false end
    local between = c - a
    local t = (between.x * cd.y - between.y * cd.x) / cross
    local u = (between.x * ab.y - between.y * ab.x) / cross
    if t <= 0.001 or t >= 0.999 or u <= 0.001 or u >= 0.999 then
        -- A true crossing at a sampled spline node can land at t=0 or u=0.
        -- The actual route endpoint check below distinguishes those cases.
        if t < -0.001 or t > 1.001 or u < -0.001 or u > 1.001 then return false end
    end
    if t < -0.001 or t > 1.001 or u < -0.001 or u > 1.001 then return false end
    local p = a + ab * t
    local q = c + cd * u
    if math.abs(p.z - q.z) > 48 then return false end
    local atAEnd = math.min(p:DistToSqr(aStart), p:DistToSqr(aEnd)) < 16
    local atCEnd = math.min(q:DistToSqr(cStart), q:DistToSqr(cEnd)) < 16
    return not (atAEnd and atCEnd)
end
local function PathBounds(path)
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(path) do
        minX, minY = math.min(minX, p.x), math.min(minY, p.y)
        maxX, maxY = math.max(maxX, p.x), math.max(maxY, p.y)
    end
    return minX, minY, maxX, maxY
end
local function CheckNativeCrossings(parts, ignoreRouteID)
    local all = {}
    for _, part in ipairs(parts) do
        for _, path in ipairs(N.ModulePaths(part)) do
            if #path > 1 then all[#all + 1] = {path = path, part = part} end
        end
    end
    for routeID, route in ipairs(N.Routes) do
        if routeID ~= ignoreRouteID then
            for _, part in ipairs(route.parts or {}) do
                for _, existing in ipairs(N.ModulePaths(part)) do
                    if #existing > 1 then
                        local cx, cy, dx, dy = PathBounds(existing)
                        for _, entry in ipairs(all) do
                            local proposed = entry.path
                            local ax, ay, bx, by = PathBounds(proposed)
                            if ax <= dx + 1 and bx + 1 >= cx
                                and ay <= dy + 1 and by + 1 >= cy then
                                for i = 1, #proposed - 1 do
                                    local a, b = proposed[i], proposed[i + 1]
                                    for j = 1, #existing - 1 do
                                        local c, d = existing[j], existing[j + 1]
                                        if SegmentsCross(a, b, c, d,
                                            proposed[1], proposed[#proposed],
                                            existing[1], existing[#existing]) then
                                            return false, "At-grade intersection with another route. Insert a calibrated original crossing or turnout model instead."
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return true
end

local function RemoveProps(id)
    local props = N.Props[id] or {}
    for _, ent in ipairs(props) do if IsValid(ent) then ent:Remove() end end
    N.Props[id] = nil
end
local function ClearPreview(state)
    for _, ent in ipairs(state and state.preview or {}) do
        if IsValid(ent) then ent:Remove() end
    end
    if state then state.preview = {} end
end
local function RefreshPreview(state)
    ClearPreview(state)
    if not state then return end
    for _, part in ipairs(state.parts or {}) do
        local ent = ents.Create("prop_dynamic_override")
        if IsValid(ent) then
            ent:SetModel(part.model)
            ent:SetPos(V(part.pos))
            ent:SetAngles(Angle(part.ang[1], part.ang[2], part.ang[3]))
            ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
            ent:SetColor(Color(205, 205, 205, 170))
            ent:SetSolid(SOLID_NONE)
            ent:Spawn()
            ent:SetNotSolid(true)
            ent:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
            ent:DrawShadow(false)
            ent:SetNW2Bool("MEXNativePreview", true)
            ent:SetNW2Entity("MEXNativePreviewOwner", state.owner)
            ent:SetNW2Int("MEXNativePreviewIndex", #state.preview + 1)
            state.preview[#state.preview + 1] = ent
        end
    end
end
local function Notify(ply, message)
    print("[MEX Native Track] " .. message)
    if IsValid(ply) then ply:ChatPrint("[MEX Native Track] " .. message) end
end
function N.Add(ply, aim, settings)
    if not IsValid(ply) or not ply:IsAdmin() or not isvector(aim) then return false end
    settings = settings or {}
    local selected = string.lower(string.Trim(tostring(settings.native_model or "")))
    if selected == "" then
        Notify(ply, "Open Model Catalog and choose an installed Metrostroi or Track Pack MDL.")
        return false
    end
    if not N.ModelCatalog[selected] then
        Notify(ply, "Selected model is not mounted. Rescan your original model catalog.")
        return false
    end
    settings.tracks = (N.ModelCatalog[selected].double
        or tonumber(settings.native_pair) == 1) and 2 or 1
    local state = N.Active[ply]
    if not state then
        local tr = ply:GetEyeTrace()
        local rayLength = tr and tr.Hit and not tr.HitSky
            and ply:GetShootPos():Distance(tr.HitPos) or nil
        local connector = N.PortFromAimedEntity(tr, settings.tracks,
            ply:GetShootPos(), ply:GetAimVector())
            or N.FindPort(aim, 72, settings.tracks,
                ply:GetShootPos(), ply:GetAimVector(), rayLength)
        if IsValid(tr.Entity)
            and tr.Entity:GetNW2Bool("MEXNativeModule", false)
            and not connector then
            Notify(ply, "Select a free original rail-end node. The middle of a curved MDL is not a track connection.")
            return false
        end
        local yaw = connector and connector.yaw or ply:EyeAngles().y
        local pos = connector and (connector.center or connector.pos) or aim
        local pairEnds = tonumber(settings.native_pair) == 1
            and connector and connector.pair_ends or nil
        if pairEnds then
            pos = (pairEnds[1].pos + pairEnds[2].pos) * 0.5
        end
        local grade = connector and (connector.pitch or 0)
            or math.Clamp(tonumber(settings.grade) or 0, -20, 20)
        N.Active[ply] = {owner = ply, start = pos, startYaw = yaw,
            startPitch = grade, pos = pos, yaw = yaw, pitch = grade,
            parts = {}, preview = {}, pairEnds = pairEnds}
        SyncState(ply)
        Notify(ply, connector and "Connected to an original model endpoint." or "Start node set. Aim ahead to preview an original model.")
        return true
    end
    settings.start_grade = state.pitch or 0
    settings.pair_ends = state.pairEnds
    local candidate, err = N.Candidate(state.pos, state.yaw, aim, settings)
    if not candidate then Notify(ply, err); return false end
    for _, part in ipairs(candidate.parts) do state.parts[#state.parts + 1] = part end
    state.pos, state.yaw = candidate.pos, candidate.yaw
    state.pitch = candidate.pitch or state.pitch or 0
    state.pairEnds = candidate.pairEnds
    RefreshPreview(state)
    SyncState(ply)
    return true
end
function N.Finish(ply)
    local state = N.Active[ply]
    if not state or #state.parts == 0 then
        Notify(ply, "Add at least one original model first.")
        return false
    end
    local id = state.reopenID or (#N.Routes + 1)
    local route = {id = id, parts = table.Copy(state.parts)}
    local valid, why = CheckNativeCrossings(route.parts, state.reopenID)
    if not valid then
        Notify(ply, why)
        return false
    end
    -- Build successfully before deleting or replacing any saved route.
    local entities, err = SpawnRoute(route)
    if not entities then Notify(ply, err); return false end
    ClearPreview(state)
    RemoveProps(id)
    N.Routes[id] = route
    N.Props[id] = entities
    N.Active[ply] = nil
    SyncState(ply)
    Save()
    if MEXTrackBuilder and MEXTrackBuilder.RebuildMetrostroiNetwork then
        MEXTrackBuilder.RebuildMetrostroiNetwork(ply)
    end
    Notify(ply, string.format("Route #%d saved (%d original model modules).", id, #entities))
    return true
end
-- Recompute only the construction cursor. Removing a middle module must not
-- remove the modules after it, so a temporary route may contain a gap.
local function UpdateConstructionEndpoint(state)
    local last = state.parts[#state.parts]
    local previous = state.parts[#state.parts - 1]
    state.pairEnds = nil
    if last and previous and last.pairLane == 2 and previous.pairLane == 1 then
        local firstPort = N.ModulePorts(previous)[2]
        local secondPort = N.ModulePorts(last)[2]
        if firstPort and secondPort then
            state.pairEnds = {
                {pos = firstPort.center, yaw = firstPort.yaw, pitch = firstPort.pitch},
                {pos = secondPort.center, yaw = secondPort.yaw, pitch = secondPort.pitch},
            }
        end
    end
    if last then
        local ports = N.ModulePorts(last)
        local endpoint = last.junction and ports[last.branch or 2]
            or ports[last.lane == "double" and 3 or 2]
        state.pos = endpoint and (endpoint.center or endpoint.pos) or state.start
        if state.pairEnds then
            state.pos = (state.pairEnds[1].pos + state.pairEnds[2].pos) * 0.5
        end
        state.yaw = last.junction and endpoint and endpoint.yaw
            or last.endYaw or (last.yaw - (last.turn or 0) * (last.sweep or 0))
        state.pitch = last.endPitch or 0
    else
        state.pos, state.yaw = state.start, state.startYaw
        state.pitch = state.startPitch or 0
    end
end

-- Explicit Shift+R / panel Undo: only the last pending construction step.
-- An idle reload must NEVER quietly start editing or delete a saved route.
function N.Undo(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    local state = N.Active[ply]
    if not state or #state.parts == 0 then
        Notify(ply, "Nothing to undo. LMB starts construction; R deletes the aimed saved module.")
        return false
    end
    local last = table.remove(state.parts)
    if last and last.pairLane == 2 then
        local previous = state.parts[#state.parts]
        if previous and previous.pairLane == 1 then table.remove(state.parts) end
    end
    UpdateConstructionEndpoint(state)
    RefreshPreview(state)
    SyncState(ply)
    Notify(ply, "Undid the last pending module. All earlier modules are preserved.")
    return true
end
function N.Cancel(ply)
    local state = N.Active[ply]
    if not state then return false end
    -- A reopened saved route is intentionally left intact on cancel.
    ClearPreview(state)
    N.Active[ply] = nil
    SyncState(ply)
    Notify(ply, "Construction cancelled.")
    return true
end
function N.DeleteRoute(ply, ent)
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if not IsValid(ent) or not ent:GetNW2Bool("MEXNativeModule", false) then
        Notify(ply, "Aim at a saved original Metrostroi module.")
        return false
    end
    local id = ent:GetNW2Int("MEXNativeRoute", 0)
    if not N.Routes[id] then return false end
    local active = N.Active[ply]
    if active and active.reopenID == id then N.Cancel(ply) end
    RemoveProps(id)
    table.remove(N.Routes, id)
    local previousProps = N.Props
    N.Props = {}
    for routeID, route in ipairs(N.Routes) do
        route.id = routeID
        local oldID = routeID >= id and routeID + 1 or routeID
        N.Props[routeID] = previousProps[oldID] or {}
        for _, prop in ipairs(N.Props[routeID]) do
            if IsValid(prop) then prop:SetNW2Int("MEXNativeRoute", routeID) end
        end
    end
    Save()
    if MEXTrackBuilder and MEXTrackBuilder.RebuildMetrostroiNetwork then
        MEXTrackBuilder.RebuildMetrostroiNetwork(ply)
    end
    Notify(ply, "Original-model route deleted.")
    return true
end
-- R always removes EXACTLY ONE module, independently of its route position.
-- The remaining route is retained even if removal creates two disconnected
-- stretches. Free endpoints are automatically recomputed from their geometry.
function N.RemoveAimedModule(ply, traced)
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    local target = N.GetAimedModule(ply, traced)
    if not IsValid(target) then
        Notify(ply, "Point at an original track module and press R. Shift+R undoes the last pending module.")
        return false
    end

    if target:GetNW2Bool("MEXNativePreview", false) then
        local state = N.Active[ply]
        if not state then return false end
        local index = target:GetNW2Int("MEXNativePreviewIndex", 0)
        if state.preview[index] ~= target or not state.parts[index] then
            Notify(ply, "Selected construction module has changed. Aim again.")
            return false
        end
        table.remove(state.parts, index)
        UpdateConstructionEndpoint(state)
        RefreshPreview(state)
        SyncState(ply)
        Notify(ply, string.format("Removed pending module #%d. %d pending modules remain.",
            index, #state.parts))
        return true
    end

    if not target:GetNW2Bool("MEXNativeModule", false) then return false end
    local routeID = target:GetNW2Int("MEXNativeRoute", 0)
    local moduleIndex = target:GetNW2Int("MEXNativeIndex", 0)
    local route, props = N.Routes[routeID], N.Props[routeID]
    if not route or not props or props[moduleIndex] ~= target
        or not route.parts[moduleIndex] then
        Notify(ply, "Selected module is no longer part of a saved route.")
        return false
    end
    -- Do not silently overwrite deletion with a subsequently finished edit.
    local pending = N.Active[ply]
    if pending and pending.reopenID == routeID then N.Cancel(ply) end

    if #route.parts == 1 then
        return N.DeleteRoute(ply, target)
    end
    table.remove(route.parts, moduleIndex)
    table.remove(props, moduleIndex)
    target:Remove()
    for index = moduleIndex, #props do
        local ent = props[index]
        if IsValid(ent) then ent:SetNW2Int("MEXNativeIndex", index) end
    end

    Save()
    if MEXTrackBuilder and MEXTrackBuilder.RebuildMetrostroiNetwork then
        MEXTrackBuilder.RebuildMetrostroiNetwork(ply)
    end
    Notify(ply, string.format(
        "Removed only module #%d from route #%d. Remaining %d modules were kept.",
        moduleIndex, routeID, #route.parts))
    return true
end

function N.GetNetworkPaths()
    local edges = {}
    for _, route in ipairs(N.Routes) do
        for _, part in ipairs(route.parts or {}) do
            for _, points in ipairs(N.ModulePaths(part)) do
                if #points >= 2 then edges[#edges + 1] = points end
            end
        end
    end
    -- Join shared endpoint nodes into continuous paths. The Metrostroi rail
    -- loader expects a connected list, not one isolated path per prefab.
    local paths = {}
    local used = {}
    local function Attach(path, edge, prepend, reverse)
        local ordered = {}
        for i = 1, #edge do
            ordered[i] = reverse and edge[#edge - i + 1] or edge[i]
        end
        if prepend then
            local combined = {}
            for i = 1, #ordered - 1 do combined[#combined + 1] = ordered[i] end
            for _, point in ipairs(path) do combined[#combined + 1] = point end
            return combined
        end
        for i = 2, #ordered do path[#path + 1] = ordered[i] end
        return path
    end
    for i, edge in ipairs(edges) do
        if not used[i] then
            used[i] = true
            local path = table.Copy(edge)
            local changed = true
            while changed do
                changed = false
                for j, other in ipairs(edges) do
                    if not used[j] then
                        local head, tail = path[1], path[#path]
                        local first, last = other[1], other[#other]
                        if tail:DistToSqr(first) < 1 then
                            path = Attach(path, other, false, false)
                        elseif tail:DistToSqr(last) < 1 then
                            path = Attach(path, other, false, true)
                        elseif head:DistToSqr(last) < 1 then
                            path = Attach(path, other, true, false)
                        elseif head:DistToSqr(first) < 1 then
                            path = Attach(path, other, true, true)
                        else
                            continue
                        end
                        used[j], changed = true, true
                    end
                end
            end
            local output = {}
            for _, point in ipairs(path) do output[#output + 1] = point + Vector(0, 0, 10) end
            paths[#paths + 1] = output
        end
    end
    return paths
end
-- Convert pre-calibration routes using their original saved start/direction.
-- Old "turn1" ends were guessed from perfect circles; the genuine models
-- have *eased* rail geometry with different pivots and terminal headings.
-- Carry joined successors to the corrected output connector so old saved
-- routes no longer retain invisible 100+ SU gaps after an addon update.
local function RecalibrateRoute(route)
    if not istable(route.parts) then return false end
    local changed, oldEnd, newEnd, newYaw = false, nil, nil, nil
    for index, part in ipairs(route.parts) do
        local previousEnd = part.finish and V(part.finish)
            or (not part.junction and V(part.start) +
                Direction(part.yaw) * (part.length or 0))
        -- Saved part.start is encoded as {x,y,z}, not a GMod Vector.
        local originallyJoined = oldEnd and istable(part.start)
            and oldEnd:DistToSqr(V(part.start)) < 16 * 16
        local start = originallyJoined and newEnd or V(part.start)
        local yaw = originallyJoined and newYaw or part.yaw
        local profile = StockCurveProfile(part.model)
        if not part.nativeModel and profile
            and (part.turn == 1 or part.turn == -1) then
            local calibrated, finish, finalYaw
            if part.lane ~= "double" and N.ModelCatalog[part.model] then
                calibrated, finish, finalYaw = GenericOriginalPart(
                    start, yaw, part.model, {
                        mode = part.turn == 1 and "curve_right" or "curve_left"
                    })
            end
            if not calibrated then
                calibrated, finish, finalYaw =
                    StockCurveWorldPart(start, yaw, part.model, part.turn,
                        part.radius or 4096, part.lane or "single")
            end
            if calibrated then
                -- Keep the old route's model and layout choices; only realign
                -- its model pose / graph / rail nodes to the actual MDL.
                route.parts[index] = calibrated
                part = calibrated
                newEnd, newYaw = finish, finalYaw
                changed = true
            end
        elseif part.nativeModel then
            -- Existing route pieces were previously allowed to acquire an
            -- invented curve from noisy original-MDL mesh samples. Only a
            -- manual realign request should reposition their visual models.
            -- Rebuild from the now-validated TRUE entry/exit railheads and
            -- carry every previously joined successor to the corrected end.
            local fresh, reason = GenericProfile(part.model)
            if fresh then
                local rebuilt, finish, finalYaw = GenericOriginalPart(
                    start, yaw, part.model, {
                        native_reverse = part.reverse and 1 or 0,
                        start_grade = part.pitch or 0,
                    })
                if rebuilt then
                    route.parts[index] = rebuilt
                    part = rebuilt
                    newEnd, newYaw = finish, finalYaw
                    changed = true
                end
            else
                -- Never convert an uncertain straight rail into a fake arc.
                -- Leave its original pose untouched and report the failure
                -- when the manual repair command inspects this route.
                newEnd = part.finish and V(part.finish) or previousEnd
                newYaw = part.endYaw or part.yaw
                print("[MEX Native Track] Realign skipped " ..
                    tostring(part.model) .. ": " .. tostring(reason))
            end
        elseif not part.junction and (part.turn or 0) == 0 then
            if originallyJoined then
                local recalibrated = Placement(start, yaw,
                    part.model, part.length, part.lane or "single")
                route.parts[index] = recalibrated
                part = recalibrated
                changed = true
            end
            newEnd = V(part.start) + Direction(part.yaw) * part.length
            newYaw = part.yaw
        else
            local output = N.ModulePorts(part)
            local endPort = output[part.branch or 2]
            newEnd = endPort and (endPort.center or endPort.pos)
                or previousEnd
            newYaw = endPort and endPort.yaw or part.yaw
        end
        oldEnd = previousEnd
    end
    return changed
end

-- A manual one-shot repair for worlds loaded before the update (for
-- example GMod Lua auto-refresh without a full map restart).
-- Explicit repair (with backup) for old routes laid using a noisy
-- straight-rail scan. Existing saved geometry stays unchanged until invoked.
concommand.Add("mex_native_realign_routes", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local raw = file.Read(FILE, "DATA") or "{}"
    -- Keep a distinct backup for every manual repair. A single old backup
    -- filename could silently point to an outdated version of the map.
    local stamp = os.date("%Y%m%d_%H%M%S")
    local backup = string.gsub(FILE, "%.json$",
        "_before_manual_realign_" .. stamp .. ".json")
    local suffix = 1
    while file.Exists(backup, "DATA") do
        backup = string.gsub(FILE, "%.json$",
            "_before_manual_realign_" .. stamp .. "_" .. suffix .. ".json")
        suffix = suffix + 1
    end
    file.Write(backup, raw)
    print("[MEX Native Track] Backup saved: data/" .. backup)
    local count = 0
    for id, current in ipairs(N.Routes) do
        local candidate = table.Copy(current)
        if RecalibrateRoute(candidate) then
            candidate.id = id
            local props, err = SpawnRoute(candidate)
            if props then
                RemoveProps(id)
                N.Routes[id], N.Props[id] = candidate, props
                count = count + 1
            else
                print("[MEX Native Track] Route #" .. id ..
                    " calibration rejected: " .. tostring(err))
            end
        end
    end
    if count > 0 then
        Save()
        if MEXTrackBuilder and MEXTrackBuilder.RebuildMetrostroiNetwork then
            MEXTrackBuilder.RebuildMetrostroiNetwork(ply)
        end
    end
    print("[MEX Native Track] Realigned " .. count ..
        " saved routes using validated original-MDL straight/curve endpoints.")
    if IsValid(ply) then
        ply:ChatPrint("[MEX Native Track] Realigned " .. count ..
            " routes; original save backup retained.")
    end
end)

hook.Add("InitPostEntity", "MEXNativeTrackRestore", function()
    file.CreateDir("metrostroi_expanded")
    -- Native Track Pack models must be known BEFORE old routes are restored;
    -- otherwise ValidModel would reject saved MDLs outside stock folders.
    if not next(N.ModelCatalog or {}) then N.ScanModelCatalog() end
    local profiles = util.JSONToTable(file.Read(JUNCTION_FILE, "DATA") or "{}") or {}
    for _, profile in pairs(profiles) do
        if ValidProfile(profile) then N.Junctions[profile.id] = profile end
    end
    local raw = file.Read(FILE, "DATA") or "{}"
    local decoded = util.JSONToTable(raw) or {}
    local upgrade = (tonumber(decoded.version) or 1) < 2
    if not upgrade then
        for _, route in ipairs(decoded.routes or {}) do
            for _, part in ipairs(route.parts or {}) do
                if StockCurveProfile(part.model) and not part.calibrated then
                    upgrade = true
                    break
                end
            end
            if upgrade then break end
        end
    end
    if upgrade and istable(decoded.routes) and #decoded.routes > 0 then
        local backup = string.gsub(FILE, "%.json$", "_before_native_ports_v2.json")
        if not file.Exists(backup, "DATA") then file.Write(backup, raw) end
        for _, saved in ipairs(decoded.routes) do
            if istable(saved) then RecalibrateRoute(saved) end
        end
    end
    N.Routes = {}
    for _, route in ipairs(decoded.routes or {}) do
        if istable(route) and istable(route.parts) and #route.parts > 0 then
            local id = #N.Routes + 1
            route.id = id
            -- Upgrade previous saves that used nominal-circle endpoint nodes.
            -- The original placed models do not move; the real rail mesh
            -- determines where next pieces may attach from now on.
            for _, part in ipairs(route.parts) do
                N.RecalibrateCurvePart(part)
            end
            N.Routes[id] = route
            local props, err = SpawnRoute(route)
            N.Props[id] = props or {}
            if not props then
                ErrorNoHalt("[MEX Native Track] Route " .. id .. ": " .. tostring(err) .. "\\n")
            end
        end
    end
    if upgrade and #N.Routes > 0 then
        Save()
        print("[MEX Native Track] Migrated original curves to real model-local rail connectors. A backup was saved.")
    end
    if #N.Routes > 0 then Save() end
    timer.Simple(2.5, function()
        if #N.Routes > 0 and MEXTrackBuilder and MEXTrackBuilder.RebuildMetrostroiNetwork then
            MEXTrackBuilder.RebuildMetrostroiNetwork()
        end
    end)
end)
hook.Add("PostCleanupMap", "MEXNativeTrackRespawnAfterCleanup", function()
    timer.Simple(0.4, function()
        for id, route in ipairs(N.Routes) do
            RemoveProps(id)
            local props, err = SpawnRoute(route)
            N.Props[id] = props or {}
            if not props then ErrorNoHalt("[MEX Native Track] Cleanup restore failed: " ..
                tostring(err) .. "\\n") end
        end
    end)
end)
-- Update models already spawned before a Lua auto-refresh without moving,
-- respawning or deleting any track. All changes affect rendering only.
local function RefreshNativeLighting()
    local refreshed = 0
    for id, props in pairs(N.Props or {}) do
        local route = N.Routes[id]
        for index, ent in ipairs(props) do
            if IsValid(ent) then
                ent:DrawShadow(true)
                local part = route and route.parts[index]
                if part then
                    local paths = N.ModulePaths(part)
                    local points = paths and paths[1]
                    local point = points and points[math.ceil(#points * 0.5)]
                        or (part.start and V(part.start) or ent:GetPos())
                    ent:SetNW2Vector("MEXNativeLightProbe",
                        point + Vector(0, 0, 74))
                    local lowerModel = string.lower(part.model or "")
                    ent:SetNW2Bool("MEXNativeSurface",
                        not lowerModel:find("tunnel", 1, true)
                        and not lowerModel:find("station", 1, true)
                        and not lowerModel:find("arch", 1, true))
                end
                refreshed = refreshed + 1
            end
        end
    end
    return refreshed
end
hook.Add("OnReloaded", "MEXNativeTrackRestoreLightingOnReload", function()
    timer.Simple(0, RefreshNativeLighting)
end)
concommand.Add("mex_native_refresh_lighting", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local amount = RefreshNativeLighting()
    print("[MEX Native Track] Restored normal model lighting and engine shadows for " ..
        amount .. " existing original MDL track modules.")
    if IsValid(ply) then
        ply:ChatPrint("[MEX Native Track] Restored lighting/shadows for " ..
            amount .. " original track modules.")
    end
end)

hook.Add("PlayerDisconnected", "MEXNativeTrackLeave", function(ply)
    local state = N.Active[ply]
    ClearPreview(state)
    N.Active[ply] = nil
end)
hook.Add("PhysgunPickup", "MEXNativeFixedPhysics", function(_, ent)
    if IsValid(ent) and ent:GetNW2Bool("MEXNativeModule", false) then return false end
end)
hook.Add("CanTool", "MEXNativeProtectModules", function(_, trace, mode)
    local ent = trace and trace.Entity
    if IsValid(ent) and ent:GetNW2Bool("MEXNativeModule", false)
        and mode ~= "mex_track_builder" then return false end
end)
hook.Add("PlayerInitialSpawn", "MEXNativeTrackSendProfiles", function(ply)
    timer.Simple(3, function()
        if IsValid(ply) then
            SendProfiles(ply)
            SendCurveProfiles(ply)
            SendMountedCatalog(ply)
        end
    end)
end)
function N.ToggleSwitch(ply, ent)
    if not IsValid(ent) or not ent:GetNW2Bool("MEXNativeModule", false) then return end
    local junctionID = ent:GetNW2String("MEXNativeJunctionID", "")
    local profile = N.Junctions[junctionID]
    if not profile or profile.kind ~= "switch" then return false end
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    if (ply.MEXNativeSwitchNext or 0) > CurTime() then return false end
    ply.MEXNativeSwitchNext = CurTime() + 1.0
    local route = N.Routes[ent:GetNW2Int("MEXNativeRoute", 0)]
    local part = route and route.parts[ent:GetNW2Int("MEXNativeIndex", 0)]
    if not part then return false end
    if not profile.variants then
        Notify(ply, "Switch cannot move: calibrated main/diverging original MDL + .phy variants are not registered.")
        return false
    end
    -- Never move physical switch rails under any train or bogey.
    local boundsMin, boundsMax = ent:WorldSpaceAABB()
    local clearance = Vector(180, 180, 180)
    for _, nearby in ipairs(ents.FindInBox(boundsMin - clearance, boundsMax + clearance)) do
        if IsValid(nearby) and nearby ~= ent
            and (string.StartWith(nearby:GetClass(), "gmod_subway_")
                or nearby:GetClass() == "gmod_train_bogey") then
            Notify(ply, "Turnout occupied by a train; switching blocked.")
            return false
        end
    end
    local nextBranch = part.branch == 2 and 3 or 2
    local model = profile.variants[tostring(nextBranch)]
    if not ValidModel(model) then
        Notify(ply, "The alternative original switch model is missing.")
        return false
    end
    -- Source compiles collision into the MDL/PHY. Rebuilding physics after
    -- switching models makes rails and collision select the same variant.
    local prior = part.model
    ent:SetModel(model)
    local built = ent:PhysicsInitStatic(SOLID_VPHYSICS)
    local phys = ent:GetPhysicsObject()
    if not built or not IsValid(phys) then
        ent:SetModel(prior)
        ent:PhysicsInitStatic(SOLID_VPHYSICS)
        local oldPhys = ent:GetPhysicsObject()
        if IsValid(oldPhys) then oldPhys:EnableMotion(false) end
        Notify(ply, "Alternative original switch .phy is missing. State unchanged.")
        return false
    end
    phys:EnableMotion(false)
    phys:Sleep()
    part.model, part.branch = model, nextBranch
    ent:SetNW2Int("MEXNativeBranch", nextBranch)
    Save()
    if MEXTrackBuilder and MEXTrackBuilder.RebuildMetrostroiNetwork then
        MEXTrackBuilder.RebuildMetrostroiNetwork(ply)
    end
    Notify(ply, "Turnout switched to port " .. nextBranch .. ".")
    return false
end
concommand.Add("mex_native_remove_aimed", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    N.RemoveAimedModule(ply, tr and tr.Entity)
end)
concommand.Add("mex_native_delete_aimed", function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    N.DeleteRoute(ply, tr and tr.Entity)
end)
concommand.Add("mex_native_finish", function(ply) if IsValid(ply) then N.Finish(ply) end end)
concommand.Add("mex_native_undo", function(ply) if IsValid(ply) then N.Undo(ply) end end)
concommand.Add("mex_native_cancel", function(ply) if IsValid(ply) then N.Cancel(ply) end end)
concommand.Add("mex_native_register_junction", function(ply, _, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local id, kind, model, portString, pathString = unpack(args)
    if not id or not id:match("^[%w_-]+$") or (kind ~= "switch" and kind ~= "crossing") then
        Notify(ply, "Usage: mex_native_register_junction <id> <switch|crossing> <model> <x,y,z,yaw;x,y,z,yaw;...> <1-2;1-3;...>")
        return
    end
    local profile = {id = id, kind = kind, model = model, ports = {}, paths = {}}
    for group in string.gmatch(portString or "", "[^;]+") do
        local entries = {}
        for item in string.gmatch(group, "[^,]+") do entries[#entries + 1] = tonumber(item) end
        profile.ports[#profile.ports + 1] = entries
    end
    for group in string.gmatch(pathString or "", "[^;]+") do
        local a, b = group:match("^(%d+)%-(%d+)$")
        profile.paths[#profile.paths + 1] = {tonumber(a), tonumber(b)}
    end
    if not ValidProfile(profile) or not ValidModel(model) then
        Notify(ply, "Invalid junction profile or missing original model.")
        return
    end
    N.Junctions[id] = profile
    file.CreateDir("metrostroi_expanded")
    file.Write(JUNCTION_FILE, util.TableToJSON(N.Junctions, true))
    SendProfiles()
    Notify(ply, "Original junction model and connector topology saved.")
end)
concommand.Add("mex_native_set_junction_path", function(ply, _, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local id, a, b, waypointString = unpack(args)
    local profile = id and N.Junctions[id]
    local first, last = tonumber(a), tonumber(b)
    if not profile or not first or not last then
        Notify(ply, "Usage: mex_native_set_junction_path <registered_id> <port_a> <port_b> <x,y,z;x,y,z;...>")
        return
    end
    for _, link in ipairs(profile.paths) do
        if (link[1] == first and link[2] == last)
            or (link[1] == last and link[2] == first) then
            local via = {}
            for chunk in string.gmatch(waypointString or "", "[^;]+") do
                local values = {}
                for number in string.gmatch(chunk, "[^,]+") do
                    values[#values + 1] = tonumber(number)
                end
                if #values ~= 3 or not values[1] or not values[2] or not values[3] then
                    Notify(ply, "Each centerline waypoint must be local x,y,z.")
                    return
                end
                via[#via + 1] = values
            end
            if first ~= link[1] then
                local reversed = {}
                for i = #via, 1, -1 do reversed[#reversed + 1] = via[i] end
                via = reversed
            end
            link.via = via
            file.CreateDir("metrostroi_expanded")
            file.Write(JUNCTION_FILE, util.TableToJSON(N.Junctions, true) or "{}")
            SendProfiles()
            Notify(ply, "Measured native junction centerline waypoints saved.")
            return
        end
    end
    Notify(ply, "The selected pair is not a registered physical path.")
end)
concommand.Add("mex_native_set_switch_variants", function(ply, _, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local id, mainModel, divergeModel = unpack(args)
    local profile = id and N.Junctions[id]
    if not profile or profile.kind ~= "switch"
        or not ValidModel(mainModel) or not ValidModel(divergeModel) then
        Notify(ply, "Usage: mex_native_set_switch_variants <registered_id> <original_main.mdl> <original_diverging.mdl>")
        return
    end
    profile.variants = {["2"] = mainModel, ["3"] = divergeModel}
    file.CreateDir("metrostroi_expanded")
    file.Write(JUNCTION_FILE, util.TableToJSON(N.Junctions, true) or "{}")
    SendProfiles()
    Notify(ply, "Original moving-switch variants registered; .phy is checked during placement.")
end)
concommand.Add("mex_native_list_junction_models", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local roots = {"models/metrostroi/tracks", "models/metrostroi_tunnels"}
    local found = 0
    for _, dir in ipairs(roots) do
        local models = file.Find(dir .. "/*.mdl", "GAME") or {}
        for _, model in ipairs(models) do
            if string.find(model, "cross", 1, true)
                or string.find(model, "switch", 1, true)
                or string.find(model, "point", 1, true)
                or string.find(model, "junction", 1, true) then
                print("[MEX Native Track] Potential original junction: " .. dir .. "/" .. model)
                found = found + 1
            end
        end
    end
    Notify(ply, "Found " .. found .. " possible installed original junction models; see server console.")
end)
concommand.Add("mex_native_status", function(ply)
    local routes = #N.Routes
    local profiles = table.Count(N.Junctions)
    Notify(ply, string.format("%d routes, %d calibrated junction profiles.", routes, profiles))
end)
