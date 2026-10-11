-- Metrostroi Expanded - native original-model construction
-- Copyright (C) 2026 Adam Cir / Adava Software - GPL-3.0
-- No generated rail/tunnel geometry or substituted collision bodies.
if SERVER then AddCSLuaFile() end

MEXNativeTrack = MEXNativeTrack or {}
local N = MEXNativeTrack
local ROOT = "models/metrostroi/tracks/"
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
    local origin = start + Vector(0, 0, 5)
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
        local radius = tonumber(settings.radius) or 4096
        local spec = TURNS[tunnel] and TURNS[tunnel][lane]
        spec = spec and spec[radius]
        if not spec or not ValidModel(ROOT .. spec.file) then
            return nil, "Original turn1 model not found for this radius, tunnel and layout."
        end
        local sweep = 90 / spec.parts
        local sign = mode == "curve_right" and 1 or -1
        local angle = math.rad(sweep)
        local finish = start + Direction(yaw) * (radius * math.sin(angle))
            + Right(yaw) * (sign * radius * (1 - math.cos(angle)))
        local finalYaw = yaw - sign * sweep
        local pose
        if sign == 1 then
            pose = Placement(start, yaw, ROOT .. spec.file, radius * angle, lane, sign, radius, sweep)
        else
            -- Reversing the original right-handed arc yields a left curve,
            -- without mirroring the mesh or changing its contact rail.
            pose = Placement(finish, finalYaw + 180, ROOT .. spec.file,
                radius * angle, lane, sign, radius, sweep)
        end
        pose.start, pose.finish = P(start), P(finish)
        result.parts[1] = pose
        result.pos, result.yaw = finish, finalYaw
        return result
    end
    if mode == "switch" or mode == "crossing" then
        local spec = N.Junctions[tostring(settings.junction or "")]
        if not spec or spec.kind ~= mode then
            return nil, "No calibrated original junction profile is selected. Register its real model and ports first."
        end
        if not ValidModel(spec.model) then return nil, "The original junction model is not installed." end
        local ang = ModelAngles(yaw)
        local reference = V(spec.ports[1])
        reference:Rotate(ang)
        local origin = start - reference + Vector(0, 0, 5)
        local output = math.Clamp(math.floor(tonumber(settings.branch) or 2), 2, #spec.ports)
        local port = V(spec.ports[output])
        port:Rotate(ang)
        local portPos = origin + port - Vector(0, 0, 5)
        local yawOut = yaw + (tonumber(spec.ports[output][4]) or 0)
        result.parts[1] = {
            model = spec.model, pos = P(origin), ang = {ang.p, ang.y, ang.r},
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
        return {{pos = a, yaw = part.yaw + 180}, {pos = b,
            yaw = part.yaw - (part.turn or 0) * (part.sweep or 0)}}
    end
    local spec = N.Junctions[part.junction]
    if not spec then return {} end
    local ports = {}
    local ang = Angle(part.ang[1], part.ang[2], part.ang[3])
    for i, data in ipairs(spec.ports) do
        local pos = V(data)
        pos:Rotate(ang)
        local yaw = (part.yaw + (tonumber(data[4]) or 0))
        ports[i] = {pos = V(part.pos) - Vector(0, 0, 5) + pos, yaw = yaw}
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
            return {nodes}
        end
        local sweep = math.rad(part.sweep)
        local steps = math.max(2, math.ceil(part.radius * sweep / 64))
        for step = 0, steps do
            local q = sweep * step / steps
            nodes[#nodes + 1] = V(part.start)
                + Direction(part.yaw) * (part.radius * math.sin(q))
                + Right(part.yaw) * (part.turn * part.radius * (1 - math.cos(q)))
        end
        return {nodes}
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
            if a and b then paths[#paths + 1] = {a.pos, b.pos} end
        end
    end
    return paths
end

if CLIENT then
    local ghosts = {}
    local grey = Color(155, 155, 155, 130)
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
        render.SetBlend(0.48)
        render.SetColorModulation(warn and 1 or 0.68, warn and 0.45 or 0.68, warn and 0.45 or 0.68)
        ghost:SetupBones()
        ghost:DrawModel()
        render.SetBlend(1)
        render.SetColorModulation(1, 1, 1)
    end
    local nodes, nextNodesRefresh = {}, 0
    local function CollectVisibleEndpoints()
        if CurTime() < nextNodesRefresh then return nodes end
        nextNodesRefresh = CurTime() + 0.3
        local all, counts = {}, {}
        for _, ent in ipairs(ents.FindByClass("prop_physics")) do
            if IsValid(ent) and ent:GetNW2Bool("MEXNativeModule", false) then
                for j = 1, ent:GetNW2Int("MEXNativePorts", 0) do
                    local pos = ent:GetNW2Vector("MEXNativePort" .. j, vector_origin)
                    if pos ~= vector_origin then
                        local key = PortKey(pos)
                        counts[key] = (counts[key] or 0) + 1
                        all[#all + 1] = {pos = pos, key = key, index = j}
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
        if not tr.Hit or tr.HitSky then return end
        local active = ply:GetNW2Bool("MEXNativeActive", false)
        local origin = active and ply:GetNW2Vector("MEXNativeEnd", tr.HitPos) or tr.HitPos
        local yaw = active and ply:GetNW2Float("MEXNativeYaw", 0) or ply:EyeAngles().y
        local settings = {
            mode = tool:GetClientInfo("native_mode"),
            tunnel = tool:GetClientInfo("native_tunnel"),
            tracks = tool:GetClientNumber("native_tracks", 1),
            radius = tool:GetClientNumber("native_radius", 4096),
            junction = tool:GetClientInfo("native_junction"),
            branch = tool:GetClientNumber("native_branch", 2),
        }
        local candidate, errorText = N.Candidate(origin, yaw, tr.HitPos, settings)
        if candidate and #candidate.parts > 0 then
            for i, part in ipairs(candidate.parts) do
                if i <= 64 then DrawGhost(part, i, false) end
            end
            render.SetColorMaterial()
            render.DrawWireframeSphere(origin, 9, 9, 9, Color(55, 245, 120), true)
            render.DrawWireframeSphere(candidate.pos, 9, 9, 9, Color(255, 185, 70), true)
        elseif not active then
            -- Even before the first click, show a stock-size grey placement
            -- ghost at the mouse cursor, never an invisible preview.
            local tunnel, lane = Settings(settings)
            local kit = KIT[tunnel] and KIT[tunnel][lane]
            local name
            for _, len in ipairs({64, 256, 1024, 4096}) do
                if kit and kit[len] and ValidModel(ROOT .. kit[len]) then
                    name = ROOT .. kit[len]
                    break
                end
            end
            if name then DrawGhost(Placement(origin, yaw, name, 64, lane), 1, false) end
        end
        render.SetColorMaterial()
        for _, node in ipairs(CollectVisibleEndpoints()) do
            if ply:GetPos():DistToSqr(node.pos) < 5000 * 5000 then
                local c = node.index == 1 and Color(60, 245, 110) or Color(255, 175, 65)
                render.DrawWireframeSphere(node.pos, 8, 9, 9, c, true)
            end
        end
        if active then
            render.DrawWireframeSphere(origin, 9, 9, 9, Color(60, 245, 110), true)
        end
    end)
    hook.Add("ShutDown", "MEXNativeGhostCleanup", function()
        for _, ghost in pairs(ghosts) do if IsValid(ghost) then ghost:Remove() end end
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
    file.Write(FILE, util.TableToJSON({version = 1, routes = N.Routes}, true) or "{}")
end
local function ValidProfile(profile)
    if not istable(profile) or not isstring(profile.id) or not isstring(profile.model)
        or not string.StartWith(profile.model, ROOT)
        or (profile.kind ~= "switch" and profile.kind ~= "crossing")
        or not istable(profile.ports) or not istable(profile.paths) then return false end
    if #profile.ports ~= (profile.kind == "switch" and 3 or 4) then return false end
    for _, port in ipairs(profile.ports) do
        if not istable(port) or #port < 4 then return false end
        for j = 1, 4 do if not tonumber(port[j]) then return false end end
    end
    for _, link in ipairs(profile.paths) do
        if not istable(link) or not profile.ports[tonumber(link[1]) or 0]
            or not profile.ports[tonumber(link[2]) or 0] then return false end
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
                nodes[#nodes + 1] = {pos = port.pos, yaw = port.yaw, key = key}
            end
        end
    end
    return nodes, count
end
function N.FindPort(pos, distance)
    local best, bestDist = nil, (distance or 64)^2
    local nodes, count = CollectPorts()
    for _, node in ipairs(nodes) do
        local d = pos:DistToSqr(node.pos)
        if d <= bestDist and (count[node.key] or 0) < 2 then
            best, bestDist = node, d
        end
    end
    return best
end

local function SpawnRoute(route, ghost)
    local new = {}
    for _, part in ipairs(route.parts) do
        if not ValidModel(part.model) then
            for _, ent in ipairs(new) do if IsValid(ent) then ent:Remove() end end
            return nil, "Missing original model: " .. tostring(part.model)
        end
        local ent = ents.Create("prop_physics")
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
        ent:SetNW2Int("MEXNativeRoute", route.id or 0)
        ent:SetNW2Int("MEXNativeIndex", #new + 1)
    local portCount = #N.ModulePorts(part)
        for portIndex = 1, math.min(portCount, 4) do
            ent:SetNW2Vector("MEXNativePort" .. portIndex, N.ModulePorts(part)[portIndex].pos)
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
        local ent = ents.Create("prop_dynamic")
        if IsValid(ent) then
            ent:SetModel(part.model)
            ent:SetPos(V(part.pos))
            ent:SetAngles(Angle(part.ang[1], part.ang[2], part.ang[3]))
            ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
            ent:SetColor(Color(145, 145, 145, 130))
            ent:SetSolid(SOLID_NONE)
            ent:Spawn()
            ent:DrawShadow(false)
            ent:SetNW2Bool("MEXNativePreview", true)
            state.preview[#state.preview + 1] = ent
        end
    end
end
local function Notify(ply, message)
    if IsValid(ply) then ply:ChatPrint("[MEX Native Track] " .. message) end
end
function N.Add(ply, aim, settings)
    if not IsValid(ply) or not ply:IsAdmin() or not isvector(aim) then return false end
    settings = settings or {}
    local state = N.Active[ply]
    if not state then
        local connector = N.FindPort(aim, 72)
        local yaw = connector and connector.yaw or ply:EyeAngles().y
        local pos = connector and connector.pos or aim
        N.Active[ply] = {start = pos, startYaw = yaw, pos = pos, yaw = yaw, parts = {}}
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
function N.Undo(ply, aimed)
    if not IsValid(ply) or not ply:IsAdmin() then return false end
    local state = N.Active[ply]
    if not state then
        local aimedID = IsValid(aimed) and aimed:GetNW2Int("MEXNativeRoute", 0) or 0
        local id = aimedID > 0 and aimedID or #N.Routes
        local route = N.Routes[id]
        if not route or #route.parts == 0 then return false end
        local first = route.parts[1]
        state = {
            start = V(first.start), startYaw = first.yaw,
            parts = table.Copy(route.parts), reopenID = id,
            preview = {},
        }
        N.Active[ply] = state
    end
    if #state.parts > 0 then table.remove(state.parts) end
    local last = state.parts[#state.parts]
    if last then
        local ports = N.ModulePorts(last)
        local endpoint = last.junction and ports[last.branch or 2] or ports[2]
        state.pos = endpoint and endpoint.pos or state.start
        state.yaw = last.junction and endpoint and endpoint.yaw or
            (last.yaw - (last.turn or 0) * (last.sweep or 0))
    else
        state.pos, state.yaw = state.start, state.startYaw
    end
    RefreshPreview(state)
    SyncState(ply)
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
hook.Add("InitPostEntity", "MEXNativeTrackRestore", function()
    file.CreateDir("metrostroi_expanded")
    local profiles = util.JSONToTable(file.Read(JUNCTION_FILE, "DATA") or "{}") or {}
    for _, profile in pairs(profiles) do
        if ValidProfile(profile) then N.Junctions[profile.id] = profile end
    end
    local decoded = util.JSONToTable(file.Read(FILE, "DATA") or "{}") or {}
    N.Routes = {}
    for _, route in ipairs(decoded.routes or {}) do
        if istable(route) and istable(route.parts) and #route.parts > 0 then
            local id = #N.Routes + 1
            route.id = id
            N.Routes[id] = route
            N.Props[id] = SpawnRoute(route) or {}
        end
    end
end)
hook.Add("PlayerInitialSpawn", "MEXNativeTrackSendProfiles", function(ply)
    timer.Simple(2, function() if IsValid(ply) then SendProfiles(ply) end end)
end)
hook.Add("PlayerUse", "MEXNativeSwitchOperate", function(ply, ent)
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
    local choices = {}
    for _, link in ipairs(profile.paths) do
        if link[1] == 1 then choices[#choices + 1] = link[2]
        elseif link[2] == 1 then choices[#choices + 1] = link[1] end
    end
    table.sort(choices)
    if #choices < 2 then return false end
    local index = table.KeyFromValue(choices, part.branch or choices[1]) or 1
    part.branch = choices[index % #choices + 1]
    ent:SetNW2Int("MEXNativeBranch", part.branch)
    Save()
    if MEXTrackBuilder and MEXTrackBuilder.RebuildMetrostroiNetwork then
        MEXTrackBuilder.RebuildMetrostroiNetwork(ply)
    end
    Notify(ply, "Turnout switched to port " .. part.branch .. ".")
    return false
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
concommand.Add("mex_native_status", function(ply)
    local routes = #N.Routes
    local profiles = table.Count(N.Junctions)
    Notify(ply, string.format("%d routes, %d calibrated junction profiles.", routes, profiles))
end)
