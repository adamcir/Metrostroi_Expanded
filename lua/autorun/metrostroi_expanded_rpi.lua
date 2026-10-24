-- Metrostroi Expanded: map-specific legacy RPI/RRI announcer API.
-- Content addons register definitions with MEXRPI.RegisterPack().
-- Stock Metrostroi calls the playback device RRI; MEX exposes the RPI name.
MEXRPI = MEXRPI or {}
local API = MEXRPI
API.Packs = API.Packs or {}
API.Order = API.Order or {}
API.LoadedFiles = API.LoadedFiles or {}
API.MissingSounds = API.MissingSounds or {}

function API.RegisterPack(id, definition)
    assert(isstring(id) and id ~= "" and istable(definition), "Invalid MEX RPI pack")
    if not API.Packs[id] then API.Order[#API.Order + 1] = id end
    API.Packs[id] = definition
end

local function ResolvePack(definition)
    if not definition.sourceASNP then return definition end
    local source = MEXASNP and MEXASNP.Packs and MEXASNP.Packs[definition.sourceASNP]
    if not istable(source) then return end

    -- Pack-specific RPI fields override ASNP fields, while the two announcers
    -- continue to share station order, sound keys, WAVs, and route metadata.
    local resolved = table.Copy(source)
    for key, value in pairs(definition) do resolved[key] = value end
    return resolved
end

local function MatchesMap(pack, map)
    if not istable(pack.maps) then return false end
    for _, prefix in ipairs(pack.maps) do
        if isstring(prefix) and string.StartWith(map, string.lower(prefix)) then
            return true
        end
    end
    return false
end

function API.CurrentPack()
    local map = string.lower(game.GetMap() or "")
    for _, id in ipairs(API.Order) do
        local pack = ResolvePack(API.Packs[id])
        if pack and MatchesMap(pack, map) then return id, pack end
    end
end

local function SoundTable(pack)
    -- RRI hardware always queues its own cassette start/end keys. Suppress
    -- unavailable mechanical sounds without requiring stock Russian audio.
    local sounds = {click_start = 0.01, click_end = 0.01}
    if not isstring(pack.soundRoot) then return sounds end

    for key, source in pairs(pack.sounds or {}) do
        if isstring(key) and istable(source) and isstring(source[1]) then
            local path = pack.soundRoot .. "/" .. source[1]
            if file.Exists("sound/" .. path, "GAME") then
                local duration = tonumber(source[2]) or 2
                if MEXASNP and isfunction(MEXASNP.AudioDuration) then
                    duration = MEXASNP.AudioDuration(path, duration) or duration
                end
                sounds[key] = {path, math.max(0.1, duration) + 0.25}
            else
                sounds[key] = 0.01 -- Metrostroi Announcer accepts silent delays.
                if not API.MissingSounds[path] then
                    API.MissingSounds[path] = true
                    print("[MEX RPI] Missing WAV (muted): " .. path)
                end
            end
        end
    end
    return sounds
end

local function Announcement(pack, keys, stationKey, final)
    local result = {}
    local available = pack.sounds or {}
    if available.gong_1 then result[#result + 1] = "gong_1" end
    for _, key in ipairs(keys) do
        if available[key] then result[#result + 1] = key end
    end
    if stationKey and available[stationKey] then
        result[#result + 1] = stationKey
    end
    if final and available.last then result[#result + 1] = "last" end
    return result
end

local function BuildRoutes(id, pack)
    if istable(pack.routes) then return table.Copy(pack.routes) end
    if isfunction(pack.routes) then return pack.routes(pack) end
    local stations = pack.stations
    if not istable(stations) or #stations < 2 then return end

    local line = {
        Name = pack.lineName or pack.name or id,
        NameEn = pack.lineName or pack.name or id,
        Loop = pack.loop == true,
        LED = pack.led or {5, 10, 5, 5, 5},
        MEXRPIPackID = id
    }
    for i, station in ipairs(stations) do
        if station.id == nil or not isstring(station.name) then return end
        local nextStation = stations[i % #stations + 1]
        local previousStation = stations[(i - 2) % #stations + 1]
        local arrivalKey = "station_" .. tostring(station.id)
        local arrival = Announcement(pack, {"arr"}, arrivalKey, false)
        local terminal = Announcement(pack, {"arr"}, arrivalKey, true)
        local forward = Announcement(pack, {"doors_closing", "next"},
            "station_" .. tostring(nextStation.id), false)
        local reverse = Announcement(pack, {"doors_closing", "next"},
            "station_" .. tostring(previousStation.id), false)

        line[i] = {
            station.id, station.name, station.name,
            arr = {arrival, table.Copy(arrival)},
            dep = {forward, reverse},
            arrlast = {terminal, table.Copy(terminal)}
        }
    end
    return {line}
end

function API.TryRegister()
    if not Metrostroi or not isfunction(Metrostroi.SetRRIAnnouncer) then return end
    local id, pack = API.CurrentPack()
    if not id then return end

    local current = Metrostroi.RRISetup
    -- Metrostroi's RRI is one cassette per map, not a selectable ASNP list.
    -- Avoid re-registering every second unless a map script replaces it.
    if istable(current) and istable(current[1])
        and current[1].MEXRPIPackID == id then
        API.ActivePack = id
        return
    end

    local routes = BuildRoutes(id, pack)
    if not istable(routes) or not istable(routes[1]) then return end
    routes[1].MEXRPIPackID = id
    Metrostroi.SetRRIAnnouncer(SoundTable(pack), routes)
    API.ActivePack = id
    print("[MEX RPI] Registered " .. id .. " (" .. #routes[1]
        .. " stations) on " .. game.GetMap())
end

function API.PrintStatus()
    local id, pack = API.CurrentPack()
    local line = Metrostroi and Metrostroi.RRISetup and Metrostroi.RRISetup[1]
    local active = id ~= nil and istable(line) and line.MEXRPIPackID == id
    print("[MEX RPI] map=" .. tostring(game.GetMap()) ..
        " | pack=" .. tostring(id or "none") ..
        " | active=" .. tostring(active))
    if active then
        print("[MEX RPI] line=" .. tostring(line.Name) ..
            " | stations=" .. #line ..
            " | sounds=" .. table.Count(pack.sounds or {}))
    end
    for path in pairs(API.MissingSounds) do
        print("[MEX RPI] missing: " .. path)
    end
end

concommand.Add("mex_rpi_status", API.PrintStatus)

-- The addon supplies only lua/mex_rpi/lines/*.lua, like MEX ASNP packs.
timer.Create("MEXRPI_Discover", 1, 0, function()
    local files = file.Find("mex_rpi/lines/*.lua", "LUA") or {}
    table.sort(files)
    for _, name in ipairs(files) do
        local path = "mex_rpi/lines/" .. name
        if not API.LoadedFiles[path] then
            if SERVER then AddCSLuaFile(path) end
            local ok, err = pcall(include, path)
            if ok then
                API.LoadedFiles[path] = true
            else
                ErrorNoHalt("[MEX RPI] " .. path .. ": " .. tostring(err) .. "\n")
            end
        end
    end
end)

timer.Create("MEXRPI_Register", 1, 0, API.TryRegister)
hook.Add("InitPostEntity", "MEXRPI_Init", function()
    timer.Simple(0, API.TryRegister)
end)
