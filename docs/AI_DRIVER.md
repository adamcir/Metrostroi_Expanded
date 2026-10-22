# Metrostroi Expanded — AI Driver integration and train-driving rules

## Architecture: where the Markdown belongs

- **`tools/ai_driver_backend/driver_guide.md`:** model's instructions. Backend sends this file as Ollama
  system prompt, so the AI can read its driving principles. Keep this with the backend.
- **`docs/AI_DRIVER.md`:** in-game interfaces, controls, train variants,
  physics, route mapping and test procedures. Keep this in the addon repo.
- **Lua code in addon:** the actual actuator and safety implementation. **A `.md` file
  cannot control the physical train.** The game must never depend on model response
  latency or correctness to apply emergency precautions.

## Installation

Install the Metrostroi Expanded addon from this repository. The AI Driver Lua files
are already part of the addon; no manual copying is needed. Install/start the
separate Node backend using `scripts/install_ai_backend.ps1` (Windows) or
`scripts/install_ai_backend.sh` (Linux). Details: `tools/ai_driver_backend/README.md`.

Requires server-side LuaSocket. No client module and no Python.

### Commands (server console; look at the cab to attach)

```
mex_ai_host 127.0.0.1
mex_ai_port 3002
mex_ai_live 0
mex_ai_attach
mex_ai_status
mex_ai_detach
mex_ai_visual_refresh
```

The initial mode **only reads telemetry and gets AI decisions** (`mex_ai_live 0`).
Once you have a proper map route provider and verified KV control, enable `mex_ai_live 1`
using the server console. Live control is intentionally disabled by default.
Only 81-717 variants with compatible KV_70 are enabled in this first implementation.
The train needs battery/control circuits, a present wrench and set reverser in the
appropriate cab **before** enabling the driver. The AI does not prepare the cab.
It will give up control when a human driver is detected.

## Visible driver in the real front cab seat

Attaching `mex_ai_attach` also spawns a **seated, non-solid player-model
representation** at the original Metrostroi cab's `train.DriverSeat`.
The default is `models/player/barney.mdl`: an available blue-uniformed
HL2/GMod character. This is a visual prop, **not** a real player bot, so
Metrostroi's `GetDriver()` still works for detecting human takeovers.
The prop stays parented to the train's actual front driver's jeep seat,
including its cabin movement.

**Critical distinction:** MEX Passenger Seats creates many invisible
`models/nova/jeep_seat.mdl` passenger pods. AI Driver never searches for
a nearest pod. It only accepts `train.DriverSeat` (or the explicit
`seat_driver` NW2 entity) when `SeatType == "driver"`,
`TrainEntity == train`, and `MPS.PassengerSeat` is false.
No existing passenger or instructor seat is used, moved, or replaced.

The operator is cleaned up on `mex_ai_detach`, human entering the cab,
train deletion, and Lua reload. No extra vehicle seat is created.
It appears even with `mex_ai_live 0`, so you can inspect it safely.

Customize via the **server console**:

```text
mex_ai_visual 1
mex_ai_driver_model models/player/barney.mdl
mex_ai_operator_x -30
mex_ai_operator_y 0
mex_ai_operator_z -12
mex_ai_operator_yaw 0
mex_ai_visual_refresh
```

