-- MEX AI Driver - small deterministic train-command language for in-game chat.
-- Driving commands are never executed from arbitrary LLM prose.
local Chat = {}

local function Normalize(s)
    s = string.lower(string.Trim(tostring(s or "")))
    local chars = {
        ["ě"]="e", ["š"]="s", ["č"]="c", ["ř"]="r", ["ž"]="z",
        ["ý"]="y", ["á"]="a", ["í"]="i", ["é"]="e", ["ň"]="n",
        ["ů"]="u", ["ú"]="u", ["ď"]="d", ["ť"]="t", ["ó"]="o"
    }
    for from, to in pairs(chars) do s = string.Replace(s, from, to) end
    return s
end

function Chat.Parse(text)
    local raw = string.Trim(tostring(text or "")):sub(1,250)
    local textLower = Normalize(raw)
    if textLower == "" or textLower == "pomoc" or textLower == "help" then
        return {kind="HELP"}
    end
    if textLower == "prevezmi" or textLower == "rid misto me"
        or textLower == "jed misto me" or textLower == "rid ty"
        or textLower == "stridani" or textLower == "prevezmi rizeni" then
        return {kind="TAKEOVER"}
    end
    if textLower == "zastav" or textLower == "stuj"
        or textLower == "stop" or textLower == "brzdi" then
        return {kind="STOP"}
    end
    if textLower == "pokracuj" or textLower == "jed"
        or textLower == "rozjed se" then
        return {kind="CONTINUE"}
    end
    if textLower == "stav" or textLower == "status"
        or textLower == "co delas" or textLower == "jak jedes" then
        return {kind="STATUS"}
    end
    if textLower == "ars" or textLower == "oc" or textLower == "co je oc"
        or textLower == "co ukazuje ars" then
        return {kind="ARS"}
    end
    local destination = raw:match("^[Jj][Ee][ĎďDd]%s+[Dd][Oo]%s+(.+)$")
        or raw:match("^[Jj][Ee][Dd]%s+[Dd][Oo]%s+(.+)$")
        or raw:match("^[Jj][Ee][Dd]%s+[Nn][Aa]%s+(.+)$")
    -- Most station names are Czech and can include diacritics.
    if not destination then
        local simple = textLower:match("^jed%s+do%s+(.+)$")
            or textLower:match("^jed%s+na%s+(.+)$")
        if simple then
            local sep = raw:find("%s")
            local rest = sep and string.Trim(raw:sub(sep+1)) or ""
            destination = rest:match("^%S+%s+(.+)$")
        end
    end
    if destination then
        destination = string.Trim(destination):gsub("[%c]"," "):sub(1,70)
        if destination ~= "" then return {kind="DESTINATION", name=destination} end
    end
    local light = textLower:match("svetla%s+(.+)") or textLower:match("osvetleni%s+(.+)")
    if light then
        local mode = light:find("vypni", 1, true) or light:find("zhasni", 1, true)
        local turnOn = light:find("zapni", 1, true) or light:find("rozsvit", 1, true)
        if mode or turnOn then
            local key = light:find("pult",1,true) and "panel"
                or (light:find("kabin",1,true) and "cabin")
                or (light:find("salon",1,true) and "saloon")
                or ((light:find("svetlomet",1,true) or light:find("predni",1,true) or light:find("far",1,true)) and "headlights")
            if key then return {kind="LIGHT",key=key,enabled=not not turnOn} end
        end
    end
    return {kind="QUESTION", text=raw}
end

return Chat
