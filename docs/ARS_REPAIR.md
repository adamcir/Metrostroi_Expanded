# MEX ARS / EPK diagnostic and guarded LKT repair

Server file: `lua/autorun/server/mex_ars_repair.lua`. It loads automatically with Metrostroi Expanded; no changes to the base Metrostroi addon are required.

## Why this exists

An ARS-equipped train may refuse to release its brakes at a stop or trigger EPK even though the driver has applied pneumatic braking. The original ARS implementation uses LKT to confirm electric (RKTT) **or** pneumatic (DKPT) braking in **every** wagon. A false LKT state while the brakes are confirmed can lead to a spurious stopped-train EPK action.

Not every EPK application is a software bug. Loss of ALS code, an occupied/blocking signal, disabled ARS, an unconfirmed wagon, a disconnected pneumatic control, an overspeed, an emergency valve, or a legitimate stop can all account for braking. **This module never forcibly releases EPK, removes brake commands, or overrides signals.**

## Commands

Run these in the **server console** (or as an admin in-game):

```text
mex_ars_status 258
mex_ars_status
mex_ars_repair_enabled 1
mex_ars_repair_enabled 0
mex_ars_watch_enabled 1
mex_ars_watch_enabled 0
```

Replace `258` with the current train's entity ID. Without an ID the command prints all ARS-equipped trains and their connected wagons.

A log entry beginning with `[MEX ARS] EPK ACTIVATED` identifies the exact sampled transition from EPK inactive to active, with pressures, valves, relays and ARS status. `[MEX ARS] Repaired false LKT` means the guarded correction actually ran; merely loading the module does **not** mean it found or repaired anything.

## When the repair is permitted

The repair, enabled by default, only corrects a false or missing `LKT` **before the original Moscow/Piter ARS logic uses it** when ALL conditions are satisfied:

1. The same ARS instance is enabled and reports a valid nonzero speed limit and confirmed ALS code.
2. Speed is below 0.25 km/h and the ARS is **not** reporting overspeed.
3. No emergency pneumatic valve (EPK or other) is active.
4. Every wagon in `WagonList` has readable numeric `RKTT` and `DKPT` relay states, and at least one of the two is >= 0.5.
5. The ARS system exposes the relevant runtime state. If its speed or `EnableARS` is `nil`, the module **does not assume** the system is working and does not apply a correction.

The wrapper is attached per train/system instance: it does **not** overwrite Metrostroi's global ARS definition. Turn it off with `mex_ars_repair_enabled 0` to compare behavior without the correction.

## Interpreting pressure readings

`PN2=1` with `BC` around 2.5–2.7 atm means an electropneumatic brake is being held. A brake-valve release can refill `BL` while `BC` stays high if PN2 remains active. **Do not use pressure alone as proof that EPK is discharging.** The transition monitor explicitly reads `EmergencyValveEPK`.

The original Ezh3 Metrostroi variant uses type-013 brake control (`ValveType=2`), where position 5 is a service-brake setting; the source of a particular installed train may differ. A diagnostic result of `ValveType=nil` does not identify the valve model.

## When the behavior persists

Collect `mex_ars_status <ID>` during the problem, including each wagon's DKPT/RKTT and any `[MEX ARS] EPK ACTIVATED` lines. If no correction log appears, investigate the actual ALS/ARS signal or electrical state rather than disabling legitimate safety protection. In custom maps, check signal orientation, track graph, occupancy and `NextSignal` links independently; this module does not rewrite map signaling.
