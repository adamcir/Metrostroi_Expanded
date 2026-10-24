-- MEX AI Driver - opt-in, server-side train pilot (dry-run by default).
local Bridge = include("metrostroi_expanded/ai_driver/bridge.lua")
local Controller = include("metrostroi_expanded/ai_driver/controller.lua")
local Cab = include("metrostroi_expanded/ai_driver/cab.lua")
local Chat = include("metrostroi_expanded/ai_driver/chat.lua")
-- A Lua reload must not leave an orphaned operator in the old seat.
MEXAIDriver = MEXAIDriver or {}
if MEXAIDriver.Visuals and type(MEXAIDriver.Visuals.RemoveAll) == "function" then
    MEXAIDriver.Visuals.RemoveAll()
end
local Visual = include("metrostroi_expanded/ai_driver/visual.lua")
MEXAIDriver.Visuals = Visual
local LIVE = CreateConVar("mex_ai_live", "0", FCVAR_ARCHIVE, "Allow MEX AI to actuate compatible train KV (0=dry-run)")
local sessions = {}
local takeoverQueue = {}
MEXAIDriver = MEXAIDriver or {}
MEXAIDriver.Controller = Controller
MEXAIDriver.Cab = Cab

local function Inform(ply, text)
    -- ChatPrint may also be mirrored to the local console. Send one message
    -- per invocation instead of printing it twice for player commands.
    if IsValid(ply) then
        ply:ChatPrint("[MEX AI] " .. text)
    else
        print("[MEX AI] " .. text)
    end
end

local function FindViewedTrain(ply)
    if not IsValid(ply) then return nil end
    local tr = ply:GetEyeTrace()
    local ent = tr and tr.Entity
    if not IsValid(ent) then return nil end
    if string.StartWith(ent:GetClass(), "gmod_subway_") then return ent end
    if IsValid(ent:GetParent()) and string.StartWith(ent:GetParent():GetClass(), "gmod_subway_") then
        return ent:GetParent()
    end
    return nil
end

local function IsAdmin(ply) return not IsValid(ply) or ply:IsAdmin() end

local function AttachTrain(ply, train)
    if not Bridge.Available then
        Inform(ply, "AI driver cannot attach: " .. tostring(Bridge.Error or "network bridge unavailable"))
        return false
    end
    if not Controller.Supported(train) then
        Inform(ply, "Aim at a supported 81-717 cab train (KV_70).")
        return false
    end
    if sessions[train] then
        Inform(ply, "Already attached to " .. train:GetClass() .. " #" .. train:EntIndex()
            .. " (LIVE=" .. LIVE:GetInt() .. ")")
        return true
    end
    if Controller.ReadTrain(train).driver_present then
        Inform(ply, "Cannot attach while a human occupies the front driver seat.")
        return false
    end
    sessions[train] = {lastSend = -100, pending = false, reply = nil, replyAt = -100,
        lastStatus = "new", wasLive = false, lastVisualRetry = -100,
        paused = false, destination = ""}
    local ok, result = Visual.Ensure(train)
    sessions[train].visualError = ok and nil or result
    Inform(ply, "Attached to " .. train:GetClass() .. " #" .. train:EntIndex()
        .. " (LIVE=" .. LIVE:GetInt() .. ", operator=" .. Visual.Describe(train) .. ")")
    return true
end

concommand.Add("mex_ai_attach", function(ply)
    if not IsAdmin(ply) then return end
    AttachTrain(ply, FindViewedTrain(ply))
end)

concommand.Add("mex_ai_detach", function(ply)
    if not IsAdmin(ply) then return end
    local train = FindViewedTrain(ply)
    if IsValid(train) and sessions[train] then
        local session = sessions[train]
        sessions[train] = nil
        takeoverQueue[train] = nil
        Visual.Remove(train)
        -- Never actuate the train when dry-running or while a human is driving.
        if session.wasLive and not Controller.ReadTrain(train).driver_present then
            Controller.Apply(train, 0)
        end
        Inform(ply, "Detached " .. train:EntIndex())
    else
        Inform(ply, "Look at an attached cab train.")
    end
end)

concommand.Add("mex_ai_status", function(ply)
    if not IsAdmin(ply) then return end
    local pendingCount = type(Bridge.PendingCount) == "function" and Bridge.PendingCount() or 0
    local socketStatus = Bridge.Available and "OK" or ("UNAVAILABLE (" .. tostring(Bridge.Error or "module not loaded") .. ")")
    Inform(ply, "LuaSocket=" .. socketStatus .. " LIVE=" .. LIVE:GetInt() .. " pending=" .. pendingCount)
    for train, session in pairs(sessions) do
        if IsValid(train) then
            local state = {train = Controller.ReadTrain(train), route = Controller.ReadRoute(train)}
            local envelope, reason = Controller.GetEnvelope(state)
            Inform(ply, string.format("train=%d speed=%.1f envelope=%.1f route=%s reply=%s pending=%s (%s)",
                train:EntIndex(), state.train.speed_kmh, envelope,
                tostring(state.route.known), tostring(session.reply and session.reply.mode), tostring(session.pending), reason))
            Inform(ply, "operator=" .. Visual.Describe(train)
                .. " visual_error=" .. tostring(session.visualError)
                .. " destination=" .. tostring(session.destination)
                .. " paused=" .. tostring(session.paused)
                .. " route_source=" .. tostring(state.route.source))
        end
    end
end)

