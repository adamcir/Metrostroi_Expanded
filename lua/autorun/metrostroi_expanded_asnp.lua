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

function API.AudioDuration(path, fallback)
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
    return rate and rate>0 and bytes and (bytes/rate) or fallback
end

function API.TryRegister()
    if not Metrostroi or not isfunction(Metrostroi.AddANSPAnnouncer)
        or not istable(Metrostroi.ASNPSetup) or not istable(Metrostroi.AnnouncementsASNP) then return end
    local map=game.GetMap():lower()
    for id,pack in pairs(API.Packs) do
        local matches=(not pack.maps) or false
        for _,prefix in ipairs(pack.maps or {}) do
            if string.StartWith(map,prefix:lower()) then matches=true break end
        end
        if matches then
            local sounds={click1=0.01,click2=0.01,click3=0.01}
            for key,sound in pairs(pack.sounds or {}) do
                local path=pack.soundRoot.."/"..sound[1]
                if file.Exists("sound/"..path,"GAME") then
                    sounds[key]={path,API.AudioDuration(path,sound[2] or 2)+0.25}
                else
                    print("[MEX ASNP] Missing sound: "..path)
                end
            end
            local routes=isfunction(pack.routes) and pack.routes(pack) or pack.routes
            if not routes and istable(pack.stations) then
                local line={Name=pack.lineName or pack.name,Loop=pack.loop or false,LED=pack.led or {5,10,5,5,5}}
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
                        arrlast={final,table.Copy(final)}
                    }
                end
                routes={line}
            end
            if istable(routes) then
                local present
                for index,data in ipairs(Metrostroi.ASNPSetup) do
                    if data.name==pack.name then present=index break end
                end
                if not pack._applied then
                    -- Replace an older registration with the canonical pack data.
                    -- AddANSPAnnouncer supports changing an existing named announcer.
                    Metrostroi.AddANSPAnnouncer(pack.name,sounds,routes)
                    pack._applied=true
                end
                for index,data in ipairs(Metrostroi.ASNPSetup) do
                    if data.name==pack.name then
                        pack.registeredID=index
                        break
                    end
                end
            end
        end
    end
end

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
    for _,pack in pairs(API.Packs) do
        if pack.name==setup.name then return pack end
    end
end

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

if CLIENT then
    timer.Create("MEXASNP_Spawners",2,0,function()
        for _,pack in pairs(API.Packs) do
            if pack.registeredID then
                for class,record in pairs(scripted_ents.GetList() or {}) do
                    if not string.StartWith(class,"gmod_subway_") then continue end
                    local train=record.t
                    if not train or not istable(train.Spawner) then continue end
                    for _,setting in ipairs(train.Spawner) do
                        if setting[1]~="Announcer" or setting[3]~="List" then continue end
                        if not setting.MEXASNPOriginal then
                            local original=setting[4]
                            if not istable(original) and not isfunction(original) then continue end
                            setting.MEXASNPOriginal=original
                            setting[4]=function(...)
                                local base=isfunction(original) and original(...) or original
                                local list=table.Copy(istable(base) and base or {})
                                for _,p in pairs(API.Packs) do
                                    if p.registeredID then list[p.registeredID]=p.name end
                                end
                                return list
                            end
                        end
                    end
                end
            end
        end
    end)
end