To calibrate the sitting position, aim at the attached cab when running
`mex_ai_visual_refresh`. Offsets are in the **train's coordinates**, measured from the original
front driver seat anchor (not the pod's rotated local axes). The new
defaults move the operator about 30 Source units back and 14 units up
relative to the first version; this fixes the avatar clipping through
the panel seen in the October 22 screenshot. Calibration in the actual
in-game cabin may still be needed. The model needs
a compatible player skeleton and a sitting sequence such as
`sit_rollercoaster`. Unsupported/custom models without a seated
animation are removed rather than displayed standing in the cab.
`mex_ai_visual 0` hides the operator at the next update.
The operator is not a physical occupant of the jeep pod: this avoids
fake-player interference with the actual GMod vehicle driver logic.
It cannot manually press cab buttons; the separate KV controller handles
train control when explicitly enabled and route information is available.

## First train adapter (verified against published Metrostroi KV_70 code)

`train.KV:TriggerInput("ControllerSet", n)` with:

| n | Meaning |
| ---: | --- |
| -3 | T2 (stronger electrical braking) |
| -2 | T1A |
| -1 | T1 |
| 0 | Coast / zero |
| 1 | X1 |
| 2 | X2 |
| 3 | X3 |

The system may ignore controls if KV is disabled or the reverser is at zero.
The controller deliberately never forces these prerequisites to ON.
`train.Speed` and `train.ALS_ARS.SpeedLimit` are used for telemetry.
Pneumatic braking, doors, passenger exchange, damage adaptation and other cabs
are **not implemented** in this version.

## Required route-sensing contract

Attach a server-side hook from a **real track graph / sign registry**:

```lua
hook.Add("MEXAIDriverRouteState", "MEX_RealRouteState", function(train)
    -- Example contract only. Replace each value with verified track geometry data.
    -- If a real graph/route is not available, return { known = false }.
    local route = MyTrackNavigation and MyTrackNavigation.GetForwardState(train)
    if not route then return { known = false } end
    return route
end)
```

The returned object has this shape:

```lua
return {
    known = true,
    current_limit_kmh = 80,
    traction_allowed = true,       -- set by the route provider after motor-on sign
    brake_prepare_active = false,  -- latch after brake-preparation sign
    next_sign = { kind = "SPEED_LIMIT", value_kmh = 40, distance_m = 150 },
    signal = { aspect = "GREEN", distance_m = 300 },
    stop_distance_m = 700
}
```

**These are illustrative values, not a production implementation.** Track Builder
and imported Metrostroi route graphs do not automatically expose this contract.
It requires actual integration with the geometry/point registry. Use distances
along the selected forward path, following curves/switches, never Euclidean
entity distances. The system refuses to accelerate when `known = false`.

Signal kinds:
`SPEED_LIMIT`, `BRAKE_PREPARE`, `TRACTION_ALLOWED`, `TRACTION_OFF`.
Aspects: `RED`, `YELLOW`, `GREEN`, `UNKNOWN`.
`BRAKE_PREPARE` marks starting service braking: the route provider must latch
`brake_prepare_active = true` after passing it and clear it after the stop.
`TRACTION_ALLOWED`/`TRACTION_OFF` update `traction_allowed` when passed.
These sign states must come from actual route events, not AI guesses.
`BRAKE_PREPARE` is not a station stopping point; provide the real stop marker
separately (`stop_distance_m`). All values are advisory input and validated.

## Controller policy (currently implemented)

Every 0.1 s, the addon recomputes a conservative braking speed envelope:

`v_allowed = sqrt(v_target^2 + 2 * a * max(0, distance - margin))`

with `a = 0.75 m/s²`, `margin = 15 m` (initial *simulator tuning* values).
The chosen limit is the minimum of current sign limit, ARS, and any ahead
speed/stop restrictions. Unsafe accelerations are blocked even if Ollama
produces a wrong or stale suggestion. Response TTL = 4 seconds.
If AI goes offline, it requests service braking through the supported KV;
this is **not a guaranteed emergency stop** for damaged/unsupported trains.

## Before driving live

1. Confirm backend and LuaSocket work via `mex_ai_status` while live is off.
2. Implement accurate graph/sign positioning (hook above). No fabricated signage.
3. Verify `route.known`, ARS, directions and passenger door status.
4. Use an isolated test map and one prepared 81-717, first at low speed.
5. Calibrate the deceleration and braking margin for the train and load.
6. Test stop sign, 40 km/h sign, communication loss and manual takeover.
7. Only after these checks, set `mex_ai_live 1` on the server.

Do not assume integration with a real route exists just because the backend runs.
## Chat, control of lights and ARS-only first driving mode

Player chat commands are prefixed with `!mexai` or `/mexai`. Only admins
can change train controls. Players can communicate with the assigned operator
while aiming at its 81-717 cab or standing near the **front** cab seat.

Examples:

```text
!mexai prevezmi
!mexai jed misto me
!mexai jed do Centralni
!mexai priprav
!mexai zastav
!mexai pokracuj
!mexai ars
!mexai stav
!mexai svetla pult zapni
!mexai svetla kabina vypni
!mexai svetla salon zapni
!mexai svetla svetlomety vypni
!mexai proc stojime?
```

`prevezmi`: if the human is **in the front driver seat**, take-over
will be queued for 30 seconds. The player must exit first. AI never
shares or overrides an occupied cab. After exiting, attach is completed
automatically. The visual operator is a nonphysical avatar and does not
occupy a GMod seat itself. `priprav` is live-only and stopped-only:
sets the original 81-717 driver KV wrench and forward reverser through
Metrostroi input methods; it does not force power, override ARS or open
doors. To actually move the train, battery/circuits and other manual
prerequisites must already be valid.

`jed do ...` records the destination and explicitly reports that
routing cannot proceed without a genuine navigable track map and
station stop marker. **This is not a working destination autopilot yet.**
`zastav` requests controlled braking; `pokracuj` clears the stop
request, subject to all route, ARS, live mode and speed restrictions.

`ars` prints live data from the actual `train.ALS_ARS` system. The
**ОЧ / OCh lamp is the "no ARS frequency" indicator**, NOT a button.
When no frequency is reported, the safety envelope goes to **0 km/h**.
The AI cannot fake illumination of OCh or another safety indication.
`L_1` (saloon), `L_2` (cab), `L_3` (panel) and `L_4` (headlights)
are real Metrostroi switch systems. Chat commands actuate the game's
own `ButtonEvent` toggle; MEX never calls `SetPackedBool` to paint an
artificial lamp state. The switch state may remain off if train power is
unavailable. No human driver may be in the seat when AI uses switches.

**Read-only freeform chat** not matching a direct command goes to
Ollama over the existing TCP bridge (`chat_guide.md`), with its own
JSON `say` reply. The model is not allowed to issue hardware orders
through chat. After changing `chat_guide.md` in the repository,
run the backend installation script again to install it.

**Experimental ARS-only mode** lets the basic KV controller be tested
on an unannotated map, using only known ARS signal values, at a hard cap
of **15 km/h**. It cannot navigate to stations or see signs ahead.
This mode is OFF by default and must be explicitly enabled, together
with live control, on a private test server:

```text
mex_ai_ars_only 1
mex_ai_live 1
```

The ARS/ALS systems must be enabled with a valid nonzero ARS speed limit,
no OCh/no frequency, doors closed, and the cab prepared. If OCh or ARS
0 occurs, the controller requests braking, rather than bypassing any
interlock. Disable it after testing with `mex_ai_ars_only 0`.
The KV electric braking model is not an assured emergency stop.
Automatic route following and reliable station stops still require
the track graph and brake testing.

