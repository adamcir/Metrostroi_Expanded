-- MEX AI Driver - opt-in, server-side train pilot (dry-run by default).
local Bridge = include("metrostroi_expanded/ai_driver/bridge.lua")
local Controller = include("metrostroi_expanded/ai_driver/controller.lua")
local LIVE = CreateConVar("mex_ai_live", "0", FCVAR_ARCHIVE, "Allow MEX AI to actuate compatible train KV (0=dry-run)")
local sessions = {}
MEXAIDriver = MEXAIDriver or {}
MEXAIDriver.Controller = Controller

local function Inform(ply, text)
    print("[MEX AI] " .. text)
    if IsValid(ply) then ply:ChatPrint("[MEX AI] " .. text) end
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

concommand.Add("mex_ai_attach", function(ply)
    if not IsAdmin(ply) then return end
    local train = FindViewedTrain(ply)
    if not Controller.Supported(train) then
        Inform(ply, "Aim at a supported 81-717 cab train (KV_70).")
        return
    end
    sessions[train] = {lastSend = -100, pending = false, reply = nil, replyAt = -100, lastStatus = "new"}
    Inform(ply, "Attached to " .. train:GetClass() .. " #" .. train:EntIndex() .. " (LIVE=" .. LIVE:GetInt() .. ")")
end)

concommand.Add("mex_ai_detach", function(ply)
    if not IsAdmin(ply) then return end
    local train = FindViewedTrain(ply)
    if IsValid(train) and sessions[train] then
        sessions[train] = nil
        -- Stop applying traction when control is relinquished.
        Controller.Apply(train, 0)
        Inform(ply, "Detached " .. train:EntIndex())
    else
        Inform(ply, "Look at an attached cab train.")
    end
end)

concommand.Add("mex_ai_status", function(ply)
    if not IsAdmin(ply) then return end
    Inform(ply, "LuaSocket=" .. tostring(Bridge.Available) .. " LIVE=" .. LIVE:GetInt() .. " pending=" .. Bridge.PendingCount())
    for train, session in pairs(sessions) do
        if IsValid(train) then
            local state = {train = Controller.ReadTrain(train), route = Controller.ReadRoute(train)}
            local envelope, reason = Controller.GetEnvelope(state)
            Inform(ply, string.format("train=%d speed=%.1f envelope=%.1f route=%s reply=%s pending=%s (%s)",
                train:EntIndex(), state.train.speed_kmh, envelope,
                tostring(state.route.known), tostring(session.reply and session.reply.mode), tostring(session.pending), reason))
        end
    end
end)

-- Externally supported integration point for Track Builder, stations and maps:
-- hook.Add("MEXAIDriverRouteState", "...", function(train) return {known=true,...} end)
MEXAIDriver.GetAttached = function() return sessions end

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
    for train, session in pairs(sessions) do
        if not IsValid(train) then
            sessions[train] = nil
        else
            local state = {
                train = Controller.ReadTrain(train),
                route = Controller.ReadRoute(train)
            }
            if state.train.driver_present then
                -- Human operator always gets priority.
                Controller.Apply(train, 0)
                sessions[train] = nil
                print("[MEX AI] Human driver detected; pilot detached from " .. train:EntIndex())
            else
                if not session.pending and RealTime() - session.lastSend >= 2.5 then
                    SendDecision(train, session, state)
                end
                local replyAge = RealTime() - session.replyAt
                local position, target, mode = Controller.GetPosition(state, session.reply, replyAge)
                session.lastPosition = position
                session.lastTarget = target
                session.lastMode = mode
                if LIVE:GetBool() then
                    local ok, err = Controller.Apply(train, position)
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

print("[MEX AI] Driver loaded; use mex_ai_attach / mex_ai_status. LIVE is disabled by default.")