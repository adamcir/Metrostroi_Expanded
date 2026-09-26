# Metrostroi Expanded

**Metrostroi Expanded** is an unofficial open-source expansion for the Garry's Mod addon **Metrostroi Subway Simulator**.

The project is intended to grow into a larger realism/gameplay layer for Metrostroi. The first implemented module is the passenger-seat system.

## Passenger Seats

Current passenger-seat module version: **0.2.0**

It adds usable invisible `models/nova/jeep_seat.mdl` vehicle seats to the real passenger benches without modifying Metrostroi itself.

Supported official Metrostroi release classes include:

- 81-501 / 81-502
- 81-702 / 81-702 int
- 81-703 / 81-703 int
- 81-714 MVM / LVZ
- 81-717 MVM / LVZ
- 81-718 / 81-719
- 81-720 / 81-721
- 81-722 / 81-723 / 81-724
- Em508T
- Ezh / Ezh1 / Ezh3 (81-710)

Compatible third-party and future `gmod_subway_*` trains can also receive seats automatically when they expose Metrostroi's `GetStandingArea()` metadata.

The Tatra T3 entity is intentionally excluded because the current Metrostroi release does not expose enough passenger-saloon metadata to place seats reliably.

### Using a passenger seat

Walk up to a passenger bench, aim at the seat and press **E**.

Press **E** again to leave. The addon moves the player back into the aisle after exiting.

### Commands

- `mps_status` — show number of supported live trains and passenger seats
- `mps_rescan` — rescan already spawned trains
- `mps_debug_seats 1` — show passenger-seat interaction positions
- `mps_debug_seats 0` — hide debug positions


## Damage System

Current damage-system module version: **0.5.2**

Metrostroi Expanded now includes a first simple crash-damage system for all `gmod_subway_*` trains.

It currently provides:

- front, rear, left-side, right-side, roof and underframe/floor structural damage zones
- a **1000 ms spawn grace period** so Metrostroi initialization/coupling is never counted as a crash
- primary crash detection from Garry's Mod `PhysicsCollide`, using the actual contact position and pre-impact relative velocity
- velocity-change detection only as a fallback
- no global whole-wagon `RenderMultiply` scaling
- local front/rear crush, side intrusion and roof/floor contact deformation with a survival-space threshold: light impacts stay near the contact structure, severe impacts can intrude deeper into the cab/salon
- **bone-based mesh deformation** through `BuildBonePositions` + `SetBoneMatrix` wherever the existing MDL has usable weighted bones
- the main train body and structural ClientEnt models use the same deformation field
- full-length salon/interior shells remain at the train origin and may deform only through their own bones, so the entire interior cannot slide away from the carbody
- localized parts such as cab shells, front masks, doors, lamps and similar pieces remain rigid but follow their deformed mounting point
- interactive `ButtonMap` panels are shallow-cloned per wagon (nested Metrostroi runtime tables are not copied) and their generated buttons move with the same rigid panel transform, keeping controls usable
- train lights follow their deformed mounting points
- **server-authoritative breakaway components**: doors, lamps, switches, buttons, handles, brake wheels, covers, seats/fixtures and other localized mounted ClientEnt parts may tear off independently according to local deformation around their own mounting point
- detached components are real networked `mex_damage_debris` physics entities, visible to all players and manipulable with the Physgun/Gravity Gun
- debris physics is always recentered on the visible model geometry instead of the original Metrostroi model origin; this prevents detached parts from appearing to hang in mid-air while an offset collision hull rests on the ground
- combined passenger-door models are split into independent leaf models across the stock door families used by 81-710/Ezh/Em, 81-502, 81-702, 81-703, 81-717/714, 81-718/719, 81-720/721 and 81-722/723/724; addon trains also get a naming-convention fallback for `door_right/door_left` and `door_l/door_r` assets
- each component has a deterministic individual mounting threshold, so a crash can tear off only one nearby button or several components depending on impact location and severity
- **local mounting impacts** from crowbar/melee, bullets, buckshot, crush/vehicle contact and explosions resolve against the real ClientEnt geometry around the hit point; a normal pistol/crowbar hit usually releases only the nearest mounted component
- small controls are prioritized over the backing panel/case at the same hit location, preventing an entire dashboard plate from being selected when the player actually hit one switch/button
- fragile controls now release after very small local structural displacement, instead of travelling away together as one rigid ButtonMap cluster
- detached controls are blocked in the server-side `ButtonEvent` path, so neither mouse clicks nor Metrostroi keyboard shortcuts can operate a control after its physical part has torn off
- **keyboard alias expansion** automatically maps generated ButtonMap IDs back to related KeyMap events (for example `KDLSet` ↔ `KDL`, or pneumatic brake direct positions ↔ up/down events), so every generated button with a shortcut loses that shortcut when its physical control detaches
- standalone brake-valve hardware (`334`, `013`, brake/train/driver-valve disconnect cocks, EPK/EPV valves) is now treated as a control even when it is not a generated ButtonMap prop
- detached standalone controls also search nearby 3D ButtonMap hit targets and remove those local clickable regions; the server guard additionally wraps `OnButtonPress`/`OnButtonRelease`, so direct event paths cannot bypass a destroyed control
- detaching the main KV/GRKV controller blocks `KVUp`, `KVDown` and direct KV position shortcuts; detaching the driver brake valve blocks `PneumaticBrakeUp/Down` and the direct pneumatic-brake positions
- debris captures the component sequence/cycle/`position` pose at the moment of detachment, sets playback rate to zero and remains physically/visually static apart from rigid-body motion
- separate glass/window ClientEnts are treated as fragile components: local impacts can hide the intact pane, play a glass-break effect/sound and spawn physics glass shards
- cab/cabine/pult/panel structural ClientEnts receive a stronger local end deformation field than ordinary interior decorations while still avoiding whole-wagon scaling
- parking/manual-brake controls receive explicit fallback button blocking (`ParkingBrakeToggle`, `ParkingBrakeLeft`, `ParkingBrakeRight`) when their wheel/handle detaches
- detached lamp/headlight assemblies also disable nearby Metrostroi client light sources, preventing an invisible detached lamp from continuing to illuminate the world
- detached button hit targets are removed from the per-wagon panel copy so a button that physically tore off is no longer clickable; the corresponding server ButtonEvent IDs remain disabled until `mex_damage_reset`
- sparks, impact decals and smoke for harder impacts
- structural-health and generic electrical/door/equipment damage states
- `mex_damage_bones` to inspect the actual bone structure of the selected train and its structural ClientEnt models
- `mex_damage_debug 1` to show impact centres

