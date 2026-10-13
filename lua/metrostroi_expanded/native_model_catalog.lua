-- Metrostroi Expanded - original Metrostroi / Track Pack MDL catalog
-- GPL-3.0. Reads installed game models; never generates substitute track meshes.
if SERVER then AddCSLuaFile() end
MEXNativeTrack = MEXNativeTrack or {}
local N = MEXNativeTrack
N.ModelCatalog = N.ModelCatalog or {}
-- Reset old negative/failed calibration cache on Lua refresh, since older
-- fixed-step sampling rejected straight original MDLs with only end vertices.
local ANALYZER_VERSION = 4
if N.MeshProfileCacheVersion ~= ANALYZER_VERSION then
    N.MeshProfiles = {}
    N.MeshProfileCacheVersion = ANALYZER_VERSION
else
    N.MeshProfiles = N.MeshProfiles or {}
end
N.NativeOverrides = N.NativeOverrides or {}
local OVERRIDE_FILE = "metrostroi_expanded/native_model_ports.json"
if SERVER then
    N.NativeOverrides = util.JSONToTable(
        file.Read(OVERRIDE_FILE, "DATA") or "{}") or {}
end
local DEFAULT_ROOTS = {
    "models/metrostroi",
    "models/metrostroi_tracks",
    "models/metrostroi_trackpack",
    "models/trackpack",
    "models/track_pack",
    "models/metrostroi_tunnels",
    "models/nekrasovskaya",
    "models/kalininskaya",
    "models/mn_r",
}
-- The catalog includes ALL original MDLs in mounted Metrostroi / Track
-- Pack folders, not only models whose filenames contain "rail" or "turn".
local function IsPackDirectory(name)
    local s = string.lower(tostring(name))
    return s:find("metrostroi", 1, true) ~= nil
        or s:find("trackpack", 1, true) ~= nil
        or s:find("track_pack", 1, true) ~= nil
        or s:find("metrotrack", 1, true) ~= nil
        or s:find("metro_track", 1, true) ~= nil
        or s:find("railway", 1, true) ~= nil
        or s:find("tracks", 1, true) ~= nil
        or s:find("nekrasovskaya", 1, true) ~= nil
        or s:find("kalininskaya", 1, true) ~= nil
        or s:find("mn_r", 1, true) ~= nil
end
local function Kind(path)
    -- Never classify by the PARENT FOLDER. The old implementation marked
    -- every numerically named curve inside "models/metrostroi_tracks" as
    -- straight, because the directory itself contained "tracks".
    local s = string.lower(string.GetFileFromFilename(path or ""))
    if s:find("switch", 1, true) or s:find("strel", 1, true)
        or s:find("cross", 1, true) or s:find("syezd", 1, true)
        or s:find("junction", 1, true) then return "junction" end
    if s:find("turn", 1, true) or s:find("curve", 1, true)
        or s:find("povorot", 1, true) or s:find("radius", 1, true) then
        return "curve"
    end
    if s:find("tunnel", 1, true) or s:find("railroad", 1, true)
        or s:find("straight", 1, true) or s:find("track", 1, true)
        or s:find("depo", 1, true) or s:find("puti", 1, true) then
        return "straight"
    end
    -- Numeric / unknown Track Pack names must be classified by actual
    -- measured geometry, NOT mislabeled by a parent directory.
    return "other"