-- Externally supported integration point for Track Builder, stations and maps:
-- hook.Add("MEXAIDriverRouteState", "...", function(train) return {known=true,...} end)
MEXAIDriver.GetAttached = function() return sessions end

local function ChatTrain(ply)
    local vehicle = ply:GetVehicle()
    if IsValid(vehicle) and vehicle:GetNW2String("SeatType", "") == "driver" then
        local train = vehicle:GetNW2Entity("TrainEntity")
        if Controller.Supported(train) then return train end
    end
    local seen = FindViewedTrain(ply)
    if Controller.Supported(seen) then return seen end
    local best, distance = nil, 850
    for train in pairs(sessions) do
        if IsValid(train) then
            local seat = Visual.FindSeat(train)
            if IsValid(seat) then
                local d = seat:GetPos():Distance(ply:GetPos())
                if d < distance then best, distance = train, d end
            end
        end
    end
    return best
end

hook.Remove("PlayerSay", "MEX_AI_DriverChat")
hook.Add("PlayerSay", "MEX_AI_DriverChat", function(ply, text, teamChat)
    if teamChat or not IsValid(ply) then return end
    local raw = string.Trim(tostring(text or ""))
    local command = raw:match("^!mexai%s*(.*)$") or raw:match("^/mexai%s*(.*)$")
    if command == nil then return end
    if not IsAdmin(ply) then
        Inform(ply, "Chat commands require admin permissions.")
        return ""
    end
    local train = ChatTrain(ply)
    if not IsValid(train) then
        Inform(ply, "Look at a compatible 81-717 cab or stand near an attached AI operator.")
        return ""
    end
    local cmd = Chat.Parse(command)
    local session = sessions[train]
    if cmd.kind == "TAKEOVER" then
        if session then
            Inform(ply, "I am already assigned to this train.")
        else
            local seat = Visual.FindSeat(train)
            if not IsValid(seat) then
                Inform(ply, "Front driver seat is not ready.")
            elseif Controller.ReadTrain(train).driver_present then
                local driver = train:GetDriver()
                if driver ~= ply then
                    Inform(ply, "The cab is occupied by another player.")
                else
                    takeoverQueue[train] = {ply=ply, deadline=RealTime()+30}
                    Inform(ply, "I will take over when you leave the front driver's seat (within 30 seconds).")
                end
            else
                AttachTrain(ply, train)
            end
        end
        return ""
    end
    if not session then
        Inform(ply, "No AI assigned. Write !mexai prevezmi first.")
        return ""
    end
    if cmd.kind == "HELP" then
        Inform(ply, "Commands: prevezmi | jed do NAME | zastav | pokracuj | priprav | ars | stav | svetla pult/kabina/salon/svetlomety zapni/vypni")
    elseif cmd.kind == "DESTINATION" then
        session.destination = cmd.name
        Inform(ply, "Destination noted: " .. cmd.name .. ". Automatic navigation requires a mapped rail route and destination stopping point; I will not invent one.")
    elseif cmd.kind == "PREPARE" then
        if not LIVE:GetBool() then
            Inform(ply, "Turn on mex_ai_live 1 first; dry-run never touches the cab.")
        elseif Controller.ReadTrain(train).driver_present then
            Inform(ply, "A human is driving; I will not operate the controls.")
        else
            local ok, result = Cab.Prepare(train)
            Inform(ply, (ok and "" or "Cannot prepare cab: ") .. tostring(result))
        end
    elseif cmd.kind == "STOP" then
        session.paused = true
        Inform(ply, "Stopping command acknowledged. Service braking requested.")
    elseif cmd.kind == "CONTINUE" then
        session.paused = false
        Inform(ply, "Continue requested. I will move only with valid ARS and track authority.")
    elseif cmd.kind == "ARS" then
        Inform(ply, Cab.ReadARS(train).text)
    elseif cmd.kind == "STATUS" then
        local state = {train=Controller.ReadTrain(train), route=Controller.ReadRoute(train)}
        local speed, cause = Controller.GetEnvelope(state)
        Inform(ply, string.format("Speed %.1f, ARS allowed %s, route=%s, envelope %.1f (%s), paused=%s, destination=%s",
            state.train.speed_kmh, tostring(state.train.ars_limit_kmh),
            tostring(state.route.source or "unknown"), speed, cause,
            tostring(session.paused), session.destination))
    elseif cmd.kind == "LIGHT" then
        if not LIVE:GetBool() then
            Inform(ply, "Dry-run mode: mex_ai_live 0. I will not operate switches.")
        elseif Controller.ReadTrain(train).driver_present then
            Inform(ply, "Human driver is in the cab; panel commands disabled.")
        else
            local success, answer = Cab.SetLight(train, cmd.key, cmd.enabled)
            Inform(ply, (success and "" or "Cannot operate switch: ") .. tostring(answer))
        end
    elseif cmd.kind == "QUESTION" then
        if session.chatPending then
            Inform(ply, "I am still answering the previous question.")
        else
            session.chatPending = true
            local payload = {
                text = cmd.text, train = Controller.ReadTrain(train),
                route = Controller.ReadRoute(train), destination = session.destination
            }
            Bridge.RequestChat(payload, function(success, answer)
                if not IsValid(ply) or sessions[train] ~= session then return end
                session.chatPending = false
                if success and istable(answer) and isstring(answer.say) then
                    Inform(ply, answer.say)
                else
                    Inform(ply, "AI chat is unavailable: " .. tostring(answer))
                end
            end)
        end
    end
    return ""
end)

