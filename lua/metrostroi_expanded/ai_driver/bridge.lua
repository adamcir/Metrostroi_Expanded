-- Server-only LuaSocket NDJSON client for MEX AI Driver.
-- Nonblocking: no socket operation may wait for Ollama inference.
local Bridge = {
    Available = false,
    Error = "not initialized"
}
-- Always export the complete public interface. In particular, the server's
-- mex_ai_status must work even if require("socket") fails in this realm.
function Bridge.PendingCount() return 0 end
function Bridge.Reset() end

-- IMPORTANT: In GMod even pcall(require, "socket") prints "Couldn't include
-- includes\\modules\\socket.lua" if the module is missing, and that error
-- counts towards sv_kickerrornum. Check before invoking require().
-- LuaSocket is an optional *server-side* module, not shipped with MEX.
local function Usable(socket)
    return type(socket) == "table" and type(socket.tcp) == "function"
        and type(socket.select) == "function"
end

local socketLib = rawget(_G, "socket")
if not Usable(socketLib) and package and package.loaded then
    socketLib = package.loaded.socket
end

local triedRequire = false
local requireError
if not Usable(socketLib) then
    local hasLuaLoader = file.Exists("includes/modules/socket.lua", "LUA")
        or file.Exists("lua/includes/modules/socket.lua", "GAME")
    if hasLuaLoader then
        triedRequire = true
        local ok, loaded = pcall(require, "socket")
        if ok and Usable(loaded) then
            socketLib = loaded
        elseif Usable(rawget(_G, "socket")) then
            -- Some LuaSocket builds export the API globally.
            socketLib = rawget(_G, "socket")
        else
            requireError = ok and "socket module returned no TCP/select API" or tostring(loaded)
        end
    end
end

if not Usable(socketLib) then
    Bridge.Error = triedRequire
        and ("LuaSocket could not initialize: " .. tostring(requireError))
        or "LuaSocket is not installed on the server (missing lua/includes/modules/socket.lua)"
    print("[MEX AI] Driver network disabled: " .. Bridge.Error)
    print("[MEX AI] Install both LuaSocket's includes/modules files and matching server binary in garrysmod/lua/bin. Run mex_ai_status to check.")
    function Bridge.Request(_, callback)
        if callback then callback(false, "luasocket_unavailable: " .. Bridge.Error) end
        return false
    end
    Bridge.RequestChat = Bridge.Request
    return Bridge
end
Bridge.Available = true
Bridge.Error = nil

local host = CreateConVar("mex_ai_host", "127.0.0.1", FCVAR_ARCHIVE, "MEX AI backend host")
local port = CreateConVar("mex_ai_port", "3002", FCVAR_ARCHIVE, "MEX AI backend TCP port")
local pending = {}
local nextId = 0
local MAX_RESPONSE = 32768
local REQUEST_TIMEOUT = 22
local MAX_PENDING = 4

local function Finish(id, success, value)
    local request = pending[id]
    if not request then return end
    pending[id] = nil
    pcall(function() request.tcp:close() end)
    if request.callback then
        local callbackOk, err = pcall(request.callback, success, value)
        if not callbackOk then print("[MEX AI] callback error: " .. tostring(err)) end
    end
end

local function CountPending()
    local n = 0
    for _ in pairs(pending) do n = n + 1 end
    return n
end

local function Submit(message, callback, kind)
    if CountPending() >= MAX_PENDING then
        if callback then callback(false, "too_many_requests") end
        return false
    end
    nextId = nextId + 1
    local id = tostring(nextId)
    message.id = id
    message.v = 1
    message.type = kind
    local encoded = util.TableToJSON(message, false)
    if not encoded or #encoded > 16000 then
        if callback then callback(false, "bad_request") end
        return false
    end
    local tcp, errorMessage = socketLib.tcp()
    if not tcp then
        if callback then callback(false, tostring(errorMessage)) end
        return false
    end
    tcp:settimeout(0) -- IMPORTANT: no blocking 1-second connect.
    local connected, err = tcp:connect(host:GetString(), port:GetInt())
    local transient = err == "timeout" or err == "Operation already in progress"
        or err == "already in progress" or err == "Resource temporarily unavailable"
        or err == "Operation now in progress" or err == "in progress"
    if not connected and not transient then
        tcp:close()
        if callback then callback(false, "connect: " .. tostring(err)) end
        return false
    end
    pending[id] = {
        tcp = tcp,
        id = id,
        expectedType = kind,
        state = connected and "send" or "connect",
        payload = encoded .. "\n",
        sent = 0,
        buffer = "",
        since = RealTime(),
        callback = callback
    }
    return true
end

function Bridge.Request(message, callback)
    return Submit(message, callback, "decision")
end

function Bridge.RequestChat(message, callback)
    if not istable(message) or not isstring(message.text)
        or #message.text > 240 then
        if callback then callback(false, "invalid_chat_request") end
        return false
    end
    return Submit(message, callback, "chat")
end

function Bridge.Reset()
    for id in pairs(pending) do Finish(id, false, "reset") end
end

function Bridge.PendingCount() return CountPending() end

timer.Remove("MEX_AI_BridgeTick")
timer.Create("MEX_AI_BridgeTick", 0.05, 0, function()
    for id, req in pairs(pending) do
        if RealTime() - req.since > REQUEST_TIMEOUT then
            Finish(id, false, "timeout")
        elseif req.state == "connect" then
            local readable, writable, selectErr = socketLib.select(nil, {req.tcp}, 0)
            if selectErr and selectErr ~= "timeout" then
                Finish(id, false, "select: " .. tostring(selectErr))
            elseif writable and #writable > 0 then
                req.state = "send"
            end
        elseif req.state == "send" then
            local n, err, partial = req.tcp:send(req.payload, req.sent + 1)
            -- With a start index, LuaSocket returns the absolute last byte index.
            local last = n or partial
            if type(last) == "number" and last > req.sent then req.sent = last end
            if err and err ~= "timeout" then
                Finish(id, false, "send: " .. tostring(err))
            elseif req.sent >= #req.payload then
                req.state = "receive"
            end
        elseif req.state == "receive" then
            local line, err, partial = req.tcp:receive("*l")
            if partial and partial ~= "" then req.buffer = req.buffer .. partial end
            if #req.buffer > MAX_RESPONSE then
                Finish(id, false, "response_too_large")
            elseif line then
                local raw = req.buffer .. line
                local data = util.JSONToTable(raw)
                if not istable(data) then
                    Finish(id, false, "invalid_json")
                elseif tostring(data.id) ~= req.id then
                    Finish(id, false, "mismatched_id")
                elseif data.type == "error" then
                    Finish(id, false, tostring(data.error))
                elseif data.type ~= req.expectedType or data.v ~= 1 then
                    Finish(id, false, "invalid_protocol")
                else
                    Finish(id, true, data)
                end
            elseif err and err ~= "timeout" then
                Finish(id, false, "receive: " .. tostring(err))
            end
        end
    end
end)

return Bridge