Design notes and the crashworthiness references used for the rewrite are in [docs/DAMAGE_SYSTEM.md](docs/DAMAGE_SYSTEM.md).

The outer skin can only form a true local dent when the compiled Source model has vertices weighted to suitable bones. Version 0.4.2 keeps the stronger local crush/intrusion field from v0.4 while avoiding any global wagon scaling, and detects whether the selected body has non-root bones in the front region and prints a clear warning when true front-sheet denting is not available on the stock MDL. Garry's Mod can change existing bone matrices clientside, but it cannot add new bones/vertex weights to an already compiled MDL at runtime. On a single-root-bone shell, v0.4 deliberately leaves that shell rigid instead of producing the unrealistic stretched/cut-open wagon seen in the old global-scaling versions. For a full BeamNG-style skin on such a model, a locally prepared deformable MDL with additional deformation bones and weights is required.

### Damage test commands

Aim at a Metrostroi train and use:

```text
mex_damage_test front 0.25
mex_damage_test rear 0.25
mex_damage_test left 0.25
mex_damage_test right 0.25
mex_damage_status
mex_damage_reset
```

The amount is from `0.01` to `1.0`.

The module also exposes the `MetrostroiExpandedTrainDamaged` hook so future electrical, pneumatic, bogey and door-failure modules can react to the same crash event.

## Development installation

### Linux

```bash
git clone https://github.com/adamcir/Metrostroi_Expanded.git
cd Metrostroi_Expanded
chmod +x tools/install.sh
./tools/install.sh
```

The Linux installer automatically checks common Steam locations, including:

```text
~/.steam/steam/steamapps/common/GarrysMod
~/.local/share/Steam/steamapps/common/GarrysMod
```

You can also provide the Garry's Mod path explicitly:

```bash
./tools/install.sh /path/to/GarrysMod
```

or:

```bash
GMOD_DIR=/path/to/GarrysMod ./tools/install.sh
```


### Windows

Clone the repository and run:

```bat
tools\install.bat
```

The Windows installer checks the usual Steam installation, Steam registry entries and additional Steam libraries from `libraryfolders.vdf`.

You can also pass the Garry's Mod directory explicitly:

```bat
tools\install.bat "D:\SteamLibrary\steamapps\common\GarrysMod"
```

Or run the PowerShell installer directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install.ps1 "D:\SteamLibrary\steamapps\common\GarrysMod"
```

Both installers copy the addon to:

```text
garrysmod/addons/metrostroi-expanded
```

If the old standalone `metrostroi-passenger-seats` addon is present, the installer removes it to prevent the same passenger-seat module from loading twice.

## Dependency

Metrostroi Expanded requires **Metrostroi Subway Simulator** to be installed separately.

Original Metrostroi code, train models, textures and other assets are not redistributed by this repository and remain under their respective licenses.

## License

Metrostroi Expanded's own source code is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE).


### Damage 0.5.2 fixes

- adds an `OnKeyEvent` guard before Metrostroi can execute `OnKeyPress/OnKeyRelease`, fixing controls such as pneumatic F/R that could react before the existing `ButtonEvent` blocker
- restricts geometry-nearest ButtonMap matching to standalone valve/controller hardware; arbitrary props no longer steal nearby large door hitboxes
- explicitly excludes `FrontDoor`, `RearDoor`, `CabinDoor` and `PassengerDoor` from paired passenger-door leaf splitting; only true `doorNx0/doorNx1` side-door ClientEnts are eligible
