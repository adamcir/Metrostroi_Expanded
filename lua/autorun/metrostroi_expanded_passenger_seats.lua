-- Metrostroi Extended - Passenger Seats
-- Universal passenger-seat module for Metrostroi subway rolling stock.
-- Adds invisible jeep seats without modifying Metrostroi itself.
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

if SERVER then
    AddCSLuaFile()
end

MetrostroiPassengerSeats = MetrostroiPassengerSeats or {}
local MPS = MetrostroiPassengerSeats

MPS.Version = "0.2.0"

-- The X positions come from the passenger-seat prototype that existed in the
-- old Metrostroi AI entity. They line up with the gaps between the four pairs
-- of passenger doors on the classic Metrostroi carbody.
local STANDARD_SEAT_X = {
     280,  250,  220,  190,  160,
      50,   20,  -10,  -40,  -70,
    -180, -210, -240, -270, -300,
    -410, -440,
}

-- Official Metrostroi release profiles. seat_z is normally floor_z + 14.
-- y=52 is the tuned position used by 81-717/Ezh3; newer bodies use y=51.
MPS.Configs = {
    -- Old E / Ezh / Ema family
    ["gmod_subway_81-501"]      = { name="81-501",      x=STANDARD_SEAT_X, y=52, floor_z=-55 },
    ["gmod_subway_81-502"]      = { name="81-502",      x=STANDARD_SEAT_X, y=52, floor_z=-55 },
    ["gmod_subway_81-702"]      = { name="81-702",      x=STANDARD_SEAT_X, y=52, floor_z=-55 },
    ["gmod_subway_81-702_int"]  = { name="81-702 int",  x=STANDARD_SEAT_X, y=52, floor_z=-55 },
    ["gmod_subway_81-703"]      = { name="81-703",      x=STANDARD_SEAT_X, y=52, floor_z=-55 },
    ["gmod_subway_81-703_int"]  = { name="81-703 int",  x=STANDARD_SEAT_X, y=52, floor_z=-55 },
    ["gmod_subway_em508t"]      = { name="Em508T",      x=STANDARD_SEAT_X, y=52, floor_z=-55 },
    ["gmod_subway_ezh"]         = { name="Ezh",         x=STANDARD_SEAT_X, y=52, floor_z=-55 },
    ["gmod_subway_ezh1"]        = { name="Ezh1",        x=STANDARD_SEAT_X, y=52, floor_z=-55 },
    ["gmod_subway_ezh3"]        = { name="Ezh3 (81-710)",x=STANDARD_SEAT_X,y=52, floor_z=-55 },

    -- 81-717 / 714 and closely related bodies
    ["gmod_subway_81-714_lvz"]  = { name="81-714 LVZ",  x=STANDARD_SEAT_X, y=52, floor_z=-48 },
    ["gmod_subway_81-714_mvm"]  = { name="81-714 MVM",  x=STANDARD_SEAT_X, y=52, floor_z=-48 },
    ["gmod_subway_81-717_lvz"]  = { name="81-717 LVZ",  x=STANDARD_SEAT_X, y=52, floor_z=-48 },
    ["gmod_subway_81-717_mvm"]  = { name="81-717 MVM",  x=STANDARD_SEAT_X, y=52, floor_z=-48 },
    ["gmod_subway_81-718"]      = { name="81-718",      x=STANDARD_SEAT_X, y=52, floor_z=-48 },
    ["gmod_subway_81-719"]      = { name="81-719",      x=STANDARD_SEAT_X, y=52, floor_z=-48 },

    -- Yauza family
    ["gmod_subway_81-720"]      = { name="81-720",      x=STANDARD_SEAT_X, y=51, floor_z=-60 },
    ["gmod_subway_81-721"]      = { name="81-721",      x=STANDARD_SEAT_X, y=51, floor_z=-60 },

    -- 81-722/723/724 family
    ["gmod_subway_81-722"]      = { name="81-722",      x=STANDARD_SEAT_X, y=51, floor_z=-62 },
    ["gmod_subway_81-723"]      = { name="81-723",      x=STANDARD_SEAT_X, y=51, floor_z=-62 },
    ["gmod_subway_81-724"]      = { name="81-724",      x=STANDARD_SEAT_X, y=51, floor_z=-62 },
}

for _, cfg in pairs(MPS.Configs) do
    cfg.seat_z = cfg.seat_z or (cfg.floor_z + 14)
end

