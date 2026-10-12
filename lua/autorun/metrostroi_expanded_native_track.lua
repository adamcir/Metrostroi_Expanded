-- Metrostroi Expanded - native original-model construction
-- Copyright (C) 2026 Adam Cir / Adava Software - GPL-3.0
-- No generated rail/tunnel geometry or substituted collision bodies.
if SERVER then AddCSLuaFile() end

MEXNativeTrack = MEXNativeTrack or {}
local N = MEXNativeTrack
local ROOT = "models/metrostroi/tracks/"
if CLIENT then
    CreateClientConVar("mex_native_outdoor_brightness", "0.85", true, false,
        "Neutral model lighting for real Metrostroi surface railway prefabs", 0.35, 1.5)
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
local KIT = {
    none = {single = {[4096] = "railroad4096.mdl", [1024] = "railroad1024.mdl"}},
    round = {
        single = {[1024] = "tunnel1024.mdl", [256] = "tunnel256.mdl", [64] = "tunnel64.mdl"},
        double = {[1024] = "tunnel1024_double.mdl"},
    },
    rectangular = {
        single = {[1024] = "tunnel1024_rect.mdl", [256] = "tunnel256_rect.mdl", [64] = "tunnel64_rect.mdl"},
        double = {[1024] = "tunnel1024_double.mdl"},
    },
    wide = {double = {[1024] = "tunnel1024_double.mdl"}},
}
local TURNS = {
    round = {
        single = {
            [3072] = {file = "tunnel3072_turn1.mdl", parts = 3},
            [4096] = {file = "tunnel4096_turn1.mdl", parts = 4},
            [8192] = {file = "tunnel8192_turn1.mdl", parts = 8},
        },
        double = {
            [4096] = {file = "tunnel4096_double_turn1.mdl", parts = 4},
            [8192] = {file = "tunnel8192_double_turn1.mdl", parts = 8},
        },
    },
    rectangular = {
        single = {[3072] = {file = "tunnel3072_rect_turn1.mdl", parts = 3}},
    },
}
N.Junctions = N.Junctions or {}

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
    if not ok then
        ErrorNoHalt("[MEX Native Track] Original model has no usable .phy: " ..
            self:GetModel() .. "\\n")
    end
    self:SetUseType(SIMPLE_USE)
    self:DrawShadow(false)
end
function NativePiece:Draw()
    -- Stock Source tunnel/railroad models usually received baked map lighting
    -- as static props. When spawned as scripted entities their light sample can
    -- be inside grass/BSP, turning the long outside rail nearly black.
    -- Give ONLY these original MDLs neutral vertex-light fill, never replace
    -- the original materials or recolor their textures.
    local brightness = GetConVar("mex_native_outdoor_brightness")
    local outdoors = self:GetNW2Bool("MEXNativeOutdoor",
        self:GetNW2Bool("MEXNativeSurface", false))
    local fill = outdoors
        and (brightness and math.Clamp(brightness:GetFloat(), 0.35, 1.5) or 0.85)
        or 0.55
    render.SuppressEngineLighting(true)
    render.ResetModelLighting(fill, fill, fill)
    self:DrawModel()
    render.SuppressEngineLighting(false)
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
    if not isstring(model) or not string.StartWith(model, ROOT) then return false end
    local cached = modelCache[model]
    if cached and cached.expiry > CurTime() then return cached.valid end
    local valid = util.IsValidModel(model)
    modelCache[model] = {valid = valid, expiry = CurTime() + 30}
    return valid