end
function N.ScanModelCatalog()
    if CLIENT then return N.ModelCatalog end
    local found, roots, pending, visited = {}, {}, {}, {}
    for _, root in ipairs(DEFAULT_ROOTS) do roots[#roots + 1] = root end
    local forcedRoots = {}
    local rootFile = file.Read("metrostroi_expanded/native_catalog_roots.json", "DATA")
    local custom = util.JSONToTable(rootFile or "[]") or {}
    for _, root in ipairs(custom) do
        if isstring(root) and string.StartWith(root, "models/")
            and not root:find("%.%.", 1, true) then
            local customRoot = string.lower(root)
            roots[#roots + 1] = customRoot
            forcedRoots[customRoot] = true
        end
    end
    -- Only look at appropriately named GAME-mounted roots. This includes
    -- GMA/Workshop and non-Workshop Metrostroi/TrackPack content.
    local _, topDirs = file.Find("models/*", "GAME")
    for _, dirname in ipairs(topDirs or {}) do
        if IsPackDirectory(dirname) then
            roots[#roots + 1] = "models/" .. dirname
        end
    end
    for _, root in ipairs(roots) do pending[#pending + 1] = {root, 0} end
    local processed, discovered = 0, 0
    while #pending > 0 and processed < 10000 and discovered < 50000 do
        local item = table.remove(pending)
        local path, depth = item[1], item[2]
        local key = string.lower(path)
        if not visited[key] then
            visited[key] = true
            processed = processed + 1
            local models, dirs = file.Find(path .. "/*", "GAME")
            for _, name in ipairs(models or {}) do
                if string.EndsWith(string.lower(name), ".mdl") then
                    local mdl = string.lower(path .. "/" .. name)
                    -- The roots themselves were restricted to installed
                    -- Metrostroi/Track Pack directories. Every mounted MDL
                    -- below them is discoverable, including trains, signals,
                    -- stations, accessories and models with numeric names.
                    if not found[mdl] then discovered = discovered + 1 end
                    local source = (mdl:find("trackpack", 1, true)
                        or mdl:find("track_pack", 1, true))
                        and "Track Pack" or "Metrostroi"
                    found[mdl] = {
                        model = mdl, kind = Kind(mdl), source = source,
                        name = name:gsub("%.mdl$", ""),
                    }
                end
            end
            if depth < 12 then
                for _, dir in ipairs(dirs or {}) do
                    pending[#pending + 1] = {path .. "/" .. dir, depth + 1}
                end
            end
        end
    end
    if #pending > 0 then
        print("[MEX Native Track] Model scan reached safety limit (" ..
            processed .. " folders, " .. discovered ..
            " models). Narrow custom catalog roots if necessary.")
    end
    N.ModelCatalog = found
    return found
end
local function CandidateMaterial(material)
    local s = string.lower(tostring(material or ""))
    if s:find("railroad_001b", 1, true) then return 3 end
    if s:find("rail", 1, true) or s:find("rels", 1, true)
        or s:find("relsy", 1, true) then return 2 end
    if s:find("track", 1, true) or s:find("put", 1, true)
        or s:find("polo", 1, true) then return 1 end
    return 0
end
local function Position(vertex)
    return istable(vertex) and vertex.pos or nil
end
local function PlanarYaw(a, b)
    return math.deg(math.atan2(b[2] - a[2], b[1] - a[1]))
end
local function Dist2(a, b)
    local x, y = a[1] - b[1], a[2] - b[2]
    return math.sqrt(x*x + y*y)
end

-- Catalog categories are display hints, not evidence of curvature.
-- A straight stock prefab must not acquire a bend merely because vertices
-- from its sleepers, third rail or tunnel wall resemble a rail pair.
local function NamedStraightModel(model)
    return Kind(model) == "straight"
end
local function NamedCurveModel(model)
    return Kind(model) == "curve"
end
local function AngularError(a, b)
    return math.abs(math.AngleDifference(a, b))
end
local function ValidateRailProfile(profile)
    local points = profile.points
    local first, last = points[1], points[#points]
    local chordYaw = PlanarYaw(first, last)
    local maxKink, prevYaw = 0, nil
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        local length = Dist2(a, b)
        if length < 0.5 then
            return false, "rail mesh has duplicate station positions"
        end
        local yaw = PlanarYaw(a, b)
        if prevYaw then
            maxKink = math.max(maxKink, AngularError(yaw, prevYaw))
        end
        prevYaw = yaw
    end
    profile.maxLocalKink = maxKink
    profile.chordYaw = chordYaw
    if NamedStraightModel(profile.model) then
        -- Strong invariant: a straight rail has identical entry/exit
        -- tangents and runs through both end faces without lateral bends.
        -- A 10+ SU mismatch is visible as a sharp kink in the game.
        if profile.lateralDeviation > 4
            or AngularError(profile.entryYaw, chordYaw) > 2.5
            or AngularError(profile.exitYaw, chordYaw) > 2.5
            or AngularError(profile.entryYaw, profile.exitYaw) > 2.5
            or maxKink > 4 then
            return false,
                "Ambiguous rail mesh: this straight MDL was falsely measured as curved. No inaccurate connector will be used."
        end
        -- The two REAL seam centers determine its line. An intentionally
        -- straight prefab may have 40+ extraneous sleeper mesh stations;
        -- these must not enter the Metrostroi track network as a zigzag.
        profile.points = {first, last}
        profile.entryYaw = chordYaw
        profile.exitYaw = chordYaw
        profile.deltaYaw = 0
        profile.curved = false
        profile.lateralDeviation = 0
        profile.method = "validated original straight rail end faces"
        return true
    end
    -- A turn may have a smooth arc or transition, but cannot change its
    -- heading by tens of degrees in one microscopic rail-mesh step.
    if maxKink > 14 then
        return false, "Railhead measurement contains sharp inconsistent kinks"
    end
    if NamedCurveModel(profile.model) then
        if #points < 4 or not profile.curved then
            return false, "Curve model needs a verified curved railhead path"
        end
    end
    return true
end
-- A compiled original MDL may have only TWO railhead vertex rows:
-- one at each end of a 256/1024 SU straight! A fixed 25-slice sampler
-- incorrectly rejected these perfectly valid models as "missing rails".
-- Probe ACTUAL rail-vertex stations instead of imaginary uniform sections.
local function SliceCross(vertices, axis, station, tolerance)
    local bins = {}
    for _, p in ipairs(vertices) do
        if math.abs(p[axis] - station) <= tolerance then
            local across = p[3 - axis]
            local bin = math.floor(across / 5 + 0.5)
            local cell = bins[bin]
            if not cell then
                cell = {n = 0, across = 0, height = 0}
                bins[bin] = cell
            end
            cell.n = cell.n + 1
            cell.across = cell.across + across
            cell.height = cell.height + p[3]
        end
    end
    local peaks = {}
    for _, cell in pairs(bins) do
        if cell.n >= 1 then
            peaks[#peaks + 1] = {
                across = cell.across / cell.n,
                height = cell.height / cell.n,
                count = cell.n,
            }
        end
    end
    local best, bestScore = nil, -math.huge
    for i = 1, #peaks do
        for j = i + 1, #peaks do
            local a, b = peaks[i], peaks[j]
            local gauge = math.abs(a.across - b.across)
            local dz = math.abs(a.height - b.height)
            -- Allow differences between model versions. The original
            -- rail-spacing is measured, never *set* to an assumed gauge.
            if gauge >= 65 and gauge <= 110 and dz <= 20 then
                local score = a.count + b.count
                    - math.abs(gauge - 85.8) * 0.5 - dz * 0.6
                if score > bestScore then
                    bestScore = score
                    best = {
                        across = (a.across + b.across) * 0.5,
                        height = (a.height + b.height) * 0.5,
                        gauge = gauge,
                        score = score,
                    }
                end
            end
        end
    end
    return best
end

local function ModelRailProfile(model, allVertices, axis, materialScore)
    if #allVertices < 8 or #allVertices > 110000 then return nil end
    local low, high = math.huge, -math.huge
    local stationBins = {}
    for _, p in ipairs(allVertices) do
        local along = p[axis]
        low, high = math.min(low, along), math.max(high, along)
        stationBins[math.floor(along / 2 + 0.5)] = true
    end
    local span = high - low
    if span < 50 or span > 16384 then return nil end
    local stations = {}
    for bin in pairs(stationBins) do
        stations[#stations + 1] = bin * 2
    end
    table.sort(stations)
    if #stations < 2 then return nil end
    -- Limit the work on huge complex original MDLs. Preserve the exact
    -- first and last stations even if we downsample the interior.
    local candidates = {}
    local step = math.max(1, math.ceil(#stations / 90))
    for i = 1, #stations, step do candidates[#candidates + 1] = stations[i] end
    if candidates[#candidates] ~= stations[#stations] then
        candidates[#candidates + 1] = stations[#stations]
    end
    local points, scores, gauges = {}, 0, {}
    for _, station in ipairs(candidates) do
        local match
        for _, tolerance in ipairs({2.5, 6, 14}) do
            match = SliceCross(allVertices, axis, station, tolerance)
            if match then break end
        end
        if match then
            points[#points + 1] = axis == 2
                and {match.across, station, match.height}
                or {station, match.across, match.height}
            scores = scores + match.score
            gauges[#gauges + 1] = match.gauge
        end
    end
    -- Valid original straight rails often have no intermediate vertex
    -- at all. Two verified end faces are therefore sufficient *only*
    -- for an unambiguously straight original segment.
    if #points < 2 then return nil end
    if math.abs(points[1][axis] - low) > math.max(8, math.min(24, span * 0.035))
        or math.abs(points[#points][axis] - high) >
            math.max(8, math.min(24, span * 0.035)) then
        return nil
    end
    if #points == 2 and (model:find("turn", 1, true)
        or model:find("curve", 1, true)
        or model:find("povorot", 1, true)) then
        return nil -- A two-point guess cannot reconstruct a curved rail.
    end

    local first, last = points[1], points[#points]
    local firstNext = points[math.min(3, #points)]
    local lastPrev = points[math.max(1, #points - 2)]
    local entryYaw = PlanarYaw(first, firstNext)
    local exitYaw = PlanarYaw(lastPrev, last)
    local delta = math.AngleDifference(exitYaw, entryYaw)
    local length, maxBend = 0, 0
    for i = 2, #points do length = length + Dist2(points[i-1], points[i]) end
    local dx, dy = last[1] - first[1], last[2] - first[2]
    local chord = math.max(1, math.sqrt(dx * dx + dy * dy))
    for _, point in ipairs(points) do
        maxBend = math.max(maxBend, math.abs(
            (point[1] - first[1]) * dy -
            (point[2] - first[2]) * dx) / chord)
    end
    if math.abs(first[3] - last[3]) > 24 then return nil end
    local gaugeMean = 0
    for _, g in ipairs(gauges) do gaugeMean = gaugeMean + g end
    gaugeMean = gaugeMean / #gauges
    return {
        model = model,
        points = points, entry = first, finish = last,
        entryYaw = entryYaw, exitYaw = exitYaw, deltaYaw = delta,
        length = length, axis = axis,
        curved = math.abs(delta) > 0.8 or maxBend > 12,
        lateralDeviation = maxBend, gauge = gaugeMean,
        -- Trust several railhead stations more than two; favor original
        -- material names but never insist that a straight has 5+ stations.
        confidence = #points * 4 + materialScore * 20 + scores * 0.05,
        method = #points == 2
            and "measured original straight rail end faces"
            or "measured original railhead mesh",
    }
end

local function ExtractRailProfile(model)
    if not util.GetModelMeshes then return nil, "mesh API unavailable" end
    local ok, meshes = pcall(util.GetModelMeshes, model, 0)
    if not ok or not istable(meshes) or #meshes == 0 then
        return nil, "no readable original render mesh"
    end

    local pools = {[1] = {}, [2] = {}, [3] = {}}
    local sizes = {[1] = 0, [2] = 0, [3] = 0}
    for _, meshData in ipairs(meshes) do
        local strength = CandidateMaterial(meshData.material)
        if strength > 0 then
            local verts = meshData.verticies or meshData.triangles or {}
            for _, vert in ipairs(verts) do
                local pos = Position(vert)
                if isvector(pos) and sizes[strength] < 110000 then
                    local p = {pos.x, pos.y, pos.z}
                    pools[strength][#pools[strength] + 1] = p
                    sizes[strength] = sizes[strength] + 1
                end
            end
        end
    end
    local best, bestScore = nil, -math.huge
    -- Separate candidate materials are important: a model's sleepers
    -- can use a generic "railroad" texture but the real rails another.
    for strength = 3, 1, -1 do
        if sizes[strength] >= 8 then
            for _, axis in ipairs({2, 1}) do
                local profile = ModelRailProfile(model,
                    pools[strength], axis, strength)
                if profile then
                    local accepted = ValidateRailProfile(profile)
                    if accepted and profile.confidence > bestScore then
                        best, bestScore = profile, profile.confidence
                    end
                end
            end
        end
    end
    if not best then
        -- Some Track Packs assign a different but still rail-related
        -- material to each running rail. Try their combined vertices.
        local combined = {}
        for strength = 3, 1, -1 do
            for _, p in ipairs(pools[strength]) do
                if #combined >= 110000 then break end
                combined[#combined + 1] = p
            end
        end
        if #combined >= 8 then
            for _, axis in ipairs({2, 1}) do
                local profile = ModelRailProfile(model, combined, axis, 1)
                if profile then
                    local accepted = ValidateRailProfile(profile)
                    if accepted and profile.confidence > bestScore then
                        best, bestScore = profile, profile.confidence
                    end
                end
            end
        end
    end
    if not best then
        return nil, "Original railheads could not be measured reliably; straight models are never bent to match a bad scan. Try another rail MDL or a measured profile."
    end
    return best
end

local function ValidOverride(override)
    if not istable(override) or not istable(override.points)
        or #override.points < 2 or #override.points > 256 then
        return false
    end
    for _, p in ipairs(override.points) do
        if not istable(p) or #p ~= 3 then return false end
        for i = 1, 3 do
            local x = tonumber(p[i])
            if not x or math.abs(x) > 262144 then return false end
        end
    end
    return true
end
local function OverrideProfile(model, points)
    local first, last = points[1], points[#points]
    local length,maxBend = 0,0
    for i = 2, #points do length = length + Dist2(points[i-1], points[i]) end
    local entryYaw = PlanarYaw(first, points[2])
    local exitYaw = PlanarYaw(points[#points-1], last)
    local delta = math.AngleDifference(exitYaw, entryYaw)
    local dx,dy = last[1]-first[1],last[2]-first[2]
    local lengthXY = math.max(1,math.sqrt(dx*dx+dy*dy))
    for _,p in ipairs(points) do
        maxBend = math.max(maxBend,
            math.abs((p[1]-first[1])*dy - (p[2]-first[2])*dx)/lengthXY)
    end
    return {
        model = model, points = points, entry = first, finish = last,
        entryYaw = entryYaw, exitYaw = exitYaw, deltaYaw = delta,
        curved = math.abs(delta) > 0.8 or maxBend > 12,
        lateralDeviation = maxBend, length = length,
        method = "registered original rail centerline",
    }
end
function N.AnalyzeNativeModel(model)
    if not isstring(model) or not string.StartWith(model,"models/")
        or not string.EndsWith(model,".mdl") then
        return nil,"invalid original model path"
    end
    model=string.lower(model)
    if not N.ModelCatalog[model] then
        return nil,"model is not in the scanned installed Metrostroi/Track Pack catalog"
    end
    local override = N.NativeOverrides[model]
    if ValidOverride(override) then
        local profile = OverrideProfile(model, override.points)
        local valid, reason = ValidateRailProfile(profile)
        if not valid then
            return nil, "Registered original rail ports are inconsistent: " ..
                tostring(reason)
        end
        return profile
    end
    local cached=N.MeshProfiles[model]
    if cached then return cached.profile,cached.error end
    if not util.IsValidModel(model) then
        return nil,"original MDL is missing or invalid"
    end
    local profile,err=ExtractRailProfile(model)
    N.MeshProfiles[model]={profile=profile,error=err}
    return profile,err
end

-- Calibration fallback for unusual Track Pack meshes without recognizable
-- rail-head material names. A superadmin supplies REAL local track centerline
-- measurements. Unknown junctions still require the multi-port registry.
if SERVER then
    concommand.Add("mex_native_register_model_path", function(ply, _, args)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local model = string.lower(tostring(args[1] or ""))
        local series = tostring(args[2] or "")
        if not N.ModelCatalog[model] then
            print("[MEX Native Track] Model not in catalog; use mex_native_rescan_models.")
            return
        end
        local points = {}
        for group in string.gmatch(series, "[^;]+") do
            local p = {}
            for v in string.gmatch(group, "[^,]+") do
                p[#p + 1] = tonumber(v)
            end
            points[#points + 1] = p
        end
        if not ValidOverride({points = points}) then
            print("[MEX Native Track] Usage: mex_native_register_model_path models/<path>.mdl \"x,y,z;x,y,z;...;\" (at least 2 measured points)")
            return
        end
        -- Two endpoints alone cannot describe a physical rail bend.
        if #points == 2 and Kind(model) == "curve" then
            print("[MEX Native Track] Curved models need 3+ measured centerline points.")
            return
        end
        N.NativeOverrides[model] = {points = points}
        N.MeshProfiles[model] = nil
        file.CreateDir("metrostroi_expanded")
        file.Write(OVERRIDE_FILE, util.TableToJSON(N.NativeOverrides, true) or "{}")
        print("[MEX Native Track] Registered original rail-path profile for " .. model)
    end)
    concommand.Add("mex_native_model_info", function(ply, _, args)
        if IsValid(ply) and not ply:IsAdmin() then return end
        local model = string.lower(tostring(args[1] or ""))
        local profile, err = N.AnalyzeNativeModel(model)
        if not profile then
            print("[MEX Native Track] " .. model .. ": " .. tostring(err))
            return
        end
        print(string.format("[MEX Native Track] %s | %s | %s | %.1f SU | turn %.2f degrees",
            model, profile.method or "unknown", profile.curved and "CURVE" or "STRAIGHT",
            profile.length, profile.deltaYaw))
        print(string.format("  entry (%.3f,%.3f,%.3f) yaw %.2f | exit (%.3f,%.3f,%.3f) yaw %.2f",
            profile.entry[1],profile.entry[2],profile.entry[3],profile.entryYaw,
            profile.finish[1],profile.finish[2],profile.finish[3],profile.exitYaw))
    end)
end
