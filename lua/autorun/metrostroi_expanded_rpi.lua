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

    local continuous = pack.loop == true and pack.continuousLoop == true
    local line = {
        Name = pack.lineName or pack.name or id,
        NameEn = pack.lineName or pack.name or id,
        Loop = pack.loop == true,
        ContinuousLoop = continuous,
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
            -- No selectable terminal for a continuous circle (Depo is a stop).
            arrlast = not continuous and {terminal, table.Copy(terminal)} or nil
        }
    end
    return {line}
end

-- RRI stores a reference to the map-wide route table when the train first
-- initializes. SetRRIAnnouncer replaces that table, so existing trains otherwise
-- keep playing old routes (e.g. Luka -> Centrum, skipping Depo).
function API.RefreshTrainTables()
    if not Metrostroi or not istable(Metrostroi.RRISetup) then return end
    local route=Metrostroi.RRISetup[1]
    if not istable(route) or not route.MEXRPIPackID then return end
    for _,train in ipairs(ents.FindByClass("gmod_subway_*")) do
        local rri=train.RRI
        -- A train with its own AnnTable is not using map-wide RRI cassettes.
        if rri and not rri.AnnTable and rri.CurrentTable ~= Metrostroi.RRISetup then
            rri.CurrentTable=Metrostroi.RRISetup
            rri.Line=math.Clamp(tonumber(rri.Line) or 1,1,#Metrostroi.RRISetup)
            local line=rri.CurrentTable[rri.Line]
            if line and (not isnumber(rri.Station) or rri.Station<1 or rri.Station>#line) then
                rri.Station=1
                rri.Arrived=true
            end
        end
    end
end

-- Stock RRI advances on button presses, not on a map station detector. Its
-- end-of-line handling differs across Metrostroi versions. For continuous
-- circles the state must always alternate departure -> arrival, wrapping
-- modulo the station count with no terminal or jump over station 1 (Depo).
local function PatchCircularRRI(system)
    if not system or not isfunction(system.Trigger) or system.MEXRPICircularWrapped then return end
    local original=system.Trigger
    system.Trigger=function(self,name,value,...)
        local train=self.Train
        local line=self.CurrentTable and self.CurrentTable[self.Line]
        if not line or not line.Loop or not line.ContinuousLoop
            or not line.MEXRPIPackID or not IsValid(train) then
            return original(self,name,value,...)
        end
        local press=value and value>0 and self.Power
            and (name=="R_Program1" or name=="R_Program1H"
                or name=="SB10" or name=="SB20")
        if not press then return original(self,name,value,...) end
        local before=self.Station
        local arrived=self.Arrived
        if not isnumber(before) or before<1 or before>#line then
            self.Station=1
            self.Arrived=true
            before=1
            arrived=true
        end
        local expected=arrived
            and (before+(self.Path and -1 or 1)-1)%#line+1 or before
        local result=original(self,name,value,...)
        if self.Station~=expected or self.Arrived==arrived then
            self.Station=expected
            self.Arrived=not arrived
            print("[MEX RPI] Fixed circular step "..before.." -> "..expected)
        end
        return result
    end
    system.MEXRPICircularWrapped=true
end

timer.Create("MEXRPI_CircularTrains",1,0,function()
    if not Metrostroi or not Metrostroi.RRISetup then return end
    if Metrostroi.BaseSystems then PatchCircularRRI(Metrostroi.BaseSystems["81_71_RRI"]) end
    for _,train in ipairs(ents.FindByClass("gmod_subway_*")) do
        if train.RRI then PatchCircularRRI(train.RRI) end
    end
end)

function API.TryRegister()
    if not Metrostroi or not isfunction(Metrostroi.SetRRIAnnouncer) then return end
    local id, pack = API.CurrentPack()
    if not id then return end

    local routes = BuildRoutes(id, pack)
    if not istable(routes) or not istable(routes[1]) then return end

    -- Do not trust only the pack ID: a previous map/session may still have
    -- the old non-continuous route that ended at Luka and skipped Depo.
    local current = Metrostroi.RRISetup
    local old = istable(current) and current[1]
    local new = routes[1]
    local same = istable(old) and old.MEXRPIPackID == id
        and old.Loop == new.Loop
        and old.ContinuousLoop == new.ContinuousLoop and #old == #new
    if same then
        for i=1,#new do
            if not old[i] or old[i][1] ~= new[i][1] then
                same=false
                break
            end
            for direction=1,2 do
                local a=old[i].dep and old[i].dep[direction]
                local b=new[i].dep and new[i].dep[direction]
                local aa=old[i].arr and old[i].arr[direction]
                local bb=new[i].arr and new[i].arr[direction]
                if not istable(a) or not istable(b) or not istable(aa) or not istable(bb)
                    or table.concat(a,"|") ~= table.concat(b,"|")
                    or table.concat(aa,"|") ~= table.concat(bb,"|") then
                    same=false
                    break
                end
            end
            if not same then break end
        end
    end
    if same then
        API.ActivePack=id
        API.RefreshTrainTables()
        return
    end
    routes[1].MEXRPIPackID = id
    Metrostroi.SetRRIAnnouncer(SoundTable(pack), routes)
    API.ActivePack = id
    API.RefreshTrainTables()
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

-- Inspect what the *installed* Metrostroi cassette would play, not merely
-- the content addon definition. Useful when an old map config skips Depo.
concommand.Add("mex_rpi_route_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local id,pack=API.CurrentPack()
    local route=Metrostroi and Metrostroi.RRISetup and Metrostroi.RRISetup[1]
    if not id or not istable(route) then
        print("[MEX RPI] No registered route on this map")
        return
    end
    print("[MEX RPI] "..id.." loop="..tostring(route.Loop)
        .." continuous="..tostring(route.ContinuousLoop))
    for i,station in ipairs(route) do
        local forward=station.dep and station.dep[1] or {}
        local arrive=station.arr and station.arr[1] or {}
        local wave=pack.soundRoot.."/"..tostring(pack.sounds
            and pack.sounds["station_"..tostring(station[1])]
            and pack.sounds["station_"..tostring(station[1])][1] or "")
        print(string.format("[MEX RPI] %d %s (%d) arr=%s dep=%s wav=%s",
            i,tostring(station[2]),station[1],table.concat(arrive,","),
            table.concat(forward,","),tostring(file.Exists("sound/"..wave,"GAME"))))
    end
end)

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
