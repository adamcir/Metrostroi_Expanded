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
            if istable(routes) then
                local present
                for index,data in ipairs(Metrostroi.ASNPSetup) do
                    if data.name==pack.name then present=index break end
                end
                if not present then Metrostroi.AddANSPAnnouncer(pack.name,sounds,routes) end
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
