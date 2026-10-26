-- Universal Metrostroi Expanded ASNP pack loader.
-- Packs are supplied by independent addons; this core owns registration.
MEXASNP = MEXASNP or {}
local API = MEXASNP
API.Languages = API.Languages or {}
API.Packs = API.Packs or {}

function API.RegisterLanguage(code, dictionary)
    assert(isstring(code) and istable(dictionary), "Invalid ASNP language")
    API.Languages[code] = dictionary
end

function API.Translate(code, phrase)
    local lang = API.Languages[code] or API.Languages.en or {}
    return lang[phrase] or (API.Languages.en and API.Languages.en[phrase]) or phrase
end

function API.RegisterPack(id, definition)
    assert(isstring(id) and istable(definition), "Invalid ASNP pack")
    API.Packs[id] = definition
end

local function Read32(data, offset)
    local a,b,c,d = string.byte(data,offset,offset+3)
    if not d then return end
    return a+b*256+c*65536+d*16777216
end

API.DurationCache=API.DurationCache or {}
function API.AudioDuration(path, fallback)
    local cached=API.DurationCache[path]
    if cached then return cached end
    local data = file.Read("sound/"..path,"GAME")
    if not data or data:sub(1,4)~="RIFF" or data:sub(9,12)~="WAVE" then return fallback end
    local pos,rate,bytes=13
    while pos+7<=#data do
        local name,size=data:sub(pos,pos+3),Read32(data,pos+4)
        if not size then break end
        local body=pos+8
        if name=="fmt " and size>=16 then rate=Read32(data,body+8) end
        if name=="data" then bytes=size end
        if rate and bytes then break end
        pos=body+size+(size%2)
    end
    local duration=rate and rate>0 and bytes and (bytes/rate) or nil
    if duration and duration>0 then API.DurationCache[path]=duration end
    return duration or fallback
end

-- A client can have a different set/order of legacy Metrostroi announcers
-- than a dedicated server. The server's Announcer NW2 index is authoritative.
API.ServerIndices=API.ServerIndices or {}
API.ServerDefinitions=API.ServerDefinitions or {}
local function PinServerIndex(id,pack)
    if not CLIENT then return end
    local expected=API.ServerIndices[id]
    if not expected or expected<1
        or not Metrostroi or not istable(Metrostroi.ASNPSetup)
        or not istable(Metrostroi.AnnouncementsASNP) then return end

    -- Replicate the route, not just the numeric index. Map-provided Metrostroi
    -- announcers are not automatically synchronized on multiplayer clients.
    -- In particular, a player lacking the content Lua sees no ASNP option at
    -- all, or the same ID selecting a completely different Russian announcer.
    local network=API.ServerDefinitions[id]
    if network and istable(network.routes) and istable(network.sounds) then
        Metrostroi.ASNPSetup[expected]=network.routes
        Metrostroi.AnnouncementsASNP[expected]=network.sounds
        pack.registeredID=expected
        return
    end

    if not pack.registeredID then return end
    local current=pack.registeredID
    local route=Metrostroi.ASNPSetup[current]
    local sounds=Metrostroi.AnnouncementsASNP[current]
    if not route or route.name~=pack.name or not sounds then return end
    if expected~=current then
        Metrostroi.ASNPSetup[expected]=route
        Metrostroi.AnnouncementsASNP[expected]=sounds
    end
    pack.registeredID=expected
end

if SERVER then
    util.AddNetworkString("MEXASNP_IndexSync")
    util.AddNetworkString("MEXASNP_RequestSync")
    API.SentResources=API.SentResources or {}
    local function SendIndexSync(ply)
        if not Metrostroi then return end
        local map=string.lower(game.GetMap() or "")
        for id,pack in pairs(API.Packs) do
            local matching=false
            for _,prefix in ipairs(pack.maps or {}) do
                if string.StartWith(map,string.lower(prefix)) then matching=true break end
            end
            local setup=Metrostroi.ASNPSetup and Metrostroi.ASNPSetup[pack.registeredID or -1]
            local sounds=Metrostroi.AnnouncementsASNP
                and Metrostroi.AnnouncementsASNP[pack.registeredID or -1]
            if matching and pack.registeredID and istable(setup) and istable(sounds) then
                net.Start("MEXASNP_IndexSync")
                net.WriteString(id)
                net.WriteUInt(pack.registeredID,16)
                net.WriteTable(setup)
                net.WriteTable(sounds)
                net.WriteString(pack.name or id)
                net.WriteString(pack.language or "en")
                -- Content-only packs (including Adamovian Metro) may not
                -- have their Lua files on remote clients. The translated UI
                -- needs the server's actual language dictionary too.
                local dictionary=API.Languages[pack.language or "en"]
                net.WriteTable(istable(dictionary) and dictionary or {})
                if IsValid(ply) then net.Send(ply) else net.Broadcast() end
            end
        end
    end
    -- Players who connect later and clients whose Lua loads slowly both
    -- receive a fresh mapping. No player action or manual reload required.
    hook.Add("PlayerInitialSpawn","MEXASNP_SendIndexOnJoin",function(ply)
        timer.Simple(3,function() if IsValid(ply) then SendIndexSync(ply) end end)
    end)
    -- A client may initialize MEX after PlayerInitialSpawn. Allow an explicit
    -- late request instead of depending on a long repeating broadcast.
    net.Receive("MEXASNP_RequestSync",function(_,ply)
        if not IsValid(ply) then return end
        local now=CurTime()
        if (ply.MEXASNPNextSync or 0)>now then return end
        ply.MEXASNPNextSync=now+2
        SendIndexSync(ply)
    end)
    timer.Create("MEXASNP_IndexBroadcast",8,0,function() SendIndexSync() end)
