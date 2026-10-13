-- Metrostroi Expanded - original Metrostroi / Track Pack MDL catalog
-- GPL-3.0. Reads installed game models; never generates substitute track meshes.
if SERVER then AddCSLuaFile() end
MEXNativeTrack = MEXNativeTrack or {}
local N = MEXNativeTrack
N.ModelCatalog = N.ModelCatalog or {}
N.MeshProfiles = N.MeshProfiles or {}
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
local function TrackCandidate(filename)
    local s = string.lower(filename)
    return s:find("track", 1, true) ~= nil
        or s:find("rail", 1, true) ~= nil
        or s:find("tunnel", 1, true) ~= nil
        or s:find("metrotrack", 1, true) ~= nil
        or s:find("depo", 1, true) ~= nil
        or s:find("strel", 1, true) ~= nil
        or s:find("turn", 1, true) ~= nil
        or s:find("curve", 1, true) ~= nil
        or s:find("povorot", 1, true) ~= nil
        or s:find("cross", 1, true) ~= nil
        or s:find("syezd", 1, true) ~= nil
end
local function Kind(path)
    local s = string.lower(path)
    if s:find("switch", 1, true) or s:find("strel", 1, true)
        or s:find("cross", 1, true) or s:find("syezd", 1, true) then
        return "junction"
    end
    if s:find("turn", 1, true) or s:find("curve", 1, true)
        or s:find("povorot", 1, true) then
        return "curve"
    end
    return "straight"
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
        if TrackCandidate(dirname) then roots[#roots + 1] = "models/" .. dirname end
    end
    for _, root in ipairs(roots) do pending[#pending + 1] = {root, 0} end
    local processed = 0
    while #pending > 0 and processed < 1400 and table.Count(found) < 12000 do
        local item = table.remove(pending)
        local path, depth = item[1], item[2]
        local key = string.lower(path)
        if not visited[key] then
            visited[key] = true
            processed = processed + 1
            local models, dirs = file.Find(path .. "/*", "GAME")
            for _, name in ipairs(models or {}) do
                if string.EndsWith(string.lower(name), ".mdl")
                    and not name:find("_anim", 1, true)
                    and not name:find("_shared", 1, true) then
                    local mdl = string.lower(path .. "/" .. name)
                    local railFolder = path:find("/tracks", 1, true)
                        or path:find("/tunnels", 1, true)
                        or path:find("/mn_r", 1, true)
                    local forced = false
                    for root in pairs(forcedRoots) do
                        if string.StartWith(string.lower(path), root) then
                            forced = true
                            break
                        end
                    end
                    if TrackCandidate(name) or railFolder or forced
                        or path:find("trackpack", 1, true)
                        or path:find("track_pack", 1, true) then
                        found[mdl] = {model = mdl, kind = Kind(mdl),
                            source = mdl:find("metrostroi", 1, true)
                                and "Metrostroi" or "Track Pack"}
                    end
                end
            end
            if depth < 7 then
                for _, dir in ipairs(dirs or {}) do
                    pending[#pending + 1] = {path .. "/" .. dir, depth + 1}
                end
            end
        end
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
local function SliceCross(verts, axis, sample, span)
    -- Select only the seam-plane railhead vertices, group two railheads
    -- separated by Metrostroi's 85.8 SU center-to-center rail gauge.
    local bins = {}
    for _, p in ipairs(verts) do
        if math.abs(p[axis] - sample) <= span then
            local cross = p[3 - axis]
            local bin = math.floor(cross / 3 + 0.5)
            local cell = bins[bin]
            if not cell then cell = {n=0,x=0,z=0}; bins[bin]=cell end
            cell.n = cell.n + 1
            cell.x = cell.x + cross
            cell.z = cell.z + p[3]
        end
    end
    local peaks = {}
    for k, value in pairs(bins) do
        if value.n >= 2 then
            peaks[#peaks+1] = {cross=value.x/value.n,
                height=value.z/value.n, n=value.n}
        end
    end
    if #peaks < 2 then return nil end
    -- Higher frequency and closer to correct gauge beats an off-axis
    -- contact rail (one more lateral rail on tunnel models).
    local best, bestScore = nil, -math.huge
    for i=1,#peaks do
        for j=i+1,#peaks do
            local a,b = peaks[i],peaks[j]
            local gauge = math.abs(a.cross-b.cross)
            if gauge >= 79 and gauge <= 94 and math.abs(a.height-b.height) < 14 then
                local score = a.n+b.n - math.abs(gauge-85.8)*7
                if score>bestScore then
                    bestScore=score
                    best={ (a.cross+b.cross)/2, (a.height+b.height)/2 }
                end
            end
        end
    end
    return best
end
local function ExtractRailProfile(model)
    if not util.GetModelMeshes then return nil, "mesh API unavailable" end
    local ok, meshes = pcall(util.GetModelMeshes, model, 0)
    if not ok or not istable(meshes) then return nil, "no readable render meshes" end
    local selected, strength = {}, 0
    for _, mesh in ipairs(meshes) do
        local score = CandidateMaterial(mesh.material)
        if score > 0 then
            local verts = mesh.verticies or mesh.triangles or {}
            if score >= strength and #verts >= 12 then
                if score > strength then selected = {}; strength = score end
                selected[#selected+1] = verts
            end
        end
    end
    if #selected == 0 then return nil, "no recognizable running-rail material" end
    local verts, x0,x1,y0,y1 = {}, math.huge,-math.huge,math.huge,-math.huge
    for _, list in ipairs(selected) do
        for _, vert in ipairs(list) do
            local p=Position(vert)
            if isvector(p) then
                verts[#verts+1] = {p.x,p.y,p.z}
                x0,x1=math.min(x0,p.x),math.max(x1,p.x)
                y0,y1=math.min(y0,p.y),math.max(y1,p.y)
            end
        end
    end
    if #verts > 200000 then return nil,"too many mesh vertices for safe calibration" end
    local axis = (y1-y0 >= x1-x0) and 2 or 1
    local low,high = axis==2 and y0 or x0,axis==2 and y1 or x1
    if high-low < 64 or high-low > 16384 then
        return nil,"not a single recognizable rail segment" end
    local points = {}
    -- Each coordinate is measured from the actual running railhead pair,
    -- not a fake circular arc, the model OBB or the concrete tunnel rim.
    for i=0,24 do
        local at = low + (high-low)*i/24
        local edge = i == 0 or i == 24
        local pair = SliceCross(verts, axis, at, edge and 3 or 9)
        if pair then
            local point = axis==2 and {pair[1],at,pair[2]} or {at,pair[1],pair[2]}
            points[#points+1] = point
        end
    end
    if #points < 5 then return nil,"could not detect both running rails at the ends" end
    if math.abs(points[1][axis]-low)>8 or math.abs(points[#points][axis]-high)>8 then
        return nil,"end rail cross-sections missing" end
    local startA,endA=points[1],points[#points]
    local entryYaw=PlanarYaw(startA,points[math.min(#points,3)])
    local exitYaw=PlanarYaw(points[math.max(1,#points-2)],endA)
    local delta=math.AngleDifference(exitYaw,entryYaw)
    local length=0
    for i=2,#points do length=length+Dist2(points[i-1],points[i]) end
    local profile={
        model=model, points=points,
        entry=startA, finish=endA,
        entryYaw=entryYaw, exitYaw=exitYaw, deltaYaw=delta,
        length=length, axis=axis,
        curved=math.abs(delta)>0.8,
        method="running-rail mesh",
    }
    if math.abs(startA[3]-endA[3]) > 24 then
        return nil,"grade-changing segment needs measured 3-D connector orientation" end
    return profile
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
    local length = 0
    for i = 2, #points do length = length + Dist2(points[i-1], points[i]) end
    local entryYaw = PlanarYaw(first, points[2])
    local exitYaw = PlanarYaw(points[#points-1], last)
    local delta = math.AngleDifference(exitYaw, entryYaw)
    return {
        model = model, points = points, entry = first, finish = last,
        entryYaw = entryYaw, exitYaw = exitYaw, deltaYaw = delta,
        curved = math.abs(delta) > 0.8, length = length,
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
        return OverrideProfile(model, override.points)
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
        if #points == 2 and math.abs(math.AngleDifference(
                PlanarYaw(points[1], points[2]), 0)) >= 0 then
            -- Two-point profiles are valid only for a real straight section.
            local name = model:lower()
            if Kind(name) == "curve" then
                print("[MEX Native Track] Curved models need 3+ measured points to define their real centerline.")
                return
            end
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