end
local function Settings(settings)
    local kind = tostring(settings.tunnel or "round")
    if not KIT[kind] then kind = "round" end
    local lane = tonumber(settings.tracks) == 2 and "double" or "single"
    return kind, lane
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
local function StockCurveProfile(model)
    return STOCK_CURVE_PORTS[string.lower(tostring(model or ""))]
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
    local localStart = Vector(profile.entryX or 0, 0, 0)
    local localEnd = Vector(profile.x, profile.y, 0)
    local sweep = profile.sweep
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
-- Generate a strict sequence of original-size stock modules. There is no
-- arbitrary deformation, scaling, procedural tunnel or geometry fallback.
function N.Candidate(start, yaw, aimed, settings)
    settings = settings or {}
    local tunnel, lane = Settings(settings)
    local mode = tostring(settings.mode or "straight")
    local result = {parts = {}, pos = start, yaw = yaw}
    if mode == "straight" then
        local kit = KIT[tunnel] and KIT[tunnel][lane]
        if not kit then return nil, "No original straight modules for this tunnel/track layout." end
        local distance = (aimed - start):Dot(Direction(yaw))
        local sideways = (aimed - start - Direction(yaw) * distance):Length()
        if distance < 32 then return nil, "Point forward along the track to extend it." end
        if sideways > 120 then return nil, "Original straight modules cannot bend. Select a curve module." end
        local lengths = {}
        for length, model in pairs(kit) do
            if ValidModel(ROOT .. model) then lengths[#lengths + 1] = length end
        end
        table.sort(lengths, function(a,b) return a > b end)
        if #lengths == 0 then return nil, "No matching original Metrostroi tunnel models are installed." end
        local minimum = lengths[#lengths]
        local rounded = math.floor(distance / minimum + 0.5) * minimum
        if rounded > 16384 or rounded < minimum then return nil, "Route length is outside available module sizes." end
        local used, current = 0, start
        for _, length in ipairs(lengths) do
            while rounded - used >= length and #result.parts < 128 do
                result.parts[#result.parts + 1] = Placement(current, yaw, ROOT .. kit[length], length, lane)
                current = current + Direction(yaw) * length
                used = used + length
            end
        end
        if used ~= rounded then return nil, "The selected distance cannot be assembled from installed original models." end
        result.pos = current
        return result
    end
    if mode == "curve_left" or mode == "curve_right" then
        local requestedRadius = tonumber(settings.radius) or 4096
        local profiles = TURNS[tunnel] and TURNS[tunnel][lane]
        if not profiles then
            return nil, "No original curved tunnel is catalogued for this layout."
        end
        local radius, spec
        local bestDifference = math.huge
        for nominal, available in pairs(profiles) do
            if ValidModel(ROOT .. available.file) then
                local diff = math.abs(nominal - requestedRadius)
                if diff < bestDifference then
                    radius, spec, bestDifference = nominal, available, diff
                end
            end
        end
        if not spec then
            return nil, "No authentic turn1 MDL is mounted for this tunnel layout. Install the Metrostroi track models."
        end
        -- The optional size fallback always uses a REAL installed prefab.
        -- Geometry, endpoint connectors, and network paths all use its TRUE
        -- nominal radius, never the uninstalled radius requested by the tool.
        local sign = mode == "curve_right" and 1 or -1
        local model = ROOT .. spec.file
        local part, finish, exitYaw = StockCurveWorldPart(
            start, yaw, model, sign, radius, lane)
        if not part then
            return nil, "This original curve has no verified rail-end coordinates."
        end
        result.parts[1] = part
        result.pos, result.yaw = finish, exitYaw
        return result
    end
    if mode == "switch" or mode == "crossing" then
        local spec = N.Junctions[tostring(settings.junction or "")]
        if not spec or spec.kind ~= mode then
            return nil, "No calibrated original junction profile is selected. Register its real model and ports first."
        end
        local selected = spec.variants and spec.variants[tostring(tonumber(settings.branch) or 2)] or spec.model
        if spec.kind == "switch" and not spec.variants
            and tonumber(settings.branch or 2) ~= 2 then
            return nil, "This original switch has a fixed main route. Install and register matching main/diverging .phy model variants to enable port 3."
        end
        if not ValidModel(selected) then return nil, "The selected original junction model is not installed." end
        local ang = ModelAngles(yaw)
        local reference = V(spec.ports[1])
        reference:Rotate(ang)
        local origin = start - reference + Vector(0, 0, 5)
        local output = math.Clamp(math.floor(tonumber(settings.branch) or 2), 2, #spec.ports)
        local linked = false
        for _, link in ipairs(spec.paths) do
            if (link[1] == 1 and link[2] == output)
                or (link[2] == 1 and link[1] == output) then linked = true end
        end
        if not linked then
            return nil, "The chosen exit is not connected to the junction input. Select a physically connected output port."
        end
        local port = V(spec.ports[output])
        port:Rotate(ang)
        local portPos = origin + port - Vector(0, 0, 5)
        local yawOut = yaw + (tonumber(spec.ports[output][4]) or 0)
        result.parts[1] = {
            model = selected, pos = P(origin), ang = {ang.p, ang.y, ang.r},
            start = P(start), yaw = yaw, length = 0, lane = lane,
            junction = spec.id, branch = output,
        }
        result.pos, result.yaw = portPos, yawOut
        return result
    end
    return nil, "Unknown module mode."
end

local function PortKey(pos)
    return string.format("%d:%d:%d", math.Round(pos.x), math.Round(pos.y), math.Round(pos.z))
end
function N.ModulePorts(part)
    if not part.junction then
        local a, b = V(part.start), part.finish and V(part.finish)
            or (V(part.start) + Direction(part.yaw) * part.length)
        local endYaw = part.yaw - (part.turn or 0) * (part.sweep or 0)
        local lanes = part.lane == "double" and 2 or 1
        if lanes == 1 then
            return {
                {pos = RenderPort(a), center = a, yaw = part.yaw + 180,
                    lanes = 1, start = true},
                {pos = RenderPort(b), center = b, yaw = endYaw,
                    lanes = 1, start = false}
            }
        end
        local ports = {}
        for lane = 1, 2 do
            local offset = lane == 1 and -132 or 132
            ports[#ports + 1] = {
                pos = RenderPort(a + Right(part.yaw) * offset),
                center = a, yaw = part.yaw + 180, lanes = 2, start = true,
            }
        end
        for lane = 1, 2 do
            local offset = lane == 1 and -132 or 132
            ports[#ports + 1] = {
                pos = RenderPort(b + Right(endYaw) * offset),
                center = b, yaw = endYaw, lanes = 2, start = false,
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
                local points = {{x = profile.entryX or 0, y = 0}}
                for i = 2, #profile.track do
                    points[#points + 1] = {x = profile.track[i], y = (i - 1) * 128}
                end
                points[#points + 1] = {x = profile.x, y = profile.y}
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
        render.SetBlend(0.57)
        render.SetColorModulation(warn and 1 or 0.95,
            warn and 0.45 or 0.95, warn and 0.45 or 0.95)
        render.SuppressEngineLighting(true)
        render.ResetModelLighting(0.78, 0.78, 0.78)
        ghost:SetupBones()
        ghost:DrawModel()
        render.SuppressEngineLighting(false)
        render.SetBlend(1)
        render.SetColorModulation(1, 1, 1)
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
                        all[#all + 1] = {pos = pos, key = key,
                            start = double and j <= 2 or (not double and j == 1)}
                    end
                end
            end
        end
        nodes = {}
        for _, node in ipairs(all) do
            if counts[node.key] == 1 then nodes[#nodes + 1] = node end
        end
        return nodes
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
        local origin = active and ply:GetNW2Vector("MEXNativeEnd", aim) or aim
        local yaw = active and ply:GetNW2Float("MEXNativeYaw", 0) or ply:EyeAngles().y
        local settings = {
            mode = tool:GetClientInfo("native_mode"),
            tunnel = tool:GetClientInfo("native_tunnel"),
            tracks = tool:GetClientNumber("native_tracks", 1),
            radius = tool:GetClientNumber("native_radius", 4096),
            junction = tool:GetClientInfo("native_junction"),
            branch = tool:GetClientNumber("native_branch", 2),
        }
        local candidate, errorText = N.Candidate(origin, yaw, aim, settings)
        N.PreviewError = candidate and nil or errorText
        N.PreviewCurveRadius = nil
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
            if settings.mode == "curve_left" or settings.mode == "curve_right" then
                N.PreviewCurveRadius = candidate.parts[1].radius
            else
                N.PreviewCurveRadius = nil
            end
        else
            -- Never draw an unrelated STRAIGHT MDL when a curved tunnel is
            -- requested but not installed: its apparent endpoints would be
            -- wrong and the next click could never actually place it.
            -- In straight mode show a valid original sample at the cursor.
            if settings.mode == "straight" then
                local tunnel, lane = Settings(settings)
                local kit = KIT[tunnel] and KIT[tunnel][lane]
                local name, realLength
                for _, len in ipairs({64, 256, 1024, 4096}) do
                    if kit and kit[len] and ValidModel(ROOT .. kit[len]) then
                        name, realLength = ROOT .. kit[len], len
                        break
                    end
                end
                if name then
                    DrawGhost(Placement(origin, yaw, name, realLength, lane), 1, false)
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
            if distanceAlong > 0 and distanceAlong < trDistance + 32 then
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
    hook.Add("HUDPaint", "MEXNativeTrackCurveRadiusInfo", function()
        if not Tool() or not N.PreviewCurveRadius then return end
        draw.SimpleTextOutlined("Original curve radius: " ..
            tostring(N.PreviewCurveRadius) .. " SU",
            "DermaDefaultBold", ScrW() * 0.5, ScrH() * 0.68,
            Color(235, 235, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
            1, Color(0, 0, 0, 220))
    end)
    hook.Add("ShutDown", "MEXNativeGhostCleanup", function()
        for _, ghost in pairs(ghosts) do if IsValid(ghost) then ghost:Remove() end end
    end)
    concommand.Add("mex_native_curve_assets", function()
        local installed = 0
        print("[MEX Native Track] Original curved model availability:")
        for family, layouts in pairs(TURNS) do
            for layout, specs in pairs(layouts) do
                for radius, spec in pairs(specs) do
                    local model = ROOT .. spec.file
                    local ok = ValidModel(model)
                    print(string.format("  [%s] %s / %s / R%d: %s",
                        ok and "OK" or "MISSING", family, layout, radius, model))
                    if ok then installed = installed + 1 end
                end
            end
        end
        local available = file.Find(ROOT .. "*.mdl", "GAME") or {}
        print("[MEX Native Track] Other mounted original curve candidates:")
        for _, name in ipairs(available) do
            if string.find(name, "turn", 1, true)
                or string.find(name, "curve", 1, true) then
                print("    " .. ROOT .. name)
            end
        end
        chat.AddText(Color(230, 230, 230),
            "[MEX Track Builder] " .. installed ..
            " original curve profiles installed. See client console for exact filenames.")
    end)
    net.Receive("MEXNativeJunctionProfiles", function()
        local decoded = util.JSONToTable(net.ReadString() or "") or {}
        if istable(decoded) then N.Junctions = decoded end
    end)
    return
end

util.AddNetworkString("MEXNativeJunctionProfiles")
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
end
local function CollectPorts()
    local nodes, count = {}, {}
    for _, route in ipairs(N.Routes) do
        for _, part in ipairs(route.parts or {}) do
            for _, port in ipairs(N.ModulePorts(part)) do
                local key = PortKey(port.pos)
                count[key] = (count[key] or 0) + 1
                nodes[#nodes + 1] = {pos = port.pos, center = port.center,
                    yaw = port.yaw, lanes = port.lanes, key = key}
            end
        end
    end
    return nodes, count
end
function N.FindPort(pos, distance, tracks, eye, aimDir, traceDistance)
    local best, bestDist = nil, (distance or 72)^2
    local nodes, count = CollectPorts()
    -- Screen-center targeting is much more intuitive than asking players
    -- to shoot the map surface exactly behind a floating connector marker.
    local rayBest, rayDist = nil, 28 * 28
    for _, node in ipairs(nodes) do
        if (count[node.key] or 0) < 2
            and (not tracks or node.lanes == (tonumber(tracks) == 2 and 2 or 1)) then
            local d = pos:DistToSqr(node.pos)
            if d < bestDist then best, bestDist = node, d end
            if isvector(eye) and isvector(aimDir) then
                local along = (node.pos - eye):Dot(aimDir)
                if along >= 0 and along <= 8192
                    and (not traceDistance or along <= traceDistance + 32) then
                    local miss = node.pos:DistToSqr(eye + aimDir * along)
                    if miss < rayDist then rayBest, rayDist = node, miss end
                end
            end
        end
    end
    return rayBest or best
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
        ent:SetPos(V(part.pos))
        ent:SetAngles(Angle(part.ang[1], part.ang[2], part.ang[3]))
        ent:Spawn()
        ent:Activate()
        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then
            ent:Remove()
            for _, prev in ipairs(new) do if IsValid(prev) then prev:Remove() end end
            return nil, "Model has no usable original .phy collision: " .. part.model
        end
        phys:EnableMotion(false)
        phys:Sleep()
        ent:SetNW2Bool("MEXNativeModule", true)
        local surfaceModel = string.find(
            string.lower(part.model), "/railroad", 1, true) ~= nil
        ent:SetNW2Bool("MEXNativeSurface", surfaceModel)
        -- A tunnel MDL placed above ground on flatgrass is also an OUTDOOR
        -- prop. Its Source light probe can fall below the map and go black.
        -- Detect a clear line to sky once on spawn, not during Draw().
        local daylightOrigin = ent:GetPos() + Vector(0, 0, 40)
        local daylightTrace = util.TraceLine({
            start = daylightOrigin,
            endpos = daylightOrigin + Vector(0, 0, 8192),
            mask = MASK_SOLID_BRUSHONLY or MASK_SOLID,
        })
        ent:SetNW2Bool("MEXNativeOutdoor",
            surfaceModel or not daylightTrace.Hit or daylightTrace.HitSky)
        ent:SetNW2Int("MEXNativeRoute", route.id or 0)
        ent:SetNW2Int("MEXNativeIndex", #new + 1)
    local ports = N.ModulePorts(part)
        local portCount = #ports
        for portIndex = 1, math.min(portCount, 4) do
            ent:SetNW2Vector("MEXNativePort" .. portIndex, ports[portIndex].pos)
        end
        ent:SetNW2Int("MEXNativePorts", portCount)
        if part.junction then
            ent:SetNW2String("MEXNativeJunctionID", part.junction)
            ent:SetNW2Int("MEXNativeBranch", part.branch or 2)
        end
        ent:DrawShadow(false)
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
    local state = N.Active[ply]
    if not state then
        local tr = ply:GetEyeTrace()
        local rayLength = tr and tr.Hit and not tr.HitSky
            and ply:GetShootPos():Distance(tr.HitPos) or nil
        local connector = N.FindPort(aim, 72, settings.tracks,
            ply:GetShootPos(), ply:GetAimVector(), rayLength)
        local yaw = connector and connector.yaw or ply:EyeAngles().y
        local pos = connector and (connector.center or connector.pos) or aim
        N.Active[ply] = {owner = ply, start = pos, startYaw = yaw,
            pos = pos, yaw = yaw, parts = {}, preview = {}}
        SyncState(ply)
        Notify(ply, connector and "Connected to an original model endpoint." or "Start node set. Aim ahead to preview an original model.")
        return true
    end
    local candidate, err = N.Candidate(state.pos, state.yaw, aim, settings)
    if not candidate then Notify(ply, err); return false end
    for _, part in ipairs(candidate.parts) do state.parts[#state.parts + 1] = part end
    state.pos, state.yaw = candidate.pos, candidate.yaw
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
    if last then
        local ports = N.ModulePorts(last)
        local endpoint = last.junction and ports[last.branch or 2]
            or ports[last.lane == "double" and 3 or 2]
        state.pos = endpoint and (endpoint.center or endpoint.pos) or state.start
        state.yaw = last.junction and endpoint and endpoint.yaw
            or (last.yaw - (last.turn or 0) * (last.sweep or 0))
    else
        state.pos, state.yaw = state.start, state.startYaw
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
    table.remove(state.parts)
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
        if profile and (part.turn == 1 or part.turn == -1) then
            local calibrated, finish, finalYaw =
                StockCurveWorldPart(start, yaw, part.model, part.turn,
                    part.radius or 4096, part.lane or "single")
            if calibrated then
                -- Keep the old route's model and layout choices; only realign
                -- its model pose / graph / rail nodes to the actual MDL.
                route.parts[index] = calibrated
                part = calibrated
                newEnd, newYaw = finish, finalYaw
                changed = true
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
concommand.Add("mex_native_realign_routes", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local raw = file.Read(FILE, "DATA") or "{}"
    local backup = FILE .. ".before_manual_realign"
    if not file.Exists(backup, "DATA") then file.Write(backup, raw) end
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
        " saved routes using measured rail seam vertices.")
    if IsValid(ply) then
        ply:ChatPrint("[MEX Native Track] Realigned " .. count ..
            " routes; original save backup retained.")
    end
end)

hook.Add("InitPostEntity", "MEXNativeTrackRestore", function()
    file.CreateDir("metrostroi_expanded")
    local profiles = util.JSONToTable(file.Read(JUNCTION_FILE, "DATA") or "{}") or {}
    for _, profile in pairs(profiles) do
        if ValidProfile(profile) then N.Junctions[profile.id] = profile end
    end
    local raw = file.Read(FILE, "DATA") or "{}"
    local decoded = util.JSONToTable(raw) or {}
    local upgrade = (tonumber(decoded.version) or 1) < 2
    if upgrade and istable(decoded.routes) and #decoded.routes > 0 then
        local backup = FILE .. ".before_native_ports_v2"
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
    timer.Simple(2, function() if IsValid(ply) then SendProfiles(ply) end end)
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
