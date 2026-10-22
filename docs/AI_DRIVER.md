# Metrostroi Expanded — AI Driver integration and train-driving rules

## Architecture: where the Markdown belongs

- **`backend/driver_guide.md`:** model's instructions. Backend sends this file as Ollama
  system prompt, so the AI can read its driving principles. Keep this with the backend.
- **`addon/docs/AI_DRIVER_INTEGRATION.md`:** in-game interfaces, controls, train variants,
  physics, route mapping and test procedures. Keep this in the addon repo.
- **Lua code in addon:** the actual actuator and safety implementation. **A `.md` file
  cannot control the physical train.** The game must never depend on model response
  latency or correctness to apply emergency precautions.

## Installation

Copy the `addon/lua/` tree into `garrysmod/addons/metrostroi-expanded/lua/`.
Do not alter any existing files. The addon adds `mex_ai_driver.lua` and two modules.
Install/start the separate Node backend (see `backend/README.md`).

Requires server-side LuaSocket. No client module and no Python.

### Commands (server console; look at the cab to attach)

```
mex_ai_host 127.0.0.1
mex_ai_port 3002
mex_ai_live 0
mex_ai_attach
mex_ai_status
mex_ai_detach
```

The initial mode **only reads telemetry and gets AI decisions** (`mex_ai_live 0`).
Once you have a proper map route provider and verified KV control, enable `mex_ai_live 1`
using the server console. Live control is intentionally disabled by default.
Only 81-717 variants with compatible KV_70 are enabled in this first implementation.
The train needs battery/control circuits, a present wrench and set reverser in the
appropriate cab **before** enabling the driver. The AI does not prepare the cab.
It will give up control when a human driver is detected.

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