concommand.Add("mex_ai_visual_refresh", function(ply)
    if not IsAdmin(ply) then return end
    local train = FindViewedTrain(ply)
    if not IsValid(train) or not sessions[train] then
        Inform(ply, "Aim at a train with an attached MEX AI Driver.")
        return
    end
    local ok, result = Visual.Refresh(train)
    sessions[train].visualError = ok and nil or result
    Inform(ply, ok and ("Operator refreshed: " .. Visual.Describe(train))
        or ("Operator could not be created: " .. tostring(result)))
end)

local function SendDecision(train, session, state)
    session.pending = true
    session.lastSend = RealTime()
    Bridge.Request(state, function(success, result)
        if not IsValid(train) or sessions[train] ~= session then return end
        session.pending = false
        if success and istable(result) and result.status == "ok" then
            session.reply = result
            session.replyAt = RealTime()
            session.error = nil
        else
            session.reply = nil
            session.error = success and tostring(result.status) or tostring(result)
        end
    end)
end

timer.Remove("MEX_AI_DriverTick")
timer.Create("MEX_AI_DriverTick", 0.1, 0, function()
    for train, pending in pairs(takeoverQueue) do
        if not IsValid(train) or not IsValid(pending.ply)
            or RealTime() > pending.deadline then
            takeoverQueue[train] = nil
        elseif not Controller.ReadTrain(train).driver_present then
            takeoverQueue[train] = nil
            AttachTrain(pending.ply, train)
        end
    end
    for train, session in pairs(sessions) do
        if not IsValid(train) then
            Visual.Remove(train)
            sessions[train] = nil
        else
            local state = {
                train = Controller.ReadTrain(train),
                route = Controller.ReadRoute(train)
            }
            if state.train.driver_present then
                -- Human operator always gets priority. Do not touch their KV.
                Visual.Remove(train)
                sessions[train] = nil
                print("[MEX AI] Human driver detected; pilot detached from " .. train:EntIndex())
            else
                if RealTime() - (session.lastVisualRetry or -100) >= 1 then
                    session.lastVisualRetry = RealTime()
                    local ok, result = Visual.Ensure(train)
                    session.visualError = ok and nil or result
                end
                if not session.pending and RealTime() - session.lastSend >= 2.5 then
                    state.destination = session.destination
                    SendDecision(train, session, state)
                end
                local replyAge = RealTime() - session.replyAt
                local position, target, mode = Controller.GetPosition(state, session.reply, replyAge, session.paused)
                session.lastPosition = position
                session.lastTarget = target
                session.lastMode = mode
                if not LIVE:GetBool() and session.wasLive then
                    -- One-time safe relinquish when live control is turned off.
                    Controller.Apply(train, 0)
                    session.wasLive = false
                end
                if LIVE:GetBool() then
                    local ok, err = Controller.Apply(train, position)
                    if ok then session.wasLive = true end
                    if not ok and session.lastStatus ~= err then
                        session.lastStatus = err
                        print("[MEX AI] Cannot actuate #" .. train:EntIndex() .. ": " .. tostring(err))
                    elseif ok then
                        session.lastStatus = "driving"
                    end
                end
            end
        end
    end
end)

if Bridge.Available then
    print("[MEX AI] Driver ready; use mex_ai_attach / mex_ai_status / mex_ai_visual_refresh. LIVE is disabled by default.")
else
    print("[MEX AI] Driver controls disabled until the server LuaSocket dependency is installed; use mex_ai_status.")
end