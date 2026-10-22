-- MEX AI Driver independent route, train and braking controller.
-- Only KV_70 on compatible 81-717 cab cars is supported for LIVE drive initially.
local Controller = {}
local DECELERATION_MPS2 = 0.75
local SAFETY_MARGIN_M = 15

local function ValidNumber(value, min, max)
    value = tonumber(value)
    if value and value == value and value >= min and value <= max then return value end
    return nil
end

function Controller.ReadTrain(train)
    local ars = train.ALS_ARS
    local arsLimit = nil
    if ars then
        -- If an installed ARS is not available/enabled, fail closed.
        if ars.EnableARS == true and ars.EnableALS == true then
            arsLimit = ValidNumber(ars.SpeedLimit, 0, 120) or 0
        else
            arsLimit = 0
        end
    end
    local doorsClosed = nil
    if train.LeftDoorsOpen ~= nil and train.RightDoorsOpen ~= nil then
        doorsClosed = not train.LeftDoorsOpen and not train.RightDoorsOpen
    end
    local driverPresent = false
    if type(train.GetDriver) == "function" then
        local ok, ply = pcall(train.GetDriver, train)
        if ok then driverPresent = IsValid(ply) end
    end
    return {
        id = tostring(train:EntIndex()),
        class = train:GetClass(),
        speed_kmh = math.abs(ValidNumber(train.Speed, -160, 160) or 0),
        ars_limit_kmh = arsLimit,
        kv_position = train.KV and ValidNumber(train.KV.ControllerPosition, -3, 3) or nil,
        reverser_position = train.KV and ValidNumber(train.KV.ReverserPosition, -1, 1) or nil,
        doors_closed = doorsClosed,
        driver_present = driverPresent
    }
end

function Controller.ReadRoute(train)
    -- Track Builder or map integration can register a hook returning this object.
    local ok, route = pcall(hook.Run, "MEXAIDriverRouteState", train)
    if not ok or not istable(route) or route.known ~= true then
        return { known = false }
    end
    -- Unknown fields are intentionally dropped. Never infer a sign by proximity alone.
    local result = {
        known = true,
        traction_allowed = route.traction_allowed,
        brake_prepare_active = route.brake_prepare_active == true,
        current_limit_kmh = ValidNumber(route.current_limit_kmh, 0, 120),
        stop_distance_m = ValidNumber(route.stop_distance_m, 0, 5000)
    }
    if type(result.traction_allowed) ~= "boolean" then result.traction_allowed = nil end
    if istable(route.next_sign) then
        local kind = route.next_sign.kind
        if kind == "SPEED_LIMIT" or kind == "BRAKE_PREPARE" or kind == "TRACTION_ALLOWED" or kind == "TRACTION_OFF" then
            local distance = ValidNumber(route.next_sign.distance_m, 0, 5000)
            local value = ValidNumber(route.next_sign.value_kmh, 0, 120)
            if distance and (kind ~= "SPEED_LIMIT" or value) then
                result.next_sign = {kind = kind, distance_m = distance, value_kmh = value}
            end
        end
    end
    if istable(route.signal) then
        local aspect = route.signal.aspect
        local distance = ValidNumber(route.signal.distance_m, 0, 5000)
        if distance and (aspect == "RED" or aspect == "YELLOW" or aspect == "GREEN" or aspect == "UNKNOWN") then
            result.signal = {aspect = aspect, distance_m = distance}
        end
    end
    return result
end

local function ApproachSpeed(target, distance)
    local use = math.max(0, distance - SAFETY_MARGIN_M)
    return math.sqrt((target / 3.6)^2 + 2 * DECELERATION_MPS2 * use) * 3.6
end

function Controller.GetEnvelope(state)
    local r, t = state.route, state.train
    if not r.known then return 0, "route_unknown" end
    if t.doors_closed ~= true or t.driver_present == true then return 0, "interlock" end
    local allowed = 120
    local hasAuthority = false
    if t.ars_limit_kmh ~= nil then
        allowed = math.min(allowed, t.ars_limit_kmh)
        hasAuthority = true
    end
    if r.current_limit_kmh ~= nil then
        allowed = math.min(allowed, r.current_limit_kmh)
        hasAuthority = true
    end
    if not hasAuthority then return 0, "speed_authority_unknown" end
    if r.next_sign and r.next_sign.kind == "SPEED_LIMIT" then
        allowed = math.min(allowed, ApproachSpeed(r.next_sign.value_kmh, r.next_sign.distance_m))
    end
    if r.signal and (r.signal.aspect == "RED" or r.signal.aspect == "UNKNOWN") then
        allowed = math.min(allowed, ApproachSpeed(0, r.signal.distance_m))
    end
    if r.stop_distance_m then
        allowed = math.min(allowed, ApproachSpeed(0, r.stop_distance_m))
    end
    return math.max(0, allowed), "route_envelope"
end

function Controller.GetPosition(state, reply, replyAge)
    local train, route = state.train, state.route
    local speed = train.speed_kmh
    local envelope = Controller.GetEnvelope(state)
    local target = 0
    local mode = "BRAKE"
    if istable(reply) and reply.status == "ok" and replyAge < 4
        and (reply.mode == "ACCELERATE" or reply.mode == "COAST" or reply.mode == "BRAKE"
            or reply.mode == "HOLD" or reply.mode == "STOP") then
        target = ValidNumber(reply.target_speed_kmh, 0, 120) or 0
        mode = reply.mode
    end
    target = math.min(target, envelope)
    local delta = speed - target
    local overspeed = speed - envelope
    if (route.next_sign and route.next_sign.kind == "TRACTION_OFF" and route.next_sign.distance_m <= 5) then
        if mode == "ACCELERATE" then mode = "COAST" end
    end
    -- Failsafe BRAKE takes priority over AI preference.
    if overspeed > 0.5 or delta > 2 or mode == "STOP" or (target < 0.5 and speed > 0.5) then
        if math.max(delta, overspeed) >= 12 then return -3, target, "brake_strong" end
        if math.max(delta, overspeed) >= 4 then return -2, target, "brake_medium" end
        return -1, target, "brake_light"
    end
    if (mode == "BRAKE" or route.brake_prepare_active) and speed > 0.5 then
        return -1, target, "brake_requested"
    end
    if mode == "ACCELERATE" and route.traction_allowed ~= false
        and speed < target - 2 and speed < envelope - 1 then
        if target - speed > 20 then return 2, target, "accelerate" end
        return 1, target, "accelerate_gentle"
    end
    return 0, target, "coast"
end

function Controller.Supported(train)
    return IsValid(train)
        and string.find(train:GetClass(), "^gmod_subway_81%-717") ~= nil
        and istable(train.KV)
        and type(train.KV.TriggerInput) == "function"
end

function Controller.Apply(train, position)
    if not Controller.Supported(train) then return false, "unsupported_train" end
    if tonumber(train.KV.Enabled) ~= 1 then return false, "kv_disabled" end
    if tonumber(train.KV.ReverserPosition) == 0 then return false, "reverser_neutral" end
    position = math.floor(ValidNumber(position, -3, 3) or 0)
    if train.KV.ControllerPosition ~= position then
        -- Verified KV_70 input on classic 81-717: -3..-1 brake, 0 coast, 1..3 traction.
        local ok, err = pcall(train.KV.TriggerInput, train.KV, "ControllerSet", position)
        if not ok then return false, tostring(err) end
    end
    return true
end

return Controller