local function IsSubwayClass(className)
    return isstring(className)
        and className ~= "gmod_subway_base"
        and string.sub(className, 1, 12) == "gmod_subway_"
end

local function SeatOccupied(seat)
    if not IsValid(seat) then return true end
    if seat.GetPassenger then
        local passenger = seat:GetPassenger(0)
        if IsValid(passenger) then return true end
    end
    if seat.GetDriver then
        local driver = seat:GetDriver()
        if IsValid(driver) then return true end
    end
    return false
end

local function GetStandingAreaSafe(train)
    if not IsValid(train) or not isfunction(train.GetStandingArea) then return nil, nil end
    local ok, a, b = pcall(train.GetStandingArea, train)
    if not ok or not isvector(a) or not isvector(b) then return nil, nil end
    return a, b
end

local function BuildFallbackX(minX, maxX)
    local result = {}
    minX = math.min(minX or -450, maxX or 380)
    maxX = math.max(minX or -450, maxX or 380)

    for _, x in ipairs(STANDARD_SEAT_X) do
        if x >= minX + 5 and x <= maxX - 5 then
            result[#result + 1] = x
        end
    end

    -- Very unusual/short addon car: generate a conservative line of seats.
    if #result < 4 then
        local startX = maxX - 55
        local endX = minX + 25
        local x = startX
        while x >= endX and #result < 24 do
            result[#result + 1] = x
            x = x - 45
        end
    end

    return result
end

local function GuessSeatY(train)
    local ys = {}
    local function addDoorTable(t)
        if not istable(t) then return end
        for _, pos in ipairs(t) do
            if isvector(pos) then ys[#ys + 1] = math.abs(pos.y) end
        end
    end

    addDoorTable(train.LeftDoorPositions)
    addDoorTable(train.RightDoorPositions)

    if #ys > 0 then
        local sum = 0
        for _, y in ipairs(ys) do sum = sum + y end
        return math.Clamp(sum / #ys - 13, 42, 56)
    end

    if isfunction(train.OBBMaxs) then
        local obb = train:OBBMaxs()
        if isvector(obb) and math.abs(obb.y) > 35 then
            return math.Clamp(math.abs(obb.y) - 16, 42, 56)
        end
    end

    return 52
end

local function GetConfigForTrain(train)
    if not IsValid(train) then return nil end

    local className = train:GetClass()
    local exact = MPS.Configs[className]
    if exact then return exact end

    -- Generic support for third-party/future Metrostroi subway cars that expose
    -- the standard standing-area metadata.
    if not IsSubwayClass(className) then return nil end

    local a, b = GetStandingAreaSafe(train)
    if not a then return nil end

    local minX = math.min(a.x, b.x)
    local maxX = math.max(a.x, b.x)
    local floorZ = (a.z + b.z) * 0.5

    return {
        name = className .. " (auto)",
        x = BuildFallbackX(minX, maxX),
        y = GuessSeatY(train),
        floor_z = floorZ,
        seat_z = floorZ + 14,
        automatic = true,
    }
end

local function GetSeatTargetWorld(seat)
    if not IsValid(seat) then return nil end
    local train = seat:GetNW2Entity("MPS.Train")
    if not IsValid(train) then return nil end
    local localPos = seat:GetNW2Vector("MPS.UseLocal", vector_origin)
    return train:LocalToWorld(localPos)
end

local function FindLookedAtSeat(ply, maxDistance, minDot)
    if not IsValid(ply) then return nil end

    local eye = ply:EyePos()
    local aim = ply:GetAimVector()
    local bestSeat = nil
    local bestScore = -math.huge

    for _, seat in ipairs(ents.FindByClass("prop_vehicle_prisoner_pod")) do
        if IsValid(seat) and seat:GetNW2Bool("MPS.PassengerSeat", false) and not SeatOccupied(seat) then
            local target = GetSeatTargetWorld(seat)
            if target then
                local delta = target - eye
                local distance = delta:Length()
                if distance > 0 and distance <= maxDistance then
                    local dot = aim:Dot(delta / distance)
                    if dot >= minDot then
                        local score = dot - distance * 0.00035
                        if score > bestScore then
                            bestScore = score
                            bestSeat = seat
                        end
                    end
                end
            end
        end
    end

    return bestSeat
end

if SERVER then
    MPS.Seats = MPS.Seats or {}

    local function RegisterSeat(train, cfg, x, side)
        local y = cfg.y * side
        local localPos = Vector(x, y, cfg.seat_z)
        local localAngle = side < 0 and Angle(0, 90, 0) or Angle(0, 270, 0)

        local seat = train:CreateSeat(
            "passenger",
            localPos,
            localAngle,
            "models/nova/jeep_seat.mdl"
        )
        if not IsValid(seat) then return nil end

        -- Real train bench remains visible; vehicle base does not.
        seat:SetRenderMode(RENDERMODE_TRANSALPHA)
        seat:SetColor(Color(0, 0, 0, 0))
        seat:SetNoDraw(true)
        seat:DrawShadow(false)

        seat:SetNW2Bool("MPS.PassengerSeat", true)
        seat:SetNW2Entity("MPS.Train", train)
        seat:SetNW2String("MPS.TrainName", cfg.name)
        seat:SetNW2Vector("MPS.LocalPos", localPos)
        seat:SetNW2Vector("MPS.UseLocal", localPos + Vector(0, 0, 14))
        seat:SetNW2Vector("MPS.ExitLocal", Vector(x, 0, cfg.floor_z + 2))

        seat.MPSPassengerSeat = true
        seat.MPSTrain = train
        seat.MPSLocalPos = localPos

        train:DeleteOnRemove(seat)
        MPS.Seats[#MPS.Seats + 1] = seat
        train.MPSPassengerSeats[#train.MPSPassengerSeats + 1] = seat
        return seat
    end

    local function CreateSeatsForTrain(train)
        if not IsValid(train) then return false end
        if train.MPSPassengerSeatsCreated then return true end
        if not isfunction(train.CreateSeat) or not istable(train.Seats) then return false end

        local cfg = GetConfigForTrain(train)
        if not cfg or not istable(cfg.x) or #cfg.x == 0 then return false end

        train.MPSPassengerSeatsCreated = true
        train.MPSPassengerSeats = {}

        for _, x in ipairs(cfg.x) do
            RegisterSeat(train, cfg, x, -1)
            RegisterSeat(train, cfg, x, 1)
        end

        print(string.format(
            "[Metrostroi Extended/Passenger Seats] %s (%s): created %d passenger seats%s",
            cfg.name,
            train:GetClass(),
            #train.MPSPassengerSeats,
            cfg.automatic and " [automatic profile]" or ""
        ))

        return #train.MPSPassengerSeats > 0
    end

    local function ScheduleSeatCreation(train, attempt)
        attempt = attempt or 1
        if not IsValid(train) or train.MPSPassengerSeatsCreated then return end
        if not IsSubwayClass(train:GetClass()) then return end

        timer.Simple(0.10, function()
            if not IsValid(train) or train.MPSPassengerSeatsCreated then return end
            if CreateSeatsForTrain(train) then return end
            if attempt < 35 then
                ScheduleSeatCreation(train, attempt + 1)
            end
        end)
    end

    local function ScanExistingTrains()
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and IsSubwayClass(ent:GetClass()) then
                ScheduleSeatCreation(ent, 1)
            end
        end
    end

    hook.Add("OnEntityCreated", "MPS.CreatePassengerSeats", function(ent)
        if not IsValid(ent) then return end
        if not IsSubwayClass(ent:GetClass()) then return end
        ScheduleSeatCreation(ent, 1)
    end)

    hook.Add("InitPostEntity", "MPS.CreateSeatsForExistingTrains", function()
        timer.Simple(0.75, ScanExistingTrains)
    end)

    hook.Add("KeyPress", "MPS.UsePassengerSeat", function(ply, key)
        if key ~= IN_USE then return end
        if not IsValid(ply) or not ply:Alive() or ply:InVehicle() then return end

        local seat = FindLookedAtSeat(ply, 105, 0.91)
        if not IsValid(seat) or SeatOccupied(seat) then return end
        if (ply.MPSNextSeatUse or 0) > CurTime() then return end

        ply.MPSNextSeatUse = CurTime() + 0.35

        timer.Simple(0.05, function()
            if not IsValid(ply) or not ply:Alive() or ply:InVehicle() then return end
            if not IsValid(seat) or SeatOccupied(seat) then return end

            local train = seat:GetNW2Entity("MPS.Train")
            if not IsValid(train) then return end

            ply.MPSEntryLockUntil = CurTime() + 0.55
            ply.MPSEntrySeat = seat
            ply:EnterVehicle(seat)
        end)
    end)

    hook.Add("PlayerEnteredVehicle", "MPS.PassengerSeatEntered", function(ply, vehicle)
        if not IsValid(vehicle) or not vehicle:GetNW2Bool("MPS.PassengerSeat", false) then return end
        ply.MPSEntryLockUntil = CurTime() + 0.55
        ply.MPSEntrySeat = vehicle
    end)

    hook.Add("CanExitVehicle", "MPS.PreventImmediatePassengerExit", function(vehicle, ply)
        if not IsValid(vehicle) or not IsValid(ply) then return end
        if not vehicle:GetNW2Bool("MPS.PassengerSeat", false) then return end
        if ply.MPSEntrySeat == vehicle and (ply.MPSEntryLockUntil or 0) > CurTime() then
            return false
        end
    end)

    hook.Add("PlayerLeaveVehicle", "MPS.PassengerSeatExit", function(ply, vehicle)
        if not IsValid(vehicle) or not vehicle:GetNW2Bool("MPS.PassengerSeat", false) then return end

        ply.MPSEntryLockUntil = nil
        ply.MPSEntrySeat = nil

        local train = vehicle:GetNW2Entity("MPS.Train")
        local exitLocal = vehicle:GetNW2Vector("MPS.ExitLocal", vector_origin)

        timer.Simple(0, function()
            if not IsValid(ply) or not IsValid(train) then return end
            ply:SetPos(train:LocalToWorld(exitLocal))
            local desiredVelocity = train:GetVelocity()
            ply:SetVelocity(desiredVelocity - ply:GetVelocity())
        end)
    end)

    hook.Add("EntityRemoved", "MPS.ForgetRemovedSeat", function(ent)
        if not ent.MPSPassengerSeat then return end
        for i = #MPS.Seats, 1, -1 do
            if MPS.Seats[i] == ent or not IsValid(MPS.Seats[i]) then
                table.remove(MPS.Seats, i)
            end
        end
    end)

    concommand.Add("mps_rescan", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end
        ScanExistingTrains()
        print("[Metrostroi Extended/Passenger Seats] rescan requested")
    end)

    concommand.Add("mps_status", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end

        local trains, seats, auto = 0, 0, 0
        for _, train in ipairs(ents.GetAll()) do
            if IsValid(train) and IsSubwayClass(train:GetClass()) and train.MPSPassengerSeatsCreated then
                trains = trains + 1
                if not MPS.Configs[train:GetClass()] then auto = auto + 1 end
                if istable(train.MPSPassengerSeats) then
                    for _, seat in ipairs(train.MPSPassengerSeats) do
                        if IsValid(seat) then seats = seats + 1 end
                    end
                end
            end
        end

        print(string.format(
            "[Metrostroi Extended/Passenger Seats] trains: %d, live seats: %d, automatic profiles: %d",
            trains, seats, auto
        ))
    end)
end

if CLIENT then
    local debugSeats = CreateClientConVar(
        "mps_debug_seats",
        "0",
        true,
        false,
        "Draw Metrostroi Passenger Seats helper positions"
    )

    local nextCandidateUpdate = 0
    local currentCandidate = nil

    hook.Add("Think", "MPS.UpdatePassengerSeatPrompt", function()
        if CurTime() < nextCandidateUpdate then return end
        nextCandidateUpdate = CurTime() + 0.10

        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() or ply:InVehicle() then
            currentCandidate = nil
            return
        end

        currentCandidate = FindLookedAtSeat(ply, 105, 0.91)
    end)

    hook.Add("HUDPaint", "MPS.PassengerSeatPrompt", function()
        if not IsValid(currentCandidate) or SeatOccupied(currentCandidate) then return end
        draw.SimpleTextOutlined(
            "E  Sednout si",
            "Trebuchet24",
            ScrW() * 0.5,
            ScrH() * 0.5 + 42,
            Color(255, 255, 255),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER,
            1,
            Color(0, 0, 0, 220)
        )
    end)

    hook.Add("PostDrawTranslucentRenderables", "MPS.DebugPassengerSeats", function()
        if not debugSeats:GetBool() then return end
        for _, seat in ipairs(ents.FindByClass("prop_vehicle_prisoner_pod")) do
            if IsValid(seat) and seat:GetNW2Bool("MPS.PassengerSeat", false) then
                local train = seat:GetNW2Entity("MPS.Train")
                if IsValid(train) then
                    local pos = train:LocalToWorld(seat:GetNW2Vector("MPS.UseLocal", vector_origin))
                    render.DrawWireframeSphere(pos, 4, 8, 8, Color(80, 220, 120), true)
                end
            end
        end
    end)
end
