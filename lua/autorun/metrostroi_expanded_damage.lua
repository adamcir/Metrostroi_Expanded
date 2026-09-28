-- Metrostroi Expanded - Damage System
-- Simple directional crash damage and visual deformation for Metrostroi trains.
-- Copyright (C) 2026 Adam Cir / Adava Software
-- Licensed under GNU GPL v3.0.

if SERVER then
    AddCSLuaFile()
end

MetrostroiExpandedDamage = MetrostroiExpandedDamage or {}
local MEXD = MetrostroiExpandedDamage

MEXD.Version = "0.16.0"

local DAMAGE_ENABLED_CVAR_NAME = "mex_damage_enabled"
local DEFORMATION_ENABLED_CVAR_NAME = "mex_damage_deformation_enabled"

local damageEnabledConVar
local deformationEnabledConVar

if SERVER then
    local settingFlags = bit.bor(
        FCVAR_ARCHIVE,
        FCVAR_REPLICATED,
        FCVAR_NOTIFY
    )

    damageEnabledConVar = CreateConVar(
        DAMAGE_ENABLED_CVAR_NAME,
        "1",
        settingFlags,
        "Enable Metrostroi Expanded damage system",
        0,
        1
    )

    deformationEnabledConVar = CreateConVar(
        DEFORMATION_ENABLED_CVAR_NAME,
        "1",
        settingFlags,
        "Enable Metrostroi Expanded visual deformation",
        0,
        1
    )
end

local function ReadBoolConVar(name, defaultValue)
    local convar = GetConVar(name)
    if not convar then return defaultValue == true end
    return convar:GetBool()
end

function MEXD.IsDamageEnabled()
    return ReadBoolConVar(DAMAGE_ENABLED_CVAR_NAME, true)
end

function MEXD.IsDeformationEnabled()
    return MEXD.IsDamageEnabled()
        and ReadBoolConVar(DEFORMATION_ENABLED_CVAR_NAME, true)
end

local MEXD_SOURCE_FILE = "unknown"
if debug and isfunction(debug.getinfo) then
    local sourceInfo = debug.getinfo(1, "S")
    if istable(sourceInfo) then
        MEXD_SOURCE_FILE = sourceInfo.short_src
            or sourceInfo.source
            or MEXD_SOURCE_FILE
    end
end

MEXD.SourceFile = MEXD_SOURCE_FILE

print(string.format(
    "[Metrostroi Expanded/Damage] loaded v%s from %s (%s)",
    tostring(MEXD.Version),
    tostring(MEXD.SourceFile),
    SERVER and "SERVER" or "CLIENT"
))

concommand.Add("mex_damage_version", function()
    print(string.format(
        "[Metrostroi Expanded/Damage] v%s | source: %s | realm: %s",
        tostring(MEXD.Version),
        tostring(MEXD.SourceFile),
        SERVER and "SERVER" or "CLIENT"
    ))
end)

local ZONES = {
    front = true,
    rear = true,
    left = true,
    right = true,
    roof = true,
    floor = true,
}

local SU_TO_KMH = 0.09144 -- Source units/s (inches/s) -> km/h
local SPAWN_GRACE_SECONDS = 1.0
local MIN_CRASH_SPEED_KMH = 6.0
local MAX_CRASH_SPEED_KMH = 65.0

local function IsSubwayTrain(ent)
    if not IsValid(ent) then return false end
    local className = ent:GetClass()
    return isstring(className)
        and className ~= "gmod_subway_base"
        and string.sub(className, 1, 12) == "gmod_subway_"
end

local function NormalizedHardwareText(name, model)
    local text = string.lower(
        (name or "") .. " " .. (model or "")
    )
    local compact = string.gsub(text, "[^%w]", "")
    return text, compact
end

local function IsMechanicalElectricalException(
    name,
    model,
    buttonIDs
)
    local text, compact = NormalizedHardwareText(name, model)

    local function has(value)
        return string.find(compact, value, 1, true) ~= nil
    end

    -- These controls mechanically position another mechanism. Losing the
    -- external handle/key must not magically drive the internal mechanism to
    -- zero; it simply becomes inaccessible in its last physical position.
    local mechanical =
        has("reverser")
        or has("reversor")
        or has("controller")
        or has("grkv")
        or has("rheostatcontroller")
        or has("kvwrench")
        or has("kru")
        or has("kro")
        or has("krr")
        or has("rcu")
        or has("gvwrench")
        or has("brakevalve")
        or has("parkingbrake")
        or has("manualbrake")
        or has("handbrake")
        or has("brakewheel")
        or has("disconnect")
        or has("isolation")
        or has("stopkran")
        or has("emergencybrakevalve")

    -- GV is a high-voltage mechanical disconnect/switch handle on the classic
    -- cars. If the handle is broken off, retain the actual HV switch position.
    if compact == "gv"
        or string.find(compact, "gvtoggle", 1, true)
        or string.find(text, "/gv.", 1, true)
        or string.find(text, "/gv_", 1, true)
    then
        mechanical = true
    end

    for _, id in ipairs(buttonIDs or {}) do
        local idCompact = string.lower(
            tostring(id):gsub("[^%w]", "")
        )

        if string.find(idCompact, "reverser", 1, true)
            or string.find(idCompact, "kvwrench", 1, true)
            or string.find(idCompact, "kvup", 1, true)
            or string.find(idCompact, "kvdown", 1, true)
            or string.find(idCompact, "kvset", 1, true)
            or string.find(idCompact, "kro", 1, true)
            or string.find(idCompact, "krr", 1, true)
            or string.find(idCompact, "driver", 1, true)
                and string.find(idCompact, "valve", 1, true)
            or string.find(idCompact, "parkingbrake", 1, true)
            or string.find(idCompact, "brakeline", 1, true)
            or string.find(idCompact, "trainline", 1, true)
            or idCompact == "gvtoggle"
        then
            mechanical = true
            break
        end
    end

    return mechanical == true
end

local function AddKnownDetachedHardwareButtons(name, model, add)
    if not isfunction(add) then return end

    local text, compact = NormalizedHardwareText(name, model)
    local nameLower = string.lower(name or "")

    local disconnectLike =
        string.find(compact, "disconnect", 1, true)
        or string.find(compact, "isolation", 1, true)
        or string.find(compact, "isolat", 1, true)

    -- Driver's pneumatic brake valve is one multi-action physical mechanism.
    -- Old 81-717 variants expose the moving handles as brake334/brake013
    -- (models cabin_cran_334.mdl / cran13.mdl), not as brake_valve_*.
    local driverBrake =
        not disconnectLike
        and (
            string.find(compact, "brakevalve", 1, true)
            or string.find(compact, "brake334", 1, true)
            or string.find(compact, "brake013", 1, true)
            or string.find(compact, "cran334", 1, true)
            or string.find(compact, "cran013", 1, true)
            or string.find(compact, "cran13", 1, true)
            or string.find(compact, "crane334", 1, true)
            or string.find(compact, "crane013", 1, true)
            or string.find(compact, "kran334", 1, true)
            or string.find(compact, "kran013", 1, true)
        )

    if driverBrake then
        add("PneumaticBrakeUp")
        add("PneumaticBrakeDown")
        add("PneumaticBrakeSet1")
        add("PneumaticBrakeSet2")
        add("PneumaticBrakeSet3")
        add("PneumaticBrakeSet4")
        add("PneumaticBrakeSet5")
        add("PneumaticBrakeSet6")
        add("PneumaticBrakeSet7")
        add("EmergencyBrake")
    end

    -- End-of-car brake/train-line isolation cocks.
    if nameLower == "frontbrake"
        or (
            string.find(text, "front", 1, true)
            and (
                string.find(compact, "brakeline", 1, true)
                or string.find(compact, "brakeisolation", 1, true)
            )
        )
    then
        add("FrontBrakeLineIsolationToggle")
    end

    if nameLower == "fronttrain"
        or (
            string.find(text, "front", 1, true)
            and string.find(compact, "trainline", 1, true)
        )
    then
        add("FrontTrainLineIsolationToggle")
    end

    if nameLower == "rearbrake"
        or (
            string.find(text, "rear", 1, true)
            and (
                string.find(compact, "brakeline", 1, true)
                or string.find(compact, "brakeisolation", 1, true)
            )
        )
    then
        add("RearBrakeLineIsolationToggle")
    end

    if nameLower == "reartrain"
        or (
            string.find(text, "rear", 1, true)
            and string.find(compact, "trainline", 1, true)
        )
    then
        add("RearTrainLineIsolationToggle")
    end

    -- Cab pneumatic shut-off valves are separate physical devices.
    --
    -- Classic 81-717/714 trains expose them through several different names:
    -- the authored ClientProps are brake_disconnect/train_disconnect, while
    -- generated ButtonMap props/actions may be named
    -- DriverValveBLDisconnectToggle / DriverValveTLDisconnectToggle.
    -- Normalize both forms here so the server does not depend on whichever
    -- representation happened to be detached client-side.
    local driverBLDisconnect =
        string.find(text, "brake_disconnect", 1, true)
        or string.find(text, "driver_valve_bl", 1, true)
        or string.find(compact, "drivervalvebldisconnect", 1, true)

    local driverTLDisconnect =
        string.find(text, "train_disconnect", 1, true)
        or string.find(text, "driver_valve_tl", 1, true)
        or string.find(compact, "drivervalvetldisconnect", 1, true)

    local driverCombinedDisconnect =
        (
            string.find(text, "valve_disconnect", 1, true)
            or string.find(
                compact,
                "drivervalvedisconnect",
                1,
                true
            )
        )
        and not driverBLDisconnect
        and not driverTLDisconnect

    if driverBLDisconnect then
        add("DriverValveBLDisconnect")
        add("DriverValveBLDisconnectToggle")

        -- 81-717 MVM maps NUM0 / Shift+L to DriverValveDisconnect. For
        -- ValveType 1 that event directly toggles BOTH BL and TL cocks in
        -- OnButtonPress, so it must not remain as a back door after the
        -- physical BL valve has been torn off.
        add("DriverValveDisconnect")
    end

    if driverTLDisconnect then
        add("DriverValveTLDisconnect")
        add("DriverValveTLDisconnectToggle")

        -- Same shared keyboard path as above: allowing it would still move
        -- this missing physical valve even when its own ButtonMap is dead.
        add("DriverValveDisconnect")
    end

    if driverCombinedDisconnect then
        add("DriverValveDisconnect")
        add("DriverValveDisconnectToggle")
    end

    if string.find(text, "epk_disconnect", 1, true)
        or string.find(text, "epv_disconnect", 1, true)
    then
        add("EPKToggle")
    end

    if string.find(compact, "airdistributor", 1, true)
        and disconnectLike
    then
        add("AirDistributorDisconnectToggle")
    end

    if string.find(compact, "stopkran", 1, true)
        or string.find(compact, "emergencybrakevalve", 1, true)
    then
        add("EmergencyBrake")
        add("EmergencyBrakeValveToggle")
    end

    if string.find(compact, "parkingbrake", 1, true)
        or string.find(compact, "manualbrake", 1, true)
        or string.find(compact, "handbrake", 1, true)
        or string.find(compact, "brakewheel", 1, true)
    then
        add("ParkingBrakeToggle")
        add("ParkingBrakeLeft")
        add("ParkingBrakeRight")
    end
end

local function DamageKey(zone)
    return "MEX.Damage." .. zone
end

local function CrushKey(zone)
    return "MEX.Crush." .. zone
end

function MEXD.GetCrushEnergy(train, zone)
    if not IsValid(train) or not ZONES[zone] then return 0 end
    return train:GetNW2Float(CrushKey(zone), 0)
end

function MEXD.GetZoneDamage(train, zone)
    if not IsValid(train) or not ZONES[zone] then return 0 end
    return train:GetNW2Float(DamageKey(zone), 0)
end

function MEXD.GetOverallDamage(train)
    if not IsValid(train) then return 0 end
    return math.max(
        MEXD.GetZoneDamage(train, "front"),
        MEXD.GetZoneDamage(train, "rear"),
        MEXD.GetZoneDamage(train, "left"),
        MEXD.GetZoneDamage(train, "right"),
        MEXD.GetZoneDamage(train, "roof"),
        MEXD.GetZoneDamage(train, "floor")
    )
end

function MEXD.GetStructuralHealth(train)
    return math.Clamp(1 - MEXD.GetOverallDamage(train), 0, 1)
end

local function ZoneLocalImpactPoint(train, zone)
    local mins = train:OBBMins()
    local maxs = train:OBBMaxs()
    local center = (mins + maxs) * 0.5

    if zone == "front" then
        return Vector(maxs.x, center.y, center.z)
    elseif zone == "rear" then
        return Vector(mins.x, center.y, center.z)
    elseif zone == "left" then
        return Vector(center.x, -math.max(math.abs(mins.y), math.abs(maxs.y)), center.z)
    elseif zone == "right" then
        return Vector(center.x, math.max(math.abs(mins.y), math.abs(maxs.y)), center.z)
    elseif zone == "roof" then
        return Vector(center.x, center.y, maxs.z)
    elseif zone == "floor" then
        return Vector(center.x, center.y, mins.z)
    end

    return center
end

local function ZoneOutwardNormal(train, zone)
    if zone == "front" then return train:GetForward() end
    if zone == "rear" then return -train:GetForward() end
    if zone == "left" then return -train:GetRight() end
    if zone == "right" then return train:GetRight() end
    if zone == "roof" then return train:GetUp() end
    if zone == "floor" then return -train:GetUp() end
    return train:GetUp()
end

local function UpdateDamageState(train)
    if not IsValid(train) then return end

    local front = MEXD.GetZoneDamage(train, "front")
    local rear = MEXD.GetZoneDamage(train, "rear")
    local left = MEXD.GetZoneDamage(train, "left")
    local right = MEXD.GetZoneDamage(train, "right")
    local roof = MEXD.GetZoneDamage(train, "roof")
    local floor = MEXD.GetZoneDamage(train, "floor")
    local overall = math.max(front, rear, left, right, roof, floor)

    train:SetNW2Float("MEX.Damage.overall", overall)
    train:SetNW2Float(
        "MEX.StructuralHealth",
        math.Clamp(1 - overall, 0, 1)
    )

    train:SetNW2Bool("MEX.Damage.Moderate", overall >= 0.35)
    train:SetNW2Bool("MEX.Damage.Heavy", overall >= 0.65)
    train:SetNW2Bool("MEX.Damage.Critical", overall >= 0.90)

    -- First simple subsystem damage states. These are intentionally generic.
    -- Future modules can connect them to individual Metrostroi electrical,
    -- pneumatic and door systems without modifying Metrostroi itself.
    train:SetNW2Bool("MEX.Damage.DoorsLeft", left >= 0.55)
    train:SetNW2Bool("MEX.Damage.DoorsRight", right >= 0.55)
    train:SetNW2Bool("MEX.Damage.FrontEquipment", front >= 0.55)
    train:SetNW2Bool("MEX.Damage.RearEquipment", rear >= 0.55)

    local electrical = train:GetNW2Float("MEX.Damage.electrical", 0)
    train:SetNW2Bool("MEX.Damage.ElectricalFault", electrical >= 0.45)
end

if SERVER then
    util.AddNetworkString("MEX.DamageImpact")
    util.AddNetworkString("MEX.DetachRequest")
    util.AddNetworkString("MEX.ComponentDetached")
    util.AddNetworkString("MEX.DetachReset")
    util.AddNetworkString("MEX.ComponentImpact")

    local ClassifyFromWorldDeltaVelocity
    local ClassifyFromWorldPosition

    local function EnsureButtonEventGuard(train)
        if not IsSubwayTrain(train) then return end
        if train.MEXDamageOriginalButtonEvent then return end
        if not isfunction(train.ButtonEvent) then return end

        train.MEXDamageOriginalButtonEvent = train.ButtonEvent
        train.MEXDamageOriginalOnButtonPress = train.OnButtonPress
        train.MEXDamageOriginalOnButtonRelease = train.OnButtonRelease
        train.MEXDamageBlockedButtons = train.MEXDamageBlockedButtons or {}

        local function blocked(self, button)
            if not self.MEXDamageBlockedButtons then return false end
            button = isstring(button)
                and button:gsub("^.+:", "")
                or button
            return self.MEXDamageBlockedButtons[button] == true
        end

        train.ButtonEvent = function(self, button, state, ply)
            local normalized = isstring(button)
                and button:gsub("^.+:", "")
                or button

            if blocked(self, normalized) then
                return false
            end

            return self.MEXDamageOriginalButtonEvent(
                self,
                button,
                state,
                ply
            )
        end

        if isfunction(train.MEXDamageOriginalOnButtonPress) then
            train.OnButtonPress = function(self, button, ply)
                local normalized = isstring(button)
                    and button:gsub("^.+:", "")
                    or button

                if blocked(self, normalized) then
                    return true
                end

                return self.MEXDamageOriginalOnButtonPress(
                    self,
                    button,
                    ply
                )
            end
        end

        if isfunction(train.MEXDamageOriginalOnButtonRelease) then
            train.OnButtonRelease = function(self, button, ply)
                local normalized = isstring(button)
                    and button:gsub("^.+:", "")
                    or button

                if blocked(self, normalized) then
                    return true
                end

                return self.MEXDamageOriginalOnButtonRelease(
                    self,
                    button,
                    ply
                )
            end
        end

        -- Metrostroi calls OnKeyPress/OnKeyRelease before it forwards the
        -- KeyMap entry into ButtonEvent. Some train classes therefore react to
        -- F/R or other controls before ButtonEvent can reject the destroyed
        -- device. Guard the keyboard path one level earlier.
        if isfunction(train.OnKeyEvent)
            and not train.MEXDamageOriginalOnKeyEvent
        then
            train.MEXDamageOriginalOnKeyEvent = train.OnKeyEvent

            local function selectedActionBlocked(
                self,
                action,
                helper
            )
                if isstring(action) then
                    return blocked(
                        self,
                        action:gsub("^.+:", "")
                    )
                end

                if not istable(action) then return false end

                -- Some KeyMap actions use {"Action", helper="OtherAction"}.
                -- Only inspect the action Metrostroi is about to execute, not
                -- every sibling in a modifier table.
                local selected = helper
                    and action.helper
                    or action[1]

                if isstring(selected) then
                    return blocked(
                        self,
                        selected:gsub("^.+:", "")
                    )
                end

                return false
            end

            local function resolvedKeyEventBlocked(
                self,
                key,
                state,
                helper
            )
                -- Never swallow key releases. If a control was held when it
                -- broke, Metrostroi must still receive the release so nothing
                -- can remain electrically latched.
                if not state then return false end

                local keyMap = self.KeyMap
                if not istable(keyMap) then return false end

                local keyT = keyMap[key]

                -- Mirror gmod_subway_base:OnKeyEvent exactly enough to test
                -- only the action selected by the currently active modifier.
                if isfunction(self.HasModifier)
                    and self:HasModifier(key)
                    and not helper
                    and isfunction(self.GetActiveModifiers)
                then
                    local active = self:GetActiveModifiers(key)

                    if istable(active) and #active > 0 then
                        for _, modifier in pairs(active) do
                            local modTable = keyMap[modifier]
                            local action = istable(modTable)
                                and modTable[key]
                                or nil

                            if action ~= nil
                                and selectedActionBlocked(
                                    self,
                                    action,
                                    false
                                )
                            then
                                return true
                            end
                        end

                        return false
                    end
                end

                if isfunction(self.IsModifier)
                    and self:IsModifier(key)
                    and istable(keyT)
                then
                    if keyT.helper then
                        local action = helper
                            and keyT.helper
                            or keyT[1]

                        return selectedActionBlocked(
                            self,
                            action,
                            helper
                        )
                    end

                    if not helper and isstring(keyT.def) then
                        return blocked(
                            self,
                            keyT.def:gsub("^.+:", "")
                        )
                    end

                    return false
                end

                if isstring(keyT) and not helper then
                    return blocked(
                        self,
                        keyT:gsub("^.+:", "")
                    )
                end

                return false
            end

            train.OnKeyEvent = function(self, key, state, ply, helper)
                if resolvedKeyEventBlocked(
                    self,
                    key,
                    state,
                    helper
                ) then
                    if istable(self.KeyBuffer) then
                        self.KeyBuffer[key] = nil
                    end
                    return false
                end

                return self.MEXDamageOriginalOnKeyEvent(
                    self,
                    key,
                    state,
                    ply,
                    helper
                )
            end
        end
    end

    local function KeyMapContainsButton(tbl, target, depth)
        if not istable(tbl) or depth > 3 then return false end

        for _, value in pairs(tbl) do
            if isstring(value) and value == target then
                return true
            elseif istable(value) and KeyMapContainsButton(
                value,
                target,
                depth + 1
            ) then
                return true
            end
        end

        return false
    end

    local function NormalizeButtonFamily(button)
        if not isstring(button) then return "" end

        button = button:gsub("^.+:", "")
        button = button:gsub("_Unlocked$", "")
        button = button:gsub("%d+$", "")

        local changed = true
        while changed do
            changed = false

            for _, suffix in ipairs({
                "Toggle", "Engage", "Set", "Left", "Right",
                "Up", "Down", "On", "Off",
            }) do
                if #button > #suffix
                    and string.sub(button, -#suffix) == suffix
                then
                    button = string.sub(button, 1, #button - #suffix)
                    button = button:gsub("%d+$", "")
                    changed = true
                    break
                end
            end
        end

        return string.lower(button)
    end

    local function CollectKeyMapEvents(tbl, out, seen, depth)
        if not istable(tbl) or depth > 5 then return end

        for _, value in pairs(tbl) do
            if isstring(value) then
                value = value:gsub("^.+:", "")

                if value ~= "" and not seen[value] then
                    seen[value] = true
                    out[#out + 1] = value
                end
            elseif istable(value) then
                CollectKeyMapEvents(value, out, seen, depth + 1)
            end
        end
    end

    local function ExpandDetachedButtonAliases(train, buttonIDs)
        local result = {}
        local seen = {}
        local families = {}

        local function add(id)
            if not isstring(id) or id == "" then return end
            id = id:gsub("^.+:", "")
            if seen[id] then return end
            seen[id] = true
            result[#result + 1] = id

            local family = NormalizeButtonFamily(id)
            if family ~= "" then
                families[family] = true
            end
        end

        for _, id in ipairs(buttonIDs or {}) do
            add(id)
        end

        local keyEvents = {}
        CollectKeyMapEvents(train.KeyMap, keyEvents, {}, 0)

        for _, event in ipairs(keyEvents) do
            local family = NormalizeButtonFamily(event)
            if family ~= "" and families[family] then
                add(event)
            end
        end

        return result
    end

    local function IsValidDetachedButtonID(train, button)
        if not IsSubwayTrain(train) or not isstring(button) then return false end
        if button == "" or #button > 96 or string.sub(button, 1, 1) == "!" then
            return false
        end

        button = button:gsub("^.+:", "")

        if train[button] ~= nil then return true end
        if KeyMapContainsButton(train.KeyMap, button, 0) then return true end

        local base = button
        for _, suffix in ipairs({
            "Toggle", "Set", "Left", "Right", "Up", "Down",
        }) do
            if string.sub(base, -#suffix) == suffix then
                base = string.sub(base, 1, #base - #suffix)
                break
            end
        end

        if base ~= "" and train[base] ~= nil then return true end

        if string.find(button, "ParkingBrake", 1, true)
            and train.ParkingBrake ~= nil
        then
            return true
        end

        return false
    end

    local function BlockDetachedButton(train, button)
        if not IsSubwayTrain(train) or not isstring(button) or button == "" then
            return
        end

        EnsureButtonEventGuard(train)

        button = button:gsub("^.+:", "")
        train.MEXDamageBlockedButtons = train.MEXDamageBlockedButtons or {}

        -- Release the input once before disabling it. If a key/button happened
        -- to be held during the crash, it must not remain electrically stuck.
        if not train.MEXDamageBlockedButtons[button]
            and train.MEXDamageOriginalButtonEvent
        then
            pcall(
                train.MEXDamageOriginalButtonEvent,
                train,
                button,
                false,
                nil
            )
        end

        train.MEXDamageBlockedButtons[button] = true
    end

    local function ClearDetachedButtons(train)
        if not IsSubwayTrain(train) then return end
        train.MEXDamageBlockedButtons = {}
    end

    local function RebuildDetachedButtonGuard(train)
        if not IsSubwayTrain(train) then return end

        EnsureButtonEventGuard(train)

        local desired = {}

        if istable(train.MEXDamageDetachedServer) then
            for _, data in pairs(train.MEXDamageDetachedServer) do
                if not istable(data) or not istable(data.buttons) then
                    continue
                end

                for _, button in ipairs(data.buttons) do
                    if isstring(button) and button ~= "" then
                        desired[button:gsub("^.+:", "")] = true
                    end
                end
            end
        end

        -- Release controls that were blocked by an older/stale association but
        -- no longer belong to any physically detached component.
        for button in pairs(train.MEXDamageBlockedButtons or {}) do
            if desired[button] then continue end

            if train.MEXDamageOriginalButtonEvent then
                pcall(
                    train.MEXDamageOriginalButtonEvent,
                    train,
                    button,
                    false,
                    nil
                )
            end
        end

        train.MEXDamageBlockedButtons = desired
    end

    local function FindNearestDamagedZone(train, localPos)
        local bestZone = nil
        local bestScore = 0

        for zone in pairs(ZONES) do
            local amount = MEXD.GetZoneDamage(train, zone)
            if amount <= 0.001 then continue end

            local hit = train:GetNW2Vector(
                "MEX.Damage.HitLocal." .. zone,
                ZoneLocalImpactPoint(train, zone)
            )

            local radius =
                (zone == "front" or zone == "rear") and 235
                or (zone == "left" or zone == "right") and 180
                or 150

            local distance = localPos:Distance(hit)
            local score = amount * math.Clamp(1 - distance / radius, 0, 1)

            if score > bestScore then
                bestScore = score
                bestZone = zone
            end
        end

        return bestZone, bestScore
    end

    local function BroadcastDetachedComponent(train, name, debris, receiver)
        if not IsSubwayTrain(train) or not isstring(name) then return end

        net.Start("MEX.ComponentDetached")
            net.WriteEntity(train)
            net.WriteString(name)
            net.WriteEntity(IsValid(debris) and debris or NULL)

        if IsValid(receiver) then
            net.Send(receiver)
        else
            net.Broadcast()
        end
    end

    local function IsRelayLikeElectricalSystem(system)
        if not istable(system) or not isfunction(system.TriggerInput) then
            return false
        end

        return isnumber(system.Value)
            or isnumber(system.TargetValue)
            or system.relay_type ~= nil
            or system.defaultvalue ~= nil
            or system.three_position ~= nil
            or system.maxvalue ~= nil
    end

    local function ElectricalInputWouldEnergize(system, input, value)
        input = tostring(input or "")
        value = tonumber(value) or 0

        if input == "Open"
            or input == "-"
            or input == "OpenBypass"
        then
            return false
        end

        if input == "Set" then
            return value > 0
        end

        if input == "Block"
            or input == "OpenTime"
            or input == "CloseTime"
            or input == "Check"
        then
            return false
        end

        -- Toggle/Close/+ and any unknown manual activation path must not be
        -- allowed to re-energize a switch whose physical operator is gone.
        return true
    end

    local function RestoreElectricalFailures(train)
        if not IsValid(train) then return end

        if istable(train.MEXDamageElectricalFailureSystems) then
            local names = {}

            for systemName in pairs(
                train.MEXDamageElectricalFailureSystems
            ) do
                names[#names + 1] = systemName
            end

            for _, systemName in ipairs(names) do
                local data =
                    train.MEXDamageElectricalFailureSystems[systemName]
                local system = train[systemName]

                if istable(data)
                    and istable(system)
                    and isfunction(data.originalTriggerInput)
                then
                    system.TriggerInput = data.originalTriggerInput

                    local originalTarget =
                        tonumber(data.originalTargetValue)
                    local originalValue =
                        tonumber(data.originalValue)
                    local restoreValue =
                        originalTarget ~= nil
                            and originalTarget
                            or originalValue

                    if restoreValue ~= nil then
                        pcall(
                            data.originalTriggerInput,
                            system,
                            "Set",
                            restoreValue
                        )
                    end
                end

                train.MEXDamageElectricalFailureSystems[systemName] = nil
            end
        end

        train.MEXDamageElectricalFailureSystems = {}
        train.MEXDamageNextElectricalEnforce = nil
    end

    local function RestoreSingleElectricalFailure(
        train,
        systemName,
        restoreState
    )
        if not IsSubwayTrain(train)
            or not isstring(systemName)
            or not istable(train.MEXDamageElectricalFailureSystems)
        then
            return false
        end

        local data =
            train.MEXDamageElectricalFailureSystems[systemName]
        local system = train[systemName]

        if not istable(data)
            or not istable(system)
            or not isfunction(data.originalTriggerInput)
        then
            train.MEXDamageElectricalFailureSystems[systemName] = nil
            return false
        end

        system.TriggerInput = data.originalTriggerInput

        if restoreState ~= false then
            local originalTarget =
                tonumber(data.originalTargetValue)
            local originalValue =
                tonumber(data.originalValue)
            local restoreValue =
                originalTarget ~= nil
                    and originalTarget
                    or originalValue

            if restoreValue ~= nil then
                pcall(
                    data.originalTriggerInput,
                    system,
                    "Set",
                    restoreValue
                )
            end
        end

        train.MEXDamageElectricalFailureSystems[systemName] = nil
        return true
    end

    local function FailElectricalSystemOpen(
        train,
        systemName,
        options
    )
        if not IsSubwayTrain(train)
            or not isstring(systemName)
            or systemName == ""
        then
            return false
        end

        local system = train[systemName]
        if not IsRelayLikeElectricalSystem(system) then
            return false
        end

        options = istable(options) and options or {}

        train.MEXDamageElectricalFailureSystems =
            train.MEXDamageElectricalFailureSystems or {}

        local data =
            train.MEXDamageElectricalFailureSystems[systemName]

        if not data then
            local original = system.TriggerInput

            data = {
                originalTriggerInput = original,
                originalValue = tonumber(system.Value),
                originalTargetValue = tonumber(system.TargetValue),
                causes = {},
                permanent = false,
            }

            train.MEXDamageElectricalFailureSystems[systemName] =
                data

            system.TriggerInput = function(self, input, value, ...)
                local failures =
                    IsValid(train)
                    and train.MEXDamageElectricalFailureSystems
                    or nil
                local failure =
                    failures and failures[systemName]
                    or nil

                if failure then
                    if ElectricalInputWouldEnergize(
                        self,
                        input,
                        value
                    ) then
                        return
                    end
                end

                return original(self, input, value, ...)
            end
        end

        data.causes = data.causes or {}
        local cause = tostring(options.cause or "damage")
        data.causes[cause] = true

        if options.temporary == true
            and data.permanent ~= true
        then
            data.temporary = true
            data.waterSensitivity =
                options.waterSensitivity or data.waterSensitivity or "normal"
            data.minDrySeconds = math.max(
                tonumber(options.minDrySeconds) or 20,
                tonumber(data.minDrySeconds) or 0
            )
            data.recoverMoisture = math.min(
                tonumber(options.recoverMoisture) or 0.12,
                tonumber(data.recoverMoisture) or 1
            )
        else
            data.permanent = true
            data.temporary = false
        end

        local trigger = data.originalTriggerInput
        if isfunction(trigger) then
            pcall(trigger, system, "Set", 0)
            pcall(trigger, system, "Open", 1)
        end

        return true
    end

    local function EnforceElectricalFailures(train)
        if not IsSubwayTrain(train)
            or not istable(train.MEXDamageElectricalFailureSystems)
        then
            return
        end

        local now = CurTime()
        if (train.MEXDamageNextElectricalEnforce or 0) > now then
            return
        end
        train.MEXDamageNextElectricalEnforce = now + 0.10

        for systemName, data in pairs(
            train.MEXDamageElectricalFailureSystems
        ) do
            local system = train[systemName]

            if not istable(system)
                or not istable(data)
                or not isfunction(data.originalTriggerInput)
            then
                continue
            end

            local value = tonumber(system.Value)
            local target = tonumber(system.TargetValue)

            if (value and value > 0.001)
                or (target and target > 0.001)
            then
                pcall(
                    data.originalTriggerInput,
                    system,
                    "Set",
                    0
                )
                pcall(
                    data.originalTriggerInput,
                    system,
                    "Open",
                    1
                )
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Water + live electrical equipment
    ---------------------------------------------------------------------------

    local WATER_SCAN_INTERVAL = 0.12
    local WATER_FAILURE_BASE_EXPOSURE = 0.34
    local WATER_PLAYER_RADIUS = 220
    local WATER_SHOCK_COOLDOWN = 0.32
    local WATER_SURFACE_DRY_SECONDS = 45
    local WATER_DEEP_DRY_SECONDS = 180

    local WATER_ARC_SOUNDS = {
        "ambient/energy/zap1.wav",
        "ambient/energy/zap2.wav",
        "ambient/energy/zap3.wav",
        "ambient/energy/zap5.wav",
    }

    local WATER_RELAY_CHATTER_SOUNDS = {
        "buttons/lightswitch2.wav",
        "buttons/button14.wav",
        "buttons/button15.wav",
    }

    local function NumberOrZero(value)
        value = tonumber(value)
        if not value or value ~= value then return 0 end
        return value
    end

    local function IsPointInConductiveWater(worldPos)
        if not isvector(worldPos) then return false end

        local contents = util.PointContents(worldPos)
        local waterMask = bit.bor(
            CONTENTS_WATER or 32,
            CONTENTS_SLIME or 16
        )

        return bit.band(contents, waterMask) ~= 0
    end

    local function SampleTrainWater(train)
        if not IsSubwayTrain(train) then
            return 0, nil
        end

        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()

        if not isvector(mins) or not isvector(maxs) then
            return 0, nil
        end

        local centerX = (mins.x + maxs.x) * 0.5
        local centerY = (mins.y + maxs.y) * 0.5
        local length = math.max(maxs.x - mins.x, 1)
        local width = math.max(maxs.y - mins.y, 1)
        local height = math.max(maxs.z - mins.z, 1)

        -- Sample the equipment/floor region along the whole car. This catches
        -- partial flooding even when the entity origin itself remains dry.
        local xs = {
            mins.x + length * 0.12,
            centerX,
            maxs.x - length * 0.12,
        }
        local ys = {
            centerY - width * 0.28,
            centerY,
            centerY + width * 0.28,
        }
        local zs = {
            mins.z + height * 0.10,
            mins.z + height * 0.32,
        }

        local wet = 0
        local total = 0
        local wetPoints = {}

        for _, x in ipairs(xs) do
            for _, y in ipairs(ys) do
                for _, z in ipairs(zs) do
                    total = total + 1
                    local worldPos = train:LocalToWorld(
                        Vector(x, y, z)
                    )

                    if IsPointInConductiveWater(worldPos) then
                        wet = wet + 1
                        wetPoints[#wetPoints + 1] = worldPos
                    end
                end
            end
        end

        local sampled = total > 0 and wet / total or 0

        -- WaterLevel is useful on maps where brush-water sampling around a
        -- large scripted entity is sparse. Never let it reduce point sampling.
        local entityLevel = 0
        if isfunction(train.WaterLevel) then
            local level = math.Clamp(train:WaterLevel() or 0, 0, 3)
            entityLevel = level / 3
        end

        local wetness = math.Clamp(
            math.max(sampled, entityLevel * 0.8),
            0,
            1
        )

        local sparkPos
        if #wetPoints > 0 then
            sparkPos = wetPoints[math.random(1, #wetPoints)]
        elseif wetness > 0 then
            sparkPos = train:WorldSpaceCenter()
        end

        return wetness, sparkPos
    end

    local function MaxAbsField(object, fields)
        if not istable(object) then return 0 end

        local best = 0
        for _, key in ipairs(fields) do
            best = math.max(
                best,
                math.abs(NumberOrZero(object[key]))
            )
        end
        return best
    end

    local function GetTrainElectricalWaterState(train)
        local electric = istable(train.Electric)
            and train.Electric
            or nil
        local tr = istable(train.TR) and train.TR or nil
        local battery = istable(train.Battery)
            and train.Battery
            or nil

        local hv = math.max(
            MaxAbsField(electric, {
                "Main750V",
                "Power750V",
                "Aux750V",
            }),
            MaxAbsField(tr, {
                "Main750V",
            })
        )

        local lv = MaxAbsField(electric, {
            "Aux80V",
            "Lights80V",
            "Battery80V",
            "ControlVoltage",
        })

        local batteryVoltage = NumberOrZero(
            battery and battery.Voltage
        )

        -- Classic trains use VB as the battery disconnect. Do not treat the
        -- battery terminals as feeding the flooded car when VB is definitely
        -- open; modern cars may expose their low-voltage relay differently.
        if istable(train.VB)
            and isnumber(train.VB.Value)
            and train.VB.Value <= 0.05
        then
            batteryVoltage = 0
        end

        lv = math.max(lv, batteryVoltage)

        local measuredCurrent = math.max(
            MaxAbsField(electric, {
                "Itotal",
                "I13",
                "I24",
                "Current",
                "Current750V",
                "BatteryCurrent",
            }),
            MaxAbsField(
                istable(train.AsyncInverter)
                    and train.AsyncInverter
                    or nil,
                {
                    "Current",
                    "Current1",
                    "Current2",
                }
            ),
            MaxAbsField(
                istable(train.Engines)
                    and train.Engines
                    or nil,
                {
                    "Current",
                    "I",
                    "I13",
                    "I24",
                }
            )
        )

        local voltage = math.max(hv, lv)

        -- This is a gameplay fault-current capacity, not an electrical-safety
        -- calculator. Prefer actual Metrostroi current when present, but keep
        -- an energized source hazardous even while traction load is currently
        -- zero.
        local sourceCurrent
        if hv >= 200 then
            sourceCurrent = math.max(
                measuredCurrent,
                90 + hv * 0.20
            )
        elseif lv >= 24 then
            sourceCurrent = math.max(
                measuredCurrent,
                8 + lv * 0.22
            )
        else
            sourceCurrent = measuredCurrent
        end

        return math.Clamp(voltage, 0, 1200),
            math.Clamp(sourceCurrent, 0, 2000),
            math.Clamp(hv, 0, 1200),
            math.Clamp(lv, 0, 200)
    end

    local function IsTrainInstrumentationPowered(train)
        if not IsSubwayTrain(train) then return false end

        local _, _, _, lv =
            GetTrainElectricalWaterState(train)

        if lv >= 18 then
            return true
        end

        local modernSystems = {
            train.BUKV,
            train.BUKP,
            train.BUP,
            train.BUV,
            train.BUVS,
        }

        for _, system in ipairs(modernSystems) do
            if istable(system) then
                local power =
                    tonumber(system.Power)
                    or tonumber(system.Active)
                    or tonumber(system.Enabled)

                if power and power > 0.05 then
                    return true
                end
            end
        end

        if istable(train.Panel) then
            local v1 = tonumber(train.Panel.V1)
            if v1 and v1 > 0.05 then
                return true
            end
        end

        return false
    end

    local function EmitWaterElectricalArc(
        train,
        worldPos,
        voltage,
        current,
        severe
    )
        if not IsSubwayTrain(train) then return end

        worldPos = isvector(worldPos)
            and worldPos
            or train:WorldSpaceCenter()

        local effect = EffectData()
        effect:SetOrigin(worldPos)
        effect:SetNormal(VectorRand():GetNormalized())
        effect:SetMagnitude(
            math.Clamp(1 + voltage / 220, 1, 6)
        )
        effect:SetScale(
            math.Clamp(0.6 + current / 180, 0.6, 3.2)
        )
        effect:SetRadius(
            math.Clamp(8 + voltage / 15, 10, 70)
        )
        util.Effect("Sparks", effect, true, true)

        local soundName = WATER_ARC_SOUNDS[
            math.random(1, #WATER_ARC_SOUNDS)
        ]

        train:EmitSound(
            soundName,
            severe and 92 or 78,
            math.random(severe and 82 or 94, severe and 102 or 116),
            math.Clamp(0.45 + voltage / 1200, 0.45, 1)
        )
    end

    local function IsCircuitBreakerSystem(systemName, system)
        if not isstring(systemName) or not istable(system) then
            return false
        end

        local upper = string.upper(systemName)
        local relayType = tostring(system.relay_type or "")

        if relayType == "VA21-29" then
            return true
        end

        return string.match(upper, "^A%d+$") ~= nil
            or string.match(upper, "^AV%d*$") ~= nil
            or string.match(upper, "^SF%d+$") ~= nil
            or string.match(upper, "^QF%d+$") ~= nil
            or string.match(upper, "^CB%d*$") ~= nil
    end

    local function IsFuseSystemName(systemName)
        if not isstring(systemName) then return false end

        local upper = string.upper(systemName)
        return string.match(upper, "^PNB_1250_") ~= nil
            or upper == "PP_28"
            or string.match(upper, "^FU%d*$") ~= nil
            or string.match(upper, "^FUSE") ~= nil
    end

    local function TripCircuitBreaker(train, systemName)
        if not IsSubwayTrain(train) then return false end

        local system = train[systemName]
        if not IsRelayLikeElectricalSystem(system)
            or not IsCircuitBreakerSystem(systemName, system)
        then
            return false
        end

        train.MEXDamageTrippedProtection =
            train.MEXDamageTrippedProtection or {}

        if not train.MEXDamageTrippedProtection[systemName] then
            train.MEXDamageTrippedProtection[systemName] = {
                kind = "breaker",
                originalValue = tonumber(system.Value),
                originalTargetValue = tonumber(system.TargetValue),
            }
        end

        -- VA21-29 implements a real breaker trip path: Check < 0 opens the
        -- breaker and plays Metrostroi's native av_off sound. Other breaker
        -- families use their normal Set/Open input.
        if tostring(system.relay_type or "") == "VA21-29" then
            pcall(system.TriggerInput, system, "Check", -1)
        else
            pcall(system.TriggerInput, system, "Set", 0)
            pcall(system.TriggerInput, system, "Open", 1)
        end

        return true
    end

    local function BlowFuse(train, systemName)
        if not IsSubwayTrain(train)
            or not IsFuseSystemName(systemName)
        then
            return false
        end

        local system = train[systemName]
        if not IsRelayLikeElectricalSystem(system) then
            return false
        end

        -- A fuse is not a resettable breaker. Reuse the persistent failed-open
        -- layer so it stays open until Train Fixer / mex_damage_reset repairs it.
        if not FailElectricalSystemOpen(
            train,
            systemName,
            { cause = "fuse", temporary = false }
        ) then
            return false
        end

        train.MEXDamageBlownFuses =
            train.MEXDamageBlownFuses or {}
        train.MEXDamageBlownFuses[systemName] = true
        return true
    end

    local function RestoreTrippedProtection(train)
        if not IsValid(train) then return end

        for systemName, data in pairs(
            train.MEXDamageTrippedProtection or {}
        ) do
            local system = train[systemName]
            if not istable(system)
                or not isfunction(system.TriggerInput)
            then
                continue
            end

            local target = tonumber(data.originalTargetValue)
            local value = tonumber(data.originalValue)
            local restore = target ~= nil and target or value

            if restore ~= nil then
                pcall(
                    system.TriggerInput,
                    system,
                    "Set",
                    restore
                )
            end
        end

        train.MEXDamageTrippedProtection = {}
        train.MEXDamageBlownFuses = {}
        train.MEXDamageNextProtectionRetrip = nil
    end

    local function IsProtectionClosed(system)
        if not istable(system) then return false end

        local value = tonumber(system.Value)
        local target = tonumber(system.TargetValue)

        return (value and value > 0.5)
            or (target and target > 0.5)
    end

    local function CollectWaterProtectionCandidates(
        train,
        highVoltage
    )
        local breakers = {}
        local fuses = {}

        if not istable(train.Systems) then
            return breakers, fuses
        end

        for systemName, system in pairs(train.Systems) do
            systemName = tostring(systemName)

            if not IsRelayLikeElectricalSystem(system) then
                continue
            end

            if IsFuseSystemName(systemName) then
                local alreadyBlown =
                    train.MEXDamageBlownFuses
                    and train.MEXDamageBlownFuses[systemName]

                local failedOpen =
                    train.MEXDamageElectricalFailureSystems
                    and train.MEXDamageElectricalFailureSystems[systemName]

                if alreadyBlown or failedOpen then
                    continue
                end

                local upper = string.upper(systemName)

                if highVoltage then
                    if string.match(upper, "^PNB_1250_") then
                        fuses[#fuses + 1] = systemName
                    end
                elseif upper == "PP_28"
                    or string.match(upper, "^FU%d*$")
                then
                    fuses[#fuses + 1] = systemName
                end
            elseif IsCircuitBreakerSystem(systemName, system)
                and IsProtectionClosed(system)
            then
                breakers[#breakers + 1] = systemName
            end
        end

        return breakers, fuses
    end

    local function OperateWaterProtection(
        train,
        highVoltage,
        worldPos,
        voltage,
        current
    )
        local breakers, fuses =
            CollectWaterProtectionCandidates(
                train,
                highVoltage
            )

        -- For classic high-voltage cars, PNB-1250 is the actual main-circuit
        -- fuse and therefore takes precedence over unrelated cab breakers.
        if highVoltage and #fuses > 0 then
            local fuse = fuses[math.random(1, #fuses)]
            if BlowFuse(train, fuse) then
                train:SetNW2String(
                    "MEX.Damage.LastProtection",
                    fuse .. " (fuse)"
                )
                EmitWaterElectricalArc(
                    train,
                    worldPos,
                    voltage,
                    current,
                    true
                )
                return true, fuse, "fuse"
            end
        end

        -- Low-voltage/control faults normally trip a resettable automatic
        -- breaker first. This does not mark the breaker itself as destroyed.
        if #breakers > 0 then
            local breaker =
                breakers[math.random(1, #breakers)]

            if TripCircuitBreaker(train, breaker) then
                train:SetNW2String(
                    "MEX.Damage.LastProtection",
                    breaker .. " (breaker)"
                )
                EmitWaterElectricalArc(
                    train,
                    worldPos,
                    voltage,
                    current,
                    highVoltage
                )
                return true, breaker, "breaker"
            end
        end

        -- Some older cars have an auxiliary PP-28 fuse instead of a suitable
        -- automatic breaker for the affected auxiliary circuit.
        if #fuses > 0 then
            local fuse = fuses[math.random(1, #fuses)]
            if BlowFuse(train, fuse) then
                train:SetNW2String(
                    "MEX.Damage.LastProtection",
                    fuse .. " (fuse)"
                )
                EmitWaterElectricalArc(
                    train,
                    worldPos,
                    voltage,
                    current,
                    highVoltage
                )
                return true, fuse, "fuse"
            end
        end

        return false
    end

    local function RetripWaterProtectionIfNeeded(
        train,
        wetness,
        voltage,
        current,
        sparkPos
    )
        if wetness <= 0.04 or voltage < 24 then return end

        local now = CurTime()
        if (train.MEXDamageNextProtectionRetrip or 0) > now then
            return
        end
        train.MEXDamageNextProtectionRetrip = now + 0.07

        for systemName, data in pairs(
            train.MEXDamageTrippedProtection or {}
        ) do
            if data.kind ~= "breaker" then continue end

            local system = train[systemName]
            if IsProtectionClosed(system) then
                TripCircuitBreaker(train, systemName)
                EmitWaterElectricalArc(
                    train,
                    sparkPos,
                    voltage,
                    current,
                    voltage >= 200
                )
            end
        end
    end

    local function ForceSensitiveSystemOutputsOff(
        system,
        data
    )
        if not istable(system) or not istable(data) then return end

        for _, fieldName in ipairs(data.outputFields or {}) do
            local value = system[fieldName]

            if isnumber(value) then
                system[fieldName] = 0
            elseif isbool(value) then
                system[fieldName] = false
            end
        end

        local common = {
            "Active",
            "Power",
            "Powered",
            "Enabled",
            "Enable",
            "Working",
            "Online",
        }

        for _, fieldName in ipairs(common) do
            local value = system[fieldName]

            if isnumber(value) then
                system[fieldName] = 0
            elseif isbool(value) then
                system[fieldName] = false
            end
        end
    end

    local function GetSensitiveSystemOutputs(system)
        local outputs = {}

        if not istable(system) or not isfunction(system.Outputs) then
            return outputs
        end

        local ok, result = pcall(system.Outputs, system)
        if not ok or not istable(result) then
            return outputs
        end

        local seen = {}
        for _, fieldName in ipairs(result) do
            if isstring(fieldName)
                and fieldName ~= ""
                and not seen[fieldName]
            then
                seen[fieldName] = true
                outputs[#outputs + 1] = fieldName
            end
        end

        return outputs
    end

    local function DisableSensitiveWaterSystem(
        train,
        systemName,
        options
    )
        if not IsSubwayTrain(train)
            or not isstring(systemName)
            or systemName == ""
        then
            return false
        end

        local system = train[systemName]
        if not istable(system) or not isfunction(system.Think) then
            return false
        end

        options = istable(options) and options or {}

        train.MEXDamageWetSensitiveSystems =
            train.MEXDamageWetSensitiveSystems or {}

        local data =
            train.MEXDamageWetSensitiveSystems[systemName]

        if not data then
            data = {
                originalThink = system.Think,
                originalTriggerInput = system.TriggerInput,
                outputFields = GetSensitiveSystemOutputs(system),
                permanent = false,
            }

            train.MEXDamageWetSensitiveSystems[systemName] = data

            system.Think = function(self, ...)
                local disabled =
                    IsValid(train)
                    and train.MEXDamageWetSensitiveSystems
                    and train.MEXDamageWetSensitiveSystems[systemName]
                    or nil

                if disabled then
                    ForceSensitiveSystemOutputsOff(self, disabled)
                    return
                end

                return data.originalThink(self, ...)
            end

            if isfunction(data.originalTriggerInput) then
                system.TriggerInput = function(self, ...)
                    -- Inputs are still accepted while the module is wet. This
                    -- lets the driver move physical switches normally; the
                    -- electronics simply produces no useful output until it
                    -- recovers.
                    local result =
                        data.originalTriggerInput(self, ...)

                    local disabled =
                        IsValid(train)
                        and train.MEXDamageWetSensitiveSystems
                        and train.MEXDamageWetSensitiveSystems[systemName]
                        or nil

                    if disabled then
                        ForceSensitiveSystemOutputsOff(
                            self,
                            disabled
                        )
                    end

                    return result
                end
            end
        end

        if options.permanent == true then
            data.permanent = true
        end

        data.sensitivity =
            options.sensitivity or data.sensitivity or "sensitive"
        data.minDrySeconds = math.max(
            tonumber(options.minDrySeconds) or 90,
            tonumber(data.minDrySeconds) or 0
        )
        data.recoverMoisture = math.min(
            tonumber(options.recoverMoisture) or 0.05,
            tonumber(data.recoverMoisture) or 1
        )

        ForceSensitiveSystemOutputsOff(system, data)
        return true
    end

    local function RestoreSensitiveWaterSystem(
        train,
        systemName
    )
        if not IsSubwayTrain(train)
            or not istable(train.MEXDamageWetSensitiveSystems)
        then
            return false
        end

        local data =
            train.MEXDamageWetSensitiveSystems[systemName]
        local system = train[systemName]

        if not istable(data) or not istable(system) then
            train.MEXDamageWetSensitiveSystems[systemName] = nil
            return false
        end

        if isfunction(data.originalThink) then
            system.Think = data.originalThink
        end

        if data.originalTriggerInput ~= nil then
            system.TriggerInput = data.originalTriggerInput
        end

        train.MEXDamageWetSensitiveSystems[systemName] = nil
        return true
    end

    local function RestoreSensitiveWaterSystems(train)
        if not IsValid(train)
            or not istable(train.MEXDamageWetSensitiveSystems)
        then
            return
        end

        local names = {}
        for systemName in pairs(
            train.MEXDamageWetSensitiveSystems
        ) do
            names[#names + 1] = systemName
        end

        for _, systemName in ipairs(names) do
            RestoreSensitiveWaterSystem(train, systemName)
        end

        train.MEXDamageWetSensitiveSystems = {}
    end

    local function IsManualOperatorElectricalSystem(
        systemName,
        system
    )
        if not isstring(systemName) or not istable(system) then
            return false
        end

        local relayType = tostring(system.relay_type or "")

        -- These are physical panel switches, breaker handles or mechanical HV
        -- operators. Water may make the circuit behind them ineffective, but
        -- it must not freeze the visible handle in one position.
        if relayType == "Switch"
            or relayType == "VA21-29"
            or relayType == "GV_10ZH"
        then
            return true
        end

        if IsCircuitBreakerSystem(systemName, system)
            or IsFuseSystemName(systemName)
        then
            return true
        end

        return IsMechanicalElectricalException(
            systemName,
            "",
            {}
        )
    end

    local SENSITIVE_WATER_ELECTRONICS = {
        "ars",
        "als",
        "bars",
        "bpsn",
        "bup",
        "buv",
        "bep",
        "igla",
        "asnp",
        "upo",
        "puav",
        "vityaz",
        "inverter",
        "async",
        "radio",
        "rri",
        "announcer",
        "informator",
        "computer",
        "display",
    }

    local function WaterElectronicSensitivity(systemName)
        local lower = string.lower(tostring(systemName or ""))

        for _, token in ipairs(SENSITIVE_WATER_ELECTRONICS) do
            if string.find(lower, token, 1, true) then
                return "sensitive"
            end
        end

        return "normal"
    end

    local function CollectSensitiveWaterSystemCandidates(train)
        local candidates = {}

        if not istable(train.Systems) then
            return candidates
        end

        for systemName, system in pairs(train.Systems) do
            systemName = tostring(systemName)

            if WaterElectronicSensitivity(systemName) ~= "sensitive" then
                continue
            end

            if not istable(system) or not isfunction(system.Think) then
                continue
            end

            if IsManualOperatorElectricalSystem(
                systemName,
                system
            ) then
                continue
            end

            if train.MEXDamageWetSensitiveSystems
                and train.MEXDamageWetSensitiveSystems[systemName]
            then
                continue
            end

            candidates[#candidates + 1] = systemName
        end

        return candidates
    end

    local function CollectWaterFailureCandidates(train)
        local active = {}
        local inactive = {}

        if not istable(train.Systems) then
            return active, inactive
        end

        for systemName, system in pairs(train.Systems) do
            systemName = tostring(systemName)

            if not IsRelayLikeElectricalSystem(system) then
                continue
            end

            if train.MEXDamageElectricalFailureSystems
                and train.MEXDamageElectricalFailureSystems[systemName]
            then
                continue
            end

            -- Important: do not water-fail the operator itself. A soaked VU,
            -- battery switch, breaker lever etc. must remain physically
            -- movable. The downstream circuit/equipment may fail instead.
            if IsManualOperatorElectricalSystem(
                systemName,
                system
            ) then
                continue
            end

            local item = {
                name = systemName,
                sensitivity =
                    WaterElectronicSensitivity(systemName),
            }

            local target = tonumber(system.TargetValue)
            local value = tonumber(system.Value)
            local energized =
                (target and target > 0.05)
                or (value and value > 0.05)

            if energized then
                active[#active + 1] = item
            else
                inactive[#inactive + 1] = item
            end
        end

        return active, inactive
    end

    local function FailRandomWaterElectricalSystem(
        train,
        worldPos,
        voltage,
        current,
        wetness
    )
        local sensitiveSystems =
            CollectSensitiveWaterSystemCandidates(train)
        local active, inactive =
            CollectWaterFailureCandidates(train)

        local relaySource =
            #active > 0 and active or inactive

        -- Sensitive electronic modules (ARS/ALS/BPSN/radio/information
        -- electronics, when present as real Metrostroi systems) fail before a
        -- robust electromechanical relay. Their panel switches remain movable;
        -- the module simply produces no useful output while offline.
        local chooseSensitive =
            #sensitiveSystems > 0
            and (
                #relaySource <= 0
                or math.Rand(0, 1) < 0.58
            )

        if chooseSensitive then
            local systemName =
                sensitiveSystems[
                    math.random(1, #sensitiveSystems)
                ]

            local permanentChance = math.Clamp(
                0.08
                    + math.Clamp(voltage / 750, 0, 1) * 0.22
                    + math.Clamp(current / 600, 0, 1) * 0.14
                    + math.Clamp(tonumber(wetness) or 0, 0, 1) * 0.10,
                0,
                0.48
            )

            local permanent =
                math.Rand(0, 1) < permanentChance

            if not DisableSensitiveWaterSystem(
                train,
                systemName,
                {
                    permanent = permanent,
                    sensitivity = "sensitive",
                    minDrySeconds = 95,
                    recoverMoisture = 0.045,
                }
            ) then
                return false
            end

            train:SetNW2Bool(
                "MEX.Damage.ElectricalFault",
                true
            )

            local electrical = train:GetNW2Float(
                "MEX.Damage.electrical",
                0
            )
            train:SetNW2Float(
                "MEX.Damage.electrical",
                math.Clamp(electrical + 0.11, 0, 1)
            )

            EmitWaterElectricalArc(
                train,
                worldPos,
                voltage,
                current,
                voltage >= 200
            )

            return true
        end

        if #relaySource <= 0 then return false end

        local item =
            relaySource[math.random(1, #relaySource)]
        local systemName = item.name
        local sensitive =
            item.sensitivity == "sensitive"

        local permanentChance = math.Clamp(
            (sensitive and 0.06 or 0.015)
                + math.Clamp(voltage / 750, 0, 1)
                    * (sensitive and 0.18 or 0.06)
                + math.Clamp(current / 600, 0, 1)
                    * (sensitive and 0.12 or 0.04)
                + math.Clamp(tonumber(wetness) or 0, 0, 1)
                    * (sensitive and 0.08 or 0.025),
            0,
            sensitive and 0.42 or 0.14
        )

        local permanent =
            math.Rand(0, 1) < permanentChance

        local options = {
            cause = "water",
            temporary = not permanent,
            waterSensitivity =
                sensitive and "sensitive" or "normal",
            minDrySeconds =
                sensitive and 80 or 25,
            recoverMoisture =
                sensitive and 0.055 or 0.14,
        }

        if not FailElectricalSystemOpen(
            train,
            systemName,
            options
        ) then
            return false
        end

        train:SetNW2Bool(
            "MEX.Damage.ElectricalFault",
            true
        )

        local electrical = train:GetNW2Float(
            "MEX.Damage.electrical",
            0
        )
        train:SetNW2Float(
            "MEX.Damage.electrical",
            math.Clamp(
                electrical + (sensitive and 0.10 or 0.06),
                0,
                1
            )
        )

        EmitWaterElectricalArc(
            train,
            worldPos,
            voltage,
            current,
            voltage >= 200
        )

        return true
    end

    local function UpdateWaterMoistureState(
        train,
        wetness,
        dT
    )
        local surface = math.Clamp(
            NumberOrZero(train.MEXDamageWaterMoisture),
            0,
            1
        )
        local deep = math.Clamp(
            NumberOrZero(train.MEXDamageDeepMoisture),
            0,
            1
        )

        if wetness > 0.015 then
            train.MEXDamageDrySince = nil

            surface = math.Clamp(
                surface
                    + dT * (0.045 + wetness * 0.11),
                0,
                1
            )

            deep = math.Clamp(
                deep
                    + dT * wetness * 0.035,
                0,
                1
            )
        else
            if not train.MEXDamageDrySince then
                train.MEXDamageDrySince = CurTime()
            end

            surface = math.max(
                0,
                surface - dT / WATER_SURFACE_DRY_SECONDS
            )
            deep = math.max(
                0,
                deep - dT / WATER_DEEP_DRY_SECONDS
            )
        end

        train.MEXDamageWaterMoisture = surface
        train.MEXDamageDeepMoisture = deep

        local drySeconds =
            train.MEXDamageDrySince
            and math.max(0, CurTime() - train.MEXDamageDrySince)
            or 0

        train:SetNW2Float(
            "MEX.Damage.WaterMoisture",
            surface
        )
        train:SetNW2Float(
            "MEX.Damage.DeepMoisture",
            deep
        )
        train:SetNW2Float(
            "MEX.Damage.DrySeconds",
            drySeconds
        )

        return surface, deep, drySeconds
    end

    local function RecoverDriedWaterFailures(
        train,
        surfaceMoisture,
        deepMoisture,
        drySeconds
    )
        local recoveredAny = false

        if istable(train.MEXDamageElectricalFailureSystems) then
            local recover = {}

            for systemName, data in pairs(
                train.MEXDamageElectricalFailureSystems
            ) do
                if not istable(data)
                    or data.permanent == true
                    or data.temporary ~= true
                    or not (data.causes and data.causes.water)
                then
                    continue
                end

                local sensitive =
                    data.waterSensitivity == "sensitive"
                local moisture =
                    sensitive and deepMoisture or surfaceMoisture
                local threshold =
                    tonumber(data.recoverMoisture)
                    or (sensitive and 0.055 or 0.14)
                local minDry =
                    tonumber(data.minDrySeconds)
                    or (sensitive and 80 or 25)

                if moisture <= threshold
                    and drySeconds >= minDry
                then
                    recover[#recover + 1] = systemName
                end
            end

            for _, systemName in ipairs(recover) do
                if RestoreSingleElectricalFailure(
                    train,
                    systemName,
                    true
                ) then
                    recoveredAny = true
                end
            end
        end

        if istable(train.MEXDamageWetSensitiveSystems) then
            local recoverSensitive = {}

            for systemName, data in pairs(
                train.MEXDamageWetSensitiveSystems
            ) do
                if not istable(data)
                    or data.permanent == true
                then
                    continue
                end

                local threshold =
                    tonumber(data.recoverMoisture) or 0.045
                local minDry =
                    tonumber(data.minDrySeconds) or 95

                if deepMoisture <= threshold
                    and drySeconds >= minDry
                then
                    recoverSensitive[#recoverSensitive + 1] =
                        systemName
                end
            end

            for _, systemName in ipairs(recoverSensitive) do
                if RestoreSensitiveWaterSystem(
                    train,
                    systemName
                ) then
                    recoveredAny = true
                end
            end
        end

        if recoveredAny then
            local relayFailure =
                istable(train.MEXDamageElectricalFailureSystems)
                and next(train.MEXDamageElectricalFailureSystems)
                    ~= nil
            local sensitiveFailure =
                istable(train.MEXDamageWetSensitiveSystems)
                and next(train.MEXDamageWetSensitiveSystems)
                    ~= nil
            local blownFuse =
                istable(train.MEXDamageBlownFuses)
                and next(train.MEXDamageBlownFuses)
                    ~= nil

            train:SetNW2Bool(
                "MEX.Damage.ElectricalFault",
                relayFailure
                    or sensitiveFailure
                    or blownFuse
            )
        end
    end

    local function PackedBoolLooksLikeIndicator(idx)
        if not isstring(idx) then return false end

        local lower = string.lower(idx)

        local tokens = {
            "lamp",
            "light",
            "led",
            "indicator",
            "signal",
            "warning",
            "fault",
            "alarm",
            "gauge",
            "panel",
        }

        for _, token in ipairs(tokens) do
            if string.find(lower, token, 1, true) then
                return true
            end
        end

        return false
    end

    local function PackedRatioLooksLikeSpeedIndicator(idx)
        if not isstring(idx) then return false end

        local lower = string.lower(idx)

        return lower == "speed"
            or string.find(lower, "speedometer", 1, true) ~= nil
            or string.find(lower, "speed_meter", 1, true) ~= nil
            or string.find(lower, "cps_speed", 1, true) ~= nil
    end

    local function PackedRatioLooksLikeElectricGauge(idx)
        if not isstring(idx) then return false end

        local lower = string.lower(idx)

        if string.find(lower, "pressure", 1, true)
            or string.find(lower, "brake", 1, true)
            or string.find(lower, "trainline", 1, true)
        then
            return false
        end

        local tokens = {
            "voltage",
            "volt",
            "current",
            "amp",
            "battery",
            "ammeter",
            "voltmeter",
            "meter",
            "electric",
            "power",
            "lamp",
            "lighting",
            "lightstrength",
        }

        for _, token in ipairs(tokens) do
            if string.find(lower, token, 1, true) then
                return true
            end
        end

        return false
    end

    local function RestoreWaterVisualGlitchHooks(train)
        if not IsValid(train) then return end

        if train.MEXDamageOriginalSetPackedBool then
            train.SetPackedBool =
                train.MEXDamageOriginalSetPackedBool
        end

        if train.MEXDamageOriginalSetPackedRatio then
            train.SetPackedRatio =
                train.MEXDamageOriginalSetPackedRatio
        end

        train.MEXDamageOriginalSetPackedBool = nil
        train.MEXDamageOriginalSetPackedRatio = nil
        train.MEXDamageWaterVisualHooksInstalled = nil
        train.MEXDamageWaterVisualGlitchUntil = nil
        train.MEXDamageWaterVisualGlitchIntensity = 0
    end

    local function EnsureWaterVisualGlitchHooks(train)
        if not IsSubwayTrain(train)
            or train.MEXDamageWaterVisualHooksInstalled
        then
            return
        end

        if isfunction(train.SetPackedBool) then
            local originalSetPackedBool =
                train.SetPackedBool

            train.MEXDamageOriginalSetPackedBool =
                originalSetPackedBool

            train.SetPackedBool = function(self, idx, value)
                local glitching =
                    (self.MEXDamageWaterVisualGlitchUntil or 0)
                        > CurTime()
                local intensity = math.Clamp(
                    tonumber(
                        self.MEXDamageWaterVisualGlitchIntensity
                    ) or 0,
                    0,
                    1
                )

                if glitching
                    and intensity > 0.01
                    and PackedBoolLooksLikeIndicator(idx)
                    and math.Rand(0, 1)
                        < 0.18 + intensity * 0.62
                then
                    value = not tobool(value)
                end

                return originalSetPackedBool(
                    self,
                    idx,
                    value
                )
            end
        end

        if isfunction(train.SetPackedRatio) then
            local originalSetPackedRatio =
                train.SetPackedRatio

            train.MEXDamageOriginalSetPackedRatio =
                originalSetPackedRatio

            train.SetPackedRatio = function(self, idx, value)
                local glitching =
                    (self.MEXDamageWaterVisualGlitchUntil or 0)
                        > CurTime()
                local intensity = math.Clamp(
                    tonumber(
                        self.MEXDamageWaterVisualGlitchIntensity
                    ) or 0,
                    0,
                    1
                )

                local speedIndicator =
                    PackedRatioLooksLikeSpeedIndicator(idx)

                -- Metrostroi normally keeps publishing physical Speed even on
                -- several cars whose cab speedometer should be electrically
                -- dead. Expanded gates the displayed speed by the actual
                -- low-voltage/instrument power state.
                if speedIndicator
                    and not IsTrainInstrumentationPowered(self)
                then
                    value = 0
                elseif speedIndicator
                    and glitching
                    and intensity > 0.01
                then
                    local mode = math.random(1, 5)

                    if mode == 1 then
                        value = 0
                    elseif mode == 2 then
                        value = math.Rand(0, 1)
                    elseif mode == 3 then
                        value = math.Clamp(
                            (tonumber(value) or 0)
                                + math.Rand(-0.60, 0.60)
                                    * intensity,
                            0,
                            1
                        )
                    elseif mode == 4 then
                        value = math.Rand(0.75, 1.0)
                    else
                        value = math.Rand(0, 0.12)
                    end
                elseif glitching
                    and intensity > 0.01
                    and PackedRatioLooksLikeElectricGauge(idx)
                then
                    local mode = math.random(1, 4)

                    if mode == 1 then
                        value = math.Rand(0, 1)
                    elseif mode == 2 then
                        value = math.Clamp(
                            (tonumber(value) or 0)
                                + math.Rand(-0.75, 0.75)
                                    * intensity,
                            0,
                            1
                        )
                    elseif mode == 3 then
                        value = math.Rand(0.82, 1.0)
                    else
                        value = math.Rand(0, 0.16)
                    end
                end

                return originalSetPackedRatio(
                    self,
                    idx,
                    value
                )
            end
        end

        train.MEXDamageWaterVisualHooksInstalled = true
    end

    local function RestoreWaterBatteryGlitchHook(train)
        if not IsValid(train) then return end

        local battery = train.Battery

        if istable(battery)
            and train.MEXDamageOriginalBatteryThink
        then
            battery.Think =
                train.MEXDamageOriginalBatteryThink
        end

        train.MEXDamageOriginalBatteryThink = nil
        train.MEXDamageBatteryGlitchHookInstalled = nil
        train.MEXDamageBatteryGlitchUntil = nil
        train.MEXDamageBatteryVoltageFactor = nil
        train:SetNW2Float(
            "MEX.Damage.BatteryGlitchFactor",
            1
        )
    end

    local function EnsureWaterBatteryGlitchHook(train)
        if not IsSubwayTrain(train)
            or train.MEXDamageBatteryGlitchHookInstalled
            or not istable(train.Battery)
            or not isfunction(train.Battery.Think)
        then
            return
        end

        local battery = train.Battery
        local originalThink = battery.Think

        train.MEXDamageOriginalBatteryThink = originalThink

        battery.Think = function(self, ...)
            local result = originalThink(self, ...)

            if IsValid(train)
                and (train.MEXDamageBatteryGlitchUntil or 0)
                    > CurTime()
            then
                local factor = math.Clamp(
                    tonumber(
                        train.MEXDamageBatteryVoltageFactor
                    ) or 1,
                    0.10,
                    1.10
                )

                if isnumber(self.Voltage) then
                    self.Voltage = self.Voltage * factor
                end

                if isnumber(self.Current) then
                    self.Current =
                        self.Current
                        + math.Rand(-18, 18)
                            * (1 - factor + 0.15)
                end
            end

            return result
        end

        train.MEXDamageBatteryGlitchHookInstalled = true
    end

    local function StartWaterBatteryGlitch(
        train,
        intensity
    )
        if not IsSubwayTrain(train)
            or not istable(train.Battery)
        then
            return false
        end

        EnsureWaterBatteryGlitchHook(train)

        local now = CurTime()
        local severe =
            math.Rand(0, 1) < (0.15 + intensity * 0.45)

        local factor
        if severe then
            factor = math.Rand(
                0.18,
                Lerp(intensity, 0.65, 0.32)
            )
        else
            factor = math.Rand(
                Lerp(intensity, 0.92, 0.56),
                1.04
            )
        end

        train.MEXDamageBatteryVoltageFactor = factor
        train.MEXDamageBatteryGlitchUntil =
            now + math.Rand(0.05, 0.32 + intensity * 0.35)

        train:SetNW2Float(
            "MEX.Damage.BatteryGlitchFactor",
            factor
        )

        if factor < 0.55 then
            train:EmitSound(
                WATER_RELAY_CHATTER_SOUNDS[
                    math.random(
                        1,
                        #WATER_RELAY_CHATTER_SOUNDS
                    )
                ],
                66,
                math.random(88, 108),
                0.52
            )
        end

        return true
    end

    local DOOR_WATER_RELAY_NAMES = {
        kdl = true,
        kdlr = true,
        kdp = true,
        kdpk = true,
        kdlk = true,
        kdph = true,
        vdl = true,
        vud = true,
        vud1 = true,
        vud2 = true,
        doorleft = true,
        doorright = true,
        doorleft2 = true,
        doorright2 = true,
        doorclose = true,
        emerclosedoors = true,
        emergencydoors = true,
    }

    local function CollectWaterDoorRelayCandidates(train)
        local candidates = {}

        if not istable(train.Systems) then
            return candidates
        end

        for systemName, system in pairs(train.Systems) do
            local lower =
                string.lower(tostring(systemName))

            if not DOOR_WATER_RELAY_NAMES[lower] then
                continue
            end

            if not IsRelayLikeElectricalSystem(system)
                or not isfunction(system.TriggerInput)
            then
                continue
            end

            if train.MEXDamageElectricalFailureSystems
                and train.MEXDamageElectricalFailureSystems[
                    tostring(systemName)
                ]
            then
                continue
            end

            candidates[#candidates + 1] = {
                name = tostring(systemName),
                system = system,
            }
        end

        return candidates
    end

    local function StartWaterDoorRelayFault(
        train,
        intensity
    )
        if not IsSubwayTrain(train) then return false end

        local candidates =
            CollectWaterDoorRelayCandidates(train)

        if #candidates <= 0 then return false end

        train.MEXDamageRelayChatter =
            train.MEXDamageRelayChatter or {}

        local item =
            candidates[math.random(1, #candidates)]

        if train.MEXDamageRelayChatter[item.name] then
            return false
        end

        local system = item.system
        local trigger = system.TriggerInput
        local originalTarget =
            tonumber(system.TargetValue)
        local originalValue =
            tonumber(system.Value)
        local current =
            originalTarget ~= nil
                and originalTarget
                or originalValue
                or 0

        -- This is a bridged wet contact downstream of the driver's hand
        -- control. It does not call ButtonEvent, so the physical button/toggle
        -- does not need to move even though the door command relay energizes.
        local faultValue =
            current > 0.5 and 0 or 1

        train.MEXDamageRelayChatter[item.name] = {
            trigger = trigger,
            originalTarget = originalTarget,
            originalValue = originalValue,
            restoreAt =
                CurTime()
                + math.Rand(
                    0.08,
                    0.28 + intensity * 0.55
                ),
            waterDoorFault = true,
        }

        pcall(
            trigger,
            system,
            "Set",
            faultValue
        )

        train:SetNW2String(
            "MEX.Damage.ChatteringRelay",
            item.name
        )
        train:SetNW2String(
            "MEX.Damage.DoorWaterFault",
            item.name
        )

        train:EmitSound(
            WATER_RELAY_CHATTER_SOUNDS[
                math.random(
                    1,
                    #WATER_RELAY_CHATTER_SOUNDS
                )
            ],
            68,
            math.random(88, 112),
            0.58
        )

        return true
    end

    local function CollectWaterRelayChatterCandidates(train)
        local candidates = {}

        if not istable(train.Systems) then
            return candidates
        end

        for systemName, system in pairs(train.Systems) do
            systemName = tostring(systemName)

            if not IsRelayLikeElectricalSystem(system) then
                continue
            end

            if IsManualOperatorElectricalSystem(
                systemName,
                system
            ) then
                continue
            end

            if IsCircuitBreakerSystem(systemName, system)
                or IsFuseSystemName(systemName)
            then
                continue
            end

            if train.MEXDamageElectricalFailureSystems
                and train.MEXDamageElectricalFailureSystems[systemName]
            then
                continue
            end

            if train.MEXDamageWetSensitiveSystems
                and train.MEXDamageWetSensitiveSystems[systemName]
            then
                continue
            end

            if not isfunction(system.TriggerInput) then
                continue
            end

            candidates[#candidates + 1] = {
                name = systemName,
                system = system,
            }
        end

        return candidates
    end

    local function RestoreWaterRelayChatter(train)
        if not IsSubwayTrain(train)
            or not istable(train.MEXDamageRelayChatter)
        then
            return
        end

        for systemName, data in pairs(
            train.MEXDamageRelayChatter
        ) do
            local system = train[systemName]

            if istable(system)
                and istable(data)
                and isfunction(data.trigger)
            then
                pcall(
                    data.trigger,
                    system,
                    "Set",
                    tonumber(data.originalTarget)
                        or tonumber(data.originalValue)
                        or 0
                )
            end
        end

        train.MEXDamageRelayChatter = {}
        train:SetNW2String(
            "MEX.Damage.ChatteringRelay",
            ""
        )
        train:SetNW2String(
            "MEX.Damage.DoorWaterFault",
            ""
        )
    end

    local function ProcessWaterRelayChatter(train)
        if not IsSubwayTrain(train)
            or not istable(train.MEXDamageRelayChatter)
        then
            return
        end

        local now = CurTime()

        for systemName, data in pairs(
            train.MEXDamageRelayChatter
        ) do
            if now < (data.restoreAt or 0) then
                continue
            end

            local system = train[systemName]
            if istable(system)
                and isfunction(data.trigger)
            then
                pcall(
                    data.trigger,
                    system,
                    "Set",
                    tonumber(data.originalTarget)
                        or tonumber(data.originalValue)
                        or 0
                )
            end

            train.MEXDamageRelayChatter[systemName] = nil
        end

        if next(train.MEXDamageRelayChatter) == nil then
            train:SetNW2String(
                "MEX.Damage.ChatteringRelay",
                ""
            )
            train:SetNW2String(
                "MEX.Damage.DoorWaterFault",
                ""
            )
        else
            local hasDoorFault = false

            for _, data in pairs(
                train.MEXDamageRelayChatter
            ) do
                if data.waterDoorFault then
                    hasDoorFault = true
                    break
                end
            end

            if not hasDoorFault then
                train:SetNW2String(
                    "MEX.Damage.DoorWaterFault",
                    ""
                )
            end
        end
    end

    local function StartWaterRelayChatter(
        train,
        glitchIntensity
    )
        if not IsSubwayTrain(train) then return false end

        local candidates =
            CollectWaterRelayChatterCandidates(train)

        if #candidates <= 0 then return false end

        train.MEXDamageRelayChatter =
            train.MEXDamageRelayChatter or {}

        local item =
            candidates[math.random(1, #candidates)]

        if train.MEXDamageRelayChatter[item.name] then
            return false
        end

        local system = item.system
        local trigger = system.TriggerInput
        local originalTarget =
            tonumber(system.TargetValue)
        local originalValue =
            tonumber(system.Value)
        local current =
            originalTarget ~= nil
                and originalTarget
                or originalValue
                or 0

        local glitchValue =
            current > 0.5 and 0 or 1

        train.MEXDamageRelayChatter[item.name] = {
            trigger = trigger,
            originalTarget = originalTarget,
            originalValue = originalValue,
            restoreAt =
                CurTime()
                + math.Rand(
                    0.035,
                    0.10 + glitchIntensity * 0.13
                ),
        }

        pcall(
            trigger,
            system,
            "Set",
            glitchValue
        )

        train:SetNW2String(
            "MEX.Damage.ChatteringRelay",
            item.name
        )

        train:EmitSound(
            WATER_RELAY_CHATTER_SOUNDS[
                math.random(
                    1,
                    #WATER_RELAY_CHATTER_SOUNDS
                )
            ],
            62 + math.floor(glitchIntensity * 12),
            math.random(92, 116),
            0.45 + glitchIntensity * 0.25
        )

        return true
    end

    local function UpdateWaterTransientGlitches(
        train,
        wetness,
        surfaceMoisture,
        deepMoisture,
        voltage,
        current
    )
        if not IsSubwayTrain(train) then return end

        EnsureWaterVisualGlitchHooks(train)
        ProcessWaterRelayChatter(train)

        local powered = voltage >= 24
        local moistureLevel = math.Clamp(
            math.max(
                tonumber(wetness) or 0,
                (tonumber(surfaceMoisture) or 0) * 0.88,
                (tonumber(deepMoisture) or 0) * 0.42
            ),
            0,
            1
        )

        local powerFactor = math.Clamp(
            voltage / 120,
            0,
            1
        )
        local currentFactor = math.Clamp(
            current / 250,
            0,
            1
        )

        local glitchIntensity = math.Clamp(
            moistureLevel
                * (0.38 + powerFactor * 0.42
                    + currentFactor * 0.20),
            0,
            1
        )

        train:SetNW2Float(
            "MEX.Damage.WaterGlitchIntensity",
            glitchIntensity
        )

        if not powered or glitchIntensity < 0.06 then
            train.MEXDamageWaterVisualGlitchIntensity = 0
            train.MEXDamageWaterVisualGlitchUntil = nil

            if moistureLevel < 0.025 then
                RestoreWaterRelayChatter(train)
            end

            return
        end

        local now = CurTime()
        local nextVisual =
            train.MEXDamageNextWaterVisualGlitch or 0

        if now >= nextVisual then
            local chance = math.Clamp(
                0.10 + glitchIntensity * 0.72,
                0,
                0.90
            )

            if math.Rand(0, 1) < chance then
                train.MEXDamageWaterVisualGlitchIntensity =
                    glitchIntensity
                train.MEXDamageWaterVisualGlitchUntil =
                    now
                    + math.Rand(
                        0.04,
                        0.16 + glitchIntensity * 0.34
                    )
            end

            train.MEXDamageNextWaterVisualGlitch =
                now
                + math.Rand(
                    0.08,
                    Lerp(glitchIntensity, 0.72, 0.16)
                )
        end

        local nextRelay =
            train.MEXDamageNextRelayChatter or 0

        if now >= nextRelay then
            local relayChance = math.Clamp(
                0.025
                    + glitchIntensity * glitchIntensity * 0.42,
                0,
                0.52
            )

            if math.Rand(0, 1) < relayChance then
                StartWaterRelayChatter(
                    train,
                    glitchIntensity
                )
            end

            train.MEXDamageNextRelayChatter =
                now
                + math.Rand(
                    0.07,
                    Lerp(glitchIntensity, 0.88, 0.15)
                )
        end

        local nextDoor =
            train.MEXDamageNextDoorWaterFault or 0

        if now >= nextDoor then
            local doorChance = math.Clamp(
                0.015
                    + glitchIntensity * glitchIntensity * 0.34,
                0,
                0.44
            )

            if math.Rand(0, 1) < doorChance then
                StartWaterDoorRelayFault(
                    train,
                    glitchIntensity
                )
            end

            train.MEXDamageNextDoorWaterFault =
                now
                + math.Rand(
                    0.20,
                    Lerp(glitchIntensity, 2.0, 0.38)
                )
        end

        local nextBattery =
            train.MEXDamageNextBatteryGlitch or 0

        if now >= nextBattery then
            local batteryChance = math.Clamp(
                0.02
                    + glitchIntensity * glitchIntensity * 0.31,
                0,
                0.42
            )

            if math.Rand(0, 1) < batteryChance then
                StartWaterBatteryGlitch(
                    train,
                    glitchIntensity
                )
            end

            train.MEXDamageNextBatteryGlitch =
                now
                + math.Rand(
                    0.18,
                    Lerp(glitchIntensity, 1.9, 0.34)
                )
        end
    end

    local function DistanceToTrainOBB(train, worldPos)
        if not IsSubwayTrain(train) or not isvector(worldPos) then
            return math.huge
        end

        local localPos = train:WorldToLocal(worldPos)
        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()

        local dx = math.max(
            mins.x - localPos.x,
            0,
            localPos.x - maxs.x
        )
        local dy = math.max(
            mins.y - localPos.y,
            0,
            localPos.y - maxs.y
        )
        local dz = math.max(
            mins.z - localPos.z,
            0,
            localPos.z - maxs.z
        )

        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    local function ShockPlayerFromFloodedTrain(
        train,
        ply,
        wetness,
        voltage,
        availableCurrent,
        sparkPos
    )
        if not IsValid(ply)
            or not ply:IsPlayer()
            or not ply:Alive()
            or (ply:WaterLevel() or 0) <= 0
        then
            return
        end

        if voltage < 24 or availableCurrent <= 0.01 then
            return
        end

        local playerPos = ply:WorldSpaceCenter()
        local distance = DistanceToTrainOBB(train, playerPos)
        if distance > WATER_PLAYER_RADIUS then return end

        -- Require actual conductive water at the player as well as WaterLevel.
        -- This prevents a nearby dry player being shocked through open air.
        if not IsPointInConductiveWater(
            ply:GetPos() + Vector(0, 0, 8)
        ) and ply:WaterLevel() < 2 then
            return
        end

        local proximity = 1 - math.Clamp(
            distance / WATER_PLAYER_RADIUS,
            0,
            1
        )
        local immersion = math.Clamp(
            (ply:WaterLevel() or 0) / 3,
            0.25,
            1
        )

        -- Gameplay body-current estimate. Voltage determines the attempted
        -- current through the wet path, while Metrostroi's available source
        -- current caps it. These numbers are intentionally game tuning, not
        -- real-world electrocution guidance.
        local simulatedPathResistance = Lerp(
            immersion,
            1800,
            720
        )
        local simulatedCurrent = math.min(
            availableCurrent,
            voltage / simulatedPathResistance
        )

        local voltageFactor = math.Clamp(
            (voltage - 20) / 730,
            0,
            1
        )
        local currentFactor = math.Clamp(
            simulatedCurrent / 0.75,
            0,
            1
        )

        local hazard = math.Clamp(
            wetness
                * proximity
                * immersion
                * (0.30 + voltageFactor * 0.70)
                * (0.25 + currentFactor * 0.75),
            0,
            1
        )

        if hazard < 0.025 then return end

        local now = CurTime()
        if (ply.MEXDamageWaterShockUntil or 0) > now then
            return
        end

        local chance = math.Clamp(
            0.10 + hazard * 0.78,
            0.10,
            0.88
        )

        if math.Rand(0, 1) > chance then return end

        ply.MEXDamageWaterShockUntil =
            now + WATER_SHOCK_COOLDOWN

        local damageAmount = math.Clamp(
            (
                simulatedCurrent * 92
                + voltage / 38
            )
                * (0.45 + wetness * 0.55)
                * (0.45 + proximity * 0.55),
            2,
            120
        )

        local dmg = DamageInfo()
        dmg:SetDamage(damageAmount)
        dmg:SetDamageType(DMG_SHOCK)
        dmg:SetAttacker(IsValid(train) and train or game.GetWorld())
        dmg:SetInflictor(IsValid(train) and train or game.GetWorld())
        dmg:SetDamagePosition(playerPos)
        dmg:SetDamageForce(
            VectorRand() * math.Clamp(damageAmount * 8, 20, 500)
        )
        ply:TakeDamageInfo(dmg)

        if isfunction(ply.ViewPunch) then
            ply:ViewPunch(
                Angle(
                    math.Rand(-5, 5) * hazard,
                    math.Rand(-4, 4) * hazard,
                    math.Rand(-3, 3) * hazard
                )
            )
        end

        ply:EmitSound(
            WATER_ARC_SOUNDS[
                math.random(1, #WATER_ARC_SOUNDS)
            ],
            82,
            math.random(92, 112),
            math.Clamp(0.55 + hazard * 0.45, 0.55, 1)
        )

        EmitWaterElectricalArc(
            train,
            isvector(sparkPos) and sparkPos or playerPos,
            voltage,
            availableCurrent,
            damageAmount >= 45
        )
    end

    local function UpdateWaterElectricalDamage(train, dT)
        if not IsSubwayTrain(train) then return end

        if not MEXD.IsDamageEnabled() then
            train:SetNW2Float("MEX.Damage.WaterWetness", 0)
            train:SetNW2Float("MEX.Damage.WaterVoltage", 0)
            train:SetNW2Float("MEX.Damage.WaterCurrent", 0)
            train:SetNW2Float("MEX.Damage.WaterHazard", 0)
            train:SetNW2Float("MEX.Damage.WaterMoisture", 0)
            train:SetNW2Float("MEX.Damage.DeepMoisture", 0)
            train:SetNW2Float("MEX.Damage.DrySeconds", 0)
            train:SetNW2Float(
                "MEX.Damage.WaterGlitchIntensity",
                0
            )
            train:SetNW2String(
                "MEX.Damage.ChatteringRelay",
                ""
            )
            RestoreWaterRelayChatter(train)
            RestoreWaterVisualGlitchHooks(train)
            RestoreWaterBatteryGlitchHook(train)
            return
        end

        local wetness, sparkPos = SampleTrainWater(train)
        local voltage, current, hv, lv =
            GetTrainElectricalWaterState(train)

        train:SetNW2Float(
            "MEX.Damage.WaterWetness",
            wetness
        )
        train:SetNW2Float(
            "MEX.Damage.WaterVoltage",
            voltage
        )
        train:SetNW2Float(
            "MEX.Damage.WaterCurrent",
            current
        )

        local powered = voltage >= 24
        local voltageFactor = math.Clamp(
            voltage / 750,
            0,
            1.4
        )
        local currentFactor = math.Clamp(
            current / 300,
            0,
            1.5
        )
        local hazard = math.Clamp(
            wetness
                * (powered and 0.35 or 0.08)
                * (0.25 + voltageFactor * 0.75)
                * (0.30 + currentFactor * 0.70),
            0,
            1
        )

        train:SetNW2Float(
            "MEX.Damage.WaterHazard",
            hazard
        )

        local surfaceMoisture, deepMoisture, drySeconds =
            UpdateWaterMoistureState(
                train,
                wetness,
                dT
            )

        RecoverDriedWaterFailures(
            train,
            surfaceMoisture,
            deepMoisture,
            drySeconds
        )

        UpdateWaterTransientGlitches(
            train,
            wetness,
            surfaceMoisture,
            deepMoisture,
            voltage,
            current
        )

        local exposure = NumberOrZero(
            train.MEXDamageWaterExposure
        )

        if wetness > 0.015 then
            -- Electronics can still be ruined by immersion while unpowered;
            -- live HV accelerates the failure and adds arcing/shock hazards.
            local rate =
                wetness
                * (
                    0.30
                    + math.Clamp(voltage / 750, 0, 1) * 1.25
                    + math.Clamp(current / 500, 0, 1) * 0.46
                )

            exposure = exposure + dT * rate
        else
            exposure = math.max(
                0,
                exposure - dT * 0.10
            )
        end

        train.MEXDamageWaterExposure = exposure
        train:SetNW2Float(
            "MEX.Damage.WaterExposure",
            math.Clamp(exposure, 0, 10)
        )

        if wetness > 0.02 then
            local electrical = train:GetNW2Float(
                "MEX.Damage.electrical",
                0
            )

            local waterElectricalDamage = math.Clamp(
                exposure * 0.055,
                0,
                0.55
            )

            if waterElectricalDamage > electrical then
                train:SetNW2Float(
                    "MEX.Damage.electrical",
                    waterElectricalDamage
                )
            end
        end

        if wetness > 0.02 and powered then
            local now = CurTime()
            local nextArc =
                train.MEXDamageNextWaterArc or 0

            if now >= nextArc then
                local interval = Lerp(
                    math.Clamp(hazard, 0, 1),
                    0.72,
                    0.09
                )

                train.MEXDamageNextWaterArc =
                    now + interval * math.Rand(0.70, 1.25)

                if math.Rand(0, 1)
                    < math.Clamp(0.18 + hazard * 0.72, 0, 0.9)
                then
                    EmitWaterElectricalArc(
                        train,
                        sparkPos,
                        voltage,
                        current,
                        hv >= 200
                    )
                end
            end
        end

        train.MEXDamageWaterNextFailureExposure =
            train.MEXDamageWaterNextFailureExposure
            or WATER_FAILURE_BASE_EXPOSURE

        if wetness > 0.04
            and exposure
                >= train.MEXDamageWaterNextFailureExposure
        then
            local protected = false

            if powered then
                protected = OperateWaterProtection(
                    train,
                    hv >= 200,
                    sparkPos,
                    voltage,
                    current
                )
            end

            if protected then
                -- Give the protection time to de-energize the circuit. If the
                -- fault is still live later, the next stage may damage actual
                -- equipment or retrip a breaker that was manually reset.
                train.MEXDamageWaterNextFailureExposure =
                    exposure + math.Rand(0.22, 0.55)
            elseif FailRandomWaterElectricalSystem(
                train,
                sparkPos,
                voltage,
                current,
                wetness
            ) then
                train.MEXDamageWaterNextFailureExposure =
                    exposure + math.Rand(0.26, 0.62)
            else
                -- No suitable protection or relay remains.
                train.MEXDamageWaterNextFailureExposure =
                    exposure + 1.5
            end
        end

        if powered then
            RetripWaterProtectionIfNeeded(
                train,
                wetness,
                voltage,
                current,
                sparkPos
            )
        end

        if powered and wetness > 0.02 then
            for _, ply in ipairs(player.GetHumans()) do
                ShockPlayerFromFloodedTrain(
                    train,
                    ply,
                    wetness,
                    voltage,
                    current,
                    sparkPos
                )
            end
        end
    end

    local function AddElectricalCandidate(out, seen, value)
        if not isstring(value) then return end
        value = value:gsub("^.+:", "")
        if value == "" or #value > 64 then return end
        if not string.match(value, "^[%w_%-]+$") then return end
        if seen[value] then return end
        seen[value] = true
        out[#out + 1] = value
    end

    local function CandidateFromButtonID(buttonID)
        if not isstring(buttonID) then return nil end

        local id = buttonID:gsub("^.+:", "")

        local suffixes = {
            "Toggle",
            "Set",
            "On",
            "Off",
        }

        for _, suffix in ipairs(suffixes) do
            if string.sub(id, -#suffix) == suffix
                and #id > #suffix
            then
                return string.sub(id, 1, #id - #suffix)
            end
        end

        return nil
    end

    local function AddButtonRoutedElectricalSystems(
        train,
        buttonID,
        candidates,
        seen
    )
        if not IsSubwayTrain(train)
            or not isstring(buttonID)
            or not istable(train.Systems)
        then
            return
        end

        buttonID = buttonID:gsub("^.+:", "")

        for systemName, system in pairs(train.Systems) do
            if not istable(system)
                or not istable(system.IsInput)
            then
                continue
            end

            if system.IsInput[buttonID] then
                AddElectricalCandidate(
                    candidates,
                    seen,
                    tostring(systemName)
                )
            end

            local routeName = isstring(system.Name)
                and system.Name
                or tostring(systemName)

            if string.sub(buttonID, 1, #routeName) == routeName then
                local subname = string.sub(
                    buttonID,
                    #routeName + 1
                )

                if subname ~= ""
                    and system.IsInput[subname]
                then
                    AddElectricalCandidate(
                        candidates,
                        seen,
                        tostring(systemName)
                    )
                end
            end
        end
    end

    local function ApplyDetachedElectricalFailure(
        train,
        name,
        model,
        buttonIDs,
        electricalTargets,
        clientMechanical
    )
        if not IsSubwayTrain(train) then return {} end

        -- Server classification is authoritative. A client may request that a
        -- system is treated as mechanical, but it cannot make a known
        -- mechanical controller electrically fail-open.
        local mechanical =
            IsMechanicalElectricalException(
                name,
                model,
                buttonIDs
            )

        if mechanical then
            return {}
        end

        local candidates = {}
        local seen = {}

        for _, target in ipairs(electricalTargets or {}) do
            AddElectricalCandidate(candidates, seen, target)
        end

        for _, buttonID in ipairs(buttonIDs or {}) do
            -- Some legacy ButtonMaps use the relay/system name directly as
            -- the ButtonEvent ID; others append Toggle/Set/On/Off.
            AddElectricalCandidate(
                candidates,
                seen,
                buttonID
            )
            AddElectricalCandidate(
                candidates,
                seen,
                CandidateFromButtonID(buttonID)
            )

            -- Mirror gmod_subway_base:TriggerInput routing. This discovers
            -- the actual Metrostroi system which accepts the ButtonEvent even
            -- when addon authors use non-obvious system names.
            AddButtonRoutedElectricalSystems(
                train,
                buttonID,
                candidates,
                seen
            )

            local normalized = string.lower(
                tostring(buttonID):gsub("[^%w]", "")
            )

            -- Classic cars expose the physical switch as BatteryToggle /
            -- model.var=Battery, but the disconnect relay itself is VB while
            -- train.Battery is the accumulator model. Modern cars may instead
            -- use a relay actually named Battery, so retain both candidates.
            if normalized == "batterytoggle"
                or normalized == "batteryset"
                or normalized == "battery"
            then
                AddElectricalCandidate(
                    candidates,
                    seen,
                    "VB"
                )
            end
        end

        local failed = {}

        for _, systemName in ipairs(candidates) do
            if FailElectricalSystemOpen(
                train,
                systemName,
                { cause = "detached", temporary = false }
            ) then
                failed[#failed + 1] = systemName
            end
        end

        -- If the client identified an otherwise unrecognised mechanical
        -- handle and no real relay/system matched any supplied target, do
        -- nothing. This keeps custom mechanical controllers from being
        -- guessed into an electrical failure while still preventing the hint
        -- from suppressing a validated electrical relay.
        if #failed == 0 and clientMechanical == true then
            return {}
        end

        return failed
    end

    local function RemoveDetachedServerComponents(train, broadcastReset)
        if not IsSubwayTrain(train) then return end

        if istable(train.MEXDamageDetachedServer) then
            for _, data in pairs(train.MEXDamageDetachedServer) do
                if IsValid(data.debris) then
                    data.debris:Remove()
                end

                if istable(data.debrisList) then
                    for _, debris in ipairs(data.debrisList) do
                        if IsValid(debris) then
                            debris:Remove()
                        end
                    end
                end
            end
        end

        train.MEXDamageDetachedServer = {}
        RestoreElectricalFailures(train)
        ClearDetachedButtons(train)
        RebuildDetachedButtonGuard(train)

        if broadcastReset then
            net.Start("MEX.DetachReset")
                net.WriteEntity(train)
            net.Broadcast()
        end
    end

    local function SpawnDetachedPhysicsProp(
        train,
        name,
        model,
        localPos,
        localAng,
        mins,
        maxs,
        skin,
        color,
        material,
        bodygroups,
        isDoor,
        isControl,
        zone,
        frozenSequence,
        frozenCycle,
        frozenPose
    )
        if not util.IsValidModel(model) then return nil end

        local debris = ents.Create("mex_damage_debris")
        if not IsValid(debris) then return nil end

        debris:SetModel(model)

        if not isvector(mins) or not isvector(maxs)
            or (maxs - mins):LengthSqr() <= 1
        then
            mins = debris:OBBMins()
            maxs = debris:OBBMaxs()
        end

        if not isvector(mins) or not isvector(maxs)
            or (maxs - mins):LengthSqr() <= 1
        then
            mins = Vector(-4, -4, -4)
            maxs = Vector(4, 4, 4)
        end

        local visualCenter = (mins + maxs) * 0.5

        -- Put the *physics entity* at the actual visible geometry centre.
        -- mex_damage_debris:Draw() shifts only the rendered MDL back to its
        -- original model origin. This fixes Metrostroi models whose origin is
        -- hundreds of Source units away from the visible part.
        local anchorLocal = LocalToWorld(
            visualCenter,
            angle_zero,
            localPos,
            localAng
        )

        debris.MEXFallbackMins = mins
        debris.MEXFallbackMaxs = maxs
        debris:SetPos(train:LocalToWorld(anchorLocal))
        debris:SetAngles(train:LocalToWorldAngles(localAng))
        debris:SetSourceTrain(train)
        debris:SetComponentName(name)
        debris:SetVisualCenter(visualCenter)
        debris:SetFrozenSequence(math.max(math.floor(frozenSequence or 0), 0))
        debris:SetFrozenCycle(math.Clamp(frozenCycle or 0, 0, 1))
        debris:SetFrozenPosePosition(tonumber(frozenPose) or 0)
        debris:Spawn()

        if not IsValid(debris) then return nil end

        debris:SetSkin(math.max(0, skin or 0))
        debris:SetColor(color or color_white)
        debris:SetPlaybackRate(0)
        debris:SetSequence(debris:GetFrozenSequence())
        debris:SetCycle(debris:GetFrozenCycle())
        debris:SetPoseParameter(
            "position",
            debris:GetFrozenPosePosition()
        )

        if isstring(material) and material ~= "" then
            debris:SetMaterial(material)
        end

        if istable(bodygroups) then
            for id, value in pairs(bodygroups) do
                if isnumber(id) and isnumber(value) then
                    debris:SetBodygroup(id, value)
                end
            end
        end

        debris.MEXDamageDebris = true
        debris.MEXDamageIsDoor = isDoor
        debris.MEXDamageIsControl = isControl

        local owner = train.CPPIGetOwner and train:CPPIGetOwner() or nil
        if IsValid(owner) and debris.CPPISetOwner then
            debris:CPPISetOwner(owner)
        end

        local phys = debris:GetPhysicsObject()
        if IsValid(phys) then
            local normal = ZoneOutwardNormal(train, zone or "front")
            local seed = (tonumber(util.CRC(name)) or 0) % 1000 / 1000

            local mass
            if isDoor then
                mass = 42
            elseif isControl then
                mass = 1.8
            else
                local size = maxs - mins
                local volume = math.abs(size.x * size.y * size.z)
                mass = math.Clamp(volume / 6500, 2.5, 28)
            end

            phys:SetMass(mass)
            phys:EnableGravity(true)
            phys:EnableMotion(true)

            -- Keep the pre-detachment vehicle velocity. The actual release
            -- impulse is applied later from the collision/blast event at the
            -- real impact point, which produces physically meaningful torque.
            phys:SetVelocity(train:GetVelocity())
            phys:Wake()
        end

        return debris
    end

    local function WorldDirectionToLocal(train, worldVector)
        if not IsSubwayTrain(train) or not isvector(worldVector) then
            return Vector(0, 0, 0)
        end

        return Vector(
            worldVector:Dot(train:GetForward()),
            worldVector:Dot(train:GetRight()),
            worldVector:Dot(train:GetUp())
        )
    end

    local function LocalDirectionToWorld(train, localVector)
        if not IsSubwayTrain(train) or not isvector(localVector) then
            return Vector(0, 0, 0)
        end

        return
            train:GetForward() * localVector.x
            + train:GetRight() * localVector.y
            + train:GetUp() * localVector.z
    end

    local function ApplyBreakawayImpulse(
        train,
        debris,
        impact,
        zone,
        anchorLocal,
        isDoor,
        isControl,
        ordinal
    )
        if not IsValid(debris) then return end

        local phys = debris:GetPhysicsObject()
        if not IsValid(phys) then return end

        ordinal = tonumber(ordinal) or 1

        local velocityImpulse = Vector(0, 0, 0)
        local applicationPoint = debris:GetPos()

        if istable(impact) then
            if isvector(impact.localImpulse)
                and impact.localImpulse:LengthSqr() > 1
            then
                velocityImpulse = LocalDirectionToWorld(
                    train,
                    impact.localImpulse
                )
            end

            if isvector(impact.localPos) then
                applicationPoint = train:LocalToWorld(impact.localPos)
            end

            if impact.blast then
                -- A blast wave pushes approximately radially away from its
                -- local pressure centre. Blend that radial impulse with the
                -- Source DamageForce direction so an off-centre blast both
                -- translates and rotates the released component.
                local radialLocal = anchorLocal - impact.localPos

                if radialLocal:LengthSqr() > 1 then
                    radialLocal:Normalize()
                    local radialWorld = LocalDirectionToWorld(
                        train,
                        radialLocal
                    )

                    local blastVelocity =
                        42 + math.Clamp(impact.power or 0, 0, 2) * 92

                    velocityImpulse =
                        velocityImpulse * 0.45
                        + radialWorld * blastVelocity
                end
            end
        end

        if velocityImpulse:LengthSqr() < 1 then
            local severity = MEXD.GetZoneDamage(train, zone or "front")
            velocityImpulse =
                ZoneOutwardNormal(train, zone or "front")
                    * (22 + severity * 62)
        end

        local typeScale =
            isDoor and 1.28
            or (isControl and 0.82 or 1.0)

        velocityImpulse = velocityImpulse * typeScale

        -- Split leaves need a tiny opposite shear so the two pieces do not
        -- continue occupying the same visual volume after the mount fails.
        if isDoor and ordinal > 1 then
            velocityImpulse =
                velocityImpulse
                + train:GetForward()
                    * ((ordinal % 2 == 0) and 22 or -22)
        end

        local mass = math.max(phys:GetMass(), 0.1)
        local impulse = velocityImpulse * mass

        -- Clamp the point to a useful lever arm around the debris centre.
        local lever = applicationPoint - debris:GetPos()
        local maxLever = math.max(
            debris:OBBMaxs():Length() * 0.65,
            8
        )

        if lever:Length() > maxLever then
            lever:Normalize()
            applicationPoint = debris:GetPos() + lever * maxLever
        end

        phys:ApplyForceOffset(impulse, applicationPoint)

        local seed =
            ((tonumber(util.CRC(debris:GetComponentName() or "")) or 0)
                % 1000) / 1000

        phys:AddAngleVelocity(Vector(
            -18 + seed * 36,
            12 - seed * 24,
            -26 + seed * 52
        ))

        if isDoor then
            local mins = debris:OBBMins()
            local maxs = debris:OBBMaxs()
            local size = maxs - mins

            local longAxis
            local longHalf

            if math.abs(size.z) >= math.abs(size.x)
                and math.abs(size.z) >= math.abs(size.y)
            then
                longAxis = debris:GetUp()
                longHalf = math.abs(size.z) * 0.5
            elseif math.abs(size.y) >= math.abs(size.x) then
                longAxis = debris:GetRight()
                longHalf = math.abs(size.y) * 0.5
            else
                longAxis = debris:GetForward()
                longHalf = math.abs(size.x) * 0.5
            end

            local sideways =
                train:GetRight()
                + train:GetForward() * (seed > 0.5 and 0.45 or -0.45)

            if sideways:LengthSqr() > 0.001 then
                sideways:Normalize()
            end

            -- Door leaves are tall thin bodies. Without an explicit hinge-fail
            -- moment Source can leave a perfectly vertical box balanced on its
            -- lower edge. Apply force away from COM near the long edge so the
            -- released leaf must tumble.
            local tipPoint =
                debris:GetPos()
                + longAxis * math.max(longHalf * 0.72, 14)

            phys:ApplyForceOffset(
                sideways * mass * (75 + seed * 45),
                tipPoint
            )
            phys:AddAngleVelocity(
                sideways * (115 + seed * 95)
            )

            local tipDirection = Vector(
                sideways.x,
                sideways.y,
                sideways.z
            )
            local lever = math.max(longHalf * 0.68, 14)

            for _, delay in ipairs({0.10, 0.34}) do
                timer.Simple(delay, function()
                    if not IsValid(debris) then return end

                    local p = debris:GetPhysicsObject()
                    if not IsValid(p) then return end

                    p:Wake()

                    -- If the leaf is still suspiciously upright / nearly
                    -- motionless, give gravity a lever arm instead of letting
                    -- the VPhysics box sleep on its bottom edge.
                    if p:GetVelocity():Length() < 95 then
                        local currentLongAxis

                        if math.abs(size.z) >= math.abs(size.x)
                            and math.abs(size.z) >= math.abs(size.y)
                        then
                            currentLongAxis = debris:GetUp()
                        elseif math.abs(size.y) >= math.abs(size.x) then
                            currentLongAxis = debris:GetRight()
                        else
                            currentLongAxis = debris:GetForward()
                        end

                        if math.abs(currentLongAxis:Dot(vector_up)) > 0.48 then
                            p:ApplyForceOffset(
                                tipDirection * p:GetMass() * 62,
                                debris:GetPos()
                                    + currentLongAxis * lever
                            )
                            p:AddAngleVelocity(
                                tipDirection * 95
                            )
                        end
                    end
                end)
            end
        end

        phys:Wake()
    end

    local PASSENGER_DOOR_FAMILIES = {
        {
            prefix = "models/metrostroi_train/81-717/81-717_doors_pos",
            leafA = "models/metrostroi_train/81-717/door_right_spb.mdl",
            leafB = "models/metrostroi_train/81-717/door_left_spb.mdl",
            position = function(i, k, leaf)
                local x = 338.0 - 230.1 * i + (1 - k) * 0.8
                if leaf == 2 then x = x + 0.2 end
                return Vector(x, -65 * (1 - 2 * k), 0.761)
            end,
        },
        {
            prefix = "models/metrostroi_train/81-718/81-718_doors_pos",
            leafA = "models/metrostroi_train/81-718/door_right.mdl",
            leafB = "models/metrostroi_train/81-718/door_left.mdl",
            position = function(i, k)
                return Vector(
                    338.2 - 230.1 * i + (1 - k) * 0.8,
                    -65.449 * (1 - 2 * k),
                    0.761
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-710/81-710_doors_pos",
            leafA = "models/metrostroi_train/81-710/81-710_door_right.mdl",
            leafB = "models/metrostroi_train/81-710/81-710_door_left.mdl",
            position = function(i, k, leaf)
                local x
                if leaf == 1 then
                    x = 344.9 - 0.1 * k - 233.6 * i
                else
                    x = 344.9 - 0.1 * (1 - k) - 233.6 * i
                end

                return Vector(
                    x,
                    -63.86 * (1 - 2.02 * k),
                    -5.75
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-502/81-502_doors_pos",
            leafA = "models/metrostroi_train/81-502/81-502_door_right.mdl",
            leafB = "models/metrostroi_train/81-502/81-502_door_left.mdl",
            position = function(i, k, leaf)
                local x
                if leaf == 1 then
                    x = 344.9 - 0.1 * k - 233.6 * i
                else
                    x = 344.9 - 0.1 * (1 - k) - 233.6 * i
                end

                return Vector(
                    x,
                    -63.86 * (1 - 2.02 * k),
                    -5.75
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-702/81-702_doors_pos",
            leafA = "models/metrostroi_train/81-702/81-702_door_right.mdl",
            leafB = "models/metrostroi_train/81-702/81-702_door_left.mdl",
            position = function(i, k, leaf)
                local x
                if leaf == 1 then
                    x = 349.45 - k - 232.202 * i
                else
                    x = 349.45 - (1 - k) - 232.202 * i
                end

                return Vector(
                    x,
                    -64.6 * (1 - 2 * k),
                    -8.728
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-703/81-703_doors_pos",
            leafA = "models/metrostroi_train/81-703/81-703_door_right.mdl",
            leafB = "models/metrostroi_train/81-703/81-703_door_left.mdl",
            position = function(i, k, leaf)
                local x
                if leaf == 1 then
                    x = 323.0 - 0.5 * k - 0.8 * (1 - k) - 233.5 * i
                else
                    x = 323.0 - 0.5 * (1 - k) - 0.8 * (1 - k) - 233.5 * i
                end

                return Vector(
                    x,
                    -62.8 * (1 - 2.045 * k),
                    -5.3
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-720/81-720_doors_pos",
            leafA = "models/metrostroi_train/81-720/81-720_door_l.mdl",
            leafB = "models/metrostroi_train/81-720/81-720_door_r.mdl",
            position = function(i, k)
                return Vector(
                    341 + k - 230 * i,
                    -64 * (1 - 2 * k),
                    -10
                )
            end,
        },
        {
            prefix = "models/metrostroi_train/81-722/81-722_doors_pos",
            leafA = "models/metrostroi_train/81-722/81-722_door_l.mdl",
            leafB = "models/metrostroi_train/81-722/81-722_door_r.mdl",
            position = function(i, k)
                return Vector(
                    341 + k - 230 * i,
                    -64 * (1 - 2 * k),
                    -10
                )
            end,
        },
    }

    local function GetPassengerDoorFamily(name, model)
        local lowerName = string.lower(name or "")

        if string.find(lowerName, "frontdoor", 1, true)
            or string.find(lowerName, "reardoor", 1, true)
            or string.find(lowerName, "cabindoor", 1, true)
            or string.find(lowerName, "passengerdoor", 1, true)
        then
            return nil
        end

        if not string.match(name or "", "^door%d+x[01]$") then
            return nil
        end

        local lowerModel = string.lower(model or "")

        for _, family in ipairs(PASSENGER_DOOR_FAMILIES) do
            if string.find(lowerModel, family.prefix, 1, true) == 1 then
                return family
            end
        end

        -- Generic addon fallback. A lot of Metrostroi-derived trains keep the
        -- same naming convention even when their class is not part of the
        -- stock repository. Try common individual-leaf names beside a
        -- *_doors_posN.mdl combined model.
        local base = string.match(
            lowerModel,
            "^(.*)doors_pos%d+%.mdl$"
        )

        if not base then return nil end

        local dir = string.match(lowerModel, "^(.*[/])") or ""

        local pairsToTry = {
            {
                base .. "door_right.mdl",
                base .. "door_left.mdl",
            },
            {
                base .. "door_l.mdl",
                base .. "door_r.mdl",
            },
            {
                dir .. "door_right.mdl",
                dir .. "door_left.mdl",
            },
            {
                dir .. "door_l.mdl",
                dir .. "door_r.mdl",
            },
        }

        for _, pair in ipairs(pairsToTry) do
            if util.IsValidModel(pair[1])
                and util.IsValidModel(pair[2])
            then
                return {
                    leafA = pair[1],
                    leafB = pair[2],
                    generic = true,
                }
            end
        end

        return nil
    end

    local function SpawnSplitPassengerDoorLeaves(
        train,
        name,
        model,
        originalLocalPos,
        originalLocalAng,
        zone,
        skin,
        color,
        material,
        bodygroups,
        frozenSequence,
        frozenCycle,
        frozenPose
    )
        local family = GetPassengerDoorFamily(name, model)
        if not family then return nil end

        local i, k = string.match(name, "^door(%d)x([01])$")
        i = tonumber(i)
        k = tonumber(k)

        if not i or not k then return nil end

        local specs

        if family.generic then
            local basePos = isvector(originalLocalPos)
                and originalLocalPos
                or Vector(0, 0, 0)

            specs = {
                {
                    suffix = "a",
                    model = family.leafA,
                    pos = basePos + Vector(-0.12, 0, 0),
                },
                {
                    suffix = "b",
                    model = family.leafB,
                    pos = basePos + Vector(0.12, 0, 0),
                },
            }
        else
            specs = {
                {
                    suffix = "a",
                    model = family.leafA,
                    pos = family.position(i, k, 1),
                },
                {
                    suffix = "b",
                    model = family.leafB,
                    pos = family.position(i, k, 2),
                },
            }
        end

        local leaves = {}

        for leafIndex, spec in ipairs(specs) do
            if not util.IsValidModel(spec.model) then
                for _, leaf in ipairs(leaves) do
                    if IsValid(leaf) then leaf:Remove() end
                end
                return nil
            end

            local leaf = SpawnDetachedPhysicsProp(
                train,
                name .. ":" .. spec.suffix,
                spec.model,
                spec.pos,
                family.generic and (
                    isangle(originalLocalAng)
                        and originalLocalAng
                        or Angle(0, 90 + 180 * k, 0)
                ) or Angle(0, 90 + 180 * k, 0),
                nil,
                nil,
                skin,
                color,
                material,
                bodygroups,
                true,
                false,
                zone,
                frozenSequence,
                frozenCycle,
                frozenPose
            )

            if not IsValid(leaf) then
                for _, existing in ipairs(leaves) do
                    if IsValid(existing) then existing:Remove() end
                end
                return nil
            end

            local phys = leaf:GetPhysicsObject()
            if IsValid(phys) then
                local separation =
                    train:GetForward() * (leafIndex == 1 and -1 or 1)
                    + train:GetRight() * (k == 1 and 0.18 or -0.18)

                phys:AddVelocity(separation * (26 + leafIndex * 7))
                phys:AddAngleVelocity(Vector(
                    leafIndex == 1 and 90 or -90,
                    leafIndex == 1 and -60 or 60,
                    leafIndex == 1 and 125 or -125
                ))
                phys:Wake()
            end

            leaves[#leaves + 1] = leaf
        end

        return leaves
    end

    local function IsGlassComponentName(name, model)
        local lowerModel = string.lower(model or "")

        if string.find(lowerModel, "glass", 1, true)
            or string.find(lowerModel, "window", 1, true)
            or string.find(lowerModel, "stekl", 1, true)
        then
            return true
        end

        local lowerName = string.lower(name or "")

        if string.find(lowerName, "washer", 1, true)
            or string.find(lowerName, "cleaner", 1, true)
            or string.find(lowerName, "wiper", 1, true)
            or string.find(lowerName, "button", 1, true)
            or string.find(lowerName, "switch", 1, true)
            or string.find(lowerName, "toggle", 1, true)
        then
            return false
        end

        return string.find(lowerName, "glass", 1, true) ~= nil
            or string.find(lowerName, "window", 1, true) ~= nil
            or string.find(lowerName, "stekl", 1, true) ~= nil
    end

    local function SpawnGlassShards(train, name, anchorLocal, zone)
        local shards = {}
        local worldPos = train:LocalToWorld(anchorLocal)
        local normal = ZoneOutwardNormal(train, zone or "front")

        local effect = EffectData()
        effect:SetOrigin(worldPos)
        effect:SetNormal(normal)
        effect:SetMagnitude(2)
        effect:SetScale(1.5)
        util.Effect("GlassImpact", effect, true, true)

        sound.Play(
            "physics/glass/glass_largesheet_break1.wav",
            worldPos,
            78,
            100,
            0.9
        )

        local shardModels = {
            "models/gibs/glass_shard01.mdl",
            "models/gibs/glass_shard02.mdl",
            "models/gibs/glass_shard03.mdl",
            "models/gibs/glass_shard04.mdl",
        }

        for i = 1, 6 do
            local model = shardModels[((i - 1) % #shardModels) + 1]
            if not util.IsValidModel(model) then continue end

            local offset = Vector(
                math.Rand(-7, 7),
                math.Rand(-7, 7),
                math.Rand(-5, 7)
            )

            local shard = SpawnDetachedPhysicsProp(
                train,
                name .. ":glass:" .. i,
                model,
                anchorLocal + offset,
                Angle(
                    math.Rand(-25, 25),
                    math.Rand(0, 360),
                    math.Rand(-25, 25)
                ),
                Vector(-2, -2, -2),
                Vector(2, 2, 2),
                0,
                color_white,
                "",
                {},
                false,
                false,
                zone,
                0,
                0,
                0
            )

            if IsValid(shard) then
                local phys = shard:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetMass(0.35)
                    phys:AddVelocity(
                        normal * math.Rand(45, 110)
                        + train:GetUp() * math.Rand(15, 70)
                        + train:GetRight() * math.Rand(-55, 55)
                    )
                    phys:Wake()
                end

                shards[#shards + 1] = shard

                timer.Simple(25 + i * 2, function()
                    if IsValid(shard) then shard:Remove() end
                end)
            end
        end

        return shards
    end

    local COMPONENT_IMPACT_LIFETIME = 0.90

    local function PruneComponentImpacts(train)
        if not istable(train.MEXDamageComponentImpacts) then
            train.MEXDamageComponentImpacts = {}
            return
        end

        local now = CurTime()

        for i = #train.MEXDamageComponentImpacts, 1, -1 do
            local impact = train.MEXDamageComponentImpacts[i]
            if not istable(impact)
                or impact.expires <= now
                or impact.remaining <= 0
            then
                table.remove(train.MEXDamageComponentImpacts, i)
            end
        end
    end

    local function SendComponentImpact(
        train,
        worldPos,
        power,
        radius,
        maxDetach,
        source,
        worldImpulse,
        isBlast
    )
        if not MEXD.IsDamageEnabled() then return end
        if not IsSubwayTrain(train) or not isvector(worldPos) then return end

        power = math.Clamp(tonumber(power) or 0, 0.05, 2.0)
        radius = math.Clamp(tonumber(radius) or 20, 8, 320)
        maxDetach = math.Clamp(math.floor(tonumber(maxDetach) or 1), 1, 96)

        local localImpulse = Vector(0, 0, 0)
        if isvector(worldImpulse) then
            localImpulse = WorldDirectionToLocal(train, worldImpulse)
        end

        PruneComponentImpacts(train)

        train.MEXDamageComponentImpactSerial =
            (train.MEXDamageComponentImpactSerial or 0) + 1

        local impact = {
            id = train.MEXDamageComponentImpactSerial,
            localPos = train:WorldToLocal(worldPos),
            localImpulse = localImpulse,
            power = power,
            radius = radius,
            remaining = maxDetach,
            source = source or "unknown",
            blast = isBlast == true,
            expires = CurTime() + COMPONENT_IMPACT_LIFETIME,
        }

        table.insert(train.MEXDamageComponentImpacts, impact)

        net.Start("MEX.ComponentImpact")
            net.WriteEntity(train)
            net.WriteUInt(impact.id % 65536, 16)
            net.WriteVector(impact.localPos)
            net.WriteVector(localImpulse)
            net.WriteFloat(power)
            net.WriteFloat(radius)
            net.WriteUInt(maxDetach, 7)
            net.WriteBool(impact.blast)
        net.Broadcast()
    end

    local function FindRecentComponentImpact(
        train,
        anchorLocal,
        componentRadius
    )
        if not IsSubwayTrain(train) or not isvector(anchorLocal) then
            return nil
        end

        PruneComponentImpacts(train)

        local best = nil
        local bestScore = 0

        for _, impact in ipairs(train.MEXDamageComponentImpacts or {}) do
            if impact.remaining <= 0 then continue end

            local distance = math.max(
                0,
                anchorLocal:Distance(impact.localPos)
                    - math.max(componentRadius or 0, 0)
            )
            if distance > impact.radius then continue end

            local falloff = 1 - distance / math.max(impact.radius, 1)
            local score = falloff * impact.power

            if score > bestScore then
                best = impact
                bestScore = score
            end
        end

        return best, bestScore
    end

    local function DamageImpactWorldPosition(train, dmginfo)
        local pos = dmginfo:GetDamagePosition()

        if isvector(pos) and pos ~= vector_origin then
            return pos
        end

        local attacker = dmginfo:GetAttacker()

        if IsValid(attacker) and attacker:IsPlayer() then
            local startPos = attacker:GetShootPos()
            local trace = util.TraceLine({
                start = startPos,
                -- 160 SU was only a few metres. From normal shooting
                -- distances the trace therefore missed the train and the
                -- damage system guessed a generic nearest point instead of
                -- denting the actual bullet impact position.
                endpos = startPos + attacker:GetAimVector() * 32768,
                filter = attacker,
            })

            if trace.Entity == train and trace.Hit then
                return trace.HitPos
            end
        end

        if IsValid(attacker) then
            return train:NearestPoint(attacker:GetPos())
        end

        return train:GetPos()
    end

    local function IsComponentDamageType(dmginfo)
        return
            dmginfo:IsDamageType(DMG_BULLET)
            or dmginfo:IsDamageType(DMG_BUCKSHOT)
            or dmginfo:IsDamageType(DMG_CLUB)
            or dmginfo:IsDamageType(DMG_SLASH)
            or dmginfo:IsDamageType(DMG_CRUSH)
            or dmginfo:IsDamageType(DMG_BLAST)
            or dmginfo:IsDamageType(DMG_VEHICLE)
    end

    local function IsRecentPhysgunEntity(ent)
        return IsValid(ent)
            and (
                ent.MEXDamagePhysgunHeld == true
                or (ent.MEXDamagePhysgunUntil or 0) > CurTime()
            )
    end

    -- Physgun motion is partly kinematic in Source, so OurOldVelocity can be
    -- much smaller than the visible movement. Remember held/thrown entities so
    -- PhysicsCollide can trust collisionData.Speed and use a lower threshold
    -- for deliberate destructive tests instead of silently ignoring them.
    hook.Add("PhysgunPickup", "MEX.Damage.TrackPhysgunPickup", function(_, ent)
        if not IsValid(ent) then return end
        ent.MEXDamagePhysgunHeld = true
        ent.MEXDamagePhysgunUntil = CurTime() + 0.25
    end)

    hook.Add("PhysgunDrop", "MEX.Damage.TrackPhysgunDrop", function(_, ent)
        if not IsValid(ent) then return end
        ent.MEXDamagePhysgunHeld = false
        ent.MEXDamagePhysgunUntil = CurTime() + 0.55
    end)

    local function InitializeTrainDamage(train)
        if not IsSubwayTrain(train) then return end
        if train.MEXDamageInitialized then return end

        train.MEXDamageInitialized = true
        EnsureButtonEventGuard(train)
        train.MEXDamageIgnoreUntil = CurTime() + SPAWN_GRACE_SECONDS
        train.MEXDamageLastVelocity = train:GetVelocity()
        train.MEXDamageLastPosition = train:GetPos()
        train.MEXDamageLastSample = CurTime()
        train.MEXDamagePreviousSpeedKmh = train:GetVelocity():Length() * SU_TO_KMH

        train:SetNW2Bool("MEX.DamageReady", false)
        train:SetNW2Float("MEX.DamageReadyAt", train.MEXDamageIgnoreUntil)

        -- PhysicsCollide gives us the real contact point and pre-impact
        -- velocities. This is the primary crash detector in v0.4; the old
        -- velocity-change detector remains only as a fallback for collisions
        -- that Source does not report to the scripted train entity.
        if not train.MEXDamagePhysicsCallback then
            train.MEXDamagePhysicsCallback = train:AddCallback("PhysicsCollide", function(ent, data)
                if not MEXD.IsDamageEnabled() then return end
                if not IsSubwayTrain(ent) then return end
                if CurTime() < (ent.MEXDamageIgnoreUntil or 0) then return end
                if (ent.MEXDamageCrashCooldown or 0) > CurTime() then return end
                if not istable(data) then return end

                local ourOld = isvector(data.OurOldVelocity)
                    and data.OurOldVelocity
                    or ent:GetVelocity()
                local theirOld = isvector(data.TheirOldVelocity)
                    and data.TheirOldVelocity
                    or vector_origin
                local relativeVelocity = ourOld - theirOld

                local hitNormal = isvector(data.HitNormal)
                    and data.HitNormal
                    or vector_origin
                local normalSpeed = 0
                if hitNormal:LengthSqr() > 0.001 then
                    normalSpeed = math.abs(relativeVelocity:Dot(hitNormal))
                end

                local relativeSpeed = relativeVelocity:Length()

                -- collisionData.Speed is a scalar and is much more reliable
                -- for entities moved by the physgun than OurOldVelocity.
                local reportedSpeed = tonumber(data.Speed) or 0
                local hitSpeed = isvector(data.HitSpeed)
                    and data.HitSpeed:Length()
                    or tonumber(data.HitSpeed)
                    or 0

                local impactSpeedSU = math.max(
                    normalSpeed,
                    relativeSpeed * 0.68,
                    reportedSpeed,
                    hitSpeed
                )

                local other = IsValid(data.HitEntity)
                    and data.HitEntity
                    or nil
                local physgunImpact =
                    IsRecentPhysgunEntity(ent)
                    or IsRecentPhysgunEntity(other)

                local impactKmh = impactSpeedSU * SU_TO_KMH
                local threshold = physgunImpact and 2.5 or MIN_CRASH_SPEED_KMH
                if impactKmh < threshold then return end

                local hitPos = isvector(data.HitPos)
                    and data.HitPos
                    or ent:GetPos()
                local zone = ClassifyFromWorldPosition
                    and ClassifyFromWorldPosition(ent, hitPos)
                    or nil
                if not zone then
                    zone = ClassifyFromWorldDeltaVelocity
                        and ClassifyFromWorldDeltaVelocity(
                            ent,
                            relativeVelocity
                        )
                        or "front"
                end

                local maxSpeed = physgunImpact
                    and 48
                    or MAX_CRASH_SPEED_KMH
                local severity = math.Clamp(
                    (impactKmh - threshold)
                        / math.max(maxSpeed - threshold, 1),
                    physgunImpact and 0.030 or 0.015,
                    0.95
                )

                if physgunImpact then
                    severity = math.Clamp(
                        severity * 1.20 + 0.012,
                        0.035,
                        0.95
                    )
                end

                -- Repeated sub-crash contacts in one physical impact arrive in
                -- consecutive physics steps. Physgun testing intentionally
                -- allows more distinct impacts per second.
                ent.MEXDamageCrashCooldown =
                    CurTime() + (physgunImpact and 0.065 or 0.12)
                ent:SetNW2Float("MEX.Damage.LastImpactKmh", impactKmh)

                local impactVelocity = relativeVelocity
                if impactVelocity:Length() < impactSpeedSU * 0.35
                    and hitNormal:LengthSqr() > 0.001
                then
                    impactVelocity = -hitNormal:GetNormalized() * impactSpeedSU
                end

                SendComponentImpact(
                    ent,
                    hitPos,
                    math.Clamp(
                        impactKmh / (physgunImpact and 28 or 42),
                        physgunImpact and 0.24 or 0.15,
                        1.9
                    ),
                    math.Clamp(
                        18 + impactKmh * (physgunImpact and 2.1 or 1.65),
                        22,
                        210
                    ),
                    math.Clamp(
                        1 + math.floor(impactKmh / (physgunImpact and 8 or 12)),
                        1,
                        20
                    ),
                    physgunImpact and "physgun" or "physics",
                    impactVelocity * 0.70,
                    false
                )

                MEXD.ApplyDamage(
                    ent,
                    zone,
                    severity,
                    hitPos,
                    ZoneOutwardNormal(ent, zone),
                    physgunImpact and "physgun" or "physics"
                )
            end)
        end

        MEXD.Reset(train)

        -- Metrostroi can move/reparent/settle a newly spawned wagon very
        -- aggressively. Ignore all of that and take a fresh baseline exactly
        -- one second after creation.
        timer.Simple(SPAWN_GRACE_SECONDS, function()
            if not IsSubwayTrain(train) then return end

            MEXD.Reset(train)
            train.MEXDamageLastVelocity = train:GetVelocity()
            train.MEXDamageLastPosition = train:GetPos()
            train.MEXDamageLastSample = CurTime()
            train.MEXDamagePreviousSpeedKmh = train:GetVelocity():Length() * SU_TO_KMH
            train.MEXDamageCrashCooldown = CurTime() + 0.10
            train:SetNW2Bool("MEX.DamageReady", true)
        end)
    end

    function MEXD.Reset(train)
        if not IsValid(train) then return end

        RemoveDetachedServerComponents(train, train.MEXDamageInitialized == true)

        for zone in pairs(ZONES) do
            train:SetNW2Float(DamageKey(zone), 0)
            train:SetNW2Float(CrushKey(zone), 0)
            train:SetNW2Float("MEX.Damage.HitStrength." .. zone, 0)
            train:SetNW2Vector("MEX.Damage.HitLocal." .. zone, vector_origin)
        end

        train:SetNW2Float("MEX.Damage.electrical", 0)
        train:SetNW2Float("MEX.Damage.overall", 0)
        train:SetNW2Float("MEX.StructuralHealth", 1)
        train:SetNW2Float("MEX.Damage.LastImpactKmh", 0)
        train:SetNW2Float("MEX.Damage.BlastStrength", 0)
        train:SetNW2Float("MEX.Damage.BlastRadius", 0)
        train:SetNW2Vector("MEX.Damage.BlastLocal", vector_origin)
        train:SetNW2Vector("MEX.Damage.BlastImpulseLocal", vector_origin)
        train.MEXDamageComponentImpacts = {}

        train:SetNW2Bool("MEX.Damage.Moderate", false)
        train:SetNW2Bool("MEX.Damage.Heavy", false)
        train:SetNW2Bool("MEX.Damage.Critical", false)
        train:SetNW2Bool("MEX.Damage.DoorsLeft", false)
        train:SetNW2Bool("MEX.Damage.DoorsRight", false)
        train:SetNW2Bool("MEX.Damage.FrontEquipment", false)
        train:SetNW2Bool("MEX.Damage.RearEquipment", false)
        train:SetNW2Bool("MEX.Damage.ElectricalFault", false)

        RestoreTrippedProtection(train)
        RestoreSensitiveWaterSystems(train)
        RestoreWaterRelayChatter(train)
        RestoreWaterVisualGlitchHooks(train)
        RestoreWaterBatteryGlitchHook(train)

        train.MEXDamageWaterExposure = 0
        train.MEXDamageWaterMoisture = 0
        train.MEXDamageDeepMoisture = 0
        train.MEXDamageDrySince = nil
        train.MEXDamageWaterNextFailureExposure = nil
        train.MEXDamageNextWaterArc = nil
        train.MEXDamageNextWaterVisualGlitch = nil
        train.MEXDamageNextRelayChatter = nil
        train.MEXDamageNextDoorWaterFault = nil
        train.MEXDamageNextBatteryGlitch = nil
        train:SetNW2Float("MEX.Damage.WaterGlitchIntensity", 0)
        train:SetNW2Float("MEX.Damage.BatteryGlitchFactor", 1)
        train:SetNW2String("MEX.Damage.ChatteringRelay", "")
        train:SetNW2String("MEX.Damage.DoorWaterFault", "")
        train:SetNW2Float("MEX.Damage.WaterWetness", 0)
        train:SetNW2Float("MEX.Damage.WaterVoltage", 0)
        train:SetNW2Float("MEX.Damage.WaterCurrent", 0)
        train:SetNW2Float("MEX.Damage.WaterHazard", 0)
        train:SetNW2Float("MEX.Damage.WaterExposure", 0)
        train:SetNW2Float("MEX.Damage.WaterMoisture", 0)
        train:SetNW2Float("MEX.Damage.DeepMoisture", 0)
        train:SetNW2Float("MEX.Damage.DrySeconds", 0)
        train:SetNW2String("MEX.Damage.LastProtection", "")

        hook.Run("MetrostroiExpandedDamageReset", train)
    end

    local function SetServerDamageEnabled(enabled)
        if not damageEnabledConVar then return end

        enabled = enabled == true
        damageEnabledConVar:SetBool(enabled)

        if not enabled and deformationEnabledConVar then
            deformationEnabledConVar:SetBool(false)
        end
    end

    local function SetServerDeformationEnabled(enabled)
        if not deformationEnabledConVar then return end

        if not MEXD.IsDamageEnabled() then
            deformationEnabledConVar:SetBool(false)
            return
        end

        deformationEnabledConVar:SetBool(enabled == true)
    end

    concommand.Add("mex_damage_set_enabled", function(ply, _, args)
        if IsValid(ply) and not ply:IsAdmin() then return end
        SetServerDamageEnabled(tobool(args[1]))
    end)

    concommand.Add("mex_damage_set_deformation_enabled", function(ply, _, args)
        if IsValid(ply) and not ply:IsAdmin() then return end
        SetServerDeformationEnabled(tobool(args[1]))
    end)

    cvars.AddChangeCallback(
        DAMAGE_ENABLED_CVAR_NAME,
        function(_, _, newValue)
            if tobool(newValue) then return end

            if deformationEnabledConVar
                and deformationEnabledConVar:GetBool()
            then
                deformationEnabledConVar:SetBool(false)
            end

            for _, train in ipairs(ents.GetAll()) do
                if IsSubwayTrain(train) then
                    MEXD.Reset(train)
                end
            end
        end,
        "MEX.Damage.Settings.DamageEnabled"
    )

    cvars.AddChangeCallback(
        DEFORMATION_ENABLED_CVAR_NAME,
        function(_, _, newValue)
            if MEXD.IsDamageEnabled() then return end
            if not tobool(newValue) then return end

            if deformationEnabledConVar then
                deformationEnabledConVar:SetBool(false)
            end
        end,
        "MEX.Damage.Settings.DeformationEnabled"
    )

    local function SendImpactEffect(train, zone, amount, worldPos, normal)
        if not IsValid(train) then return end

        worldPos = worldPos or train:LocalToWorld(ZoneLocalImpactPoint(train, zone))
        normal = normal or ZoneOutwardNormal(train, zone)

        net.Start("MEX.DamageImpact")
            net.WriteEntity(train)
            net.WriteString(zone)
            net.WriteFloat(amount)
            net.WriteVector(worldPos)
            net.WriteNormal(normal)
        net.Broadcast()

        if amount >= 0.10 then
            local effect = EffectData()
            effect:SetOrigin(worldPos)
            effect:SetNormal(normal)
            effect:SetMagnitude(math.Clamp(amount * 6, 1, 6))
            effect:SetScale(math.Clamp(amount * 2, 0.5, 2))
            effect:SetRadius(math.Clamp(amount * 12, 2, 12))
            util.Effect("Sparks", effect, true, true)
        end

        if amount >= 0.18 then
            util.Decal(
                "Impact.Metal",
                worldPos + normal * 12,
                worldPos - normal * 12,
                train
            )
        end
    end

    function MEXD.ApplyDamage(train, zone, amount, worldPos, normal, source)
        if not MEXD.IsDamageEnabled() then
            return MEXD.GetZoneDamage(train, zone)
        end

        if not IsSubwayTrain(train) or not ZONES[zone] then return 0 end

        amount = math.Clamp(tonumber(amount) or 0, 0, 1)
        if amount <= 0 then return MEXD.GetZoneDamage(train, zone) end

        local old = MEXD.GetZoneDamage(train, zone)

        -- Logical/system damage remains normalized to 0..1.
        local effective = amount * (1 - old * 0.45)
        local new = math.Clamp(old + effective, 0, 1)
        train:SetNW2Float(DamageKey(zone), new)

        -- Plastic crush is deliberately NOT capped at 1.0. Once a wagon is
        -- already "destroyed" logically, later impacts must still be able to
        -- fold more metal. This lets repeated crashes/weapon hits continue
        -- compressing the body until it can become scrap instead of freezing
        -- at one final dent shape.
        local oldCrush = MEXD.GetCrushEnergy(train, zone)
        local sourceScale =
            source == "physgun" and 1.28
            or source == "physics" and 1.18
            or source == "blast" and 1.22
            or source == "bullet" and 0.82
            or source == "buckshot" and 0.95
            or source == "melee" and 0.62
            or 1

        local crushAdded = math.max(amount, 0.004) * sourceScale
        local newCrush = math.Clamp(
            oldCrush + crushAdded,
            0,
            6.0
        )
        train:SetNW2Float(CrushKey(zone), newCrush)

        if isvector(worldPos) then
            local hitLocal = train:WorldToLocal(worldPos)
            local hitKey = "MEX.Damage.HitLocal." .. zone
            local strengthKey = "MEX.Damage.HitStrength." .. zone
            local oldStrength = train:GetNW2Float(strengthKey, 0)
            local oldHit = train:GetNW2Vector(hitKey, hitLocal)
            local combinedStrength = math.Clamp(oldStrength + amount, 0, 6)

            if oldStrength <= 0.001 then
                oldHit = hitLocal
            end

            local blend = math.Clamp(amount / math.max(oldStrength + amount, 0.001), 0, 1)
            train:SetNW2Vector(hitKey, LerpVector(blend, oldHit, hitLocal))
            train:SetNW2Float(strengthKey, combinedStrength)
        end

        -- Hard impacts can disturb electrical equipment even when the physical
        -- deformation is elsewhere. This is a generic state for the future
        -- electrical subsystem module.
        if amount >= 0.22 then
            local electrical = train:GetNW2Float("MEX.Damage.electrical", 0)
            electrical = math.Clamp(electrical + amount * 0.30, 0, 1)
            train:SetNW2Float("MEX.Damage.electrical", electrical)
        end

        UpdateDamageState(train)
        SendImpactEffect(train, zone, amount, worldPos, normal)

        if amount >= 0.10 then
            local pitch = math.floor(Lerp(math.Clamp(amount, 0, 1), 115, 80))
            train:EmitSound("physics/metal/metal_box_impact_hard3.wav", 82, pitch, 0.8)
        end

        hook.Run(
            "MetrostroiExpandedTrainDamaged",
            train,
            zone,
            amount,
            old,
            new,
            source or "unknown"
        )

        return new
    end

    ClassifyFromWorldDeltaVelocity = function(train, deltaVelocity)
        local x = deltaVelocity:Dot(train:GetForward())
        local y = deltaVelocity:Dot(train:GetRight())
        local z = deltaVelocity:Dot(train:GetUp())

        local ax, ay, az = math.abs(x), math.abs(y), math.abs(z)

        if ax >= ay and ax >= az then
            -- A front impact pushes/decelerates the train towards -local X.
            return x < 0 and "front" or "rear"
        elseif ay >= az then
            -- A hit on the right side pushes the train towards -local Y.
            return y < 0 and "right" or "left"
        end

        -- Roof contact pushes down; floor contact pushes up.
        return z < 0 and "roof" or "floor"
    end

    ClassifyFromWorldPosition = function(train, worldPos)
        if not isvector(worldPos) then return nil end

        local localPos = train:WorldToLocal(worldPos)
        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()

        local centerX = (mins.x + maxs.x) * 0.5
        local centerY = (mins.y + maxs.y) * 0.5
        local centerZ = (mins.z + maxs.z) * 0.5

        local nx = math.abs(localPos.x - centerX) / math.max((maxs.x - mins.x) * 0.5, 1)
        local ny = math.abs(localPos.y - centerY) / math.max((maxs.y - mins.y) * 0.5, 1)
        local nz = math.abs(localPos.z - centerZ) / math.max((maxs.z - mins.z) * 0.5, 1)

        if nx >= ny and nx >= nz then
            return localPos.x >= centerX and "front" or "rear"
        elseif ny >= nz then
            return localPos.y >= centerY and "right" or "left"
        end

        return localPos.z >= centerZ and "roof" or "floor"
    end

    net.Receive("MEX.DetachRequest", function(_, ply)
        if not MEXD.IsDamageEnabled() then return end

        local train = net.ReadEntity()
        local name = net.ReadString()
        local model = net.ReadString()
        local localPos = net.ReadVector()
        local localAng = net.ReadAngle()
        local anchorLocal = net.ReadVector()
        local mins = net.ReadVector()
        local maxs = net.ReadVector()
        local isDoor = net.ReadBool()
        local isControl = net.ReadBool()
        local skin = net.ReadUInt(8)
        local color = net.ReadColor()
        local material = net.ReadString()
        local frozenSequence = net.ReadUInt(16)
        local frozenCycle = net.ReadFloat()
        local frozenPose = net.ReadFloat()

        local bodygroups = {}
        local bodygroupCount = math.min(net.ReadUInt(5), 31)
        for _ = 1, bodygroupCount do
            local id = net.ReadUInt(5)
            local value = net.ReadUInt(8)
            bodygroups[id] = value
        end

        local buttonIDs = {}
        local buttonCount = math.min(net.ReadUInt(6), 48)
        for _ = 1, buttonCount do
            local id = net.ReadString()
            if #id <= 96 and id ~= "" then
                buttonIDs[#buttonIDs + 1] = id:gsub("^.+:", "")
            end
        end

        local clientMechanical = net.ReadBool()
        local electricalTargets = {}
        local electricalTargetCount = math.min(net.ReadUInt(5), 24)

        for _ = 1, electricalTargetCount do
            local target = net.ReadString()
            if #target <= 64
                and target ~= ""
                and string.match(target, "^[%w_%-]+$")
            then
                electricalTargets[#electricalTargets + 1] = target
            end
        end

        if not IsSubwayTrain(train) then return end
        InitializeTrainDamage(train)
        if CurTime() < (train.MEXDamageIgnoreUntil or 0) then return end

        if not isstring(name) or name == "" or #name > 128 then return end
        if not isstring(model) or #model > 192 then return end
        if string.sub(string.lower(model), 1, 7) ~= "models/" then return end
        if not util.IsValidModel(model) then return end
        if not isvector(localPos) or not isangle(localAng) then return end
        if not isvector(anchorLocal) then return end
        if not isvector(mins) or not isvector(maxs) then return end
        if not isstring(material) or #material > 160 then return end

        local obbMins = train:OBBMins() - Vector(100, 100, 100)
        local obbMaxs = train:OBBMaxs() + Vector(100, 100, 100)

        if localPos.x < obbMins.x or localPos.x > obbMaxs.x
            or localPos.y < obbMins.y or localPos.y > obbMaxs.y
            or localPos.z < obbMins.z or localPos.z > obbMaxs.z
            or anchorLocal.x < obbMins.x or anchorLocal.x > obbMaxs.x
            or anchorLocal.y < obbMins.y or anchorLocal.y > obbMaxs.y
            or anchorLocal.z < obbMins.z or anchorLocal.z > obbMaxs.z
        then
            return
        end

        train.MEXDamageDetachedServer = train.MEXDamageDetachedServer or {}

        local now = CurTime()
        if not ply.MEXDamageDetachWindow
            or now - ply.MEXDamageDetachWindow >= 1
        then
            ply.MEXDamageDetachWindow = now
            ply.MEXDamageDetachCount = 0
        end

        ply.MEXDamageDetachCount = (ply.MEXDamageDetachCount or 0) + 1
        if ply.MEXDamageDetachCount > 192 then return end

        local detachedCount = table.Count(train.MEXDamageDetachedServer)
        if detachedCount >= 160 then return end

        if train.MEXDamageDetachedServer[name] then
            BroadcastDetachedComponent(
                train,
                name,
                train.MEXDamageDetachedServer[name].debris,
                ply
            )
            return
        end

        local zone, localScore = FindNearestDamagedZone(train, anchorLocal)
        local overall = MEXD.GetOverallDamage(train)
        local componentSize = maxs - mins
        local componentRadius = math.Clamp(
            math.max(
                math.abs(componentSize.x),
                math.abs(componentSize.y),
                math.abs(componentSize.z)
            ) * 0.30,
            3,
            isDoor and 34 or 20
        )

        local directImpact, directScore =
            FindRecentComponentImpact(
                train,
                anchorLocal,
                componentRadius
            )

        -- A mounting can fail either from accumulated structural deformation
        -- or from a direct local hit (crowbar, bullet, local collision).
        -- Direct hits are intentionally local and consume one slot from that
        -- impact so a pistol shot does not detach an entire dashboard.
        local structuralMinimum =
            isDoor and 0.055
            or (isControl and 0.020 or 0.035)

        local directMinimum

        if directImpact and directImpact.blast then
            -- Blast attachment failure is driven by impulse/movement. If the
            -- mounting is displaced at all, fragile hardware should tear away
            -- instead of elastically snapping back into the train.
            directMinimum =
                isDoor and 0.045
                or (isControl and 0.018 or 0.035)
        else
            directMinimum =
                isDoor and 0.20
                or (isControl and 0.11 or 0.20)
        end

        local structuralOK =
            zone ~= nil
            and localScore >= structuralMinimum
            and overall >= (isDoor and 0.18 or 0.08)

        local directOK =
            directImpact ~= nil
            and directScore >= directMinimum

        if not structuralOK and not directOK then
            return
        end

        if directOK then
            directImpact.remaining = math.max(0, directImpact.remaining - 1)
            zone = zone or ClassifyFromWorldPosition(
                train,
                train:LocalToWorld(anchorLocal)
            )
        end

        local debris
        local debrisList
        local isGlass = IsGlassComponentName(name, model)

        if isGlass then
            debrisList = SpawnGlassShards(
                train,
                name,
                anchorLocal,
                zone
            )
            debris = istable(debrisList) and debrisList[1] or nil
        elseif isDoor and GetPassengerDoorFamily(name, model) then
            debrisList = SpawnSplitPassengerDoorLeaves(
                train,
                name,
                model,
                localPos,
                localAng,
                zone,
                skin,
                color,
                material,
                bodygroups,
                frozenSequence,
                frozenCycle,
                frozenPose
            )

            if istable(debrisList) and #debrisList > 0 then
                debris = debrisList[1]
            else
                debrisList = nil
                debris = SpawnDetachedPhysicsProp(
                    train,
                    name,
                    model,
                    localPos,
                    localAng,
                    mins,
                    maxs,
                    skin,
                    color,
                    material,
                    bodygroups,
                    isDoor,
                    isControl,
                    zone,
                    frozenSequence,
                    frozenCycle,
                    frozenPose
                )

                if not IsValid(debris) then return end
            end
        else
            debris = SpawnDetachedPhysicsProp(
                train,
                name,
                model,
                localPos,
                localAng,
                mins,
                maxs,
                skin,
                color,
                material,
                bodygroups,
                isDoor,
                isControl,
                zone,
                frozenSequence,
                frozenCycle,
                frozenPose
            )

            if not IsValid(debris) then return end
        end

        if not isGlass then
            if istable(debrisList) and #debrisList > 0 then
                for ordinal, released in ipairs(debrisList) do
                    ApplyBreakawayImpulse(
                        train,
                        released,
                        directImpact,
                        zone,
                        anchorLocal,
                        isDoor,
                        isControl,
                        ordinal
                    )
                end
            elseif IsValid(debris) then
                ApplyBreakawayImpulse(
                    train,
                    debris,
                    directImpact,
                    zone,
                    anchorLocal,
                    isDoor,
                    isControl,
                    1
                )
            end
        end

        local validButtons = {}
        local seenButtons = {}

        local function rememberAndBlock(button)
            if not isstring(button) or button == "" then return end
            button = button:gsub("^.+:", "")
            if #button > 96 or seenButtons[button] then return end

            seenButtons[button] = true
            BlockDetachedButton(train, button)
            validButtons[#validButtons + 1] = button
        end

        -- Start with the client-resolved physical bindings, then derive
        -- well-known multi-action pneumatic hardware again on the server from
        -- the already validated component name/model. This makes a detached
        -- valve authoritative even if an old train has no usable ButtonMap
        -- relationship for that visual ClientEnt.
        local authoritativeButtons = {}
        local authoritativeSeen = {}

        local function addAuthoritative(button)
            if not isstring(button) or button == "" then return end
            button = button:gsub("^.+:", "")
            if authoritativeSeen[button] then return end
            authoritativeSeen[button] = true
            authoritativeButtons[#authoritativeButtons + 1] = button
        end

        for _, button in ipairs(buttonIDs) do
            addAuthoritative(button)
        end

        AddKnownDetachedHardwareButtons(
            name,
            model,
            addAuthoritative
        )

        for _, button in ipairs(authoritativeButtons) do
            rememberAndBlock(button)
        end

        local expandedButtons = ExpandDetachedButtonAliases(
            train,
            authoritativeButtons
        )

        for _, button in ipairs(expandedButtons) do
            if not seenButtons[button]
                and IsValidDetachedButtonID(train, button)
            then
                rememberAndBlock(button)
            end
        end

        local electricalFailures = {}

        if isControl then
            electricalFailures = ApplyDetachedElectricalFailure(
                train,
                name,
                model,
                validButtons,
                electricalTargets,
                clientMechanical
            )
        end

        train.MEXDamageDetachedServer[name] = {
            debris = debris,
            debrisList = debrisList,
            buttons = validButtons,
            electricalFailures = electricalFailures,
        }

        RebuildDetachedButtonGuard(train)

        BroadcastDetachedComponent(train, name, debris)
    end)

    hook.Add("PlayerInitialSpawn", "MEX.Damage.SyncDetachedComponents", function(ply)
        timer.Simple(2, function()
            if not IsValid(ply) then return end

            for _, train in ipairs(ents.GetAll()) do
                if not IsSubwayTrain(train)
                    or not istable(train.MEXDamageDetachedServer)
                then
                    continue
                end

                for name, data in pairs(train.MEXDamageDetachedServer) do
                    BroadcastDetachedComponent(
                        train,
                        name,
                        data.debris,
                        ply
                    )
                end
            end
        end)
    end)

    hook.Add("EntityTakeDamage", "MEX.Damage.FromEntityDamage", function(ent, dmginfo)
        if not MEXD.IsDamageEnabled() then return end
        if not IsSubwayTrain(ent) then return end

        InitializeTrainDamage(ent)
        if CurTime() < (ent.MEXDamageIgnoreUntil or 0) then return end

        local rawDamage = math.max(dmginfo:GetDamage(), 0)

        if IsComponentDamageType(dmginfo) and rawDamage > 0 then
            local componentPos = DamageImpactWorldPosition(ent, dmginfo)
            local isBlast = dmginfo:IsDamageType(DMG_BLAST)
            local isBuckshot = dmginfo:IsDamageType(DMG_BUCKSHOT)
            local isCrush = dmginfo:IsDamageType(DMG_CRUSH)
                or dmginfo:IsDamageType(DMG_VEHICLE)

            local radius
            local maxDetach

            if isBlast then
                radius = math.Clamp(58 + rawDamage * 1.15, 70, 280)
                maxDetach = math.Clamp(10 + math.floor(rawDamage / 8), 10, 80)
            elseif isCrush then
                radius = math.Clamp(22 + rawDamage * 0.45, 24, 105)
                maxDetach = math.Clamp(1 + math.floor(rawDamage / 32), 1, 7)
            elseif isBuckshot then
                radius = math.Clamp(25 + rawDamage * 0.22, 26, 55)
                maxDetach = math.Clamp(1 + math.floor(rawDamage / 35), 1, 4)
            else
                -- Crowbar/pistol/rifle: a very local hit. One physical ROOT
                -- component is selected client-side. Spare slots are reserved
                -- only for that root's attached label/plomb/cap children.
                radius = math.Clamp(13 + rawDamage * 0.18, 14, 30)
                maxDetach = 10
            end

            local damageForce = dmginfo:GetDamageForce()
            local impulseWorld = Vector(0, 0, 0)

            if isvector(damageForce) and damageForce:LengthSqr() > 1 then
                local dir = damageForce:GetNormalized()
                local speedImpulse

                if isBlast then
                    speedImpulse = math.Clamp(45 + rawDamage * 1.65, 55, 260)
                elseif isCrush then
                    speedImpulse = math.Clamp(25 + rawDamage * 0.85, 30, 170)
                elseif isBuckshot then
                    speedImpulse = math.Clamp(18 + rawDamage * 0.55, 20, 105)
                else
                    speedImpulse = math.Clamp(10 + rawDamage * 0.35, 12, 70)
                end

                impulseWorld = dir * speedImpulse
            end

            SendComponentImpact(
                ent,
                componentPos,
                math.Clamp(
                    (isBlast and 0.55 or 0.32) + rawDamage / 40,
                    isBlast and 0.55 or 0.32,
                    isBlast and 1.9 or 1.35
                ),
                radius,
                maxDetach,
                isBlast and "blast" or "damageinfo",
                impulseWorld,
                isBlast
            )
        end

        if rawDamage <= 0 then return end

        local isBlast = dmginfo:IsDamageType(DMG_BLAST)
        local isCrush = dmginfo:IsDamageType(DMG_CRUSH)
            or dmginfo:IsDamageType(DMG_VEHICLE)
        local isBullet = dmginfo:IsDamageType(DMG_BULLET)
        local isBuckshot = dmginfo:IsDamageType(DMG_BUCKSHOT)
        local isMelee = dmginfo:IsDamageType(DMG_CLUB)
            or dmginfo:IsDamageType(DMG_SLASH)

        if not (isBlast or isCrush or isBullet or isBuckshot or isMelee) then
            return
        end

        local pos = DamageImpactWorldPosition(ent, dmginfo)
        local zone = ClassifyFromWorldPosition(ent, pos)

        if not zone then
            local force = dmginfo:GetDamageForce()
            if isvector(force) and force:LengthSqr() > 1 then
                zone = ClassifyFromWorldDeltaVelocity(ent, force)
            end
        end

        zone = zone or "front"

        -- Weapons used to detach individual props but did not feed the
        -- structural deformation accumulator at all. Give them a small local,
        -- permanent dent contribution so repeated shots actually crumple the
        -- front instead of only making controls disappear.
        local amount

        if isBlast then
            amount = math.Clamp(rawDamage / 230, 0.040, 0.52)
        elseif isCrush then
            amount = math.Clamp(rawDamage / 220, 0.030, 0.48)
        elseif isBuckshot then
            amount = math.Clamp(
                0.035 + rawDamage / 230,
                0.040,
                0.20
            )
        elseif isBullet then
            amount = math.Clamp(
                0.018 + rawDamage / 340,
                0.022,
                0.16
            )
        else
            amount = math.Clamp(
                0.012 + rawDamage / 520,
                0.015,
                0.085
            )
        end

        local normal = ZoneOutwardNormal(ent, zone)

        if isBlast then
            local blastWorldPos = DamageImpactWorldPosition(ent, dmginfo)
            local blastForce = dmginfo:GetDamageForce()
            local blastImpulseLocal = Vector(0, 0, 0)

            if isvector(blastForce) and blastForce:LengthSqr() > 1 then
                local dir = blastForce:GetNormalized()
                local velocityLike =
                    math.Clamp(45 + rawDamage * 1.65, 55, 260)
                blastImpulseLocal = WorldDirectionToLocal(
                    ent,
                    dir * velocityLike
                )
            end

            ent:SetNW2Vector(
                "MEX.Damage.BlastLocal",
                ent:WorldToLocal(blastWorldPos)
            )
            ent:SetNW2Vector(
                "MEX.Damage.BlastImpulseLocal",
                blastImpulseLocal
            )
            ent:SetNW2Float(
                "MEX.Damage.BlastStrength",
                math.Clamp(rawDamage / 180, 0.08, 1.25)
            )
            ent:SetNW2Float(
                "MEX.Damage.BlastRadius",
                math.Clamp(58 + rawDamage * 1.15, 70, 280)
            )
        end

        -- Only physical collisions/blasts need velocity-detector de-duplication.
        -- A bullet immediately before a crash must not suppress that crash.
        if isCrush or isBlast then
            ent.MEXDamageCrashCooldown = CurTime() + 0.18
        end

        local source =
            isBullet and "bullet"
            or isBuckshot and "buckshot"
            or isMelee and "melee"
            or isBlast and "blast"
            or "damageinfo"

        MEXD.ApplyDamage(ent, zone, amount, pos, normal, source)
    end)

    local nextWaterElectricalScan = 0
    local lastWaterElectricalScan = CurTime()

    hook.Add("Think", "MEX.Damage.WaterElectrical", function()
        local now = CurTime()
        if now < nextWaterElectricalScan then return end

        local dT = math.Clamp(
            now - lastWaterElectricalScan,
            0.01,
            0.35
        )
        lastWaterElectricalScan = now
        nextWaterElectricalScan = now + WATER_SCAN_INTERVAL

        for _, train in ipairs(ents.GetAll()) do
            if IsSubwayTrain(train) then
                InitializeTrainDamage(train)
                EnforceElectricalFailures(train)
                UpdateWaterElectricalDamage(train, dT)
            end
        end
    end)

    local nextVelocityScan = 0

    hook.Add("Think", "MEX.Damage.VelocityCrashDetection", function()
        if CurTime() < nextVelocityScan then return end
        nextVelocityScan = CurTime() + 0.05

        for _, train in ipairs(ents.GetAll()) do
            if not IsSubwayTrain(train) then continue end

            InitializeTrainDamage(train)

            local velocity = train:GetVelocity()
            local position = train:GetPos()
            local now = CurTime()

            if not train.MEXDamageLastVelocity then
                train.MEXDamageLastVelocity = velocity
                train.MEXDamageLastPosition = position
                train.MEXDamageLastSample = now
                continue
            end

            local dt = now - (train.MEXDamageLastSample or now)
            local moved = position:Distance(train.MEXDamageLastPosition or position)
            local deltaVelocity = velocity - train.MEXDamageLastVelocity

            train.MEXDamageLastVelocity = velocity
            train.MEXDamageLastPosition = position
            train.MEXDamageLastSample = now
            train.MEXDamagePreviousSpeedKmh = velocity:Length() * SU_TO_KMH

            -- A newly created Metrostroi wagon receives several large position
            -- and velocity corrections while bogeys, couplers and systems are
            -- being initialized. Keep updating the baseline, but never turn
            -- those corrections into crash damage.
            if now < (train.MEXDamageIgnoreUntil or 0) then continue end

            -- Ignore teleports, respawns and physics reinitialisation.
            if dt <= 0 or dt > 0.25 or moved > 600 then continue end

            local deltaKmh = deltaVelocity:Length() * SU_TO_KMH
            if deltaKmh < 12 then continue end
            if (train.MEXDamageCrashCooldown or 0) > now then continue end

            local previousSpeedKmh = math.max(
                0,
                (velocity - deltaVelocity):Length() * SU_TO_KMH
            )

            -- A very low-speed train can receive a physics correction while
            -- spawning/coupling. Require either meaningful movement or a strong
            -- velocity impulse.
            if previousSpeedKmh < 5 and deltaKmh < 18 then continue end

            train.MEXDamageCrashCooldown = now + 0.22

            local zone = ClassifyFromWorldDeltaVelocity(train, deltaVelocity)
            local amount = math.Clamp((deltaKmh - 12) / 65, 0.015, 0.55)
            local localImpact = ZoneLocalImpactPoint(train, zone)
            local worldImpact = train:LocalToWorld(localImpact)

            MEXD.ApplyDamage(
                train,
                zone,
                amount,
                worldImpact,
                ZoneOutwardNormal(train, zone),
                "velocity"
            )
        end
    end)

    hook.Add("OnEntityCreated", "MEX.Damage.InitializeTrain", function(ent)
        timer.Simple(0, function()
            if not IsSubwayTrain(ent) then return end
            InitializeTrainDamage(ent)
        end)
    end)

    hook.Add("InitPostEntity", "MEX.Damage.InitializeExistingTrains", function()
        timer.Simple(0.25, function()
            for _, train in ipairs(ents.GetAll()) do
                if IsSubwayTrain(train) then
                    InitializeTrainDamage(train)
                end
            end
        end)
    end)

    local function GetAimedTrain(ply)
        if not IsValid(ply) then return nil end
        local tr = ply:GetEyeTrace()
        if not tr or not IsSubwayTrain(tr.Entity) then return nil end
        return tr.Entity
    end

    concommand.Add("mex_damage_test", function(ply, _, args)
        if IsValid(ply) and not ply:IsAdmin() then return end

        if not MEXD.IsDamageEnabled() then
            print("[Metrostroi Expanded/Damage] Damage is disabled.")
            return
        end

        local train = GetAimedTrain(ply)
        if not IsValid(train) then
            print("[Metrostroi Expanded/Damage] Aim at a Metrostroi train.")
            return
        end

        InitializeTrainDamage(train)
        if CurTime() < (train.MEXDamageIgnoreUntil or 0) then
            print("[Metrostroi Expanded/Damage] Damage system is still in the 1000 ms spawn grace period.")
            return
        end

        local zone = string.lower(args[1] or "front")
        if not ZONES[zone] then
            print("[Metrostroi Expanded/Damage] Zone must be: front, rear, left, right, roof or floor.")
            return
        end

        local amount = math.Clamp(tonumber(args[2]) or 0.25, 0.01, 1)
        local worldPos = train:LocalToWorld(ZoneLocalImpactPoint(train, zone))

        MEXD.ApplyDamage(
            train,
            zone,
            amount,
            worldPos,
            ZoneOutwardNormal(train, zone),
            "console"
        )
    end)

    concommand.Add("mex_damage_scrap_test", function(ply, _, args)
        if IsValid(ply) and not ply:IsAdmin() then return end

        if not MEXD.IsDamageEnabled() then
            print("[Metrostroi Expanded/Damage] Damage is disabled.")
            return
        end

        local train = GetAimedTrain(ply)
        if not IsValid(train) then
            print("[Metrostroi Expanded/Damage] Aim at a Metrostroi train.")
            return
        end

        InitializeTrainDamage(train)
        if CurTime() < (train.MEXDamageIgnoreUntil or 0) then
            print("[Metrostroi Expanded/Damage] Damage system is still in the spawn grace period.")
            return
        end

        local energy = math.Clamp(tonumber(args[1]) or 3.0, 0.1, 6.0)
        local worldPos = train:LocalToWorld(
            ZoneLocalImpactPoint(train, "front")
        )

        train:SetNW2Float(DamageKey("front"), 1)
        train:SetNW2Float(CrushKey("front"), energy)
        train:SetNW2Float("MEX.Damage.HitStrength.front", energy)
        train:SetNW2Vector(
            "MEX.Damage.HitLocal.front",
            train:WorldToLocal(worldPos)
        )

        UpdateDamageState(train)
        SendImpactEffect(
            train,
            "front",
            math.Clamp(energy / 4, 0.12, 1),
            worldPos,
            ZoneOutwardNormal(train, "front")
        )

        print(string.format(
            "[Metrostroi Expanded/Damage] front scrap test set to %.2f for %s",
            energy,
            train:GetClass()
        ))
    end)

    concommand.Add("mex_damage_reset", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end

        local train = GetAimedTrain(ply)
        if not IsValid(train) then
            print("[Metrostroi Expanded/Damage] Aim at a Metrostroi train.")
            return
        end

        MEXD.Reset(train)
        print("[Metrostroi Expanded/Damage] Damage reset for " .. train:GetClass())
    end)

    concommand.Add("mex_damage_status", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end

        local train = GetAimedTrain(ply)
        if not IsValid(train) then
            print("[Metrostroi Expanded/Damage] Aim at a Metrostroi train.")
            return
        end

        print(string.format(
            "[Metrostroi Expanded/Damage] %s | front %.2f rear %.2f left %.2f right %.2f roof %.2f floor %.2f | front crush %.2f | structural health %.2f | electrical %.2f | water %.2f | moisture %.2f/%.2f | dry %.0fs | %.0f V | %.1f A | hazard %.2f | last impact %.1f km/h | detached %d | blocked controls %d | failed electrical switches %d | sensitive offline %d | glitch %.2f | chatter %s | doorfault %s | batt %.2f | instruments %s | protection %s",
            train:GetClass(),
            MEXD.GetZoneDamage(train, "front"),
            MEXD.GetZoneDamage(train, "rear"),
            MEXD.GetZoneDamage(train, "left"),
            MEXD.GetZoneDamage(train, "right"),
            MEXD.GetZoneDamage(train, "roof"),
            MEXD.GetZoneDamage(train, "floor"),
            MEXD.GetCrushEnergy(train, "front"),
            train:GetNW2Float("MEX.StructuralHealth", 1),
            train:GetNW2Float("MEX.Damage.electrical", 0),
            train:GetNW2Float("MEX.Damage.WaterWetness", 0),
            train:GetNW2Float("MEX.Damage.WaterMoisture", 0),
            train:GetNW2Float("MEX.Damage.DeepMoisture", 0),
            train:GetNW2Float("MEX.Damage.DrySeconds", 0),
            train:GetNW2Float("MEX.Damage.WaterVoltage", 0),
            train:GetNW2Float("MEX.Damage.WaterCurrent", 0),
            train:GetNW2Float("MEX.Damage.WaterHazard", 0),
            train:GetNW2Float("MEX.Damage.LastImpactKmh", 0),
            istable(train.MEXDamageDetachedServer)
                and table.Count(train.MEXDamageDetachedServer)
                or 0,
            istable(train.MEXDamageBlockedButtons)
                and table.Count(train.MEXDamageBlockedButtons)
                or 0,
            istable(train.MEXDamageElectricalFailureSystems)
                and table.Count(train.MEXDamageElectricalFailureSystems)
                or 0,
            istable(train.MEXDamageWetSensitiveSystems)
                and table.Count(train.MEXDamageWetSensitiveSystems)
                or 0,
            train:GetNW2Float(
                "MEX.Damage.WaterGlitchIntensity",
                0
            ),
            train:GetNW2String(
                "MEX.Damage.ChatteringRelay",
                "none"
            ),
            train:GetNW2String(
                "MEX.Damage.DoorWaterFault",
                "none"
            ),
            train:GetNW2Float(
                "MEX.Damage.BatteryGlitchFactor",
                1
            ),
            IsTrainInstrumentationPowered(train)
                and "ON"
                or "OFF",
            train:GetNW2String(
                "MEX.Damage.LastProtection",
                "none"
            )
        ))
    end)

    hook.Add("EntityRemoved", "MEX.Damage.CleanupServerDebris", function(ent)
        if not IsSubwayTrain(ent) then return end

        RestoreWaterRelayChatter(ent)
        RestoreWaterVisualGlitchHooks(ent)
        RestoreWaterBatteryGlitchHook(ent)
        RestoreSensitiveWaterSystems(ent)

        if istable(ent.MEXDamageDetachedServer) then
            for _, data in pairs(ent.MEXDamageDetachedServer) do
                if IsValid(data.debris) then
                    data.debris:Remove()
                end

                if istable(data.debrisList) then
                    for _, debris in ipairs(data.debrisList) do
                        if IsValid(debris) then
                            debris:Remove()
                        end
                    end
                end
            end
        end
    end)
end

if CLIENT then
    ---------------------------------------------------------------------------
    -- Utilities -> Metrostroi Expanded
    ---------------------------------------------------------------------------

    hook.Add("PopulateToolMenu", "MEX.Damage.PopulateUtilities", function()
        spawnmenu.AddToolMenuOption(
            "Utilities",
            "Metrostroi Expanded",
            "MEXDamageSettings",
            "Damage",
            "",
            "",
            function(panel)
                panel:ClearControls()

                panel:Help(
                    "Metrostroi Expanded damage settings. "
                    .. "These options are server-wide."
                )

                local damageCheck = vgui.Create("DCheckBoxLabel", panel)
                damageCheck:SetText("Enable damage")
                damageCheck:SetDark(true)
                damageCheck:SizeToContents()
                panel:AddItem(damageCheck)

                local deformationCheck =
                    vgui.Create("DCheckBoxLabel", panel)
                deformationCheck:SetText("Enable deformation")
                deformationCheck:SetDark(true)
                deformationCheck:SizeToContents()
                panel:AddItem(deformationCheck)

                panel:Help(
                    "Deformation can only be enabled while damage is enabled."
                )

                local updating = false
                local nextRefresh = 0

                local function RefreshSettings()
                    if not IsValid(damageCheck)
                        or not IsValid(deformationCheck)
                    then
                        return
                    end

                    local damageEnabled = MEXD.IsDamageEnabled()
                    local deformationEnabled =
                        MEXD.IsDeformationEnabled()
                    local canEdit =
                        IsValid(LocalPlayer())
                        and LocalPlayer():IsAdmin()

                    updating = true
                    damageCheck:SetChecked(damageEnabled)
                    deformationCheck:SetChecked(
                        damageEnabled and deformationEnabled
                    )
                    updating = false

                    damageCheck:SetEnabled(canEdit)
                    deformationCheck:SetEnabled(
                        canEdit and damageEnabled
                    )
                end

                damageCheck.OnChange = function(_, enabled)
                    if updating then return end
                    if not IsValid(LocalPlayer())
                        or not LocalPlayer():IsAdmin()
                    then
                        RefreshSettings()
                        return
                    end

                    RunConsoleCommand(
                        "mex_damage_set_enabled",
                        enabled and "1" or "0"
                    )

                    if not enabled then
                        updating = true
                        deformationCheck:SetChecked(false)
                        deformationCheck:SetEnabled(false)
                        updating = false
                    end
                end

                deformationCheck.OnChange = function(_, enabled)
                    if updating then return end

                    if not MEXD.IsDamageEnabled()
                        or not IsValid(LocalPlayer())
                        or not LocalPlayer():IsAdmin()
                    then
                        RefreshSettings()
                        return
                    end

                    RunConsoleCommand(
                        "mex_damage_set_deformation_enabled",
                        enabled and "1" or "0"
                    )
                end

                panel.Think = function()
                    if RealTime() < nextRefresh then return end
                    nextRefresh = RealTime() + 0.25
                    RefreshSettings()
                end

                RefreshSettings()
            end
        )
    end)

    ---------------------------------------------------------------------------
    -- v0.4 deformation model
    --
    -- No global RenderMultiply scaling is used here. A rail vehicle does not
    -- realistically turn into a uniformly scaled box during a collision.
    --
    -- Instead, every visible part uses one local deformation field:
    --   * existing MDL bones are displaced/rotated with BuildBonePositions,
    --   * localized rigid ClientEnts follow the deformed structure,
    --   * full-car interior shells stay at the train origin and deform only
    --     through their own bones,
    --   * ButtonMap panels are shallow-cloned per wagon and moved as rigid
    --     planes together with their generated button props.
    --
    -- This keeps the cab/salon attached to the carbody while retaining
    -- Metrostroi's original animation and interaction code.
    ---------------------------------------------------------------------------

    local STRUCTURAL_WORDS = {
        "body", "interior", "salon", "cabin", "cabine", "mask",
        "pult", "panel", "door", "window", "glass", "stekl",
        "seat", "couch", "handler", "handrail", "lamp", "headlight",
        "frame", "roof",
    }

    local CABIN_WORDS = {
        "cabin", "cabine", "cab_", "cab-", "pult", "panel",
        "controller", "brake_valve", "crane", "driver",
    }

    local GLASS_WORDS = {
        "glass", "window", "stekl",
    }

    -- Use Source's real nodraw material for broken embedded glazing.
    -- A custom white/alpha material can still show as an opaque white lens on
    -- some Metrostroi shaders, especially gauge/control glass.
    local MEX_INVISIBLE_GLASS_NAME = "tools/toolsnodraw"

    local function CopyVector(v)
        return Vector(v.x, v.y, v.z)
    end

    local function CopyAngle(a)
        return Angle(a.p, a.y, a.r)
    end

    local function Smooth01(x)
        x = math.Clamp(x, 0, 1)
        return x * x * (3 - 2 * x)
    end

    local function IsFiniteVector(v)
        return isvector(v)
            and v.x == v.x and v.y == v.y and v.z == v.z
            and math.abs(v.x) < 1000000
            and math.abs(v.y) < 1000000
            and math.abs(v.z) < 1000000
    end

    local function DefaultHitLocal(train, zone)
        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()
        local center = (mins + maxs) * 0.5

        if zone == "front" then
            return Vector(maxs.x, center.y, center.z)
        elseif zone == "rear" then
            return Vector(mins.x, center.y, center.z)
        elseif zone == "left" then
            return Vector(center.x, mins.y, center.z)
        elseif zone == "right" then
            return Vector(center.x, maxs.y, center.z)
        elseif zone == "roof" then
            return Vector(center.x, center.y, maxs.z)
        elseif zone == "floor" then
            return Vector(center.x, center.y, mins.z)
        end

        return center
    end

    local function ReadHitLocal(train, zone)
        if train:GetNW2Float("MEX.Damage.HitStrength." .. zone, 0) <= 0.001 then
            return DefaultHitLocal(train, zone)
        end

        return train:GetNW2Vector(
            "MEX.Damage.HitLocal." .. zone,
            DefaultHitLocal(train, zone)
        )
    end

    local function BuildDamageState(train)
        if not train:GetNW2Bool("MEX.DamageReady", false) then return nil end

        local front = train:GetNW2Float("MEX.Damage.front", 0)
        local rear = train:GetNW2Float("MEX.Damage.rear", 0)
        local left = train:GetNW2Float("MEX.Damage.left", 0)
        local right = train:GetNW2Float("MEX.Damage.right", 0)
        local roof = train:GetNW2Float("MEX.Damage.roof", 0)
        local floor = train:GetNW2Float("MEX.Damage.floor", 0)

        local crushFront = train:GetNW2Float("MEX.Crush.front", front)
        local crushRear = train:GetNW2Float("MEX.Crush.rear", rear)
        local crushLeft = train:GetNW2Float("MEX.Crush.left", left)
        local crushRight = train:GetNW2Float("MEX.Crush.right", right)
        local crushRoof = train:GetNW2Float("MEX.Crush.roof", roof)
        local crushFloor = train:GetNW2Float("MEX.Crush.floor", floor)

        local blastStrength =
            train:GetNW2Float("MEX.Damage.BlastStrength", 0)
        local overall = math.max(
            front,
            rear,
            left,
            right,
            roof,
            floor,
            math.min(blastStrength, 1)
        )

        if overall <= 0.001 then return nil end

        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()
        local center = (mins + maxs) * 0.5

        return {
            front = front,
            rear = rear,
            left = left,
            right = right,
            roof = roof,
            floor = floor,
            overall = overall,
            crush = {
                front = crushFront,
                rear = crushRear,
                left = crushLeft,
                right = crushRight,
                roof = crushRoof,
                floor = crushFloor,
                overall = math.max(
                    crushFront,
                    crushRear,
                    crushLeft,
                    crushRight,
                    crushRoof,
                    crushFloor
                ),
            },
            blast = {
                strength = blastStrength,
                radius = train:GetNW2Float(
                    "MEX.Damage.BlastRadius",
                    0
                ),
                localPos = train:GetNW2Vector(
                    "MEX.Damage.BlastLocal",
                    center
                ),
                impulse = train:GetNW2Vector(
                    "MEX.Damage.BlastImpulseLocal",
                    vector_origin
                ),
            },
            mins = mins,
            maxs = maxs,
            center = center,
            halfLength = math.max((maxs.x - mins.x) * 0.5, 1),
            halfWidth = math.max((maxs.y - mins.y) * 0.5, 1),
            halfHeight = math.max((maxs.z - mins.z) * 0.5, 1),
            hits = {
                front = ReadHitLocal(train, "front"),
                rear = ReadHitLocal(train, "rear"),
                left = ReadHitLocal(train, "left"),
                right = ReadHitLocal(train, "right"),
                roof = ReadHitLocal(train, "roof"),
                floor = ReadHitLocal(train, "floor"),
            },
        }
    end

    ---------------------------------------------------------------------------
    -- Continuous local-space deformation field
    ---------------------------------------------------------------------------

    local function AddEndCrush(offset, localPos, state, zone, damage, inwardSign)
        if damage <= 0.001 then return end

        local hit = state.hits[zone]
        local surfaceX = zone == "front" and state.maxs.x or state.mins.x
        local depth = zone == "front"
            and (surfaceX - localPos.x)
            or (localPos.x - surfaceX)

        -- A light crash mainly damages the end structure. Only heavy damage
        -- reaches deep into the cab/saloon survival space.
        local survivalIntrusion = math.max(damage - 0.48, 0) / 0.52
        local reach = 92 + damage * 104 + survivalIntrusion * 128

        if depth < -8 or depth > reach then return end

        local axial = Smooth01(1 - math.Clamp(depth / reach, 0, 1))

        local radiusY = 34 + damage * 38 + survivalIntrusion * 24
        local radiusZ = 38 + damage * 38 + survivalIntrusion * 22
        local dy = (localPos.y - hit.y) / radiusY
        local dz = (localPos.z - hit.z) / radiusZ
        local radial = Smooth01(1 - math.Clamp(dy * dy + dz * dz, 0, 1))

        -- The strong underframe/longitudinal structure does not fold as easily
        -- as thin cab/interior sheetwork.
        local z01 = math.Clamp(
            (localPos.z - state.mins.z) / math.max(state.maxs.z - state.mins.z, 1),
            0,
            1
        )
        local frameFactor = Lerp(Smooth01(math.Clamp(z01 * 2.2, 0, 1)), 0.48, 1.0)

        local influence = axial * radial
        if influence <= 0.0001 then return end

        local primaryCrush = 7 + damage * 39
        local deepIntrusion = survivalIntrusion * 56
        local crush = (primaryCrush + deepIntrusion) * influence * frameFactor

        offset.x = offset.x + inwardSign * crush

        -- Draw nearby structure towards the contact point. This gives the end
        -- a crease/bowl instead of translating a flat rectangle.
        offset.y = offset.y + (hit.y - localPos.y)
            * (0.055 + damage * 0.08) * influence
        offset.z = offset.z + (hit.z - localPos.z)
            * (0.040 + damage * 0.055) * influence

        -- Real carbody collapse develops folds/crippling near the boundary
        -- between the crushed end and the still-stiff survival structure.
        -- Reproduce that with an inward shell buckle instead of stretching the
        -- whole wagon. This only becomes pronounced after a substantial hit.
        if damage >= 0.34 then
            local creaseCenter = reach * (0.34 + damage * 0.18)
            local creaseWidth = math.max(reach * 0.16, 12)
            local crease =
                math.exp(
                    -((depth - creaseCenter) / creaseWidth)
                    * ((depth - creaseCenter) / creaseWidth)
                )
                * radial
                * math.Clamp((damage - 0.30) / 0.70, 0, 1)

            local yNorm = math.Clamp(
                (localPos.y - state.center.y) / state.halfWidth,
                -1,
                1
            )
            local zNorm = math.Clamp(
                (localPos.z - state.center.z) / state.halfHeight,
                -1,
                1
            )

            -- Side posts and roof/floor edges bow into the occupied volume as
            -- the end frame loses column stability.
            offset.y = offset.y
                - yNorm * crease * (4 + damage * 10)
            offset.z = offset.z
                - zNorm * crease * (3 + damage * 8)

            -- A small alternating longitudinal ripple approximates sheet-metal
            -- folding where multiple deformation bones are available.
            local ripple = math.sin(
                math.Clamp(depth / math.max(reach, 1), 0, 1)
                * math.pi * 3
            )

            offset.x = offset.x
                + inwardSign
                    * ripple
                    * crease
                    * damage
                    * 4.5
        end

        -- Severe off-centre impacts also bend the occupied structure slightly.
        if survivalIntrusion > 0 then
            local offY = math.Clamp(
                (hit.y - state.center.y) / state.halfWidth,
                -1,
                1
            )
            local offZ = math.Clamp(
                (hit.z - state.center.z) / state.halfHeight,
                -1,
                1
            )
            local deep = Smooth01(1 - math.Clamp(depth / math.max(reach, 1), 0, 1))

            offset.y = offset.y + inwardSign * offY
                * survivalIntrusion * deep * 8
            offset.z = offset.z + inwardSign * offZ
                * survivalIntrusion * deep * 5
        end
    end

    local function AddSideIntrusion(offset, localPos, state, zone, damage, inwardSign)
        if damage <= 0.001 then return end

        local hit = state.hits[zone]
        local surfaceY = zone == "right" and state.maxs.y or state.mins.y
        local depth = zone == "right"
            and (surfaceY - localPos.y)
            or (localPos.y - surfaceY)

        local severe = math.max(damage - 0.52, 0) / 0.48
        local reach = 52 + damage * 62 + severe * 76
        if depth < -7 or depth > reach then return end

        local inward = Smooth01(1 - math.Clamp(depth / reach, 0, 1))
        local radiusX = 55 + damage * 75 + severe * 55
        local radiusZ = 36 + damage * 40 + severe * 34

        local dx = (localPos.x - hit.x) / radiusX
        local dz = (localPos.z - hit.z) / radiusZ
        local radial = Smooth01(1 - math.Clamp(dx * dx + dz * dz, 0, 1))
        local influence = inward * radial
        if influence <= 0.0001 then return end

        local intrusion = (5 + damage * 30 + severe * 35) * influence
        offset.y = offset.y + inwardSign * intrusion

        offset.x = offset.x + (hit.x - localPos.x)
            * (0.035 + damage * 0.055) * influence
        offset.z = offset.z + (hit.z - localPos.z)
            * (0.030 + damage * 0.040) * influence

        if damage >= 0.38 then
            local crease =
                math.exp(
                    -((depth - reach * 0.42) / math.max(reach * 0.19, 10))
                    ^ 2
                )
                * radial
                * math.Clamp((damage - 0.34) / 0.66, 0, 1)

            local xNorm = math.Clamp(
                (localPos.x - hit.x) / math.max(radiusX, 1),
                -1,
                1
            )
            local zNorm = math.Clamp(
                (localPos.z - state.center.z) / state.halfHeight,
                -1,
                1
            )

            offset.x = offset.x - xNorm * crease * (4 + damage * 8)
            offset.z = offset.z - zNorm * crease * (3 + damage * 7)
        end
    end

    local function AddVerticalIntrusion(offset, localPos, state, zone, damage, inwardSign)
        if damage <= 0.001 then return end

        local hit = state.hits[zone]
        local surfaceZ = zone == "roof" and state.maxs.z or state.mins.z
        local depth = zone == "roof"
            and (surfaceZ - localPos.z)
            or (localPos.z - surfaceZ)

        local severe = math.max(damage - 0.55, 0) / 0.45
        local reach = 40 + damage * 52 + severe * 62
        if depth < -7 or depth > reach then return end

        local inward = Smooth01(1 - math.Clamp(depth / reach, 0, 1))
        local radiusX = 62 + damage * 80
        local radiusY = 34 + damage * 42

        local dx = (localPos.x - hit.x) / radiusX
        local dy = (localPos.y - hit.y) / radiusY
        local radial = Smooth01(1 - math.Clamp(dx * dx + dy * dy, 0, 1))
        local influence = inward * radial
        if influence <= 0.0001 then return end

        local intrusion = (4 + damage * 23 + severe * 27) * influence
        offset.z = offset.z + inwardSign * intrusion
        offset.x = offset.x + (hit.x - localPos.x)
            * (0.025 + damage * 0.04) * influence
        offset.y = offset.y + (hit.y - localPos.y)
            * (0.025 + damage * 0.04) * influence
    end

    local function AddBlastDeformation(offset, localPos, state)
        local blast = state and state.blast
        if not istable(blast) or (blast.strength or 0) <= 0.001 then return end
        if not isvector(blast.localPos) then return end

        local radius = math.max(blast.radius or 0, 1)
        local delta = localPos - blast.localPos
        local distance = delta:Length()

        if distance > radius then return end

        local falloff = Smooth01(
            1 - math.Clamp(distance / radius, 0, 1)
        )
        if falloff <= 0.0001 then return end

        local dir = blast.impulse
        if not isvector(dir) or dir:LengthSqr() < 0.001 then
            dir = delta
        end

        if dir:LengthSqr() < 0.001 then return end
        dir = dir:GetNormalized()

        -- Blast loading is very local: nearby sheet/panel structure is kicked
        -- in the pressure-wave direction, then rapidly decays with distance.
        local strength = math.Clamp(blast.strength or 0, 0, 1.25)
        local push = (3 + strength * 18) * falloff

        offset:Add(dir * push)

        -- Thin sheet-metal wrinkling around the blast footprint. The ripple is
        -- deliberately small compared with the primary impulse and only shows
        -- where the MDL has enough weighted bones/independent ClientEnts.
        local radialDir = delta
        if radialDir:LengthSqr() > 0.001 then
            radialDir:Normalize()
            local wrinkle = math.sin(distance * 0.11)
                * falloff
                * strength
                * 2.8
            offset:Add(radialDir * wrinkle)
        end
    end

    local function DeformLocalPoint(localPos, state)
        if not state then return CopyVector(localPos) end

        local offset = Vector(0, 0, 0)

        -- Positive X is the front on current Metrostroi subway bodies.
        AddEndCrush(offset, localPos, state, "front", state.front, -1)
        AddEndCrush(offset, localPos, state, "rear", state.rear, 1)

        -- Positive Y = right side, negative Y = left side.
        AddSideIntrusion(offset, localPos, state, "right", state.right, -1)
        AddSideIntrusion(offset, localPos, state, "left", state.left, 1)

        -- Roof impact goes down; floor/underframe impact goes up.
        AddVerticalIntrusion(offset, localPos, state, "roof", state.roof, -1)
        AddVerticalIntrusion(offset, localPos, state, "floor", state.floor, 1)

        AddBlastDeformation(offset, localPos, state)

        return localPos + offset
    end

    local function DeformLocalAngle(localPos, localAng, state)
        if not state then return CopyAngle(localAng) end

        local step = 5
        local p0 = DeformLocalPoint(localPos, state)
        local pf = DeformLocalPoint(localPos + localAng:Forward() * step, state)
        local pu = DeformLocalPoint(localPos + localAng:Up() * step, state)

        local forward = pf - p0
        local up = pu - p0

        if forward:LengthSqr() < 0.001 or up:LengthSqr() < 0.001 then
            return CopyAngle(localAng)
        end

        forward:Normalize()
        up:Normalize()

        local side = forward:Cross(up)
        if side:LengthSqr() < 0.001 then
            return CopyAngle(localAng)
        end

        side:Normalize()
        up = side:Cross(forward)
        up:Normalize()

        return forward:AngleEx(up)
    end

    local function DeformLocalPointStrength(localPos, state, strength)
        strength = tonumber(strength) or 1

        if not state or math.abs(strength - 1) < 0.001 then
            return DeformLocalPoint(localPos, state)
        end

        local base = DeformLocalPoint(localPos, state)
        return localPos + (base - localPos) * strength
    end

    local function DeformLocalAngleStrength(
        localPos,
        localAng,
        state,
        strength
    )
        strength = tonumber(strength) or 1

        if not state or math.abs(strength - 1) < 0.001 then
            return DeformLocalAngle(localPos, localAng, state)
        end

        local step = 5
        local p0 = DeformLocalPointStrength(
            localPos,
            state,
            strength
        )
        local pf = DeformLocalPointStrength(
            localPos + localAng:Forward() * step,
            state,
            strength
        )
        local pu = DeformLocalPointStrength(
            localPos + localAng:Up() * step,
            state,
            strength
        )

        local forward = pf - p0
        local up = pu - p0

        if forward:LengthSqr() < 0.001 or up:LengthSqr() < 0.001 then
            return CopyAngle(localAng)
        end

        forward:Normalize()
        up:Normalize()

        local side = forward:Cross(up)
        if side:LengthSqr() < 0.001 then
            return CopyAngle(localAng)
        end

        side:Normalize()
        up = side:Cross(forward)
        up:Normalize()

        return forward:AngleEx(up)
    end

    -- Exact front visual deformation used by the generated main-body
    -- crumple mesh. Mounted ClientEnts/panels/lights must sample this same
    -- field or they appear to float in front of / behind the crushed shell.
    local function DeformFrontVisualPointStrength(localPos, state, strength)
        strength = tonumber(strength) or 1

        local deformed = DeformLocalPointStrength(
            localPos,
            state,
            strength
        )

        if not state then return deformed end

        local logicalDamage = math.Clamp(state.front or 0, 0, 1)

        local frontCrushEnergy = math.Clamp(
            math.max(
                logicalDamage,
                istable(state.crush)
                    and (state.crush.front or 0)
                    or logicalDamage
            ),
            0,
            6
        )

        local overallCrushEnergy = math.Clamp(
            math.max(
                frontCrushEnergy,
                istable(state.crush)
                    and (state.crush.overall or 0)
                    or 0
            ),
            0,
            6
        )

        if overallCrushEnergy <= 0.001 then return deformed end

        local overcrush = math.max(frontCrushEnergy - 1, 0)
        local scrapOvercrush = math.max(overallCrushEnergy - 1, 0)
        local severe = Smooth01(
            math.Clamp((logicalDamage - 0.42) / 0.58, 0, 1)
        )
        local scrap = Smooth01(
            math.Clamp(scrapOvercrush / 3.2, 0, 1)
        )

        local hit = state.hits.front
        local depth = state.maxs.x - localPos.x

        -- Local dent/crumple remains front-specific for now. The global scrap
        -- phase below may still collapse the whole wagon after extreme damage
        -- from any direction.
        if frontCrushEnergy > 0.001 then

        -- At ordinary damage only the nose/cab is involved. Once crush energy
        -- exceeds 1, every later impact pushes the fold boundary farther into
        -- the wagon. Around crush ~= 4 the field spans essentially the entire
        -- carbody.
        local reach =
            96
            + logicalDamage * 205
            + severe * 125
            + overcrush * 235

        if depth >= -12 and depth <= reach then
            local axial = Smooth01(
                1 - math.Clamp(depth / math.max(reach, 1), 0, 1)
            )

            local radiusY =
                82
                + logicalDamage * 72
                + severe * 32
                + overcrush * 28
            local radiusZ =
                86
                + logicalDamage * 76
                + severe * 34
                + overcrush * 32

            local dy = (localPos.y - hit.y) / math.max(radiusY, 1)
            local dz = (localPos.z - hit.z) / math.max(radiusZ, 1)
            local radial = Smooth01(
                1 - math.Clamp(dy * dy + dz * dz, 0, 1)
            )

            -- When the shell is already being scrapped, do not let a single
            -- old impact point protect the opposite corners from collapse.
            radial = math.max(radial, scrap * 0.72)

            local influence = axial * radial

            if influence > 0.0001 then
                local visualStrength = math.Clamp(strength, 0, 1.8)
                local crush =
                    (
                        6
                        + logicalDamage * 82
                        + severe * 52
                        + overcrush * 128
                    )
                    * influence
                    * visualStrength

                deformed.x = deformed.x - crush

                deformed.y = deformed.y
                    + (hit.y - localPos.y)
                        * (
                            0.070
                            + logicalDamage * 0.075
                            + overcrush * 0.018
                        )
                        * influence
                        * visualStrength

                deformed.z = deformed.z
                    + (hit.z - localPos.z)
                        * (
                            0.060
                            + logicalDamage * 0.060
                            + overcrush * 0.014
                        )
                        * influence
                        * visualStrength

                local foldGate = math.Clamp(
                    (frontCrushEnergy - 0.14) / 0.86,
                    0,
                    1
                )

                if foldGate > 0 then
                    local depth01 = math.Clamp(
                        depth / math.max(reach, 1),
                        0,
                        1
                    )
                    local crease = math.exp(
                        -((depth01
                            - (0.32 + logicalDamage * 0.10))
                            / (0.12 + logicalDamage * 0.05)) ^ 2
                    ) * radial * Smooth01(foldGate)

                    local yEdge = math.Clamp(
                        (localPos.y - state.center.y)
                            / math.max(state.halfWidth, 1),
                        -1,
                        1
                    )
                    local zEdge = math.Clamp(
                        (localPos.z - state.center.z)
                            / math.max(state.halfHeight, 1),
                        -1,
                        1
                    )
                    local wave = math.sin(
                        depth01
                        * math.pi
                        * (4.0 + math.min(overcrush, 3) * 1.2)
                    )

                    deformed.x = deformed.x
                        - math.abs(wave)
                            * crease
                            * (2 + logicalDamage * 7 + overcrush * 13)
                            * visualStrength

                    deformed.y = deformed.y
                        - yEdge
                            * crease
                            * (2 + logicalDamage * 7 + overcrush * 9)
                            * visualStrength

                    deformed.z = deformed.z
                        - zEdge
                            * crease
                            * (1.5 + logicalDamage * 5 + overcrush * 7)
                            * visualStrength
                end
            end
        end

        end

        -- Extreme destruction mode: once the shell is already critically damaged,
        -- additional impacts progressively accordion-compress the entire
        -- wagon toward the rear and squash the occupied volume. This is the
        -- "turn it into scrap / a pancake" phase rather than a realistic
        -- survivable crash limit.
        if scrap > 0.001 then
            local length = math.max(state.maxs.x - state.mins.x, 1)
            local width = math.max(state.maxs.y - state.mins.y, 1)
            local height = math.max(state.maxs.z - state.mins.z, 1)

            local x01 = math.Clamp(
                (localPos.x - state.mins.x) / length,
                0,
                1
            )
            local y01 = math.Clamp(
                (localPos.y - state.center.y) / (width * 0.5),
                -1,
                1
            )
            local z01 = math.Clamp(
                (localPos.z - state.mins.z) / height,
                0,
                1
            )

            -- Rear end is the "anvil"; everything ahead of it shortens.
            local compressedLength = length * Lerp(scrap, 1.0, 0.16)
            local targetX =
                state.mins.x + x01 * compressedLength

            -- Keep a thin underframe/slab rather than collapsing all vertices
            -- to exactly one Z plane (which would z-fight badly).
            local slabBase = state.mins.z + height * 0.08
            local slabHeight = height * Lerp(scrap, 1.0, 0.17)
            local targetZ = slabBase + z01 * slabHeight

            local targetY =
                state.center.y
                + y01
                    * (width * 0.5)
                    * Lerp(scrap, 1.0, 0.42)

            local accordion =
                math.sin(x01 * math.pi * (8 + scrapOvercrush * 2.5))
                * (4 + scrapOvercrush * 7)
                * scrap
                * (0.35 + 0.65 * math.abs(y01))

            targetX = targetX - math.abs(accordion)
            targetZ = targetZ + accordion * 0.18

            deformed.x = Lerp(scrap, deformed.x, targetX)
            deformed.y = Lerp(scrap, deformed.y, targetY)
            deformed.z = Lerp(scrap, deformed.z, targetZ)
        end

        return deformed
    end

    local function DeformFrontVisualAngleStrength(
        localPos,
        localAng,
        state,
        strength
    )
        if not state then return CopyAngle(localAng) end

        local step = 5
        local p0 = DeformFrontVisualPointStrength(
            localPos,
            state,
            strength
        )
        local pf = DeformFrontVisualPointStrength(
            localPos + localAng:Forward() * step,
            state,
            strength
        )
        local pu = DeformFrontVisualPointStrength(
            localPos + localAng:Up() * step,
            state,
            strength
        )

        local forward = pf - p0
        local up = pu - p0

        if forward:LengthSqr() < 0.001 or up:LengthSqr() < 0.001 then
            return CopyAngle(localAng)
        end

        forward:Normalize()
        up:Normalize()

        local side = forward:Cross(up)
        if side:LengthSqr() < 0.001 then
            return CopyAngle(localAng)
        end

        side:Normalize()
        up = side:Cross(forward)
        up:Normalize()

        return forward:AngleEx(up)
    end

    local function DeformMountedPointStrength(
        train,
        localPos,
        state,
        strength
    )
        if IsValid(train) and train.MEXDamageMeshOverrideInstalled then
            return DeformFrontVisualPointStrength(
                localPos,
                state,
                strength
            )
        end

        return DeformLocalPointStrength(localPos, state, strength)
    end

    local function DeformMountedAngleStrength(
        train,
        localPos,
        localAng,
        state,
        strength
    )
        if IsValid(train) and train.MEXDamageMeshOverrideInstalled then
            return DeformFrontVisualAngleStrength(
                localPos,
                localAng,
                state,
                strength
            )
        end

        return DeformLocalAngleStrength(
            localPos,
            localAng,
            state,
            strength
        )
    end

    local function CabStrengthAtPoint(localPos, state)
        if not state then return 1 end

        local endness = math.Clamp(
            math.abs(localPos.x - state.center.x)
                / math.max(state.halfLength, 1),
            0,
            1
        )

        if endness < 0.45 then return 1 end

        local endDamage =
            localPos.x >= state.center.x and state.front or state.rear

        return 1 + Smooth01((endness - 0.45) / 0.55)
            * math.Clamp(endDamage, 0, 1)
            * 0.35
    end

    local function LocalDisplacement(localPos, state)
        return DeformLocalPoint(localPos, state) - localPos
    end

    ---------------------------------------------------------------------------
    -- Legacy cleanup
    ---------------------------------------------------------------------------

    local function RecoverLegacyButtonMap(train)
        if not IsValid(train) then return end

        if train.MEXDamageButtonMapOriginal then
            train.ButtonMap = train.MEXDamageButtonMapOriginal
            train.MEXDamageButtonMapOriginal = nil
        elseif train.MEXDamagePrivateButtonMap then
            local stored = scripted_ents.GetStored(train:GetClass())
            local original = stored and stored.t and stored.t.ButtonMap
            if istable(original) then
                train.ButtonMap = original
            end
        end

        train.MEXDamagePrivateButtonMap = nil
    end

    local function ClearLegacyTransforms(train)
        if not IsValid(train) then return end
        if train.MEXDamageV4LegacyCleared then return end
        train.MEXDamageV4LegacyCleared = true

        -- v0.1-v0.3 used RenderMultiply on the whole car. Never allow that
        -- transform to survive into the bone-based system.
        train:DisableMatrix("RenderMultiply")
        train.MEXDamageMatrixApplied = nil

        RecoverLegacyButtonMap(train)

        if istable(train.ClientEnts) then
            for _, prop in pairs(train.ClientEnts) do
                if not IsValid(prop) then continue end

                prop:DisableMatrix("RenderMultiply")
                prop:SetRenderOrigin(nil)
                prop:SetRenderAngles(nil)
                prop.MEXDamageMatrixApplied = nil
                prop.MEXDamageRenderOrigin = nil
                prop.MEXDamageRenderAngles = nil
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Per-wagon ButtonMap clone
    --
    -- This is intentionally SHALLOW. Nested buttons/config tables stay the
    -- original Metrostroi objects. The old deep copy in v0.3 could disconnect
    -- generated controls from Metrostroi's runtime state.
    ---------------------------------------------------------------------------

    local function CloneInteractivePanels(train)
        if not istable(train.ButtonMap) then return false end
        if train.MEXDamageV4ButtonMapOriginal then return true end

        RecoverLegacyButtonMap(train)

        local original = train.ButtonMap
        local clone = {}

        for key, panel in pairs(original) do
            if key ~= "BaseClass" and istable(panel) and isvector(panel.pos) then
                local p = {}
                for k, v in pairs(panel) do
                    p[k] = v
                end

                -- IMPORTANT: the panel object may be shallow-copied, but its
                -- buttons CONTAINER must be private. Keeping the same table
                -- here meant that replacing one damaged button also replaced
                -- the supposed "original" Metrostroi definition, making
                -- restore/reconciliation impossible for every generated
                -- control.
                if istable(panel.buttons) then
                    local privateButtons = {}
                    for buttonKey, button in pairs(panel.buttons) do
                        privateButtons[buttonKey] = button
                    end
                    p.buttons = privateButtons
                    p.MEXDamageButtonsPrivate = true
                end

                p.MEXDamageBasePos = CopyVector(panel.pos)
                p.MEXDamageBaseAng = isangle(panel.ang)
                    and CopyAngle(panel.ang)
                    or Angle(0, 0, 0)
                p.MEXDamageBaseScale = panel.scale
                clone[key] = p
            else
                clone[key] = panel
            end
        end

        train.MEXDamageV4ButtonMapOriginal = original
        train.ButtonMap = clone
        train.MEXDamageV4PanelProps = nil
        return true
    end

    local function RestoreInteractivePanels(train)
        if not IsValid(train) then return end

        if train.MEXDamageV4ButtonMapOriginal then
            train.ButtonMap = train.MEXDamageV4ButtonMapOriginal
            train.MEXDamageV4ButtonMapOriginal = nil
        end

        train.MEXDamageV4PanelProps = nil
    end

    local function GetButtonPhysicalPropName(train, button)
        if not istable(button) then return nil end

        local function existingClientEnt(name)
            return isstring(name)
                and name ~= ""
                and istable(train and train.ClientEnts)
                and IsValid(train.ClientEnts[name])
        end

        local function visibleClientEnt(name)
            if not existingClientEnt(name) then return false end

            local ent = train.ClientEnts[name]
            return not ent:GetNoDraw() and ent:GetColor().a > 5
        end

        local function firstExisting(names)
            -- Prefer the currently displayed variant (important for 334/013
            -- cabs where EPK/EPV use alternate physical shut-off valves).
            for _, name in ipairs(names or {}) do
                if visibleClientEnt(name) then return name end
            end

            for _, name in ipairs(names or {}) do
                if existingClientEnt(name) then return name end
            end

            return nil
        end

        if existingClientEnt(button.PropName) then
            return button.PropName
        end

        local model = button.model

        -- A number of classic Metrostroi cab valves use model.var only for the
        -- logical state while model.sndid is the name of the actual moving
        -- ClientProp. Treat that real valve as the physical provider.
        if istable(model) and existingClientEnt(model.sndid) then
            return model.sndid
        end

        -- Explicit aliases for old 81-717/714-style pneumatic hardware. These
        -- keep the physical valve and its ButtonMap hitbox inseparable even on
        -- trains whose ButtonMap does not expose PropName/model.name.
        local buttonID = isstring(button.ID)
            and button.ID:gsub("^.+:", "")
            or ""

        local knownPhysical = {
            DriverValveBLDisconnectToggle = {"brake_disconnect"},
            DriverValveTLDisconnectToggle = {"train_disconnect"},
            DriverValveDisconnectToggle = {"valve_disconnect"},
            EPKToggle = {"EPK_disconnect", "EPV_disconnect"},
            ParkingBrakeToggle = {"parking_brake"},
            EmergencyBrakeValveToggle = {"stopkran"},
        }

        local known = firstExisting(knownPhysical[buttonID])
        if known then return known end

        if istable(model) then
            if existingClientEnt(model.name) then
                return model.name
            end

            if istable(model.lamp)
                and existingClientEnt(model.lamp.name)
            then
                return model.lamp.name
            end
        end

        -- Generated Metrostroi button props default to button.ID.
        if existingClientEnt(button.ID) then
            return button.ID
        end

        -- Legacy manual doors/mechanisms often have no generated model at all:
        -- the ButtonMap event is FrontDoor but model.var animates door1.
        if istable(model) and existingClientEnt(model.var) then
            return model.var
        end

        -- Fallback for pre-generation mapping. It is only used as an identity
        -- hint; exact physical binding still requires the ClientEnt later.
        if isstring(button.PropName) and button.PropName ~= "" then
            return button.PropName
        end

        if istable(model) then
            if isstring(model.sndid) and model.sndid ~= "" then
                return model.sndid
            end

            if isstring(model.name) and model.name ~= "" then
                return model.name
            end

            if istable(model.lamp)
                and isstring(model.lamp.name)
                and model.lamp.name ~= ""
            then
                return model.lamp.name
            end

            if isstring(button.ID) and button.ID ~= "" then
                return button.ID
            end
        end

        return nil
    end


    local function BuildPanelPropMap(train)
        local map = {}

        if not istable(train.ButtonMap) then
            train.MEXDamageV4PanelProps = map
            return map
        end

        for panelName, panel in pairs(train.ButtonMap) do
            if panelName == "BaseClass" or not istable(panel) then continue end

            if istable(panel.props) then
                for _, propName in pairs(panel.props) do
                    if isstring(propName) then
                        map[propName] = panelName
                    end
                end
            end

            if istable(panel.buttons) then
                for _, button in pairs(panel.buttons) do
                    if not istable(button) then continue end

                    if isstring(button.PropName) then
                        map[button.PropName] = panelName
                    end

                    -- Resolve the physical provider locally in this early
                    -- mapping path. Direct-impact processing may build the
                    -- panel map before later attachment helpers are ready.
                    local config = button.model
                    local physicalProp = nil

                    if isstring(button.PropName)
                        and button.PropName ~= ""
                    then
                        physicalProp = button.PropName
                    elseif istable(config) then
                        if isstring(config.sndid)
                            and config.sndid ~= ""
                        then
                            physicalProp = config.sndid
                        elseif isstring(config.name)
                            and config.name ~= ""
                        then
                            physicalProp = config.name
                        elseif isstring(config.var)
                            and config.var ~= ""
                            and istable(train.ClientEnts)
                            and IsValid(train.ClientEnts[config.var])
                        then
                            physicalProp = config.var
                        end
                    end

                    if not physicalProp and isstring(button.ID) then
                        local buttonID = button.ID:gsub("^.+:", "")
                        local knownPhysical = {
                            DriverValveBLDisconnectToggle = "brake_disconnect",
                            DriverValveTLDisconnectToggle = "train_disconnect",
                            DriverValveDisconnectToggle = "valve_disconnect",
                            EPKToggle = "EPK_disconnect",
                            ParkingBrakeToggle = "parking_brake",
                            EmergencyBrakeValveToggle = "stopkran",
                        }

                        local candidate = knownPhysical[buttonID]
                        if isstring(candidate) then
                            physicalProp = candidate
                        end
                    end

                    if isstring(physicalProp) and physicalProp ~= "" then
                        map[physicalProp] = panelName
                    end

                    if istable(config) then
                        local generatedName = config.name or button.ID
                        if isstring(generatedName) then
                            map[generatedName] = panelName
                        end

                        -- Old manual doors and a few other mechanisms have a
                        -- logical ButtonMap ID (FrontDoor, RearDoor...) but
                        -- animate a separately-authored ClientEnt through
                        -- model.var (door1, door2...). If that ClientEnt
                        -- exists, treat it as the physical provider.
                        if isstring(config.var)
                            and istable(train.ClientEnts)
                            and IsValid(train.ClientEnts[config.var])
                        then
                            map[config.var] = panelName
                        end

                        if istable(config.lamp) then
                            local lampName = config.lamp.name
                            if isstring(lampName) then
                                map[lampName] = panelName
                            end
                        end
                    end
                end
            end
        end

        train.MEXDamageV4PanelProps = map
        return map
    end

    local function ApplyPanelDeformation(train, state)
        if not state then
            RestoreInteractivePanels(train)
            return
        end

        if not CloneInteractivePanels(train) then return end

        for _, panel in pairs(train.ButtonMap) do
            if not istable(panel) or not panel.MEXDamageBasePos then continue end

            local strength = CabStrengthAtPoint(
                panel.MEXDamageBasePos,
                state
            )

            panel.pos = DeformMountedPointStrength(
                train,
                panel.MEXDamageBasePos,
                state,
                strength
            )
            panel.ang = DeformMountedAngleStrength(
                train,
                panel.MEXDamageBasePos,
                panel.MEXDamageBaseAng,
                state,
                strength
            )

            -- Keep the 2D coordinate system unchanged. It means the visual
            -- control and hit target remain exactly the same size.
            panel.scale = panel.MEXDamageBaseScale
        end
    end

    ---------------------------------------------------------------------------
    -- ClientEnt geometry cache / attachment logic
    ---------------------------------------------------------------------------

    local function ModelLooksStructural(name, model)
        local text = string.lower((name or "") .. " " .. (model or ""))

        for _, word in ipairs(STRUCTURAL_WORDS) do
            if string.find(text, word, 1, true) then
                return true
            end
        end

        return false
    end

    local function ModelMatchesWords(name, model, words)
        local text = string.lower((name or "") .. " " .. (model or ""))

        for _, word in ipairs(words) do
            if string.find(text, word, 1, true) then
                return true
            end
        end

        return false
    end

    local function ModelLooksCabin(name, model)
        return ModelMatchesWords(name, model, CABIN_WORDS)
    end

    local function ModelLooksGlass(name, model)
        local lowerModel = string.lower(model or "")

        for _, word in ipairs(GLASS_WORDS) do
            if string.find(lowerModel, word, 1, true) then
                return true
            end
        end

        local lowerName = string.lower(name or "")
        local excluded = {
            "washer", "cleaner", "wiper", "button", "switch",
            "toggle", "control",
        }

        for _, word in ipairs(excluded) do
            if string.find(lowerName, word, 1, true) then
                return false
            end
        end

        for _, word in ipairs(GLASS_WORDS) do
            if string.find(lowerName, word, 1, true) then
                return true
            end
        end

        return false
    end

    local function GetStaticClientPropTransform(train, name, prop)
        local def = istable(train.ClientProps) and train.ClientProps[name] or nil

        if istable(def) and isvector(def.pos) then
            local ang = isangle(def.ang) and def.ang or Angle(0, 0, 0)
            return CopyVector(def.pos), CopyAngle(ang)
        end

        if prop:GetParent() == train then
            return CopyVector(prop:GetLocalPos()), CopyAngle(prop:GetLocalAngles())
        end

        local localPos, localAng = WorldToLocal(
            prop:GetPos(),
            prop:GetAngles(),
            train:GetPos(),
            train:GetAngles()
        )

        return localPos, localAng
    end

    local function CacheClientProp(train, name, prop)
        train.MEXDamageV4PropCache = train.MEXDamageV4PropCache or {}

        local cached = train.MEXDamageV4PropCache[name]
        if cached and cached.entity == prop then
            return cached
        end

        prop:SetRenderOrigin(nil)
        prop:SetRenderAngles(nil)
        prop:DisableMatrix("RenderMultiply")

        local basePos, baseAng = GetStaticClientPropTransform(train, name, prop)
        local mins = prop:OBBMins()
        local maxs = prop:OBBMaxs()
        local obbCenter = (mins + maxs) * 0.5
        local size = maxs - mins

        -- Convert the model's actual visual center into train-local space.
        local anchorPos = LocalToWorld(
            obbCenter,
            Angle(0, 0, 0),
            basePos,
            baseAng
        )

        local model = prop:GetModel() or ""
        local spanX = math.abs(size.x)
        local spanY = math.abs(size.y)
        local spanZ = math.abs(size.z)

        cached = {
            entity = prop,
            basePos = basePos,
            baseAng = baseAng,
            obbCenter = obbCenter,
            anchorPos = anchorPos,
            size = size,
            model = model,
            structural = ModelLooksStructural(name, model),
            cabin = ModelLooksCabin(name, model),
            glass = ModelLooksGlass(name, model),

            -- A full saloon/interior shell must not be translated as one rigid
            -- object. Its ends should move only through its bones.
            fullLength = spanX >= 330,

            -- Small/localized pieces may follow one structural attachment point.
            localPiece = spanX < 330 and spanY < 230 and spanZ < 230,
        }

        train.MEXDamageV4PropCache[name] = cached
        return cached
    end

    local function OriginForAnchoredModel(anchorInModel, desiredAnchor, desiredAng)
        local rotated =
            desiredAng:Forward() * anchorInModel.x
            + desiredAng:Right() * anchorInModel.y
            + desiredAng:Up() * anchorInModel.z

        return desiredAnchor - rotated
    end

    local function ApplyLocalStructuralCrushMatrix(
        train,
        name,
        prop,
        cached,
        state
    )
        if not IsValid(prop)
            or not cached
            or not cached.structural
            or not cached.localPiece
            or not state
        then
            return
        end

        local text = string.lower(
            (name or "") .. " " .. (cached.model or "")
        )

        local excludedStructuralWords = {
            "door", "dver",
            "button", "switch", "tumbler", "toggle", "knob",
            "reverser", "controller", "handle", "lever",
            "valve", "kran", "wheel", "parking",
            "manualbrake", "brake",
            "panel", "pult", "lamp", "light",
        }

        for _, word in ipairs(excludedStructuralWords) do
            if string.find(text, word, 1, true) then
                return
            end
        end

        local structuralShell =
            cached.cabin
            or string.find(text, "mask", 1, true)
            or string.find(text, "body", 1, true)
            or string.find(text, "shell", 1, true)
            or string.find(text, "interior", 1, true)

        if not structuralShell then return end

        local size = cached.size
        local largest = math.max(
            math.abs(size.x),
            math.abs(size.y),
            math.abs(size.z)
        )

        if largest < 42 then return end

        local displacement =
            DeformMountedPointStrength(
                train,
                cached.anchorPos,
                state,
                cached.cabin
                    and math.max(
                        1.18,
                        CabStrengthAtPoint(cached.anchorPos, state)
                    )
                    or 1
            )
            - cached.anchorPos

        if displacement:LengthSqr() < 0.16 then
            prop:DisableMatrix("RenderMultiply")
            prop.MEXDamageMatrixApplied = nil
            return
        end

        local frontFallback = 0
        if (state.front or 0) > 0.001 then
            local depth = state.maxs.x - cached.anchorPos.x
            local reach = 72 + state.front * 175
            if depth >= -8 and depth <= reach then
                frontFallback =
                    Smooth01(
                        1 - math.Clamp(depth / math.max(reach, 1), 0, 1)
                    )
                    * math.Clamp(state.front, 0, 1)
            end
        end

        -- Local shell pieces are also our fallback on stock models that do not
        -- have enough weighted nose bones. Longitudinal compression is made
        -- noticeably stronger near the front while the transverse axes remain
        -- comparatively stiff.
        local sx = 1 - math.Clamp(
            math.abs(displacement.x)
                / math.max(math.abs(size.x), 28)
                * 0.50
                + frontFallback * 0.22,
            0,
            0.42
        )
        local sy = 1 - math.Clamp(
            math.abs(displacement.y)
                / math.max(math.abs(size.y), 28)
                * 0.34
                + frontFallback * 0.035,
            0,
            0.20
        )
        local sz = 1 - math.Clamp(
            math.abs(displacement.z)
                / math.max(math.abs(size.z), 28)
                * 0.30
                + frontFallback * 0.025,
            0,
            0.17
        )

        local matrix = Matrix()
        matrix:Translate(cached.obbCenter)
        matrix:Scale(Vector(sx, sy, sz))
        matrix:Translate(-cached.obbCenter)

        prop:EnableMatrix("RenderMultiply", matrix)
        prop.MEXDamageMatrixApplied = true
    end

    local function ApplyRigidAttachment(train, prop, cached, state)
        local strength = cached.cabin
            and math.max(1.18, CabStrengthAtPoint(cached.anchorPos, state))
            or 1

        local desiredAnchor = DeformMountedPointStrength(
            train,
            cached.anchorPos,
            state,
            strength
        )
        local desiredAng = DeformMountedAngleStrength(
            train,
            cached.anchorPos,
            cached.baseAng,
            state,
            strength
        )

        local desiredOrigin = OriginForAnchoredModel(
            cached.obbCenter,
            desiredAnchor,
            desiredAng
        )

        prop:SetRenderOrigin(train:LocalToWorld(desiredOrigin))
        prop:SetRenderAngles(train:LocalToWorldAngles(desiredAng))
        prop.MEXDamageV4RenderMoved = true
    end

    local function ApplyPanelAttachment(train, name, prop, cached, panelName)
        local panel = train.ButtonMap and train.ButtonMap[panelName]
        if not istable(panel) or not panel.MEXDamageBasePos then return false end

        -- Client props generated by Metrostroi are defined in train-local space.
        -- Express the prop relative to the original panel and replay the exact
        -- same rigid relationship on the deformed panel.
        local relPos, relAng = WorldToLocal(
            cached.basePos,
            cached.baseAng,
            panel.MEXDamageBasePos,
            panel.MEXDamageBaseAng
        )

        local newPos, newAng = LocalToWorld(
            relPos,
            relAng,
            panel.pos,
            panel.ang
        )

        prop:SetRenderOrigin(train:LocalToWorld(newPos))
        prop:SetRenderAngles(train:LocalToWorldAngles(newAng))
        prop.MEXDamageV4RenderMoved = true
        return true
    end

    local RestoreClientPropDamageMesh

    local function ClearClientPropRenderTransform(prop)
        if not IsValid(prop) then return end

        if prop.MEXDamageV4RenderMoved
            or prop.MEXDamageRenderOrigin
            or prop.MEXDamageRenderAngles
        then
            prop:SetRenderOrigin(nil)
            prop:SetRenderAngles(nil)
            prop.MEXDamageV4RenderMoved = nil
            prop.MEXDamageRenderOrigin = nil
            prop.MEXDamageRenderAngles = nil
        end

        if prop.MEXDamageMatrixApplied then
            prop:DisableMatrix("RenderMultiply")
            prop.MEXDamageMatrixApplied = nil
        end

        if RestoreClientPropDamageMesh then
            RestoreClientPropDamageMesh(prop)
        end
    end


    ---------------------------------------------------------------------------
    -- Breakaway components
    --
    -- Doors, controls and other mounted Metrostroi ClientEnt models may lose
    -- their mounting points under heavy local deformation. The original
    -- ClientEnt is hidden only after the server accepts the failure request;
    -- the server then creates a real networked physics debris entity.
    ---------------------------------------------------------------------------

    local DOOR_WORDS = {
        "door", "dver", "doors",
    }

    local CONTROL_WORDS = {
        "button", "switch", "tumbler", "toggle", "knob", "reverser",
        "controller", "handle", "lever", "valve", "kran", "wheel",
        "parking", "manualbrake", "manual_brake", "handbrake",
        "hand_brake", "brakewheel", "brake_wheel", "brake",
    }

    local BREAKAWAY_WORDS = {
        "lamp", "light", "headlight", "mirror", "sign", "cover", "cap",
        "window", "glass", "box", "case", "guard", "panel", "seat",
        "couch", "handrail",
        "handler", "wiper", "meter", "gauge", "indicator", "display",
        "wheel", "brake", "parking", "button", "switch", "tumbler",
        "toggle", "knob", "reverser", "controller", "handle", "lever",
        "valve", "kran", "door", "dver",
    }

    local function ContainsAnyWord(text, words)
        text = string.lower(text or "")
        for _, word in ipairs(words) do
            if string.find(text, word, 1, true) then
                return true
            end
        end
        return false
    end

    local ACCESSORY_WORDS = {
        "label", "sign", "plate", "plomb", "seal",
        "cap", "cover", "plug", "blank", "zaglush",
    }

    local function GeneratedAccessoryParent(name)
        if not isstring(name) then return nil end

        return name:match("^(.-)_pl$")
            or name:match("^(.-)_lamp%d*$")
            or name:match("^(.-)_label%d+$")
    end

    local function IsControlAccessory(name, cached)
        if GeneratedAccessoryParent(name) then return true end
        if not cached then return false end

        local text = string.lower(
            (name or "") .. " " .. (cached.model or "")
        )
        if not ContainsAnyWord(text, ACCESSORY_WORDS) then
            return false
        end

        local s = cached.size
        local largest = math.max(
            math.abs(s.x),
            math.abs(s.y),
            math.abs(s.z)
        )

        -- A generic cover/case can be a large structural panel. Only small
        -- nearby detail hardware is treated as a child of a control.
        return largest <= 30
    end

    local function StableFraction(text)
        local crc = tonumber(util.CRC(text or "")) or 0
        return (crc % 1000) / 1000
    end

    local function IsGlassComponent(name, cached)
        if cached.glass then return true end

        local text = string.lower(
            (name or "") .. " " .. (cached.model or "")
        )

        return ContainsAnyWord(text, GLASS_WORDS)
    end

    local function IsDoorComponent(name, cached)
        local text = (name or "") .. " " .. (cached.model or "")
        if not ContainsAnyWord(text, DOOR_WORDS) then return false end

        local model = string.lower(cached.model or "")
        if model == "" or model == "models/error.mdl" then return false end

        local s = cached.size
        local largest = math.max(math.abs(s.x), math.abs(s.y), math.abs(s.z))

        -- Ignore tiny handles/labels whose name merely contains "door".
        return largest >= 22
    end

    local function IsSmallControlComponent(name, cached, panelName)
        if IsControlAccessory(name, cached) then return false end

        local s = cached.size
        local largest = math.max(math.abs(s.x), math.abs(s.y), math.abs(s.z))

        local text =
            (name or "")
            .. " "
            .. (cached.model or "")
            .. " "
            .. (panelName or "")

        local namedControl = ContainsAnyWord(text, CONTROL_WORDS)

        -- Standalone driver's valves, disconnect cocks and controllers are
        -- often not generated from ButtonMap at all. Treat explicitly named
        -- control hardware as a control even without panelName.
        if namedControl then
            return largest <= 145
        end

        -- Tiny generated ButtonMap props are controls even when their file
        -- name does not literally contain "button".
        return panelName ~= nil and largest <= 28
    end

    local function IsGeneralBreakawayComponent(
        name,
        cached,
        panelName
    )
        if cached.fullLength then return false end

        if IsControlAccessory(name, cached) then
            return true
        end

        local s = cached.size
        local largest = math.max(math.abs(s.x), math.abs(s.y), math.abs(s.z))

        local text =
            (name or "")
            .. " "
            .. (cached.model or "")
            .. " "
            .. (panelName or "")

        local explicit = ContainsAnyWord(text, BREAKAWAY_WORDS)

        if explicit then
            return largest <= 220
        end

        return cached.localPiece and largest <= 85
    end

    local function ButtonCenterLocal(panel, button)
        if not istable(panel) or not istable(button) then return nil end
        if not isvector(panel.pos) or not isangle(panel.ang) then return nil end

        local x = tonumber(button.x) or 0
        local y = tonumber(button.y) or 0

        if not button.radius then
            x = x + (tonumber(button.w) or 0) * 0.5
            y = y + (tonumber(button.h) or 0) * 0.5
        end

        local pos = Vector(x, -y, 0)
        local ang = panel.MEXDamageBaseAng or panel.ang
        local basePos = panel.MEXDamageBasePos or panel.pos
        local scale = tonumber(panel.MEXDamageBaseScale)
            or tonumber(panel.scale)
            or 1

        pos:Rotate(ang)
        return basePos + pos * scale
    end

    local function GetNearbyButtonIDs(train, cached)
        local result = {}
        local candidates = {}

        if not cached or not isvector(cached.anchorPos)
            or not istable(train.ButtonMap)
        then
            return result
        end

        local s = cached.size
        local largest = math.max(
            math.abs(s.x),
            math.abs(s.y),
            math.abs(s.z)
        )

        local text = string.lower(
            (cached.model or "")
        )

        local valveLike =
            string.find(text, "valve", 1, true)
            or string.find(text, "cran", 1, true)
            or string.find(text, "kran", 1, true)
            or string.find(text, "/334", 1, true)
            or string.find(text, "/013", 1, true)

        local searchRadius = valveLike
            and math.Clamp(largest * 0.70, 28, 72)
            or math.Clamp(largest * 0.45, 10, 38)

        for panelName, panel in pairs(train.ButtonMap) do
            if panelName == "BaseClass"
                or not istable(panel)
                or not istable(panel.buttons)
            then
                continue
            end

            for _, button in pairs(panel.buttons) do
                if not istable(button) or not isstring(button.ID) then
                    continue
                end

                local buttonPos = ButtonCenterLocal(panel, button)
                if not isvector(buttonPos) then continue end

                local distance = cached.anchorPos:Distance(buttonPos)
                if distance > searchRadius then continue end

                candidates[#candidates + 1] = {
                    id = button.ID:gsub("^.+:", ""),
                    panelName = panelName,
                    distance = distance,
                }
            end
        end

        table.sort(candidates, function(a, b)
            return a.distance < b.distance
        end)

        if #candidates == 0 then return result end

        local best = candidates[1].distance
        local keepDistance = math.min(
            searchRadius,
            best + (valveLike and 18 or 8)
        )
        local seen = {}

        for _, candidate in ipairs(candidates) do
            if candidate.distance > keepDistance then break end
            if not seen[candidate.id] then
                seen[candidate.id] = true
                result[#result + 1] = candidate.id
            end
        end

        return result
    end

    local function ButtonMatchesPhysicalProp(train, button, propName)
        if not istable(button) or not isstring(propName) then
            return false
        end

        return GetButtonPhysicalPropName(train, button) == propName
    end

    local function IsPhysicalPropAttached(train, propName)
        if not IsSubwayTrain(train)
            or not isstring(propName)
            or not istable(train.ClientEnts)
        then
            return false
        end

        if istable(train.MEXDamageV4ServerDetached)
            and train.MEXDamageV4ServerDetached[propName]
        then
            return false
        end

        local prop = train.ClientEnts[propName]
        return IsValid(prop)
            and not prop:GetNoDraw()
            and prop:GetColor().a > 5
    end

    local function HasOtherAttachedProvider(
        train,
        buttonID,
        excludedProp
    )
        if not IsSubwayTrain(train) or not isstring(buttonID) then
            return false
        end

        local sourceMap =
            train.MEXDamageV4ButtonMapOriginal
            or train.ButtonMap

        if not istable(sourceMap) then return false end

        buttonID = buttonID:gsub("^.+:", "")

        for _, panel in pairs(sourceMap) do
            if not istable(panel) or not istable(panel.buttons) then
                continue
            end

            for _, button in pairs(panel.buttons) do
                if not istable(button) or not isstring(button.ID) then
                    continue
                end

                local id = button.ID:gsub("^.+:", "")
                if id ~= buttonID then continue end

                local provider = GetButtonPhysicalPropName(train, button)

                if provider
                    and provider ~= excludedProp
                    and IsPhysicalPropAttached(train, provider)
                then
                    return true
                end
            end
        end

        return false
    end

    local function GetButtonIDsForProp(train, panelName, propName, cached)
        -- A label, plomb, lamp lens or cap may physically detach on its own,
        -- but it is not the functional switch underneath it.
        if IsControlAccessory(propName, cached) then
            return {}, false
        end

        local out = {}
        local seen = {}

        local function add(id)
            if not isstring(id) or id == "" then return end
            id = id:gsub("^.+:", "")
            if seen[id] then return end
            seen[id] = true
            out[#out + 1] = id
        end

        local exactPhysicalBinding = false

        if panelName and istable(train.ButtonMap) then
            local panel = train.ButtonMap[panelName]
            if istable(panel) and istable(panel.buttons) then
                for _, button in pairs(panel.buttons) do
                    if not istable(button) then continue end

                    local matches =
                        GetButtonPhysicalPropName(
                            train,
                            button
                        ) == propName

                    if matches and isstring(button.ID) then
                        exactPhysicalBinding = true
                        add(button.ID)
                    end
                end
            end
        end

        -- Known multi-action mechanical hardware must contribute all of its
        -- logical actions even when Metrostroi exposes one exact ButtonMap
        -- binding. Otherwise removing the visible handle can leave keyboard
        -- or alternate interaction paths alive.
        AddKnownDetachedHardwareButtons(
            propName,
            cached.model,
            add
        )

        -- Core invariant: an attached physical button stays usable. When a
        -- generated ButtonMap prop has an exact identity, never infer nearby
        -- controls from geometry or model-name heuristics. Only this physical
        -- button's own ID is sent to the server; related keyboard aliases are
        -- expanded there after the detach is confirmed.
        if exactPhysicalBinding then
            local serverIDs = {}

            for _, id in ipairs(out) do
                if not HasOtherAttachedProvider(
                    train,
                    id,
                    propName
                ) then
                    serverIDs[#serverIDs + 1] = id
                end
            end

            return serverIDs, true
        end

        local text = string.lower(
            (propName or "") .. " " .. (cached.model or "")
        )

        -- Spatial ButtonMap association is intentionally restricted to
        -- standalone mechanical/electro-pneumatic hardware. Applying this to
        -- arbitrary props (especially doors) can steal a nearby large
        -- FrontDoor/RearDoor hitbox and make an unrelated door stop behaving.
        local needsSpatialAssociation =
            string.find(text, "brake_valve", 1, true)
            or string.find(text, "disconnect", 1, true)
            or string.find(text, "valve", 1, true)
            or string.find(text, "cran", 1, true)
            or string.find(text, "kran", 1, true)
            or string.find(text, "controller", 1, true)
            or string.find(text, "grkv", 1, true)
            or string.find(text, "/334", 1, true)
            or string.find(text, "/013", 1, true)

        if needsSpatialAssociation then
            -- Standalone hardware has no direct ButtonMap prop identity. Use
            -- only the single nearest hit target as a fallback; explicit
            -- hardware mappings below can still disable the complete function
            -- of one physical controller/valve after it visibly detaches.
            local nearby = GetNearbyButtonIDs(train, cached)
            if nearby[1] then
                add(nearby[1])
            end
        elseif string.find(text, "door", 1, true)
            or string.find(text, "dver", 1, true)
        then
            -- Legacy manual doors likewise bind to only the nearest Door event.
            for _, nearbyID in ipairs(GetNearbyButtonIDs(train, cached)) do
                if string.find(
                    string.lower(nearbyID),
                    "door",
                    1,
                    true
                ) then
                    add(nearbyID)
                    break
                end
            end
        end

        -- Some older trains render the manual/parking-brake mechanism as a
        -- standalone ClientEnt while keyboard bindings operate its ButtonEvent
        -- IDs. Add those well-known IDs as a fallback so the physical wheel
        -- cannot be bypassed with a shortcut after it tears off.
        if string.find(text, "parking", 1, true)
            or string.find(text, "manualbrake", 1, true)
            or string.find(text, "manual_brake", 1, true)
            or string.find(text, "handbrake", 1, true)
            or string.find(text, "hand_brake", 1, true)
            or string.find(text, "brakewheel", 1, true)
            or string.find(text, "brake_wheel", 1, true)
        then
            add("ParkingBrakeToggle")
            add("ParkingBrakeLeft")
            add("ParkingBrakeRight")
        end

        if string.find(text, "wiper", 1, true) then
            add("WiperToggle")
            add("WiperSet")
            add("Wiper")
        end

        -- Main traction/braking controller (KV/GRKV). If the physical
        -- controller is gone, no keyboard shortcut may still move its
        -- electrical positions.
        if string.find(text, "controller", 1, true)
            or string.find(text, "grkv", 1, true)
            or string.find(text, "/kv_", 1, true)
        then
            add("KVUp")
            add("KVDown")
            -- Reverser/key insertion is a separate physical mechanism. Do not
            -- disable KV_Unlock or KVWrench* merely because the traction
            -- controller itself was damaged.
            add("KVSetX1")
            add("KVSetX1B")
            add("KVSetX2")
            add("KVSetX3")
            add("KVSet0")
            add("KVSet0Fast")
            add("KVSetT1")
            add("KVSetT1A")
            add("KVSetT2")
        end

        -- Reverser key / wrench mechanics are physically independent from
        -- the main traction controller. Only a detached reverser mechanism may
        -- disable inserting/removing/turning the reverser key.
        local propNameLower = string.lower(propName or "")
        local modelLower = string.lower(cached.model or "")

        local isReverserHardware =
            string.find(propNameLower, "reverser", 1, true)
            or string.find(modelLower, "/reversor/", 1, true)
            or propNameLower == "kro"
            or propNameLower == "krr"
            or propNameLower == "kr_wrench"
            or propNameLower == "kru_wrench"

        if isReverserHardware then
            local isAuxReverser =
                string.find(propNameLower, "kru", 1, true)
                or string.find(propNameLower, "rcu", 1, true)
                or propNameLower == "krr"

            if isAuxReverser then
                add("KVWrenchKRU")
                add("WrenchKRR")
                add("KRR-")
                add("KRR+")
            else
                add("KVWrenchKV")
                add("KVWrenchKV9")
                add("WrenchKRO")
                add("KRO-")
                add("KRO+")
            end

            -- Removal is shared by several Metrostroi families. It is disabled
            -- only because an actual reverser mechanism has physically failed.
            add("KVWrenchNone")
            add("WrenchNone")

            add("KVReverserUp")
            add("KVReverserDown")
        end

        -- Pneumatic isolation cocks. These are independent physical
        -- valves: once the corresponding handle/valve is torn away, its
        -- InteractionZone/keyboard ButtonEvent must not remain usable.
        local isIsolationHardware =
            string.find(text, "isolation", 1, true)
            or string.find(text, "isolat", 1, true)
            or string.find(text, "disconnect", 1, true)
            or string.find(text, "cock", 1, true)
            or string.find(text, "kran", 1, true)
            or string.find(text, "valve", 1, true)

        if isIsolationHardware then
            local front = string.find(text, "front", 1, true)
            local rear = string.find(text, "rear", 1, true)
            local brakeLine =
                string.find(text, "brakeline", 1, true)
                or string.find(text, "brake_line", 1, true)
                or string.find(text, "brake line", 1, true)
            local trainLine =
                string.find(text, "trainline", 1, true)
                or string.find(text, "train_line", 1, true)
                or string.find(text, "train line", 1, true)

            if front and brakeLine
                or propNameLower == "frontbrake"
            then
                add("FrontBrakeLineIsolationToggle")
            end
            if front and trainLine
                or propNameLower == "fronttrain"
            then
                add("FrontTrainLineIsolationToggle")
            end
            if rear and brakeLine
                or propNameLower == "rearbrake"
            then
                add("RearBrakeLineIsolationToggle")
            end
            if rear and trainLine
                or propNameLower == "reartrain"
            then
                add("RearTrainLineIsolationToggle")
            end

            if string.find(text, "airdistributor", 1, true)
                or string.find(text, "air_distributor", 1, true)
            then
                add("AirDistributorDisconnectToggle")
            end
        end

        -- Driver brake valve / crane. The visible valve may be a standalone
        -- ClientEnt with no ButtonMap entry, while F/R and numpad keys still
        -- operate the Pneumatic system through ButtonEvent.
        if string.find(text, "brake_valve", 1, true)
            or string.find(text, "brake valve", 1, true)
            or string.find(text, "crane", 1, true)
            or string.find(text, "/334", 1, true)
            or string.find(text, "/013", 1, true)
        then
            add("PneumaticBrakeUp")
            add("PneumaticBrakeDown")
            add("PneumaticBrakeSet1")
            add("PneumaticBrakeSet2")
            add("PneumaticBrakeSet3")
            add("PneumaticBrakeSet4")
            add("PneumaticBrakeSet5")
            add("PneumaticBrakeSet6")
            add("PneumaticBrakeSet7")
            add("EmergencyBrake")
        end

        if string.find(text, "stopkran", 1, true)
            or string.find(text, "emergencybrake", 1, true)
            or string.find(text, "emergency_brake", 1, true)
        then
            add("EmergencyBrake")
            add("EmergencyBrakeValveToggle")
        end

        if propNameLower == "epk_disconnect"
            or propNameLower == "epv_disconnect"
            or string.find(text, "epk_disconnect", 1, true)
            or string.find(text, "epv_disconnect", 1, true)
        then
            add("EPKToggle")
        end

        if string.find(text, "driver_valve_bl", 1, true)
            or string.find(text, "brake_disconnect", 1, true)
        then
            add("DriverValveBLDisconnect")
            add("DriverValveBLDisconnectToggle")
        end

        if string.find(text, "driver_valve_tl", 1, true)
            or string.find(text, "train_disconnect", 1, true)
        then
            add("DriverValveTLDisconnect")
            add("DriverValveTLDisconnectToggle")
        end

        if string.find(text, "valve_disconnect", 1, true)
            and not string.find(text, "brake_disconnect", 1, true)
            and not string.find(text, "train_disconnect", 1, true)
        then
            add("DriverValveDisconnect")
            add("DriverValveDisconnectToggle")
        end

        if string.find(text, "epk_disconnect", 1, true) then
            add("EPKToggle")
        end

        if string.find(text, "epv_disconnect", 1, true) then
            add("EPKToggle")
        end

        -- Standalone 334/013 driver's brake valves are not tied to a clickable
        -- ButtonMap prop on many trains. Their physical loss disables the
        -- complete pneumatic-brake control family.
        if string.find(text, "brake_valve", 1, true)
            or string.find(text, "/334", 1, true)
            or string.find(text, "/013", 1, true)
        then
            add("PneumaticBrakeUp")
            add("PneumaticBrakeDown")
            add("PneumaticBrakeSet1")
            add("PneumaticBrakeSet2")
            add("PneumaticBrakeSet3")
            add("PneumaticBrakeSet4")
            add("PneumaticBrakeSet5")
            add("PneumaticBrakeSet6")
            add("PneumaticBrakeSet7")
        end

        -- Standalone hardware is itself the authoritative physical
        -- device. Do not let an invisible/logical ButtonMap prop masquerade as
        -- a second attached provider and keep the destroyed mechanism alive.
        -- Duplicate-provider filtering is only valid for exact physical
        -- ButtonMap bindings handled above.
        return out, false
    end

    local function CopyButtonDefinition(button)
        local copy = {}
        for k, v in pairs(button or {}) do
            copy[k] = v
        end
        return copy
    end

    local function MakeDeadButtonHitbox(button)
        local dead = CopyButtonDefinition(button)
        dead.x = 100000000
        dead.y = 100000000
        dead.w = 0
        dead.h = 0
        dead.radius = 0
        dead.tooltip = ""
        dead.MEXDamageDeadHitbox = true
        return dead
    end

    local function EnsureMetrostroiHiddenTables(train)
        train.Hidden = train.Hidden or {}
        train.Hidden.button = train.Hidden.button or {}
    end

    local function SetDamageNativeHidden(train, key, hidden)
        if not IsSubwayTrain(train) or not isstring(key) or key == "" then
            return
        end

        EnsureMetrostroiHiddenTables(train)

        train.MEXDamageNativeHiddenOriginal =
            train.MEXDamageNativeHiddenOriginal or {}

        local record = train.MEXDamageNativeHiddenOriginal[key]

        if hidden then
            if not record then
                record = {
                    direct = train.Hidden[key],
                    button = train.Hidden.button[key],
                }
                train.MEXDamageNativeHiddenOriginal[key] = record
            end

            -- findAimButton() in stock Metrostroi checks these tables directly
            -- every frame. This is the authoritative way to remove tooltip and
            -- mouse interaction for a physically missing control.
            train.Hidden.button[key] = true
        elseif record then
            train.Hidden[key] = record.direct
            train.Hidden.button[key] = record.button
            train.MEXDamageNativeHiddenOriginal[key] = nil
        end
    end

    local function RestoreDamageNativeHidden(train)
        if not IsSubwayTrain(train)
            or not istable(train.MEXDamageNativeHiddenOriginal)
        then
            return
        end

        EnsureMetrostroiHiddenTables(train)

        for key, record in pairs(train.MEXDamageNativeHiddenOriginal) do
            train.Hidden[key] = record.direct
            train.Hidden.button[key] = record.button
        end

        train.MEXDamageNativeHiddenOriginal = nil
    end

    local function SetPhysicalPropBindingsDetached(
        train,
        propName,
        detached
    )
        if not IsSubwayTrain(train) or not isstring(propName) then return end
        if not CloneInteractivePanels(train) then return end

        train.MEXDamageDeadBindings =
            train.MEXDamageDeadBindings or {}

        local sourceMap = train.MEXDamageV4ButtonMapOriginal
        if not istable(sourceMap) or not istable(train.ButtonMap) then
            return
        end

        for panelName, originalPanel in pairs(sourceMap) do
            if panelName == "BaseClass"
                or not istable(originalPanel)
                or not istable(originalPanel.buttons)
            then
                continue
            end

            local panel = train.ButtonMap[panelName]
            if not istable(panel) then continue end

            if not istable(panel.buttons) then
                panel.buttons = {}
            end

            train.MEXDamageDeadBindings[panelName] =
                train.MEXDamageDeadBindings[panelName] or {}

            for key, originalButton in pairs(originalPanel.buttons) do
                if not ButtonMatchesPhysicalProp(
                    train,
                    originalButton,
                    propName
                ) then
                    continue
                end

                if detached then
                    train.MEXDamageDeadBindings[panelName][key] = true
                    panel.buttons[key] =
                        MakeDeadButtonHitbox(originalButton)

                    SetDamageNativeHidden(
                        train,
                        propName,
                        true
                    )
                    if isstring(originalButton.ID)
                        and not HasOtherAttachedProvider(
                            train,
                            originalButton.ID,
                            propName
                        )
                    then
                        SetDamageNativeHidden(
                            train,
                            originalButton.ID,
                            true
                        )
                    end
                else
                    train.MEXDamageDeadBindings[panelName][key] = nil
                    panel.buttons[key] =
                        CopyButtonDefinition(originalButton)

                    SetDamageNativeHidden(
                        train,
                        propName,
                        false
                    )
                    if isstring(originalButton.ID) then
                        SetDamageNativeHidden(
                            train,
                            originalButton.ID,
                            false
                        )
                    end
                end
            end
        end
    end

    local function EnforceDeadPhysicalBindings(train)
        if not IsSubwayTrain(train)
            or not istable(train.MEXDamageDeadBindings)
            or not istable(train.MEXDamageV4ButtonMapOriginal)
            or not istable(train.ButtonMap)
        then
            return
        end

        for panelName, keys in pairs(train.MEXDamageDeadBindings) do
            local panel = train.ButtonMap[panelName]
            local originalPanel =
                train.MEXDamageV4ButtonMapOriginal[panelName]

            if not istable(panel)
                or not istable(panel.buttons)
                or not istable(originalPanel)
                or not istable(originalPanel.buttons)
            then
                continue
            end

            for key, dead in pairs(keys) do
                if not dead then continue end

                local originalButton = originalPanel.buttons[key]
                if istable(originalButton) then
                    panel.buttons[key] =
                        MakeDeadButtonHitbox(originalButton)
                end
            end
        end
    end

    local function ReconcileAttachedButtonHitboxes(train)
        if not IsSubwayTrain(train)
            or not istable(train.ButtonMap)
            or not istable(train.MEXDamageV4ButtonMapOriginal)
        then
            return
        end

        train.MEXDamageDisabledButtonIDs =
            train.MEXDamageDisabledButtonIDs or {}

        for panelName, panel in pairs(train.ButtonMap) do
            if panelName == "BaseClass"
                or not istable(panel)
                or not istable(panel.buttons)
            then
                continue
            end

            local originalPanel =
                train.MEXDamageV4ButtonMapOriginal[panelName]

            if not istable(originalPanel)
                or not istable(originalPanel.buttons)
            then
                continue
            end

            for key, originalButton in pairs(originalPanel.buttons) do
                if not istable(originalButton)
                    or not isstring(originalButton.ID)
                then
                    continue
                end

                local propName =
                    GetButtonPhysicalPropName(train, originalButton)

                if not propName then continue end

                local prop = istable(train.ClientEnts)
                    and train.ClientEnts[propName]
                    or nil

                -- Only reconcile buttons with a real visual ClientEnt. Pure
                -- logical/standalone controls keep their server fail-safe.
                if not IsValid(prop) then continue end

                local detached =
                    istable(train.MEXDamageV4ServerDetached)
                    and train.MEXDamageV4ServerDetached[propName] ~= nil

                local visiblyAttached =
                    not detached
                    and not prop:GetNoDraw()
                    and prop:GetColor().a > 5

                local wasDead =
                    istable(train.MEXDamageDeadBindings)
                    and istable(
                        train.MEXDamageDeadBindings[panelName]
                    )
                    and train.MEXDamageDeadBindings[panelName][key]
                        == true

                if visiblyAttached and wasDead then
                    SetPhysicalPropBindingsDetached(
                        train,
                        propName,
                        false
                    )
                elseif detached then
                    SetPhysicalPropBindingsDetached(
                        train,
                        propName,
                        true
                    )
                end
            end
        end
    end

    local function EnforceDisabledButtonHitboxes(train)
        if not IsSubwayTrain(train) then return end

        ReconcileAttachedButtonHitboxes(train)

        -- Exact physical bindings are independent from the global ID fallback
        -- list. Always enforce them, even when MEXDamageDisabledButtonIDs is
        -- empty (the common case for normal generated buttons).
        EnforceDeadPhysicalBindings(train)

        if not istable(train.MEXDamageDisabledButtonIDs)
            or table.IsEmpty(train.MEXDamageDisabledButtonIDs)
        then
            return
        end

        -- A direct bullet/crowbar hit can detach a component without creating
        -- structural deformation. Keep a private ButtonMap even in that case;
        -- otherwise Metrostroi can resurrect an invisible clickable control.
        if not train.MEXDamageV4ButtonMapOriginal then
            CloneInteractivePanels(train)
        end

        if not istable(train.ButtonMap) then return end

        for _, panel in pairs(train.ButtonMap) do
            if not istable(panel) or not istable(panel.buttons) then continue end

            if not panel.MEXDamageButtonsPrivate then
                local privateButtons = {}
                for k, v in pairs(panel.buttons) do
                    privateButtons[k] = v
                end
                panel.buttons = privateButtons
                panel.MEXDamageButtonsPrivate = true
            end

            for key, button in pairs(panel.buttons) do
                if not istable(button) or not isstring(button.ID) then continue end

                local id = button.ID:gsub("^.+:", "")
                if not train.MEXDamageDisabledButtonIDs[id] then continue end

                -- Do not rely on removing the entry alone: Metrostroi may keep
                -- a local reference to a button object for part of a frame.
                -- Replace it with a private dead hitbox object at an impossible
                -- location and zero size, preserving only harmless metadata.
                if not button.MEXDamageDeadHitbox then
                    local dead = {}
                    for k, v in pairs(button) do dead[k] = v end

                    dead.x = 100000000
                    dead.y = 100000000
                    dead.w = 0
                    dead.h = 0
                    dead.radius = 0
                    dead.tooltip = ""
                    dead.MEXDamageDeadHitbox = true

                    panel.buttons[key] = dead
                else
                    button.x = 100000000
                    button.y = 100000000
                    button.w = 0
                    button.h = 0
                    button.radius = 0
                    button.tooltip = ""
                end
            end
        end
    end

    local function DisableDetachedButtonIDs(train, buttonIDs)
        if not IsSubwayTrain(train) or not istable(buttonIDs) then return end

        train.MEXDamageDisabledButtonIDs =
            train.MEXDamageDisabledButtonIDs or {}

        for _, id in ipairs(buttonIDs) do
            if isstring(id) and id ~= "" then
                train.MEXDamageDisabledButtonIDs[
                    id:gsub("^.+:", "")
                ] = true
            end
        end

        EnforceDisabledButtonHitboxes(train)
    end

    local function GetPanelAttachedLocalTransform(train, cached, panelName)
        local panel = train.ButtonMap and train.ButtonMap[panelName]
        if not istable(panel) or not panel.MEXDamageBasePos then
            return nil, nil
        end

        local relPos, relAng = WorldToLocal(
            cached.basePos,
            cached.baseAng,
            panel.MEXDamageBasePos,
            panel.MEXDamageBaseAng
        )

        return LocalToWorld(
            relPos,
            relAng,
            panel.pos,
            panel.ang
        )
    end

    local function GetRigidAttachedLocalTransform(cached, state)
        local desiredAnchor = DeformLocalPoint(cached.anchorPos, state)
        local desiredAng = DeformLocalAngle(
            cached.anchorPos,
            cached.baseAng,
            state
        )

        local desiredOrigin = OriginForAnchoredModel(
            cached.obbCenter,
            desiredAnchor,
            desiredAng
        )

        return desiredOrigin, desiredAng
    end

    local function DisableDetachedPanelControl(
        train,
        panelName,
        propName
    )
        if not panelName or not isstring(propName) then return end

        -- Exact generated controls are disabled by their physical binding slot,
        -- not by a global ButtonEvent ID shared with other attached controls.
        SetPhysicalPropBindingsDetached(
            train,
            propName,
            true
        )
    end

    local function CopyVisualState(source, debris)
        if not IsValid(source) or not IsValid(debris) then return end

        debris:SetSkin(source:GetSkin() or 0)
        debris:SetColor(source:GetColor())
        debris:SetMaterial(source:GetMaterial() or "")

        local groups = source:GetNumBodyGroups() or 0
        for id = 0, groups - 1 do
            debris:SetBodygroup(id, source:GetBodygroup(id))
        end
    end

    local WINDOW_MATERIAL_WORDS = {
        "window", "windows", "windscreen", "windshield",
        "stekl", "stec",
    }

    local GLASS_CARRIER_EXCLUDED_WORDS = {
        "lamp", "light", "indicator", "gauge", "meter", "manometer",
        "button", "switch", "tumbler", "toggle", "display", "screen",
        "speed", "volt", "amp", "pressure", "panel", "pult",
    }

    local function MaterialPathLooksWindow(path)
        path = string.lower(path or "")

        for _, word in ipairs(GLASS_CARRIER_EXCLUDED_WORDS) do
            if string.find(path, word, 1, true) then
                return false
            end
        end

        for _, word in ipairs(WINDOW_MATERIAL_WORDS) do
            if string.find(path, word, 1, true) then
                return true
            end
        end

        return false
    end

    local function LooksLikeWindowCarrier(name, cached, mode)
        local text = string.lower(
            (name or "") .. " " .. ((cached and cached.model) or "")
        )

        for _, word in ipairs(GLASS_CARRIER_EXCLUDED_WORDS) do
            if string.find(text, word, 1, true) then
                return false
            end
        end

        if cached and cached.glass then return true end

        if mode == "passenger" then
            return string.find(text, "salon", 1, true) ~= nil
                or string.find(text, "interior", 1, true) ~= nil
                or string.find(text, "body", 1, true) ~= nil
                or string.find(text, "window", 1, true) ~= nil
        end

        return string.find(text, "cabin", 1, true) ~= nil
            or string.find(text, "cabine", 1, true) ~= nil
            or string.find(text, "mask", 1, true) ~= nil
            or string.find(text, "body", 1, true) ~= nil
            or string.find(text, "window", 1, true) ~= nil
    end

    local function HideGlassSubMaterials(train, ent)
        if not IsValid(ent) then return 0 end

        local materials = ent:GetMaterials() or {}
        local changed = 0

        train.MEXDamageBrokenGlassMaterials =
            train.MEXDamageBrokenGlassMaterials or {}

        local record = train.MEXDamageBrokenGlassMaterials[ent]
        if not record then
            record = {}
            train.MEXDamageBrokenGlassMaterials[ent] = record
        end

        for materialIndex, path in ipairs(materials) do
            -- Embedded fallback only touches materials that are explicitly
            -- window/windscreen-like. Generic "glass" is intentionally not
            -- enough because many old panels use it for indicator lenses.
            if not MaterialPathLooksWindow(path) then continue end

            local subIndex = materialIndex - 1

            if record[subIndex] == nil then
                record[subIndex] = ent:GetSubMaterial(subIndex) or ""
            end

            ent:SetSubMaterial(
                subIndex,
                MEX_INVISIBLE_GLASS_NAME
            )
            changed = changed + 1
        end

        return changed
    end

    local function RestoreBrokenGlassMaterials(train)
        if not istable(train.MEXDamageBrokenGlassMaterials) then return end

        for ent, materials in pairs(train.MEXDamageBrokenGlassMaterials) do
            if not IsValid(ent) then continue end

            for subIndex, previous in pairs(materials) do
                if isstring(previous) and previous ~= "" then
                    ent:SetSubMaterial(subIndex, previous)
                else
                    ent:SetSubMaterial(subIndex, "")
                end
            end
        end

        train.MEXDamageBrokenGlassMaterials = nil
    end

    local function ShatterEmbeddedGlass(
        train,
        hitLocal,
        power,
        radius
    )
        if not IsSubwayTrain(train) or not isvector(hitLocal) then
            return false
        end

        power = tonumber(power) or 0
        if power < 0.30 then return false end

        local shattered = 0
        local mins = train:OBBMins()
        local maxs = train:OBBMaxs()
        local center = (mins + maxs) * 0.5
        local halfLength = math.max((maxs.x - mins.x) * 0.5, 1)
        local halfWidth = math.max((maxs.y - mins.y) * 0.5, 1)
        local halfHeight = math.max((maxs.z - mins.z) * 0.5, 1)

        local endness =
            math.abs(hitLocal.x - center.x) / halfLength
        local sideness =
            math.abs(hitLocal.y - center.y) / halfWidth
        local height01 =
            (hitLocal.z - mins.z) / math.max(maxs.z - mins.z, 1)

        local cabHit =
            endness >= 0.58
            and height01 >= 0.42

        local passengerWindowHit =
            endness < 0.82
            and sideness >= 0.58
            and height01 >= 0.42

        if not cabHit and not passengerWindowHit then
            return false
        end

        -- Many stock bodies (for example older 81-717 derivatives) keep
        -- passenger/cab glazing in a dedicated *windows*.vmt slot on the main
        -- body. Hiding that slot is safe; generic glass materials are excluded.
        shattered = shattered + HideGlassSubMaterials(train, train)

        if istable(train.ClientEnts) then
            for name, prop in pairs(train.ClientEnts) do
                if not IsValid(prop) then continue end

                local cached = CacheClientProp(train, name, prop)
                local mode = passengerWindowHit and "passenger" or "cab"

                if not LooksLikeWindowCarrier(name, cached, mode) then
                    continue
                end

                local distance = cached.anchorPos:Distance(hitLocal)

                -- Full-length salon/interior shells often have their model
                -- origin at the wagon origin, so do not require their anchor to
                -- be close. Local window/cab pieces still use distance gating.
                if not cached.fullLength
                    and distance > math.max(radius or 0, 24) + 65
                then
                    continue
                end

                shattered = shattered
                    + HideGlassSubMaterials(train, prop)
            end
        end

        if shattered > 0 then
            local worldPos = train:LocalToWorld(hitLocal)
            local effect = EffectData()
            effect:SetOrigin(worldPos)
            effect:SetScale(math.Clamp(power, 0.5, 2.4))
            effect:SetMagnitude(3)
            util.Effect("GlassImpact", effect)

            surface.PlaySound(
                "physics/glass/glass_largesheet_break1.wav"
            )
        end

        return shattered > 0
    end

    local function GetDetachedElectricalMetadata(
        train,
        panelName,
        propName,
        cached,
        buttonIDs
    )
        if IsControlAccessory(propName, cached) then
            return true, {}
        end

        local candidates = {}
        local seen = {}

        local function add(value)
            if not isstring(value) then return end
            value = value:gsub("^.+:", "")
            if value == "" or #value > 64 then return end
            if not string.match(value, "^[%w_%-]+$") then return end
            if seen[value] then return end
            seen[value] = true
            candidates[#candidates + 1] = value
        end

        if panelName and istable(train.ButtonMap) then
            local panel = train.ButtonMap[panelName]

            if istable(panel) and istable(panel.buttons) then
                for _, button in pairs(panel.buttons) do
                    if not istable(button) then continue end

                    if GetButtonPhysicalPropName(train, button)
                        ~= propName
                    then
                        continue
                    end

                    local config = button.model

                    -- Older Metrostroi ButtonMaps often put the logical relay
                    -- variable directly on the button table, while newer ones
                    -- use button.model.var.
                    add(button.var)

                    if istable(config) then
                        add(config.var)
                    end

                    if isstring(button.ID) then
                        local id = button.ID:gsub("^.+:", "")
                        local base = id
                        local suffixes = {
                            "Toggle",
                            "Set",
                            "On",
                            "Off",
                        }

                        for _, suffix in ipairs(suffixes) do
                            if string.sub(base, -#suffix) == suffix
                                and #base > #suffix
                            then
                                base = string.sub(
                                    base,
                                    1,
                                    #base - #suffix
                                )
                                break
                            end
                        end

                        add(id)
                        if base ~= id then add(base) end
                    end
                end
            end
        end

        local mechanical = IsMechanicalElectricalException(
            propName,
            cached and cached.model or "",
            buttonIDs
        )

        return mechanical, candidates
    end

    local function RequestServerDetach(
        train,
        name,
        prop,
        cached,
        state,
        panelName,
        isDoor,
        isControl
    )
        train.MEXDamageV4DetachPending = train.MEXDamageV4DetachPending or {}

        local nextAllowed = train.MEXDamageV4DetachPending[name] or 0
        if nextAllowed > CurTime() then return false end
        train.MEXDamageV4DetachPending[name] = CurTime() + 1.0

        local localPos, localAng

        if panelName then
            localPos, localAng = GetPanelAttachedLocalTransform(
                train,
                cached,
                panelName
            )
        end

        if not isvector(localPos) or not isangle(localAng) then
            localPos, localAng = GetRigidAttachedLocalTransform(cached, state)
        end

        if not isvector(localPos) or not isangle(localAng) then
            return false
        end

        local buttons = GetButtonIDsForProp(
            train,
            panelName,
            name,
            cached
        )

        local mechanicalElectrical, electricalTargets =
            GetDetachedElectricalMetadata(
                train,
                panelName,
                name,
                cached,
                buttons
            )

        net.Start("MEX.DetachRequest")
            net.WriteEntity(train)
            net.WriteString(name)
            net.WriteString(cached.model)
            net.WriteVector(localPos)
            net.WriteAngle(localAng)
            net.WriteVector(cached.anchorPos)
            net.WriteVector(prop:OBBMins())
            net.WriteVector(prop:OBBMaxs())
            net.WriteBool(isDoor)
            net.WriteBool(isControl)
            net.WriteUInt(math.Clamp(prop:GetSkin() or 0, 0, 255), 8)
            net.WriteColor(prop:GetColor())
            net.WriteString(prop:GetMaterial() or "")
            net.WriteUInt(
                math.Clamp(prop:GetSequence() or 0, 0, 65535),
                16
            )
            net.WriteFloat(
                math.Clamp(prop:GetCycle() or 0, 0, 1)
            )
            net.WriteFloat(
                prop:GetPoseParameter("position") or 0
            )

            local bodygroupCount = math.min(prop:GetNumBodyGroups() or 0, 31)
            net.WriteUInt(bodygroupCount, 5)
            for id = 0, bodygroupCount - 1 do
                net.WriteUInt(id, 5)
                net.WriteUInt(
                    math.Clamp(prop:GetBodygroup(id) or 0, 0, 255),
                    8
                )
            end

            net.WriteUInt(math.min(#buttons, 48), 6)
            for i = 1, math.min(#buttons, 48) do
                net.WriteString(buttons[i])
            end

            net.WriteBool(mechanicalElectrical == true)
            net.WriteUInt(
                math.min(#electricalTargets, 24),
                5
            )
            for i = 1, math.min(#electricalTargets, 24) do
                net.WriteString(electricalTargets[i])
            end
        net.SendToServer()

        return true
    end

    local function FindControlAccessoryChildren(
        train,
        parentName,
        parentCached,
        panelMap
    )
        local result = {}

        if not IsSubwayTrain(train)
            or not istable(train.ClientEnts)
            or not parentCached
        then
            return result
        end

        panelMap = panelMap or train.MEXDamageV4PanelProps
            or BuildPanelPropMap(train)

        local function nearestFunctionalRootFor(childName, childCached)
            local bestName = nil
            local bestDistance = math.huge

            for otherName, otherProp in pairs(train.ClientEnts) do
                if otherName == childName or not IsValid(otherProp) then
                    continue
                end

                if train.MEXDamageV4ServerDetached
                    and train.MEXDamageV4ServerDetached[otherName]
                then
                    continue
                end

                local otherCached =
                    CacheClientProp(train, otherName, otherProp)

                if IsControlAccessory(otherName, otherCached) then
                    continue
                end

                local otherPanel = panelMap[otherName]
                if not IsSmallControlComponent(
                    otherName,
                    otherCached,
                    otherPanel
                ) then
                    continue
                end

                local d = otherCached.anchorPos:Distance(
                    childCached.anchorPos
                )

                if d < bestDistance then
                    bestDistance = d
                    bestName = otherName
                end
            end

            return bestName, bestDistance
        end

        for childName, childProp in pairs(train.ClientEnts) do
            if childName == parentName or not IsValid(childProp) then
                continue
            end

            if train.MEXDamageV4ServerDetached
                and train.MEXDamageV4ServerDetached[childName]
            then
                continue
            end

            if childProp.GetNoDraw and childProp:GetNoDraw() then
                continue
            end
            if childProp:GetColor().a <= 5 then continue end

            local childCached =
                CacheClientProp(train, childName, childProp)

            local generatedParent =
                GeneratedAccessoryParent(childName)

            local belongs = generatedParent == parentName

            if not belongs
                and generatedParent == nil
                and IsControlAccessory(childName, childCached)
            then
                local nearestName, nearestDistance =
                    nearestFunctionalRootFor(
                        childName,
                        childCached
                    )

                belongs =
                    nearestName == parentName
                    and nearestDistance <= 11
            end

            if belongs then
                result[#result + 1] = {
                    name = childName,
                    prop = childProp,
                    cached = childCached,
                    panelName = panelMap[childName],
                }
            end
        end

        table.sort(result, function(a, b)
            return a.cached.anchorPos:DistToSqr(parentCached.anchorPos)
                < b.cached.anchorPos:DistToSqr(parentCached.anchorPos)
        end)

        return result
    end

    local function RequestControlAccessoryChildren(
        train,
        parentName,
        parentCached,
        state,
        panelMap,
        limit
    )
        local requested = 0
        limit = math.max(math.floor(limit or 9), 0)

        for _, child in ipairs(FindControlAccessoryChildren(
            train,
            parentName,
            parentCached,
            panelMap
        )) do
            if requested >= limit then break end

            if RequestServerDetach(
                train,
                child.name,
                child.prop,
                child.cached,
                state,
                child.panelName,
                false,
                true
            ) then
                requested = requested + 1
                ClearClientPropRenderTransform(child.prop)
            end
        end

        return requested
    end

    local function ComponentCandidateRadius(cached, isDoor, isControl)
        local s = cached.size
        local largest = math.max(math.abs(s.x), math.abs(s.y), math.abs(s.z))

        if cached.glass then
            return math.Clamp(largest * 0.18, 5, 24)
        elseif isDoor then
            return math.Clamp(largest * 0.22, 8, 30)
        elseif isControl then
            return math.Clamp(largest * 0.38, 3, 12)
        end

        return math.Clamp(largest * 0.28, 4, 18)
    end

    local function DirectImpactMountThreshold(name, isDoor, isControl)
        local seed = StableFraction(name)

        if isDoor then
            return 0.20 + seed * 0.14
        elseif isControl then
            return 0.055 + seed * 0.085
        end

        return 0.13 + seed * 0.14
    end

    local function HandleDirectComponentImpact(
        train,
        hitLocal,
        impulseLocal,
        power,
        radius,
        maxDetach,
        isBlast
    )
        if not IsSubwayTrain(train) or not istable(train.ClientEnts) then
            return
        end

        local panelMap = train.MEXDamageV4PanelProps
            or BuildPanelPropMap(train)
        local state = BuildDamageState(train)
        local candidates = {}

        for name, prop in pairs(train.ClientEnts) do
            if not IsValid(prop) then continue end

            if train.MEXDamageV4ServerDetached
                and train.MEXDamageV4ServerDetached[name]
            then
                continue
            end

            if prop.GetNoDraw and prop:GetNoDraw() then continue end
            if prop:GetColor().a <= 5 then continue end

            local cached = CacheClientProp(train, name, prop)
            local panelName = panelMap[name]

            local isGlass = IsGlassComponent(name, cached)
            local isDoor = IsDoorComponent(name, cached)
            local isControl = IsSmallControlComponent(
                name,
                cached,
                panelName
            )
            local isBreakaway = IsGeneralBreakawayComponent(
                name,
                cached,
                panelName
            )

            if not isGlass
                and not isDoor
                and not isControl
                and not isBreakaway
            then
                continue
            end

            local centerDistance = cached.anchorPos:Distance(hitLocal)
            local componentRadius = ComponentCandidateRadius(
                cached,
                isDoor,
                isControl
            )
            local edgeDistance = math.max(
                0,
                centerDistance - componentRadius
            )

            if edgeDistance > radius then continue end

            local falloff = 1 - edgeDistance / math.max(radius, 1)
            local score = falloff * power
            local threshold = isGlass
                and (0.018 + StableFraction(name) * 0.035)
                or DirectImpactMountThreshold(
                    name,
                    isDoor,
                    isControl
                )

            local predictedMove = 0

            if isBlast then
                local impulseMagnitude = isvector(impulseLocal)
                    and impulseLocal:Length()
                    or 0

                local compliance =
                    isGlass and 2.2
                    or (isControl and 1.65)
                    or (isDoor and 0.92 or 1.15)

                predictedMove =
                    impulseMagnitude
                    * falloff
                    * compliance
                    / 95

                local movementThreshold =
                    isGlass and 0.025
                    or (isControl and 0.045)
                    or (isDoor and 0.085 or 0.065)

                -- Explosion rule: once a mounted part would visibly move even
                -- a small amount relative to the carbody, its fasteners are
                -- considered failed and it becomes independent debris.
                if predictedMove < movementThreshold
                    and score < threshold * 0.55
                then
                    continue
                end
            elseif score < threshold then
                continue
            end

            local isAccessory =
                IsControlAccessory(name, cached)

            candidates[#candidates + 1] = {
                name = name,
                prop = prop,
                cached = cached,
                panelName = panelName,
                isGlass = isGlass,
                isDoor = isDoor,
                isControl = isControl,
                isAccessory = isAccessory,
                score = score,
                predictedMove = predictedMove,
                centerDistance = centerDistance,
                edgeDistance = edgeDistance,
                priority =
                    isAccessory and 6
                    or (isGlass and 5)
                    or (isControl and 4)
                    or (isDoor and 2 or 3),
            }
        end

        local preciseHit =
            not isBlast and (maxDetach or 1) == 10

        table.sort(candidates, function(a, b)
            if preciseHit then
                local centerDelta = math.abs(
                    (a.centerDistance or math.huge)
                    - (b.centerDistance or math.huge)
                )

                if centerDelta > 1.25 then
                    return (a.centerDistance or math.huge)
                        < (b.centerDistance or math.huge)
                end

                if a.isAccessory ~= b.isAccessory then
                    -- A cap/label physically sits on top of the switch. If the
                    -- hit point cannot distinguish them better than ~1 SU,
                    -- detach the outer accessory first, not the mechanism.
                    return a.isAccessory == true
                end
            end

            if isBlast
                and math.abs(
                    (a.predictedMove or 0)
                    - (b.predictedMove or 0)
                ) > 0.001
            then
                return (a.predictedMove or 0)
                    > (b.predictedMove or 0)
            end

            -- Within a small local neighborhood, prefer the actually mounted
            -- control over a large panel/case behind it.
            local neighborhood = math.min(8, radius * 0.35)
            local aRank = a.edgeDistance - a.priority * neighborhood
            local bRank = b.edgeDistance - b.priority * neighborhood

            if math.abs(aRank - bRank) > 0.01 then
                return aRank < bRank
            end

            if a.priority ~= b.priority then
                return a.priority > b.priority
            end

            return a.score > b.score
        end)

        local requested = 0
        local limit = math.Clamp(maxDetach or 1, 1, 96)

        if preciseHit then
            local candidate = candidates[1]
            if not candidate then return end

            if RequestServerDetach(
                train,
                candidate.name,
                candidate.prop,
                candidate.cached,
                state,
                candidate.panelName,
                candidate.isDoor,
                candidate.isControl
            ) then
                requested = 1
                ClearClientPropRenderTransform(candidate.prop)

                -- One-way hierarchy:
                -- accessory hit -> accessory only
                -- switch/control hit -> switch + its labels/plomb/caps
                if candidate.isControl
                    and not candidate.isAccessory
                    and requested < limit
                then
                    requested = requested
                        + RequestControlAccessoryChildren(
                            train,
                            candidate.name,
                            candidate.cached,
                            state,
                            panelMap,
                            limit - requested
                        )
                end
            end

            return
        end

        for _, candidate in ipairs(candidates) do
            if requested >= limit then break end

            if RequestServerDetach(
                train,
                candidate.name,
                candidate.prop,
                candidate.cached,
                state,
                candidate.panelName,
                candidate.isDoor,
                candidate.isControl
            ) then
                requested = requested + 1

                ClearClientPropRenderTransform(candidate.prop)
            end
        end
    end

    net.Receive("MEX.ComponentImpact", function()
        if not MEXD.IsDamageEnabled() then return end

        local train = net.ReadEntity()
        net.ReadUInt(16) -- serial is currently only used server-side
        local hitLocal = net.ReadVector()
        local impulseLocal = net.ReadVector()
        local power = net.ReadFloat()
        local radius = net.ReadFloat()
        local maxDetach = net.ReadUInt(7)
        local isBlast = net.ReadBool()

        if not IsSubwayTrain(train) then return end

        -- Even when glass is baked into a larger carbody/cab model, try to
        -- remove the model's dedicated glass material slots at the impact.
        ShatterEmbeddedGlass(
            train,
            hitLocal,
            power,
            radius
        )

        -- ClientEnts/ButtonMap may be created later in the same frame as the
        -- impact callback. One zero-delay retry is enough without accumulating
        -- stale hit events.
        timer.Simple(0, function()
            if not IsSubwayTrain(train) then return end
            HandleDirectComponentImpact(
                train,
                hitLocal,
                impulseLocal,
                power,
                radius,
                maxDetach,
                isBlast
            )
        end)
    end)

    local function EnsureDamagedLightGuard(train)
        if train.MEXDamageOriginalSetLightPower then return end
        if not isfunction(train.SetLightPower) then return end

        train.MEXDamageOriginalSetLightPower = train.SetLightPower
        train.MEXDamageDisabledLights = train.MEXDamageDisabledLights or {}

        train.SetLightPower = function(self, index, power, brightness)
            if self.MEXDamageDisabledLights
                and self.MEXDamageDisabledLights[index]
            then
                return self.MEXDamageOriginalSetLightPower(
                    self,
                    index,
                    false,
                    0
                )
            end

            return self.MEXDamageOriginalSetLightPower(
                self,
                index,
                power,
                brightness
            )
        end
    end

    local function DisableLightsForDetachedComponent(
        train,
        name,
        cached
    )
        if not istable(train.Lights) or not cached then return end

        local text = string.lower(
            (name or "") .. " " .. (cached.model or "")
        )

        local isLamp =
            string.find(text, "lamp", 1, true)
            or string.find(text, "light", 1, true)
            or string.find(text, "headlight", 1, true)

        if not isLamp then return end

        EnsureDamagedLightGuard(train)

        local candidates = {}
        for index, light in pairs(train.Lights) do
            if not istable(light) or not isvector(light[2]) then continue end

            local distance = cached.anchorPos:Distance(light[2])
            candidates[#candidates + 1] = {
                index = index,
                distance = distance,
            }
        end

        table.sort(candidates, function(a, b)
            return a.distance < b.distance
        end)

        local radius =
            string.find(text, "headlight", 1, true) and 135 or 75

        local disabled = 0
        for _, candidate in ipairs(candidates) do
            if candidate.distance > radius then continue end

            train.MEXDamageDisabledLights[candidate.index] = true
            train:MEXDamageOriginalSetLightPower(
                candidate.index,
                false,
                0
            )
            disabled = disabled + 1
        end

        -- Some Metrostroi lamp group models are authored around train origin,
        -- while their visible mesh sits at the front. In that case the cached
        -- model anchor and the light definition may not be close enough. For a
        -- clearly named headlight group, disable the nearest light as a safe
        -- fallback.
        if disabled == 0
            and string.find(text, "headlight", 1, true)
            and candidates[1]
        then
            local index = candidates[1].index
            train.MEXDamageDisabledLights[index] = true
            train:MEXDamageOriginalSetLightPower(index, false, 0)
        end
    end

    local function MarkDetachedClient(train, name, debris)
        -- This function is reached only from MEX.ComponentDetached, i.e. after
        -- the server accepted the physical detach. Never disable controls from
        -- a mere detach request/prediction: if the original ClientEnt is still
        -- visibly attached, it must remain fully interactive.
        train.MEXDamageV4ServerDetached =
            train.MEXDamageV4ServerDetached or {}

        local previous = train.MEXDamageV4ServerDetached[name]

        if not previous then
            previous = {
                debris = debris,
                oldNoDraw = nil,
            }

            train.MEXDamageV4ServerDetached[name] = previous
        else
            previous.debris = debris
        end

        local panelMap =
            train.MEXDamageV4PanelProps or BuildPanelPropMap(train)
        local panelName = panelMap[name]

        if istable(train.ClientEnts) then
            local prop = train.ClientEnts[name]

            if IsValid(prop) then
                if previous.oldNoDraw == nil then
                    previous.oldNoDraw = prop:GetNoDraw()
                end

                local cached = CacheClientProp(train, name, prop)
                previous.anchorPos = cached and cached.anchorPos or nil
                previous.model = cached and cached.model or nil

                DisableLightsForDetachedComponent(
                    train,
                    name,
                    cached
                )

                local mappedButtons, exactBinding =
                    GetButtonIDsForProp(
                        train,
                        panelName,
                        name,
                        cached
                    )

                if exactBinding then
                    SetPhysicalPropBindingsDetached(
                        train,
                        name,
                        true
                    )
                else
                    DisableDetachedButtonIDs(
                        train,
                        mappedButtons
                    )
                end

                prop:SetRenderOrigin(nil)
                prop:SetRenderAngles(nil)
                prop:DisableMatrix("RenderMultiply")
                prop:SetNoDraw(true)
            end
        end

        if panelName then
            DisableDetachedPanelControl(train, panelName, name)
        end

        EnforceDisabledButtonHitboxes(train)
    end

    local function MaybeDetachClientComponent(
        train,
        name,
        prop,
        cached,
        state,
        panelName
    )
        if not IsValid(prop) then return false end

        if train.MEXDamageV4ServerDetached
            and train.MEXDamageV4ServerDetached[name]
        then
            prop:SetNoDraw(true)
            return true
        end

        -- Do not request a hidden variant which Metrostroi is not currently
        -- displaying.
        if prop.GetNoDraw and prop:GetNoDraw() then return false end
        if prop:GetColor().a <= 5 then return false end

        local displacement =
            (
                DeformMountedPointStrength(
                    train,
                    cached.anchorPos,
                    state,
                    cached.cabin
                        and math.max(
                            1.18,
                            CabStrengthAtPoint(cached.anchorPos, state)
                        )
                        or 1
                )
                - cached.anchorPos
            ):Length()

        if displacement <= 0.01 then return false end

        local crushEnergy =
            istable(state.crush)
                and (state.crush.overall or state.crush.front or 0)
                or (state.front or 0)

        local seed = StableFraction(name)
        local isGlass = IsGlassComponent(name, cached)
        local isDoor = IsDoorComponent(name, cached)
        local isControl = IsSmallControlComponent(name, cached, panelName)
        local isBreakaway = IsGeneralBreakawayComponent(
            name,
            cached,
            panelName
        )

        local largest = math.max(
            math.abs(cached.size.x),
            math.abs(cached.size.y),
            math.abs(cached.size.z)
        )

        local largeStructural =
            cached.structural
            and largest >= 58
            and not isGlass
            and not isControl

        local text = string.lower(
            (name or "") .. " " .. (cached.model or "")
        )
        local interiorFixture =
            string.find(text, "seat", 1, true)
            or string.find(text, "couch", 1, true)
            or string.find(text, "bench", 1, true)
            or string.find(text, "chair", 1, true)
            or string.find(text, "handrail", 1, true)
            or string.find(text, "handler", 1, true)
            or string.find(text, "interior", 1, true)
            or string.find(text, "salon", 1, true)

        if isGlass then
            local threshold = 0.20 + seed * 0.45
            if displacement >= threshold then
                local requested = RequestServerDetach(
                    train,
                    name,
                    prop,
                    cached,
                    state,
                    panelName,
                    false,
                    false
                )

                if requested then
                    ClearClientPropRenderTransform(prop)
                    return true
                end
            end
            return false
        end

        if isDoor then
            -- Large carbody doors should first bend with the shell. Only after
            -- substantial crush energy has accumulated may the complete door
            -- tear away as debris.
            if largeStructural and crushEnergy < 2.00 then
                return false
            end

            local threshold =
                (2.2 + seed * 2.8)
                * (largeStructural and 1.75 or 1)

            if displacement >= threshold then
                local requested = RequestServerDetach(
                    train,
                    name,
                    prop,
                    cached,
                    state,
                    panelName,
                    true,
                    false
                )

                if requested then
                    ClearClientPropRenderTransform(prop)
                    return true
                end
            end
            return false
        end

        if isControl then
            -- Small controls should not ride metres away together with a bent
            -- ButtonMap. Their mounts fail after only a small local movement.
            local threshold = 0.45 + seed * 1.05
            if displacement >= threshold then
                local requested = RequestServerDetach(
                    train,
                    name,
                    prop,
                    cached,
                    state,
                    panelName,
                    false,
                    true
                )

                if requested then
                    ClearClientPropRenderTransform(prop)

                    if not IsControlAccessory(name, cached) then
                        RequestControlAccessoryChildren(
                            train,
                            name,
                            cached,
                            state,
                            train.MEXDamageV4PanelProps
                                or BuildPanelPropMap(train),
                            9
                        )
                    end

                    return true
                end
            end
            return false
        end

        if isBreakaway then
            -- Body panels and shell sections are deformation material, not
            -- ordinary props. Keep them attached through the normal crash
            -- phase so they can buckle/accordion instead of instantly exposing
            -- an empty frame. They can still tear away in the scrap phase.
            if interiorFixture and crushEnergy < 4.50 then
                return false
            end

            if largeStructural and crushEnergy < 2.80 then
                return false
            end

            local threshold =
                (1.0 + seed * 2.4)
                * (interiorFixture and 3.2
                    or (largeStructural and 2.2 or 1))

            if displacement >= threshold then
                local requested = RequestServerDetach(
                    train,
                    name,
                    prop,
                    cached,
                    state,
                    panelName,
                    false,
                    false
                )

                if requested then
                    ClearClientPropRenderTransform(prop)
                    return true
                end
            end
        end

        return false
    end

    local function RestoreDetachedComponents(train)
        if not IsValid(train) then return end

        if istable(train.MEXDamageV4ServerDetached) then
            for name, data in pairs(train.MEXDamageV4ServerDetached) do
                if istable(train.ClientEnts) then
                    local prop = train.ClientEnts[name]
                    if IsValid(prop) then
                        prop:SetNoDraw(data.oldNoDraw or false)
                        prop:SetRenderOrigin(nil)
                        prop:SetRenderAngles(nil)
                    end
                end
            end
        end

        RestoreDamageNativeHidden(train)

        train.MEXDamageV4ServerDetached = nil
        train.MEXDamageV4DetachPending = nil
        train.MEXDamageDisabledLights = {}
        train.MEXDamageDisabledButtonIDs = {}
        train.MEXDamageDeadBindings = {}
    end

    net.Receive("MEX.ComponentDetached", function()
        local train = net.ReadEntity()
        local name = net.ReadString()
        local debris = net.ReadEntity()

        if not IsSubwayTrain(train) or not isstring(name) then return end

        MarkDetachedClient(train, name, debris)

        surface.PlaySound(
            "physics/metal/metal_solid_impact_hard5.wav"
        )
    end)

    net.Receive("MEX.DetachReset", function()
        local train = net.ReadEntity()
        if not IsSubwayTrain(train) then return end

        RestoreDetachedComponents(train)
        RestoreBrokenGlassMaterials(train)

        -- Rebuild a clean per-wagon panel copy on the next damage update.
        RestoreInteractivePanels(train)
        train.MEXDamageV4PanelProps = nil
        train.MEXDamageV4PropCache = nil
    end)

    ---------------------------------------------------------------------------
    -- Bone deformation
    ---------------------------------------------------------------------------

    local function ToTrainLocalAngle(train, worldAng)
        local _, localAng = WorldToLocal(
            vector_origin,
            worldAng,
            vector_origin,
            train:GetAngles()
        )
        return localAng
    end

    -- Extra plastic front-end crumpling for weighted bones.
    --
    -- The continuous deformation field above keeps panels/props aligned with
    -- the damaged body. This layer deliberately acts only on bone matrices and
    -- adds the irregular folding you expect from a crumple zone: neighbouring
    -- bones do not all translate by the same amount, so a sufficiently rigged
    -- model develops a dent/crease instead of looking like a rigid front mask
    -- that was merely pushed backwards.
    local function FrontBonePlasticDeformation(
        ent,
        bone,
        trainLocalPos,
        state,
        strength
    )
        local damage = state and state.front or 0
        if damage <= 0.015 then
            return vector_origin, angle_zero
        end

        local surfaceX = state.maxs.x
        local depth = surfaceX - trainLocalPos.x

        -- Keep early damage in the sacrificial end structure. Only severe
        -- crashes are allowed to propagate into the cab survival space.
        local severe = math.Clamp((damage - 0.42) / 0.58, 0, 1)
        local reach = 72 + damage * 112 + severe * 92

        if depth < -10 or depth > reach then
            return vector_origin, angle_zero
        end

        local hit = state.hits.front
        local axial = Smooth01(
            1 - math.Clamp(depth / math.max(reach, 1), 0, 1)
        )

        local radiusY = 46 + damage * 42 + severe * 18
        local radiusZ = 48 + damage * 44 + severe * 18
        local dy = (trainLocalPos.y - hit.y) / math.max(radiusY, 1)
        local dz = (trainLocalPos.z - hit.z) / math.max(radiusZ, 1)
        local radial = Smooth01(
            1 - math.Clamp(dy * dy + dz * dz, 0, 1)
        )

        local influence = axial * radial
        if influence <= 0.0001 then
            return vector_origin, angle_zero
        end

        -- Stable per-bone phase. util.CRC gives us deterministic "material
        -- imperfection" without any frame-to-frame random jitter.
        local boneName = ent:GetBoneName(bone) or tostring(bone)
        local hash = tonumber(util.CRC(
            tostring(ent:GetModel()) .. ":" .. boneName .. ":" .. bone
        )) or bone * 977
        local phase = (hash % 6283) / 1000
        local phase2 = (math.floor(hash / 17) % 6283) / 1000

        local plastic = Smooth01(
            math.Clamp((damage - 0.08) / 0.92, 0, 1)
        )
        local foldStart = Smooth01(
            math.Clamp((damage - 0.24) / 0.76, 0, 1)
        )

        -- Primary permanent crush. This is additional to AddEndCrush(), but is
        -- restricted to weighted bones so the visible sheet metal can wrinkle
        -- while ButtonMaps and rigid attachments still follow the smoother
        -- structural field.
        local crush = (3 + damage * 26 + severe * 24)
            * influence
            * plastic
            * (tonumber(strength) or 1)

        local displacement = Vector(-crush, 0, 0)

        -- Pull material towards the impact centre, then add alternating folds
        -- around the crush boundary. Multiple bones therefore form a shallow
        -- "accordion" rather than collapsing as one flat plane.
        displacement.y = displacement.y
            + (hit.y - trainLocalPos.y)
                * (0.025 + damage * 0.045)
                * influence
                * plastic

        displacement.z = displacement.z
            + (hit.z - trainLocalPos.z)
                * (0.020 + damage * 0.035)
                * influence
                * plastic

        local depth01 = math.Clamp(depth / math.max(reach, 1), 0, 1)
        local crease = math.exp(
            -((depth01 - (0.28 + damage * 0.12))
                / (0.13 + damage * 0.04)) ^ 2
        ) * radial * foldStart

        local yEdge = math.Clamp(
            (trainLocalPos.y - state.center.y)
                / math.max(state.halfWidth, 1),
            -1,
            1
        )
        local zEdge = math.Clamp(
            (trainLocalPos.z - state.center.z)
                / math.max(state.halfHeight, 1),
            -1,
            1
        )

        local foldWave = math.sin(depth01 * math.pi * 4.2 + phase)
        local foldWave2 = math.sin(depth01 * math.pi * 3.1 + phase2)

        displacement.x = displacement.x
            - math.abs(foldWave) * crease * (1.5 + damage * 5.5)

        displacement.y = displacement.y
            - yEdge * crease * (2 + damage * 7)
            + foldWave * crease * (1.1 + damage * 3.4)

        displacement.z = displacement.z
            - zEdge * crease * (1.6 + damage * 5.2)
            + foldWave2 * crease * (0.9 + damage * 2.8)

        -- Off-centre hits twist the crushed nose towards the contact point.
        -- Small deterministic per-bone rotation makes adjacent weighted
        -- sections buckle at slightly different angles.
        local offY = math.Clamp(
            (hit.y - state.center.y) / math.max(state.halfWidth, 1),
            -1,
            1
        )
        local offZ = math.Clamp(
            (hit.z - state.center.z) / math.max(state.halfHeight, 1),
            -1,
            1
        )

        local rotation = Angle(
            (-offZ * (2 + damage * 8) + foldWave2 * damage * 2.3)
                * influence
                * plastic,
            (offY * (3 + damage * 10) + foldWave * damage * 2.8)
                * influence
                * plastic,
            (foldWave - foldWave2)
                * crease
                * damage
                * 3.2
        )

        return displacement, rotation
    end

    local function InstallBoneField(
        modelEnt,
        train,
        skipRoot,
        strength
    )
        if not IsValid(modelEnt) or not IsValid(train) then return end
        strength = tonumber(strength) or 1
        if modelEnt.MEXDamageV4BoneCallback then return end

        modelEnt.MEXDamageV4BoneCallback = modelEnt:AddCallback(
            "BuildBonePositions",
            function(ent, boneCount)
                if not IsValid(train) then return end

                local state = BuildDamageState(train)
                if not state or boneCount <= 0 then return end

                for bone = 0, boneCount - 1 do
                    if skipRoot and bone == 0 then continue end
                    if ent:GetBoneName(bone) == "__INVALIDBONE__" then continue end

                    local matrix = ent:GetBoneMatrix(bone)
                    if not matrix then continue end

                    local worldPos = matrix:GetTranslation()
                    if not IsFiniteVector(worldPos) then continue end

                    local trainLocalPos = train:WorldToLocal(worldPos)
                    local baseDeformed = DeformLocalPointStrength(
                        trainLocalPos,
                        state,
                        strength
                    )
                    local displacement = baseDeformed - trainLocalPos

                    local plasticOffset, plasticRotation =
                        FrontBonePlasticDeformation(
                            ent,
                            bone,
                            trainLocalPos,
                            state,
                            strength
                        )

                    displacement:Add(plasticOffset)

                    if displacement:LengthSqr() < 0.0025
                        and math.abs(plasticRotation.p) < 0.01
                        and math.abs(plasticRotation.y) < 0.01
                        and math.abs(plasticRotation.r) < 0.01
                    then
                        continue
                    end

                    local worldAng = matrix:GetAngles()
                    local trainLocalAng = ToTrainLocalAngle(train, worldAng)
                    local deformedPos = trainLocalPos + displacement
                    local deformedAng = DeformLocalAngleStrength(
                        trainLocalPos,
                        trainLocalAng,
                        state,
                        strength
                    )

                    -- Apply the local plastic fold after the smooth structural
                    -- orientation so it behaves like permanent buckling rather
                    -- than changing the whole attachment coordinate system.
                    deformedAng.p = deformedAng.p + plasticRotation.p
                    deformedAng.y = deformedAng.y + plasticRotation.y
                    deformedAng.r = deformedAng.r + plasticRotation.r

                    matrix:SetTranslation(train:LocalToWorld(deformedPos))
                    matrix:SetAngles(train:LocalToWorldAngles(deformedAng))
                    ent:SetBoneMatrix(bone, matrix)
                end
            end
        )
    end

    local function CheckFrontBoneCapability(train)
        if not IsValid(train) or train.MEXDamageV4BoneCapabilityChecked then return end

        train.MEXDamageV4BoneCapabilityChecked = true
        train:SetupBones()

        local count = train:GetBoneCount() or 0
        local frontBones = 0
        local maxX = train:OBBMaxs().x

        for bone = 1, math.max(count - 1, 0) do
            if train:GetBoneName(bone) == "__INVALIDBONE__" then continue end

            local matrix = train:GetBoneMatrix(bone)
            if not matrix then continue end

            local localPos = train:WorldToLocal(matrix:GetTranslation())
            if localPos.x >= maxX - 140 then
                frontBones = frontBones + 1
            end
        end

        train.MEXDamageV4BodyBoneCount = count
        train.MEXDamageV4FrontBoneCount = frontBones

        if count <= 1 or frontBones == 0 then
            print(string.format(
                "[Metrostroi Expanded/Damage] %s: stock body model %s has no usable non-root bones near the front; using main-body vertex mesh fallback for front deformation.",
                train:GetClass(),
                tostring(train:GetModel())
            ))
        end
    end

    local function InstallTrainBoneField(train)
        if not IsValid(train) then return end
        CheckFrontBoneCapability(train)
        InstallBoneField(train, train, true, 1.12)
    end

    ---------------------------------------------------------------------------
    -- Main body mesh fallback
    --
    -- Many stock Metrostroi bodies (notably 81-717/714) are effectively rigid:
    -- the visible nose is part of the main MDL and has no useful weighted
    -- front bones. In that case moving mask_* ClientProps cannot visibly dent
    -- the carbody because the undeformed body remains behind them.
    --
    -- Build a deformed copy of the main visual mesh when front damage exists.
    -- This keeps the normal bone path for properly rigged models, but gives
    -- rigid stock bodies a real local front crumple instead of a translated
    -- front accessory.
    ---------------------------------------------------------------------------

    local function DestroyMainBodyDamageMesh(train)
        if not IsValid(train) then return end

        local data = train.MEXDamageMainBodyMesh
        if istable(data) and istable(data.parts) then
            for _, part in ipairs(data.parts) do
                if part.mesh and part.mesh:IsValid() then
                    part.mesh:Destroy()
                end
            end
        end

        train.MEXDamageMainBodyMesh = nil
        train.MEXDamageMainBodyMeshKey = nil
    end

    local function RestoreMainBodyRender(train)
        if not IsValid(train) then return end

        DestroyMainBodyDamageMesh(train)

        if train.MEXDamageRenderOverrideCaptured then
            train.RenderOverride = train.MEXDamageOriginalRenderOverride
        end

        train.MEXDamageOriginalRenderOverride = nil
        train.MEXDamageRenderOverrideCaptured = nil
        train.MEXDamageMeshOverrideInstalled = nil
    end

    local function MainBodyBodygroupMask(train)
        if not IsValid(train) then return 0 end

        local groups = train:GetBodyGroups()
        if not istable(groups) or #groups == 0 then
            return 0
        end

        local maxID = 0
        for _, group in ipairs(groups) do
            if istable(group) then
                maxID = math.max(maxID, tonumber(group.id) or 0)
            end
        end

        local digits = {}
        for id = 0, maxID do
            digits[#digits + 1] = tostring(
                math.Clamp(train:GetBodygroup(id) or 0, 0, 9)
            )
        end

        return table.concat(digits)
    end

    local function MainBodyMeshFallbackWanted(train, state)
        if not IsValid(train) or not state then return false end

        local frontCrushEnergy =
            istable(state.crush)
                and (state.crush.front or 0)
                or (state.front or 0)
        local overallCrushEnergy =
            istable(state.crush)
                and (state.crush.overall or frontCrushEnergy)
                or frontCrushEnergy

        if frontCrushEnergy <= 0.008
            and overallCrushEnergy < 1.05
        then
            return false
        end
        if not util or not isfunction(util.GetModelMeshes) then return false end

        local model = string.lower(train:GetModel() or "")
        local className = string.lower(train:GetClass() or "")

        -- Force the fallback for the 81-717/714 family: their visible outer
        -- shell is mostly in the rigid main MDL even though several separate
        -- mask/cab ClientProps exist.
        if string.find(model, "/81-717/", 1, true)
            or string.find(className, "81-717", 1, true)
            or string.find(className, "81-714", 1, true)
        then
            return true
        end

        -- Any train may enter the scrap phase even if its stock body has bones:
        -- vertex deformation is what lets the complete shell keep collapsing
        -- beyond the authored rig's limited range.
        if frontCrushEnergy >= 0.35
            or overallCrushEnergy >= 1.05
        then
            return true
        end

        -- Otherwise use it for rigid bodies with no usable front-region bones.
        return (train.MEXDamageV4FrontBoneCount or 0) <= 0
    end

    local function DeformMainBodyMeshPoint(localPos, state)
        return DeformFrontVisualPointStrength(localPos, state, 1)
    end

    local function CopyDeformedMeshVertex(vertex, state)
        local copy = {}
        for key, value in pairs(vertex) do
            copy[key] = value
        end

        if isvector(vertex.pos) then
            copy.pos = DeformMainBodyMeshPoint(vertex.pos, state)

            if isvector(vertex.normal) then
                local normalEnd = DeformMainBodyMeshPoint(
                    vertex.pos + vertex.normal * 2,
                    state
                )
                local normal = normalEnd - copy.pos
                if normal:LengthSqr() > 0.0001 then
                    normal:Normalize()
                    copy.normal = normal
                end
            end
        end

        return copy
    end

    local function DrawMainBodyDamageMesh(train, flags)
        local data = train.MEXDamageMainBodyMesh
        if not istable(data)
            or not istable(data.parts)
            or #data.parts == 0
        then
            -- Defensive fallback. DrawModel is valid inside RenderOverride.
            train:DrawModel(flags)
            return
        end

        local matrix = Matrix()
        matrix:SetAngles(train:GetAngles())
        matrix:SetTranslation(train:GetPos())

        local color = train:GetColor()
        render.SetColorModulation(
            color.r / 255,
            color.g / 255,
            color.b / 255
        )
        render.SetBlend(color.a / 255)

        cam.PushModelMatrix(matrix)

        for _, part in ipairs(data.parts) do
            if part.mesh and part.mesh:IsValid() and part.material then
                render.SetMaterial(part.material)
                part.mesh:Draw()
            end
        end

        cam.PopModelMatrix()

        render.SetColorModulation(1, 1, 1)
        render.SetBlend(1)
    end

    local function BuildMainBodyDamageMesh(train, state)
        if not MainBodyMeshFallbackWanted(train, state) then
            RestoreMainBodyRender(train)
            return false
        end

        local model = train:GetModel()
        if not isstring(model) or model == "" then
            return false
        end

        local skin = train:GetSkin() or 0
        local bodygroups = MainBodyBodygroupMask(train)
        local hit = state.hits.front

        local key = string.format(
            "%s|%d|%s|%.4f|%.4f|%.2f|%.2f|%.2f",
            model,
            skin,
            tostring(bodygroups),
            istable(state.crush)
                and (state.crush.front or state.front or 0)
                or (state.front or 0),
            istable(state.crush)
                and (state.crush.overall or state.crush.front or 0)
                or (state.front or 0),
            hit.x,
            hit.y,
            hit.z
        )

        if train.MEXDamageMainBodyMeshKey == key
            and istable(train.MEXDamageMainBodyMesh)
        then
            return true
        end

        local ok, visualMeshes = pcall(
            util.GetModelMeshes,
            model,
            0,
            bodygroups,
            skin
        )

        -- Some workshop models use bodygroup layouts that cannot be expressed
        -- by the compact string accepted by util.GetModelMeshes. A deformed
        -- default-bodygroup mesh is still much better than silently disabling
        -- the entire crumple fallback.
        if not ok or not istable(visualMeshes) or #visualMeshes == 0 then
            ok, visualMeshes = pcall(
                util.GetModelMeshes,
                model,
                0,
                0,
                skin
            )
        end

        if not ok or not istable(visualMeshes) or #visualMeshes == 0 then
            train.MEXDamageMainBodyMeshFailed = true
            return false
        end

        local newParts = {}
        local MAX_VERTICES = 65535

        for _, meshData in ipairs(visualMeshes) do
            local triangles = meshData.triangles
            if not istable(triangles) or #triangles < 3 then
                continue
            end

            local materialName = isstring(meshData.material)
                and meshData.material
                or "models/debug/debugwhite"
            local material = Material(materialName)

            local cursor = 1
            while cursor <= #triangles do
                local remaining = #triangles - cursor + 1
                local count = math.min(remaining, MAX_VERTICES)

                -- Mesh triangles must always be complete triplets.
                count = count - (count % 3)
                if count < 3 then break end

                local chunk = {}
                for i = 0, count - 1 do
                    chunk[#chunk + 1] = CopyDeformedMeshVertex(
                        triangles[cursor + i],
                        state
                    )
                end

                local meshObject = Mesh()
                local built = pcall(
                    meshObject.BuildFromTriangles,
                    meshObject,
                    chunk
                )

                if not built then
                    if meshObject and meshObject:IsValid() then
                        meshObject:Destroy()
                    end

                    for _, part in ipairs(newParts) do
                        if part.mesh and part.mesh:IsValid() then
                            part.mesh:Destroy()
                        end
                    end

                    return false
                end

                newParts[#newParts + 1] = {
                    mesh = meshObject,
                    material = material,
                }

                cursor = cursor + count
            end
        end

        if #newParts == 0 then
            return false
        end

        DestroyMainBodyDamageMesh(train)

        train.MEXDamageMainBodyMesh = {
            parts = newParts,
            model = model,
            skin = skin,
            bodygroups = bodygroups,
        }
        train.MEXDamageMainBodyMeshKey = key

        if not train.MEXDamageRenderOverrideCaptured then
            train.MEXDamageOriginalRenderOverride = train.RenderOverride
            train.MEXDamageRenderOverrideCaptured = true
        end

        train.RenderOverride = DrawMainBodyDamageMesh
        train.MEXDamageMeshOverrideInstalled = true
        train.MEXDamageMainBodyMeshFailed = nil

        if not train.MEXDamageMeshFallbackAnnounced then
            train.MEXDamageMeshFallbackAnnounced = true
            print(string.format(
                "[Metrostroi Expanded/Damage] main-body crumple mesh active for %s (%s), %d render parts",
                tostring(train:GetClass()),
                tostring(model),
                #newParts
            ))
        end

        return true
    end

    ---------------------------------------------------------------------------
    -- Front structural ClientEnt vertex deformation
    --
    -- 81-717 front masks are separate rigid ClientProps. Moving them as one
    -- object leaves the most visible part of the nose perfectly flat. Build a
    -- deformed mesh for those large front shells using the exact same train-
    -- local deformation field as the main body.
    ---------------------------------------------------------------------------

    local function DestroyClientPropDamageMesh(prop)
        if not IsValid(prop) then return end

        local data = prop.MEXDamageVertexMesh
        if istable(data) and istable(data.parts) then
            for _, part in ipairs(data.parts) do
                if part.mesh and part.mesh:IsValid() then
                    part.mesh:Destroy()
                end
            end
        end

        prop.MEXDamageVertexMesh = nil
        prop.MEXDamageVertexMeshKey = nil
    end

    RestoreClientPropDamageMesh = function(prop)
        if not IsValid(prop) then return end

        DestroyClientPropDamageMesh(prop)

        if prop.MEXDamageVertexRenderCaptured then
            prop.RenderOverride =
                prop.MEXDamageOriginalVertexRenderOverride
        end

        prop.MEXDamageOriginalVertexRenderOverride = nil
        prop.MEXDamageVertexRenderCaptured = nil
        prop.MEXDamageVertexOverrideInstalled = nil
        prop.MEXDamageVertexOwner = nil
    end

    local function ClientPropBodygroupMask(prop)
        if not IsValid(prop) then return 0 end

        local groups = prop:GetBodyGroups()
        if not istable(groups) or #groups == 0 then return 0 end

        local maxID = 0
        for _, group in ipairs(groups) do
            if istable(group) then
                maxID = math.max(maxID, tonumber(group.id) or 0)
            end
        end

        local digits = {}
        for id = 0, maxID do
            digits[#digits + 1] = tostring(
                math.Clamp(prop:GetBodygroup(id) or 0, 0, 9)
            )
        end

        return table.concat(digits)
    end

    local function ShouldVertexDeformClientProp(
        name,
        cached,
        state
    )
        if not cached or not state then return false end

        local frontCrushEnergy =
            istable(state.crush)
                and (state.crush.front or 0)
                or (state.front or 0)
        local overallCrushEnergy =
            istable(state.crush)
                and (state.crush.overall or frontCrushEnergy)
                or frontCrushEnergy
        local scrapPhase = overallCrushEnergy >= 1.05

        if frontCrushEnergy <= 0.008 and not scrapPhase then
            return false
        end

        local text = string.lower(
            (name or "") .. " " .. (cached.model or "")
        )

        -- Running gear and independent mechanisms must never be stretched
        -- together with the carbody. Interior furniture is different: before
        -- the scrap phase it stays rigid, but during deep crush long seat rows,
        -- handrails and similar assemblies may need vertex deformation so they
        -- cannot remain floating in their original coordinates.
        local alwaysRigid = {
            "bogey", "bogie", "truck", "wheel", "axle",
            "coupler", "autocouple", " сцеп", "pantograph",
            "collector", "compressor", "motor",
        }

        for _, word in ipairs(alwaysRigid) do
            if string.find(text, word, 1, true) then
                return false
            end
        end

        local mechanism = {
            "button", "switch", "toggle", "tumbler", "knob",
            "reverser", "controller", "lever", "valve", "kran",
            "brake_valve", "gauge", "meter", "display",
        }

        if not scrapPhase then
            for _, word in ipairs(mechanism) do
                if string.find(text, word, 1, true) then
                    return false
                end
            end
        end

        local sx = math.abs(cached.size.x)
        local sy = math.abs(cached.size.y)
        local sz = math.abs(cached.size.z)
        local largest = math.max(sx, sy, sz)
        local secondLargest = sx + sy + sz
            - largest
            - math.min(sx, sy, sz)

        -- Ignore tiny detail props. Everything sheet-like / shell-sized is a
        -- candidate regardless of addon-specific naming convention.
        if largest < 46 or secondLargest < 18 then
            return false
        end

        local isDoorLike =
            string.find(text, "door", 1, true)
            or string.find(text, "dver", 1, true)

        if isDoorLike and overallCrushEnergy < 1.25 then
            return false
        end

        local structuralName =
            cached.structural
            or cached.cabin
            or cached.glass
            or string.find(text, "body", 1, true)
            or string.find(text, "shell", 1, true)
            or string.find(text, "mask", 1, true)
            or string.find(text, "cabin", 1, true)
            or string.find(text, "cabine", 1, true)
            or string.find(text, "interior", 1, true)
            or string.find(text, "salon", 1, true)
            or string.find(text, "roof", 1, true)
            or string.find(text, "wall", 1, true)
            or string.find(text, "side", 1, true)
            or string.find(text, "panel", 1, true)
            or string.find(text, "door", 1, true)
            or string.find(text, "window", 1, true)
            or string.find(text, "glass", 1, true)
            or string.find(text, "seat", 1, true)
            or string.find(text, "couch", 1, true)
            or string.find(text, "bench", 1, true)
            or string.find(text, "chair", 1, true)
            or string.find(text, "handrail", 1, true)
            or string.find(text, "handler", 1, true)
            or string.find(text, "interior", 1, true)
            or string.find(text, "salon", 1, true)

        local depth = state.maxs.x - cached.anchorPos.x

        if not scrapPhase then
            local reach =
                135
                + math.min(frontCrushEnergy, 1) * 220
                + math.max(frontCrushEnergy - 1, 0) * 240

            if depth < -55 or depth > reach then
                return false
            end

            -- Ordinary deformation is still local to the damaged front.
            return structuralName and true or false
        end

        -- Scrap phase is deliberately whole-wagon: large shell pieces can be
        -- vertex-deformed even far from the original impact point.
        if cached.fullLength then
            return structuralName and true
                or overallCrushEnergy >= 1.8
        end

        return structuralName
            or largest >= 82
            or (largest >= 62 and secondLargest >= 36)
    end

    local function PropVertexToTrainLocal(cached, vertexPos)
        local trainPos = LocalToWorld(
            vertexPos,
            angle_zero,
            cached.basePos,
            cached.baseAng
        )
        return trainPos
    end

    local function CopyDeformedClientPropVertex(
        vertex,
        cached,
        state,
        strength
    )
        local copy = {}
        for key, value in pairs(vertex) do
            copy[key] = value
        end

        if not isvector(vertex.pos) then return copy end

        local trainPos = PropVertexToTrainLocal(
            cached,
            vertex.pos
        )
        copy.pos = DeformFrontVisualPointStrength(
            trainPos,
            state,
            strength
        )

        -- The generated mesh is rendered directly in train-local space, so its
        -- normal must be converted/deformed into train-local space as well.
        if isvector(vertex.normal) then
            local normalEndTrain = PropVertexToTrainLocal(
                cached,
                vertex.pos + vertex.normal * 2
            )
            normalEndTrain = DeformFrontVisualPointStrength(
                normalEndTrain,
                state,
                strength
            )

            local normal = normalEndTrain - copy.pos
            if normal:LengthSqr() > 0.0001 then
                normal:Normalize()
                copy.normal = normal
            end
        end

        return copy
    end

    local function DrawClientPropDamageMesh(prop)
        local data = prop.MEXDamageVertexMesh
        local train = prop.MEXDamageVertexOwner

        if not IsValid(train)
            or not istable(data)
            or not istable(data.parts)
            or #data.parts == 0
        then
            prop:DrawModel()
            return
        end

        local matrix = Matrix()
        matrix:SetAngles(train:GetAngles())
        matrix:SetTranslation(train:GetPos())

        local color = prop:GetColor()
        render.SetColorModulation(
            color.r / 255,
            color.g / 255,
            color.b / 255
        )
        render.SetBlend(color.a / 255)

        cam.PushModelMatrix(matrix)

        for _, part in ipairs(data.parts) do
            if part.mesh and part.mesh:IsValid() and part.material then
                render.SetMaterial(part.material)
                part.mesh:Draw()
            end
        end

        cam.PopModelMatrix()

        render.SetColorModulation(1, 1, 1)
        render.SetBlend(1)
    end

    local function BuildClientPropDamageMesh(
        train,
        name,
        prop,
        cached,
        state
    )
        if not ShouldVertexDeformClientProp(
            name,
            cached,
            state
        ) then
            RestoreClientPropDamageMesh(prop)
            return false
        end

        local model = prop:GetModel()
        if not isstring(model) or model == "" then return false end

        local skin = prop:GetSkin() or 0
        local bodygroups = ClientPropBodygroupMask(prop)
        local hit = state.hits.front
        local strength = cached.cabin
            and math.max(
                1.18,
                CabStrengthAtPoint(cached.anchorPos, state)
            )
            or 1

        local key = string.format(
            "%s|%d|%s|%.4f|%.4f|%.2f|%.2f|%.2f|%.3f",
            model,
            skin,
            tostring(bodygroups),
            istable(state.crush)
                and (state.crush.front or state.front or 0)
                or (state.front or 0),
            istable(state.crush)
                and (state.crush.overall or state.crush.front or 0)
                or (state.front or 0),
            hit.x,
            hit.y,
            hit.z,
            strength
        )

        if prop.MEXDamageVertexMeshKey == key
            and istable(prop.MEXDamageVertexMesh)
        then
            return true
        end

        local ok, visualMeshes = pcall(
            util.GetModelMeshes,
            model,
            0,
            bodygroups,
            skin
        )

        if not ok or not istable(visualMeshes) or #visualMeshes == 0 then
            ok, visualMeshes = pcall(
                util.GetModelMeshes,
                model,
                0,
                0,
                skin
            )
        end

        if not ok or not istable(visualMeshes) or #visualMeshes == 0 then
            return false
        end

        local parts = {}
        local MAX_VERTICES = 65535

        for _, meshData in ipairs(visualMeshes) do
            local triangles = meshData.triangles
            if not istable(triangles) or #triangles < 3 then
                continue
            end

            local material = Material(
                isstring(meshData.material)
                    and meshData.material
                    or "models/debug/debugwhite"
            )

            local cursor = 1
            while cursor <= #triangles do
                local remaining = #triangles - cursor + 1
                local count = math.min(remaining, MAX_VERTICES)
                count = count - (count % 3)
                if count < 3 then break end

                local chunk = {}
                for i = 0, count - 1 do
                    chunk[#chunk + 1] =
                        CopyDeformedClientPropVertex(
                            triangles[cursor + i],
                            cached,
                            state,
                            strength
                        )
                end

                local meshObject = Mesh()
                local built = pcall(
                    meshObject.BuildFromTriangles,
                    meshObject,
                    chunk
                )

                if not built then
                    if meshObject and meshObject:IsValid() then
                        meshObject:Destroy()
                    end

                    for _, part in ipairs(parts) do
                        if part.mesh and part.mesh:IsValid() then
                            part.mesh:Destroy()
                        end
                    end

                    return false
                end

                parts[#parts + 1] = {
                    mesh = meshObject,
                    material = material,
                }

                cursor = cursor + count
            end
        end

        if #parts == 0 then return false end

        DestroyClientPropDamageMesh(prop)

        prop.MEXDamageVertexMesh = {
            parts = parts,
            model = model,
        }
        prop.MEXDamageVertexMeshKey = key
        prop.MEXDamageVertexOwner = train

        if not prop.MEXDamageVertexRenderCaptured then
            prop.MEXDamageOriginalVertexRenderOverride =
                prop.RenderOverride
            prop.MEXDamageVertexRenderCaptured = true
        end

        prop.RenderOverride = DrawClientPropDamageMesh
        prop.MEXDamageVertexOverrideInstalled = true

        -- Vertex positions are already expressed in final train-local space.
        -- Any additional SetRenderOrigin/RenderMultiply would double-apply the
        -- deformation.
        prop:SetRenderOrigin(nil)
        prop:SetRenderAngles(nil)
        if prop.MEXDamageMatrixApplied then
            prop:DisableMatrix("RenderMultiply")
            prop.MEXDamageMatrixApplied = nil
        end
        prop.MEXDamageV4RenderMoved = nil

        return true
    end

    ---------------------------------------------------------------------------
    -- Lights follow the same deformed mounting points.
    ---------------------------------------------------------------------------

    local function CloneLights(train)
        if train.MEXDamageV4LightsOriginal then return true end
        if not istable(train.Lights) then return false end

        local original = train.Lights
        local clone = {}

        for id, light in pairs(original) do
            if istable(light) then
                local l = {}
                for k, v in pairs(light) do l[k] = v end

                if isvector(light[2]) then
                    l.MEXDamageBasePos = CopyVector(light[2])
                    l[2] = CopyVector(light[2])
                end
                if isangle(light[3]) then
                    l.MEXDamageBaseAng = CopyAngle(light[3])
                    l[3] = CopyAngle(light[3])
                end

                clone[id] = l
            else
                clone[id] = light
            end
        end

        train.MEXDamageV4LightsOriginal = original
        train.Lights = clone
        return true
    end

    local function ApplyLightDeformation(train, state)
        if not state then
            if train.MEXDamageV4LightsOriginal then
                train.Lights = train.MEXDamageV4LightsOriginal
                train.MEXDamageV4LightsOriginal = nil
            end
            return
        end

        if not CloneLights(train) then return end

        for _, light in pairs(train.Lights) do
            if not istable(light) or not light.MEXDamageBasePos then continue end

            light[2] = DeformMountedPointStrength(
                train,
                light.MEXDamageBasePos,
                state,
                1
            )

            if light.MEXDamageBaseAng then
                light[3] = DeformMountedAngleStrength(
                    train,
                    light.MEXDamageBasePos,
                    light.MEXDamageBaseAng,
                    state,
                    1
                )
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Apply / clear the complete visual deformation
    ---------------------------------------------------------------------------

    local function ShouldFollowDeformedBody(name, cached, state)
        if not cached or not state then return false end

        local text = string.lower(
            (name or "") .. " " .. (cached.model or "")
        )

        local frontCrushEnergy =
            istable(state.crush)
                and (state.crush.front or 0)
                or (state.front or 0)
        local overallCrushEnergy =
            istable(state.crush)
                and (state.crush.overall or frontCrushEnergy)
                or frontCrushEnergy
        local scrapPhase = overallCrushEnergy >= 1.05

        -- Running gear remains attached to the original physics chassis. It is
        -- intentionally excluded from the visual body/interior crush transform.
        local runningGear = {
            "bogey", "bogie", "truck", "wheel", "axle",
            "coupler", "autocouple", " сцеп", "pantograph",
            "collector", "compressor", "motor",
        }

        for _, word in ipairs(runningGear) do
            if string.find(text, word, 1, true) then
                return false
            end
        end

        if scrapPhase then
            -- Once the body enters the whole-wagon scrap phase, every remaining
            -- cabin/saloon fixture must follow it. This deliberately ignores
            -- the old localPiece/fullLength cutoff: a long bench, full seat row,
            -- handrail assembly or cab cabinet must not stay suspended in the
            -- original undamaged coordinates.
            return true
        end

        if cached.localPiece then return true end
        if cached.fullLength then return false end
        if frontCrushEnergy <= 0.001 then return false end

        local depth = state.maxs.x - cached.anchorPos.x
        local reach =
            105
            + math.min(frontCrushEnergy, 1) * 190
            + math.max(frontCrushEnergy - 1, 0) * 220

        -- During the ordinary crash phase only localized front/cab equipment
        -- follows the deformed mount point.
        return depth >= -24
            and depth <= reach
            and math.abs(cached.size.x) < 330
    end

    local function ApplyClientEnts(train, state)
        if not istable(train.ClientEnts) then return end

        local panelMap = train.MEXDamageV4PanelProps or BuildPanelPropMap(train)

        for name, prop in pairs(train.ClientEnts) do
            if not IsValid(prop) then continue end

            if train.MEXDamageV4ServerDetached
                and train.MEXDamageV4ServerDetached[name]
            then
                prop:SetNoDraw(true)
                continue
            end

            if not state then
                ClearClientPropRenderTransform(prop)
                continue
            end

            local cached = CacheClientProp(train, name, prop)
            local panelName = panelMap[name]

            local vertexDeformed = BuildClientPropDamageMesh(
                train,
                name,
                prop,
                cached,
                state
            )

            -- A sufficiently damaged mounting point can release a door or a
            -- small panel control. Its original Metrostroi ClientEnt is hidden
            -- and a physics debris copy takes over.
            if MaybeDetachClientComponent(
                train,
                name,
                prop,
                cached,
                state,
                panelName
            ) then
                continue
            end

            -- Existing bones deform the actual mesh instead of stretching the
            -- complete client entity. Root is skipped because it would move the
            -- whole full-length shell.
            if cached.structural and not vertexDeformed then
                local boneStrength = cached.cabin
                    and math.max(
                        1.22,
                        CabStrengthAtPoint(cached.anchorPos, state)
                    )
                    or 1

                InstallBoneField(
                    prop,
                    train,
                    true,
                    boneStrength
                )
            end

            if not vertexDeformed
                and panelName
                and ApplyPanelAttachment(
                train,
                name,
                prop,
                cached,
                panelName
            ) then
                continue
            end

            if vertexDeformed then
                continue
            end

            if ShouldFollowDeformedBody(name, cached, state) then
                -- Doors, front masks, lamp groups, cab shells and other
                -- localized equipment use the EXACT same deformation field as
                -- the generated main-body mesh. They therefore remain glued to
                -- the crushed shell instead of floating at the old coordinates.
                ApplyRigidAttachment(train, prop, cached, state)
                ApplyLocalStructuralCrushMatrix(
                    train,
                    name,
                    prop,
                    cached,
                    state
                )
            else
                -- Outside the affected region keep untouched models at their
                -- authored transform. In the scrap phase this branch is reached
                -- only for excluded running gear.
                ClearClientPropRenderTransform(prop)
            end
        end
    end

    local function EnforceDetachedVisuals(train)
        if not IsSubwayTrain(train)
            or not istable(train.MEXDamageV4ServerDetached)
            or not istable(train.ClientEnts)
        then
            return
        end

        for name in pairs(train.MEXDamageV4ServerDetached) do
            local prop = train.ClientEnts[name]
            if IsValid(prop) then
                RestoreClientPropDamageMesh(prop)
                prop:SetRenderOrigin(nil)
                prop:SetRenderAngles(nil)
                prop:DisableMatrix("RenderMultiply")
                prop:SetNoDraw(true)
            end
        end
    end

    local function ClearAllVisualDamage(train)
        RestoreInteractivePanels(train)
        ApplyLightDeformation(train, nil)
        RestoreMainBodyRender(train)

        if istable(train.ClientEnts) then
            for _, prop in pairs(train.ClientEnts) do
                if IsValid(prop) then
                    ClearClientPropRenderTransform(prop)
                end
            end
        end

        -- Failure state is independent of deformation state.
        EnforceDisabledButtonHitboxes(train)
        EnforceDetachedVisuals(train)
    end

    local function ApplyCompleteDamage(train)
        if not IsSubwayTrain(train) then return end

        ClearLegacyTransforms(train)

        if not MEXD.IsDeformationEnabled() then
            if not train.MEXDamageDeformationSuppressed then
                ClearAllVisualDamage(train)
                train.MEXDamageDeformationSuppressed = true
            else
                EnforceDisabledButtonHitboxes(train)
                EnforceDetachedVisuals(train)
            end
            return
        end

        train.MEXDamageDeformationSuppressed = nil

        local state = BuildDamageState(train)
        if not state then
            ClearAllVisualDamage(train)
            return
        end

        InstallTrainBoneField(train)
        BuildMainBodyDamageMesh(train, state)
        ApplyPanelDeformation(train, state)

        -- Panel props may be generated after the map was cloned.
        train.MEXDamageV4PanelProps = BuildPanelPropMap(train)

        EnforceDisabledButtonHitboxes(train)
        ApplyClientEnts(train, state)
        ApplyLightDeformation(train, state)
        EnforceDisabledButtonHitboxes(train)
        EnforceDetachedVisuals(train)
    end

    ---------------------------------------------------------------------------
    -- Update timing
    ---------------------------------------------------------------------------

    local nextDamageUpdate = 0

    hook.Add("Think", "MEX.Damage.V4StructuralUpdate", function()
        if CurTime() < nextDamageUpdate then return end
        nextDamageUpdate = CurTime() + 0.02

        for _, train in ipairs(ents.GetAll()) do
            if IsSubwayTrain(train) then
                ApplyCompleteDamage(train)
            end
        end
    end)

    -- Some Metrostroi train classes move client props late in their own Think.
    -- Reapply rigid attachment render transforms immediately before drawing.
    hook.Add("PreDrawOpaqueRenderables", "MEX.Damage.V4OpaqueAttachments", function()
        for _, train in ipairs(ents.GetAll()) do
            if not IsSubwayTrain(train) then continue end

            ReconcileAttachedButtonHitboxes(train)
            EnforceDisabledButtonHitboxes(train)

            if not MEXD.IsDeformationEnabled() then
                continue
            end

            local state = BuildDamageState(train)
            if state then
                ApplyClientEnts(train, state)
            end
        end
    end)

    hook.Add("PreDrawTranslucentRenderables", "MEX.Damage.V4TranslucentAttachments", function()
        for _, train in ipairs(ents.GetAll()) do
            if not IsSubwayTrain(train) then continue end
            if not MEXD.IsDeformationEnabled() then continue end

            local state = BuildDamageState(train)
            if state then
                ApplyClientEnts(train, state)
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Impact visual effects
    ---------------------------------------------------------------------------

    net.Receive("MEX.DamageImpact", function()
        local train = net.ReadEntity()
        local zone = net.ReadString()
        local amount = net.ReadFloat()
        local worldPos = net.ReadVector()
        local normal = net.ReadNormal()

        if not IsValid(train) then return end

        if amount >= 0.14 then
            local dlight = DynamicLight(train:EntIndex())
            if dlight then
                dlight.pos = worldPos
                dlight.r = 255
                dlight.g = 145
                dlight.b = 65
                dlight.brightness = math.Clamp(amount * 3.2, 0.5, 2.7)
                dlight.Decay = 1700
                dlight.Size = math.Clamp(70 + amount * 140, 70, 210)
                dlight.DieTime = CurTime() + 0.08
            end
        end

        if amount >= 0.38 then
            local emitter = ParticleEmitter(worldPos)
            if emitter then
                for i = 1, math.floor(2 + amount * 5) do
                    local particle = emitter:Add(
                        "particle/particle_smokegrenade",
                        worldPos
                    )

                    if particle then
                        particle:SetVelocity(
                            normal * math.Rand(6, 24) + VectorRand() * 7
                        )
                        particle:SetDieTime(math.Rand(0.8, 1.7))
                        particle:SetStartAlpha(math.random(50, 85))
                        particle:SetEndAlpha(0)
                        particle:SetStartSize(math.Rand(4, 8))
                        particle:SetEndSize(math.Rand(16, 28))
                        particle:SetRoll(math.Rand(-180, 180))
                        particle:SetRollDelta(math.Rand(-0.5, 0.5))
                        particle:SetAirResistance(85)
                        particle:SetGravity(Vector(0, 0, math.Rand(4, 10)))
                    end
                end
                emitter:Finish()
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Debug / inspection commands
    ---------------------------------------------------------------------------

    local function GetAimedClientTrain()
        local ply = LocalPlayer()
        if not IsValid(ply) then return nil end

        local trace = ply:GetEyeTrace()
        if trace and IsSubwayTrain(trace.Entity) then
            return trace.Entity
        end

        local seat = ply:GetVehicle()
        if IsValid(seat) then
            local train = seat:GetNW2Entity("TrainEntity")
            if IsSubwayTrain(train) then return train end
        end

        return nil
    end

    concommand.Add("mex_controls_restore", function()
        for _, train in ipairs(ents.GetAll()) do
            if IsSubwayTrain(train) then
                RestoreInteractivePanels(train)
                train.MEXDamageV4PanelProps = nil

                if istable(train.ClientEnts) then
                    for _, prop in pairs(train.ClientEnts) do
                        if IsValid(prop) then
                            ClearClientPropRenderTransform(prop)
                        end
                    end
                end
            end
        end

        chat.AddText(
            Color(120, 255, 120),
            "[Metrostroi Expanded] Visual control layout restored. Detached server components stay disabled until mex_damage_reset."
        )
    end)

    concommand.Add("mex_damage_bones", function()
        local train = GetAimedClientTrain()
        if not IsValid(train) then
            print("[Metrostroi Expanded/Damage] Aim at a Metrostroi train.")
            return
        end

        train:SetupBones()

        print("------------------------------------------------------------")
        print("[Metrostroi Expanded/Damage] Bone dump: " .. train:GetClass())
        print("model: " .. tostring(train:GetModel()))
        CheckFrontBoneCapability(train)
        print("body bones: " .. tostring(train:GetBoneCount()))
        print("front-region non-root bones: " .. tostring(train.MEXDamageV4FrontBoneCount or 0))

        if (train.MEXDamageV4FrontBoneCount or 0) == 0 then
            print("front bone deformation: no usable weighted front-region bone")
            print("main-body mesh fallback: " .. (
                train.MEXDamageMeshOverrideInstalled
                    and "ACTIVE"
                    or "waiting for front damage / unavailable"
            ))
        else
            print("front bone deformation: bone candidates exist (vertex weighting still determines the visible result)")
            print("main-body mesh fallback: " .. (
                train.MEXDamageMeshOverrideInstalled and "ACTIVE" or "not required"
            ))
        end

        for bone = 0, math.max(train:GetBoneCount() - 1, -1) do
            print(string.format(
                "  body [%d] %s parent=%d",
                bone,
                tostring(train:GetBoneName(bone)),
                train:GetBoneParent(bone)
            ))
        end

        if istable(train.ClientEnts) then
            for name, prop in pairs(train.ClientEnts) do
                if not IsValid(prop) then continue end

                local model = string.lower(prop:GetModel() or "")
                if not ModelLooksStructural(name, model) then continue end

                prop:SetupBones()
                print(string.format(
                    "client %s | %s | bones=%d",
                    tostring(name),
                    tostring(prop:GetModel()),
                    prop:GetBoneCount()
                ))

                for bone = 0, math.max(prop:GetBoneCount() - 1, -1) do
                    print(string.format(
                        "    [%d] %s parent=%d",
                        bone,
                        tostring(prop:GetBoneName(bone)),
                        prop:GetBoneParent(bone)
                    ))
                end
            end
        end

        print("------------------------------------------------------------")
    end)

    concommand.Add("mex_damage_mesh_status", function()
        local train = GetAimedClientTrain()
        if not IsValid(train) then
            print("[Metrostroi Expanded/Damage] Aim at a Metrostroi train.")
            return
        end

        local state = BuildDamageState(train)
        print("------------------------------------------------------------")
        print("[Metrostroi Expanded/Damage] mesh deformation status")
        print("class: " .. tostring(train:GetClass()))
        print("model: " .. tostring(train:GetModel()))
        print("version: " .. tostring(MEXD.Version))
        print("front damage: " .. tostring(
            state and state.front or 0
        ))
        print("front crush energy: " .. tostring(
            state
                and istable(state.crush)
                and state.crush.front
                or 0
        ))
        print("overall crush energy: " .. tostring(
            state
                and istable(state.crush)
                and state.crush.overall
                or 0
        ))
        print("body bones: " .. tostring(train:GetBoneCount() or 0))
        print("front bones: " .. tostring(
            train.MEXDamageV4FrontBoneCount or 0
        ))
        print("mesh override: " .. tostring(
            train.MEXDamageMeshOverrideInstalled == true
        ))
        print("mesh build failed: " .. tostring(
            train.MEXDamageMainBodyMeshFailed == true
        ))
        print("mesh parts: " .. tostring(
            istable(train.MEXDamageMainBodyMesh)
                and istable(train.MEXDamageMainBodyMesh.parts)
                and #train.MEXDamageMainBodyMesh.parts
                or 0
        ))

        local vertexProps = {}
        if istable(train.ClientEnts) then
            for name, prop in pairs(train.ClientEnts) do
                if IsValid(prop)
                    and prop.MEXDamageVertexOverrideInstalled
                then
                    vertexProps[#vertexProps + 1] = tostring(name)
                end
            end
        end

        table.sort(vertexProps)
        print("vertex-deformed ClientProps: " .. tostring(#vertexProps))
        if #vertexProps > 0 then
            print("  " .. table.concat(vertexProps, ", "))
        end

        print("------------------------------------------------------------")
    end)

    local debugDamage = CreateClientConVar(
        "mex_damage_debug",
        "0",
        true,
        false,
        "Draw Metrostroi Expanded impact/deformation debug markers"
    )

    hook.Add("PostDrawTranslucentRenderables", "MEX.Damage.V4Debug", function()
        if not debugDamage:GetBool() then return end

        for _, train in ipairs(ents.GetAll()) do
            if not IsSubwayTrain(train) then continue end

            local state = BuildDamageState(train)
            if not state then continue end

            local colors = {
                front = Color(255, 90, 70),
                rear = Color(255, 170, 70),
                left = Color(80, 180, 255),
                right = Color(170, 100, 255),
                roof = Color(255, 235, 90),
                floor = Color(80, 255, 150),
            }

            for _, zone in ipairs({"front", "rear", "left", "right", "roof", "floor"}) do
                local amount = state[zone]
                if amount <= 0.001 then continue end

                local pos = train:LocalToWorld(state.hits[zone])
                render.DrawWireframeSphere(
                    pos,
                    7 + amount * 18,
                    10,
                    8,
                    colors[zone],
                    true
                )
            end
        end
    end)

    hook.Add("EntityRemoved", "MEX.Damage.V4Cleanup", function(ent)
        if not IsSubwayTrain(ent) then return end
        RestoreMainBodyRender(ent)

        if istable(ent.ClientEnts) then
            for _, prop in pairs(ent.ClientEnts) do
                if IsValid(prop) then
                    RestoreClientPropDamageMesh(prop)
                end
            end
        end

        RestoreDetachedComponents(ent)
        RestoreInteractivePanels(ent)
    end)
end