else
    net.Receive("MEXASNP_IndexSync",function()
        local id=net.ReadString()
        local index=net.ReadUInt(16)
        -- Older MEX servers only transmit the numeric index.
        if net.BytesLeft()<=0 then
            API.ServerIndices[id]=index
            if API.Packs[id] then PinServerIndex(id,API.Packs[id]) end
            return
        end
        local setup=net.ReadTable()
        local sounds=net.ReadTable()
        local name=net.ReadString()
        local language=net.ReadString()
        local dictionary={}
        if net.BytesLeft()>0 then dictionary=net.ReadTable() end
        if index<1 or not istable(setup) or not istable(sounds) then return end
        API.ServerIndices[id]=index
        API.ServerDefinitions[id]={routes=setup,sounds=sounds}
        if isstring(language) and language~="" and istable(dictionary)
            and next(dictionary)~=nil then
            API.RegisterLanguage(language,dictionary)
        end
        local pack=API.Packs[id]
        if not pack then
            -- The pack's Lua may exist only on the dedicated server. The
            -- server advertises it directly to every connected player's UI.
            pack={name=name,maps={game.GetMap()}}
            API.Packs[id]=pack
        end
        -- Do not retain an old 'en' fallback from a previous map/session.
        pack.name=name
        pack.language=language
        PinServerIndex(id,pack)
    end)
    local attempts=0
    timer.Create("MEXASNP_RequestServerState",3,0,function()
        if next(API.ServerDefinitions)~=nil then
            timer.Remove("MEXASNP_RequestServerState")
            return
        end
        attempts=attempts+1
        if attempts>30 then timer.Remove("MEXASNP_RequestServerState");return end
        net.Start("MEXASNP_RequestSync")
        net.SendToServer()
    end)
end

