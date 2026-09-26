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

Current damage-system module version: **0.3.1**

Metrostroi Expanded now includes a first simple crash-damage system for all `gmod_subway_*` trains.

It currently provides:

- front, rear, left-side and right-side damage zones
- automatic crash detection from sudden velocity changes
- support for `DMG_CRUSH` and blast damage
- a **1000 ms spawn grace period** so Metrostroi initialization/coupling does not damage a newly spawned train
- persistent per-zone structural damage while the train entity exists
- simple client-side visual crumpling from the damaged direction
- a unified deformation field shared by the **outer carbody, salon/interior, cab equipment, panels and controls**
- Metrostroi `ButtonMap` is deliberately left untouched so all switches/buttons/touchscreens remain fully operable; interactive ClientEnts are kept on their original Metrostroi coordinates while the surrounding body/interior deformation continues
- local impact-centered crumple/dent deformation instead of only scaling the whole wagon
- `BuildBonePositions` deformation for train/interior models with multiple bones, allowing genuinely local bending where the existing MDL rig permits it
- panels, buttons, gauges, handles and other small ClientEnts keep their rigid shape but remain attached to their deformed mounting point
- the ButtonMap is cloned per wagon before deformation, so damaging one train cannot move controls on another train of the same class
- non-accumulating client-prop transforms, so deformation stays stable instead of drifting farther every frame
- sparks, impact decals and smoke for harder impacts
- structural-health state
- basic electrical-damage state
- basic left/right door-damage states
- hooks/API that later modules can connect to real Metrostroi electrical, pneumatic and door systems

The damage renderer now uses one continuous local-space deformation for the visible carbody, interior and controls. Front/rear/side impacts have a local impact center, crush depth and falloff into the cabin/salon, so the interior follows the shell instead of visually separating from it. On MDLs with useful non-root bones, those bones are displaced with the local dent field as well. Source still keeps the original physics collision mesh; arbitrary per-vertex soft-body deformation of a compiled single-bone MDL is not available from ordinary Lua.

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
