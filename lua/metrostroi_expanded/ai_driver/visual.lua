-- MEX AI Driver - seated operator model, no fake player/extra jeep seat.
local Visual = {Active = {}}
local SHOW = CreateConVar("mex_ai_visual", "1", FCVAR_ARCHIVE)
local MODEL = CreateConVar("mex_ai_driver_model", "models/player/barney.mdl", FCVAR_ARCHIVE)
local DX = CreateConVar("mex_ai_visual_x", "0", FCVAR_ARCHIVE)
local DY = CreateConVar("mex_ai_visual_y", "0", FCVAR_ARCHIVE)
local DZ = CreateConVar("mex_ai_visual_z", "-26", FCVAR_ARCHIVE)
local YAW = CreateConVar("mex_ai_visual_yaw", "90", FCVAR_ARCHIVE)

function Visual.FindSeat(train)
    if not IsValid(train) then return nil, "invalid_train" end
    -- The original Metrostroi driver's pod is explicitly train.DriverSeat.
    -- MEX passenger pods are never candidates, regardless of proximity.
    local seat = train.DriverSeat
    if not IsValid(seat) then seat = train:GetNW2Entity("seat_driver") end
    if not IsValid(seat) then return nil, "driver_seat_not_ready" end
    if not seat:IsVehicle() or seat:GetNW2String("SeatType") ~= "driver"
        or seat:GetNW2Entity("TrainEntity") ~= train
        or seat:GetNW2Bool("MPS.PassengerSeat", false)
        or seat.MPSPassengerSeat then
        return nil, "not_original_driver_seat"
    end
    return seat
end

local function Occupied(seat)
    if type(seat.GetPassenger) == "function" then
        local ok, passenger = pcall(seat.GetPassenger, seat, 0)
        if ok and IsValid(passenger) then return true end
    end
    if type(seat.GetDriver) == "function" then
        local ok, driver = pcall(seat.GetDriver, seat)
        if ok and IsValid(driver) then return true end
    end
    return false
end

local function ModelPath()
    local path = string.Trim(MODEL:GetString())
    if not string.match(path, "^models/[%w_/%-]+%.mdl$") or not util.IsValidModel(path) then
        return "models/player/barney.mdl"
    end
    return path
end

local function Pose(actor)
    if not IsValid(actor) then return end
    local seat = actor:GetParent()
    if not IsValid(seat) then return end
    actor:SetPos(seat:LocalToWorld(Vector(
        math.Clamp(DX:GetFloat(), -100, 100),
        math.Clamp(DY:GetFloat(), -100, 100),
        math.Clamp(DZ:GetFloat(), -100, 100))))
    actor:SetAngles(seat:LocalToWorldAngles(Angle(0, YAW:GetFloat(), 0)))
end

local function Sit(actor)
    if not IsValid(actor) then return end
    local seq = -1
    for _, name in ipairs({"sit_rollercoaster", "sit", "drive_jeep", "drive_pd"}) do
        local found = actor:LookupSequence(name)
        if found and found >= 0 then seq = found break end
    end
    if seq < 0 and ACT_HL2MP_SIT then seq = actor:SelectWeightedSequence(ACT_HL2MP_SIT) end
    if seq >= 0 then
        actor:ResetSequence(seq)
        actor:SetCycle(0.45)
        actor:SetPlaybackRate(0)
    else
        print("[MEX AI] Model has no seated animation: " .. actor:GetModel())
        actor:Remove()
    end
end

function Visual.Remove(train)
    local actor = Visual.Active[train]
    Visual.Active[train] = nil
    if IsValid(actor) then actor:Remove() end
end

function Visual.RemoveAll()
    for train in pairs(Visual.Active) do Visual.Remove(train) end
end

function Visual.Ensure(train)
    if not SHOW:GetBool() then Visual.Remove(train) return false, "visual_disabled" end
    local seat, err = Visual.FindSeat(train)
    if not IsValid(seat) then Visual.Remove(train) return false, err end
    if Occupied(seat) then Visual.Remove(train) return false, "occupied_by_player" end
    local path = ModelPath()
    local actor = Visual.Active[train]
    if IsValid(actor) and actor:GetParent() == seat and actor:GetModel() == path then
        return true, actor
    end
    Visual.Remove(train)
    actor = ents.Create("prop_dynamic_override")
    if not IsValid(actor) then return false, "spawn_failed" end
    actor:SetModel(path)
    actor:SetPos(seat:GetPos())
    actor:SetAngles(seat:GetAngles())
    actor:SetKeyValue("solid", "0")
    actor:Spawn()
    if not IsValid(actor) then return false, "spawn_failed" end
    actor:SetMoveType(MOVETYPE_NONE)
    actor:SetSolid(SOLID_NONE)
    actor:SetNotSolid(true)
    actor:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    actor:DrawShadow(false)
    actor:SetParent(seat)
    Pose(actor)
    actor:SetNW2Bool("MEXAI.Operator", true)
    actor:SetNW2Entity("MEXAI.Train", train)
    train:DeleteOnRemove(actor)
    Visual.Active[train] = actor
    -- Source can reject ResetSequence immediately after spawning a model.
    timer.Simple(0, function()
        if IsValid(actor) and Visual.Active[train] == actor then
            Sit(actor)
            if not IsValid(actor) then Visual.Active[train] = nil end
        end
    end)
    return true, actor
end

function Visual.Refresh(train)
    Visual.Remove(train)
    return Visual.Ensure(train)
end

function Visual.Describe(train)
    local actor = Visual.Active[train]
    return IsValid(actor) and (actor:GetModel() .. " #" .. actor:EntIndex()) or "none"
end

return Visual