function API.TryRegister()
    if not Metrostroi or not isfunction(Metrostroi.AddANSPAnnouncer)
        or not istable(Metrostroi.ASNPSetup) or not istable(Metrostroi.AnnouncementsASNP) then return end
    local map=game.GetMap():lower()
    local ids=table.GetKeys(API.Packs)
    table.sort(ids) -- Stable ordering of custom IDs on server and all clients.
    for _,id in ipairs(ids) do
        local pack=API.Packs[id]
        local matches=(not pack.maps) or false
        for _,prefix in ipairs(pack.maps or {}) do
            if string.StartWith(map,prefix:lower()) then matches=true break end
        end
        if matches then
            if CLIENT and API.ServerDefinitions[id] then
                -- The server-selected ID and sounds are authoritative.
                -- Do not re-register the client copy under a different ID.
                PinServerIndex(id,pack)
            else
            -- Workshop content is not automatically transmitted when an addon
            -- was manually installed on a dedicated server. Send the WAVs too.
            if SERVER and isstring(pack.soundRoot) then
                for _,entry in pairs(pack.sounds or {}) do
                    if istable(entry) and isstring(entry[1]) then
                        local wav="sound/"..pack.soundRoot.."/"..entry[1]
                        if not API.SentResources[wav] and file.Exists(wav,"GAME") then
                            resource.AddFile(wav)
                            API.SentResources[wav]=true
                        end
                    end
                end
            end
            local sounds={click1=0.01,click2=0.01,click3=0.01}
            for key,sound in pairs(pack.sounds or {}) do
                local path=pack.soundRoot.."/"..sound[1]
                if file.Exists("sound/"..path,"GAME") then
                    sounds[key]={path,API.AudioDuration(path,sound[2] or 2)+0.25}
                else
                    -- An unavailable sound must never be queued as a missing key.
                    -- Metrostroi's Announcer accepts a numeric silent delay.
                    sounds[key]=0.01
                    API.MissingSoundWarnings=API.MissingSoundWarnings or {}
                    if not API.MissingSoundWarnings[path] then
                        API.MissingSoundWarnings[path]=true
                        print("[MEX ASNP] Missing sound: "..path..
                            " (muted; install the WAV in sound/)")
                    end
                end
            end
            local routes=isfunction(pack.routes) and pack.routes(pack) or pack.routes
            if not routes and istable(pack.stations) then
                local continuous = pack.loop == true and pack.continuousLoop == true
                local line={Name=pack.lineName or pack.name,Loop=pack.loop or false,
                    ContinuousLoop=continuous,LED=pack.led or {5,10,5,5,5}}
                for index,station in ipairs(pack.stations) do
                    local prev=pack.stations[(index-2)%#pack.stations+1]
                    local nextStation=pack.stations[index%#pack.stations+1]
                    local current="station_"..station.id
                    local function Sequence(keys,stationKey)
                        local seq={}
                        if pack.sounds.gong_1 then seq[#seq+1]="gong_1" end
                        for _,key in ipairs(keys) do
                            if pack.sounds[key] then seq[#seq+1]=key end
                        end
                        if stationKey and pack.sounds[stationKey] then seq[#seq+1]=stationKey end
                        return seq
                    end
                    local arr=Sequence({"arr"},current)
                    local depNext=Sequence({"doors_closing","next"},"station_"..nextStation.id)
                    local depPrev=Sequence({"doors_closing","next"},"station_"..prev.id)
                    local final=Sequence({"arr"},current)
                    if pack.sounds.last then final[#final+1]="last" end
                    line[index]={station.id,station.name,station.name,
                        arr={arr,table.Copy(arr)},
                        dep={depNext,depPrev},
                        -- Circular routes have no terminal or final-stop phrase.
                        -- Metrostroi uses arrlast to offer a selectable endpoint,
                        -- which otherwise silently skips the Depo stop on wrap.
                        arrlast=not continuous and {final,table.Copy(final)} or nil
                    }
                end
                routes={line}
            end
            if istable(routes) then
                local present
                for index,data in ipairs(Metrostroi.ASNPSetup) do
                    if data.name==pack.name then present=index break end
                end
                -- Hot reload and saved spawner indexes may keep an older ASNP
                -- route even after pack files were updated. Always compare the
                -- actual registered route rather than trusting pack._applied.
                local oldSetup=present and Metrostroi.ASNPSetup[present]
                local oldRoute=oldSetup and oldSetup[1]
                local newRoute=routes[1]
                local matches=oldRoute and newRoute
                    and oldRoute.Loop==newRoute.Loop
                    and oldRoute.ContinuousLoop==newRoute.ContinuousLoop
                    and #oldRoute==#newRoute
                if matches then
                    for n=1,#newRoute do
                        if not oldRoute[n] or oldRoute[n][1]~=newRoute[n][1]
                            or not oldRoute[n].arr or not oldRoute[n].dep then
                            matches=false
                            break
                        end
                        local a=oldRoute[n]
                        local b=newRoute[n]
                        for direction=1,2 do
                            if not istable(a.arr[direction]) or not istable(a.dep[direction])
                                or table.concat(a.arr[direction],"|")~=table.concat(b.arr[direction],"|")
                                or table.concat(a.dep[direction],"|")~=table.concat(b.dep[direction],"|") then
                                matches=false
                                break
                            end
                        end
                        if not matches then break end
                    end
                end
                if matches then
                    local oldSounds=Metrostroi.AnnouncementsASNP and Metrostroi.AnnouncementsASNP[present]
                    if not oldSounds then
                        matches=false
                    else
                        for key,sound in pairs(sounds) do
                            local registered=oldSounds[key]
                            if istable(sound) then
                                if not istable(registered) or registered[1]~=sound[1] then
                                    matches=false
                                    break
                                end
                            elseif sound~=registered then
                                matches=false
                                break
                            end
                        end
                    end
                end
                if not pack._applied or not matches then
                    Metrostroi.AddANSPAnnouncer(pack.name,sounds,routes)
                    pack._applied=true
                end
                for index,data in ipairs(Metrostroi.ASNPSetup) do
                    if data.name==pack.name then
                        pack.registeredID=index
                        break
                    end
                end
                PinServerIndex(id,pack)
            end
            end -- local registration is skipped once server config has arrived
        end
    end
end

-- Show the actual registered route and station WAVs. This reveals stale
-- Metrostroi configs and files that exist in Git but not in installed addons.
concommand.Add("mex_asnp_route_status", function(ply)
    if SERVER and IsValid(ply) and not ply:IsAdmin() then return end
    local map=string.lower(game.GetMap() or "")
    for id,pack in pairs(API.Packs) do
        local relevant=false
        for _,prefix in ipairs(pack.maps or {}) do
            if string.StartWith(map,string.lower(prefix)) then relevant=true break end
        end
        if relevant then
            local index=API.ServerIndices[id] or pack.registeredID
            if not index then
                for i,setup in ipairs(Metrostroi and Metrostroi.ASNPSetup or {}) do
                    if setup.name==pack.name then index=i break end
                end
            end
            local setup=index and Metrostroi.ASNPSetup[index]
            local line=setup and setup[1]
            print("[MEX ASNP] pack="..id.." index="..tostring(index)
                .." serverIndex="..tostring(API.ServerIndices[id] or (SERVER and pack.registeredID) or "?")
                .." loop="..tostring(line and line.Loop)
                .." continuous="..tostring(line and line.ContinuousLoop))
            if istable(line) then
                for i,station in ipairs(line) do
                    local arrive=station.arr and station.arr[1] or {}
                    local depart=station.dep and station.dep[1] or {}
                    local entry=pack.sounds and pack.sounds["station_"..tostring(station[1])]
                    local wav=entry and (pack.soundRoot.."/"..entry[1])
                    local soundIndex=Metrostroi.AnnouncementsASNP[index]
                    local registered=soundIndex and soundIndex["station_"..tostring(station[1])]
                    print(string.format("[MEX ASNP] %d %s (%d) arr=%s dep=%s wav=%s registered=%s",
                        i,tostring(station[2]),station[1],table.concat(arrive,","),
                        table.concat(depart,","),tostring(wav and file.Exists("sound/"..wav,"GAME")),
                        tostring(istable(registered) and registered[1] or registered)))
                end
            end
            for _,train in ipairs(ents.FindByClass("gmod_subway_*")) do
                local sys=train.ASNP
                if sys and train:GetNW2Int("Announcer",1)==index then
                    print("[MEX ASNP] train="..train:EntIndex()
                        .." stationIndex="..tostring(sys.Station)
                        .." arrived="..tostring(sys.Arrived)
                        .." pathReverse="..tostring(sys.Path)
                        .." first="..tostring(sys.FirstStation)
                        .." last="..tostring(sys.LastStation)
                        .." state="..tostring(sys.State))
                end
            end
        end
    end
end)

-- The same command works in a listen server, on a dedicated server
-- console, and on a connected client (whose ID may have been reconciled).
concommand.Add("mex_announcer_mp_status",function(ply)
    if SERVER and IsValid(ply) and not ply:IsAdmin() then return end
    print("[MEX AUDIO] realm="..(SERVER and "server" or "client")
        .." map="..tostring(game.GetMap())
        .." ASNPsync="..tostring(CLIENT and next(API.ServerDefinitions)~=nil or SERVER)
        .." adLang="..tostring(API.Languages.ad and table.Count(API.Languages.ad) or 0))
    for id,pack in pairs(API.Packs) do
        if pack.registeredID then
            print("[MEX AUDIO] pack="..id.." localIndex="..pack.registeredID
                .." serverIndex="..tostring(API.ServerIndices[id] or (SERVER and pack.registeredID) or "?"))
        end
    end
    local count=0
    for _,train in ipairs(ents.FindByClass("gmod_subway_*")) do
        if train.ASNP or train.RRI then
            count=count+1
            if count>12 then print("[MEX AUDIO] ...");break end
            local asnp=train.ASNP
            local rri=train.RRI
            print("[MEX AUDIO] train="..train:EntIndex()
                .." class="..train:GetClass()
                .." announcer="..train:GetNW2Int("Announcer",-1)
                .." ASNP="..tostring(asnp and asnp.Station)
                .." arrived="..tostring(asnp and asnp.Arrived)
                .." RRI="..tostring(rri and rri.Station)
                .." arrived="..tostring(rri and rri.Arrived)
                .." annType="..train:GetNW2Int("AnnType",-1)
                .." rriLine="..train:GetNW2Int("RRI:Line",-1)
                .." rriCassette="..tostring(Metrostroi and Metrostroi.RRISetup
                    and Metrostroi.RRISetup[1] and Metrostroi.RRISetup[1].Name)
                .." routeCurrent="..tostring(rri and Metrostroi
                    and rri.CurrentTable==Metrostroi.RRISetup))
        end
    end
end)

-- Built-in languages are part of MEX, not the map content addons.
for _,code in ipairs({"en","cs"}) do
    local path="metrostroi_expanded/asnp/languages/"..code..".lua"
    if SERVER then AddCSLuaFile(path) end
    include(path)
end


-- Canonical UI marks. Only this file knows Metrostroi's source-language strings.
-- Long phrases are matched before fragments, so route numbers remain intact.
API.Marks = {
    ["Карта не поддерживается"]="error.map",
    ["следующей цифре"]="digit.next",
    ["предыдущей цифре"]="digit.previous",
    ["нажмите \"+\" или \"-\""]="action.plusminus",
    ["Нажмите \"+\" или \"-\""]="action.plusminus",
    ["Для возврата к"]="action.back",
    ["Маршрут"]="route.label",
    ["Путь"]="track.label",
    ["первый"]="ordinal.first",
    ["Конечная станция"]="station.terminal",
    ["Проверьте данные"]="action.verify",
    ["Нажмите \"MENU\""]="action.menu",
    ["нажмите \"МЕНЮ\""]="action.menu",
    ["нажмите \"MENU\""]="action.menu",
    ["для начала настройки"]="action.setup",
    ["Выбор N маршрута"]="route.number",
    ["Номер маршрута:"]="route.number",
    ["Номер маршрута"]="route.number",
    ["Выбор линии (кол)"]="line.loop",
    ["Выбор линии   -"]="line.choose",
    ["Выбор пути"]="track.choose",
    ["Выбор ст. оборота -"]="station.terminal",
    ["Текущая станция   -"]="station.current",
    ["Выбор приб / отпр"]="arrival.departure",
    ["ПЕРЕД ОТПРАВЛЕНИЕМ"]="departure.before",
    ["НАЖМИ КНОПКУ   ОБЪЯВИТЬ"]="action.announce",
    ["<<<  ИДЕТ ОБЪЯВЛЕНИЕ >>>"]="announcement.playing",
    ["<<<  ИДЕТ ОБЪЯВЛЕНИЕ  >>>"]="announcement.playing",
    ["<<< ИДЕТ ОБЪЯВЛЕНИЕ >>>"]="announcement.playing",
    ["Кольцевой"]="line.circular",
    ["Нет названия"]="error.unnamed",
    ["Отпр."]="departure.short",
    ["Приб."]="arrival.short",
    ["От:"]="from",
    ["До:"]="to",
    ["следующей инфе"]="info.next",
    ["предыдущей инфе"]="info.previous",
    ["Для ввода номера"]="action.number",
    ["Для перехода к"]="action.go",
    ["Для выбора +"]="action.plus",
    ["Для выбора -"]="action.minus",
    ["Для настройки выбора"]="action.choose",
    ["Для подтверждения"]="action.confirm",
    ["Для отмены"]="action.cancel",
    ["Для подтверждения выбора"]="action.confirm",
    ["Бл.Л"]="door.left",
    ["Бл.П"]="door.right",
    ["Выбор"]="choose",
    ["станция"]="station",
    ["Станция"]="station",
    ["Меню"]="menu",
    ["МЕНЮ"]="menu",
    ["Client error"]="error.client",
    ["No announcer at client"]="error.announcer",
    ["No line at client"]="error.line"
}
API.MarkList = {}
for original,mark in pairs(API.Marks) do
    API.MarkList[#API.MarkList+1]={original,mark}
end
table.sort(API.MarkList,function(a,b) return #a[1]>#b[1] end)

function API.ResolveLanguage(code,mark)
    local language=API.Languages[code] or API.Languages.en or {}
    local fallback=API.Languages.en or {}
    return language[mark] or fallback[mark] or mark
end

function API.ParseDisplay(text)
    if not isstring(text) then return text end
    local mark=API.Marks[text]
    if mark then return mark end
    -- Dynamic data is preserved; known fragments become marks in place.
    local replacements={}
    local count=0
    local result=text
    for _,pair in ipairs(API.MarkList) do
        if result:find(pair[1],1,true) then
            count=count+1
            local token=string.format("\1MEX%d\2",count)
            result=string.Replace(result,pair[1],token)
            replacements[token]=pair[2]
        end
    end
    return result,replacements
end

function API.LocalizeDisplay(code,value)
    if not isstring(value) then return value end
    local parsed,tokens=API.ParseDisplay(value)
    if not tokens then return API.ResolveLanguage(code,parsed) end
    for token,mark in pairs(tokens) do
        parsed=string.Replace(parsed,token,API.ResolveLanguage(code,mark))
    end
    -- Unsupported Cyrillic texts are never shown as Russian on custom ASNP.
    -- Warn once so each new phrase can be assigned a stable semantic mark.
    if parsed:find("[\208-\211][\128-\191]") then
        API.UnknownPhrases=API.UnknownPhrases or {}
        if not API.UnknownPhrases[value] then
            API.UnknownPhrases[value]=true
            print("[MEX ASNP] Unmapped source text: "..value)
        end
        return API.ResolveLanguage(code,"error.unknown")
    end
    return parsed
end

local function SelectedPack(train)
    if not IsValid(train) or not Metrostroi or not Metrostroi.ASNPSetup then return end
    local idx=train:GetNW2Int("Announcer",1)
    local setup=Metrostroi.ASNPSetup[idx]
    if not setup then return end
    local map=string.lower(game.GetMap() or "")
    for _,pack in pairs(API.Packs) do
        if pack.name==setup.name then
            for _,prefix in ipairs(pack.maps or {}) do
                if string.StartWith(map,string.lower(prefix)) then return pack end
            end
        end
    end
end

-- Program II is optional. Stock 81-71 ASNP dereferences spec_wait without
-- checking whether a custom announcer provides it, causing errors or noise.
local function GetContinuousLine(system)
    local train=system and system.Train
    if not IsValid(train) or not Metrostroi or not Metrostroi.ASNPSetup then return end
    local setup=Metrostroi.ASNPSetup[train:GetNW2Int("Announcer",1)]
    local line=setup and setup[system.Line]
    if line and line.Loop and line.ContinuousLoop and #line>1 then return line end
end

local function WrapProgramII(system)
    if not system or not isfunction(system.Trigger) or system.MEXASNPProgramIIWrapped then return end
    local original=system.Trigger
    system.Trigger=function(self,name,value,...)
        local train=self.Train
        local line=GetContinuousLine(self)
        if line and self.State==7 then
            self.FirstStation=0
            self.LastStation=0
        end

        if value and (name=="R_Program2" or name=="R_Program2H") then
            local pack=SelectedPack(train)
            if pack then
                local setup=Metrostroi and Metrostroi.ASNPSetup
                local selected=setup and setup[train:GetNW2Int("Announcer",1)]
                local selectedLine=selected and selected[self.Line]
                if not selectedLine or (not selectedLine.spec_wait and not selectedLine.spec_last) then return end
                if self.State==7 and not selectedLine.spec_wait then return end
            end
        end

        local result=original(self,name,value,...)
        -- Stock Metrostroi's R_ASNPPath resets FirstStation/LastStation
        -- AFTER our pre-check. Repair those flags after ANY button as well.
        if GetContinuousLine(self) and self.State==7 then
            self.FirstStation=0
            self.LastStation=0
            self.AnnounceLast=false
        end
        return result
    end
    system.MEXASNPProgramIIWrapped=true
end

-- Validate the actual station advance after each finished announcement.
-- Preserve both arrival and departure at the first station when wrapping
-- across the end of a circular line (104 Luka -> 101 Depo -> 102 Centrum).
local function WrapContinuousNext(system)
    if not system or not isfunction(system.Next)
        or system.MEXASNPContinuousNextWrapped then return end
    local original=system.Next
    system.Next=function(self,...)
        local line=GetContinuousLine(self)
        if not line or self.State~=7 then return original(self,...) end

        local previous=self.Station
        local wasArrived=self.Arrived
        local expected=previous
        if wasArrived and type(previous)=="number" and previous>=1 and previous<=#line then
            expected=previous+(self.Path and -1 or 1)
            if expected<1 then expected=#line end
            if expected>#line then expected=1 end
        end
        local result=original(self,...)
        if type(expected)=="number" and previous>=1 and previous<=#line
            and (self.Station~=expected or self.Arrived==wasArrived) then
            print("[MEX ASNP] Corrected continuous-loop step "
                ..tostring(previous).." -> "..tostring(expected))
            self.Station=expected
            self.Arrived=not wasArrived
            if isfunction(self.UpdateBoards) then self:UpdateBoards() end
        end
        return result
    end
    system.MEXASNPContinuousNextWrapped=true
end

timer.Create("MEXASNP_ProgramII",1,0,function()
    if Metrostroi and Metrostroi.BaseSystems then
        local base=Metrostroi.BaseSystems["81_71_ASNP"]
        WrapProgramII(base)
        WrapContinuousNext(base)
    end
    for _,train in ipairs(ents.FindByClass("gmod_subway_*")) do
        if train.ASNP then
            WrapProgramII(train.ASNP)
            WrapContinuousNext(train.ASNP)
        end
    end
end)

if CLIENT then
    local function WrapPrinter(system)
        if not system or not isfunction(system.PrintText) or system.MEXASNPWrapped then return end
        local original=system.PrintText
        system.PrintText=function(self,x,y,value,inverse)
            local pack=SelectedPack(self.Train)
            if pack then value=API.LocalizeDisplay(pack.language or "en",value) end
            return original(self,x,y,value,inverse)
        end
        system.MEXASNPWrapped=true
    end
    timer.Create("MEXASNP_Localize",1,0,function()
        if Metrostroi and Metrostroi.BaseSystems then WrapPrinter(Metrostroi.BaseSystems["81_71_ASNP"]) end
        for _,train in ipairs(ents.FindByClass("gmod_subway_*")) do
            if train.ASNP then WrapPrinter(train.ASNP) end
        end
    end)
end

-- Stock 81_71_Announcer broadcasts speech via an unreliable net message.
-- Small packet loss on a busy multiplayer server can skip an entire station.
-- Keep Metrostroi's native playback protocol, but send MEX speech and _STOP
-- reliably. Vanilla announcers still use their original WriteMessage method.
if SERVER then
    local function IsCustomPlayback(train)
        local device=train and train.Announcer
        if not device then return false end
        if device.AnnTable=="AnnouncementsASNP" then
            local setup=Metrostroi and Metrostroi.ASNPSetup
                and Metrostroi.ASNPSetup[train:GetNW2Int("Announcer",1)]
            if not setup then return false end
            for _,pack in pairs(API.Packs) do
                if pack.name==setup.name then return true end
            end
        elseif device.AnnTable=="AnnouncementsRRI" then
            local line=Metrostroi and Metrostroi.RRISetup and Metrostroi.RRISetup[1]
            return line and line.MEXRPIPackID~=nil or false
        end
        return false
    end
    local function PatchReliablePlayback(system)
        if not system or not isfunction(system.WriteMessage)
            or system.MEXReliablePlaybackWrapped then return end
        local original=system.WriteMessage
        system.WriteMessage=function(self,msg,...)
            local train=self.Train
            if not IsValid(train) or not IsCustomPlayback(train)
                or not isstring(msg) or not istable(train.WagonList) then
                return original(self,msg,...)
            end
            -- Same entity+string packet as stock Metrostroi, but reliable.
            for _,wagon in ipairs(train.WagonList) do
                if IsValid(wagon) then
                    net.Start("metrostroi_announcer")
                    net.WriteEntity(wagon)
                    net.WriteString(msg)
                    net.Broadcast()
                end
            end
        end
        system.MEXReliablePlaybackWrapped=true
    end
    timer.Create("MEXASNP_ReliableAudio",1,0,function()
        if Metrostroi and Metrostroi.BaseSystems then
            PatchReliablePlayback(Metrostroi.BaseSystems["81_71_Announcer"])
        end
        for _,train in ipairs(ents.FindByClass("gmod_subway_*")) do
            if train.Announcer then PatchReliablePlayback(train.Announcer) end
        end
    end)
end

-- Content discovery is run by MEX; external addons need only provide files.
API.LoadedFiles=API.LoadedFiles or {}
timer.Create("MEXASNP_Discover",1,0,function()
    for _,kind in ipairs({"languages","lines"}) do
        local files=file.Find("mex_asnp/"..kind.."/*.lua","LUA")
        for _,name in ipairs(files or {}) do
            local path="mex_asnp/"..kind.."/"..name
            if not API.LoadedFiles[path] then
                if SERVER then AddCSLuaFile(path) end
                local ok,err=pcall(include,path)
                if ok then API.LoadedFiles[path]=true
                else ErrorNoHalt("[MEX ASNP] "..path..": "..tostring(err).."\n") end
            end
        end
    end
end)

-- Handle both load orders (MEX first or content addon first).
timer.Create("MEXASNP_Register",1,0,API.TryRegister)

-- Universal ASNP support for Metrostroi trains (not Ezh3-specific).
-- The stock spawner reads ENT.Spawner separately in the client and server
-- realms. Only touch classes with an Announcer selector or proven 81_71_ASNP
-- hardware; do not offer ASNP on UPO/RRI-only or otherwise incompatible cabs.
API.ASNPHardwareClasses = API.ASNPHardwareClasses or {}
-- Standard Metrostroi classes confirmed to load the 81_71_ASNP system.
-- Do not infer ASNP compatibility merely from an "Announcer" dropdown:
-- 81-722 has Sarmat UPO, 81-703 has RRI, and 81-718 has ASNP disabled.
local StandardASNPClasses={
    ["gmod_subway_ezh"]=true,
    ["gmod_subway_ezh3"]=true,
    ["gmod_subway_81-717_mvm"]=true,
    ["gmod_subway_81-720"]=true,
}
function API.RegisterASNPTrainClass(class)
    assert(isstring(class) and string.StartWith(class,"gmod_subway_"),
        "ASNP train class name expected")
    API.ASNPHardwareClasses[class]=true
end

local function SupportsASNP(class)
    if API.ASNPHardwareClasses[class] or StandardASNPClasses[class] then return true end
    if scripted_ents and isfunction(scripted_ents.IsBasedOn) then
        for base in pairs(StandardASNPClasses) do
            if scripted_ents.IsBasedOn(class,base) then return true end
        end
    end
    return false
end

local function IsActivePack(pack)
    if not istable(pack) then return false end
    local map = string.lower(game.GetMap() or "")
    for _,prefix in ipairs(pack.maps or {}) do
        if isstring(prefix) and string.StartWith(map,string.lower(prefix)) then
            return true
        end
    end
    return false
end

local function PackIndex(id,pack)
    local index=CLIENT and API.ServerIndices[id] or nil
    index=index or pack.registeredID
    if not isnumber(index) or index<1 then return end
    local tableEntry=Metrostroi and Metrostroi.AnnouncementsASNP
        and Metrostroi.AnnouncementsASNP[index]
    local route=Metrostroi and Metrostroi.ASNPSetup
        and Metrostroi.ASNPSetup[index]
    -- Do not advertise a pack that was not installed at this index. Otherwise
    -- the spawner can select the Russian voice occupying the same number.
    if not istable(tableEntry) or not istable(route)
        or tableEntry.name~=pack.name or route.name~=pack.name then return end
    return index
end

-- Ezh3/81-710 reserve option #1 for their mechanical RRI cassette. Other
-- ASNP-equipped trains (Ezh, 81-717, 81-720, 81-718, addons...) use the
-- announcer's ID directly. Detect the offset by the *native option*, rather
-- than applying it to all "Ezh" or 81-series models.
local function IsCassetteFirst(class,options)
    if class=="gmod_subway_ezh3" or string.find(class,"81%-710") then return true end
    if not istable(options) or not isstring(options[1]) then return false end
    local rri=Metrostroi and isfunction(Metrostroi.GetPhrase)
        and Metrostroi.GetPhrase("Spawner.710.RRI")
    return rri~=nil and options[1]==rri
end

local function CustomChoices(class,original,...)
    local base=isfunction(original) and original(...) or original
    local options=table.Copy(istable(base) and base or {})
    local legacy=IsCassetteFirst(class,options)
    if legacy and options[1]==nil then
        options[1]="RRI: Cassette announcer"
    end
    for id,pack in pairs(API.Packs) do
        if IsActivePack(pack) then
            local idx=PackIndex(id,pack)
            if idx then
                local sound=Metrostroi.AnnouncementsASNP[idx]
                -- ASNP custom voices are intentionally valid for both
                -- ordinary and RIU-filtered ASNP hardware, never RRI mode.
                if not sound.riu and not sound.asnp then
                    options[legacy and idx+1 or idx]=pack.name
                end
            end
        end
    end
    return options
end

local function HasASNPAnnouncer(train)
    return IsValid(train) and train.ASNP~=nil and train.Announcer~=nil
        and train.Announcer.AnnTable=="AnnouncementsASNP"
end

local function DetectASNPClasses()
    for _,train in ipairs(ents.FindByClass("gmod_subway_*")) do
        if HasASNPAnnouncer(train) then
            API.ASNPHardwareClasses[train:GetClass()]=true
        end
    end
end

local function PatchOneSpawner(class,record)
    if not SupportsASNP(class) then return 0 end
    if not istable(record) or not istable(record.Spawner) then return 0 end
    local found=false
    local count=0
    for _,setting in ipairs(record.Spawner) do
        if istable(setting) and setting[1]=="Announcer" and setting[3]=="List" then
            found=true
            local original=setting.MEXASNPOriginal or setting[4]
            if isfunction(original) or istable(original) then
                -- The selector itself is a client-side widget. The server
                -- still runs the train's original setting[6] callback, so all
                -- original spawn conversions and ASNP/RRI mode switches stay.
                if CLIENT and not setting.MEXASNPOriginal then
                    setting.MEXASNPOriginal=original
                    setting[4]=function(...)
                        return CustomChoices(class,original,...)
                    end
                    count=count+1
                end
            end
        end
    end
    if not found and API.ASNPHardwareClasses[class] then
        -- For trains with a permanently fitted ASNP but no announcer menu,
        -- install an ordinary NW2 'Announcer' selection on both realms.
        -- Only do this after an actual spawned train confirms ASNP hardware.
        local entry={
            "Announcer","Spawner.717.Announcer","List",
            function()
                local opts={}
                for idx,sound in pairs(Metrostroi and Metrostroi.AnnouncementsASNP or {}) do
                    if isnumber(idx) and istable(sound) and not sound.riu then
                        opts[idx]=sound.name or tostring(idx)
                    end
                end
                return opts
            end,
        }
        table.insert(record.Spawner,entry)
        if CLIENT then
            entry.MEXASNPOriginal=entry[4]
            local original=entry[4]
            entry[4]=function(...) return CustomChoices(class,original,...) end
        end
        count=count+1
    end
    return count
end

function API.PatchTrainSpawners()
    DetectASNPClasses()
    local count=0
    for class,record in pairs(scripted_ents.GetList() or {}) do
        if isstring(class) and string.StartWith(class,"gmod_subway_")
            and istable(record) and istable(record.t) then
            count=count+PatchOneSpawner(class,record.t)
        end
    end
    return count
end

timer.Create("MEXASNP_Spawners",2,0,API.PatchTrainSpawners)
hook.Add("InitPostEntity","MEXASNP_SpawnerInit",function()
    timer.Simple(0,API.PatchTrainSpawners)
end)

if CLIENT then
    concommand.Add("mex_asnp_spawner_status",function(_,_,args)
        local class=(args and args[1]) or "gmod_subway_ezh3"
        print("[MEX ASNP SPAWNER] map="..tostring(game.GetMap())
            .." class="..class
            .." received="..tostring(next(API.ServerDefinitions)~=nil)
            .." adamovianLanguage="..tostring(
                istable(API.Languages.ad) and table.Count(API.Languages.ad) or 0))
        local ent=scripted_ents.Get(class)
        local found=false
        for _,setting in ipairs(ent and ent.Spawner or {}) do
            if setting[1]=="Announcer" and setting[3]=="List" then
                found=true
                local opts=isfunction(setting[4]) and setting[4]()
                    or (istable(setting[4]) and setting[4] or {})
                for idx,name in SortedPairs(opts) do
                    print("[MEX ASNP SPAWNER] option "..idx.." = "..tostring(name))
                end
            end
        end
        if not found then
            print("[MEX ASNP SPAWNER] no ASNP selector (hardware detected="
                ..tostring(API.ASNPHardwareClasses[class] or false)..")")
        end
        for id,pack in SortedPairs(API.Packs) do
            if IsActivePack(pack) then
                print("[MEX ASNP SPAWNER] pack "..id
                    .." localID="..tostring(pack.registeredID)
                    .." serverID="..tostring(API.ServerIndices[id])
                    .." validID="..tostring(PackIndex(id,pack)))
            end
        end
    end)
end
