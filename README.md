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

Current damage-system module version: **0.1.0**

Metrostroi Expanded now includes a first simple crash-damage system for all `gmod_subway_*` trains.

It currently provides:

- front, rear, left-side and right-side damage zones
- automatic crash detection from sudden velocity changes
- support for `DMG_CRUSH` and blast damage
- persistent per-zone structural damage while the train entity exists
- simple client-side visual crumpling from the damaged direction
- sparks, impact decals and smoke for harder impacts
- structural-health state
- basic electrical-damage state
- basic left/right door-damage states
- hooks/API that later modules can connect to real Metrostroi electrical, pneumatic and door systems

The visual deformation is intentionally conservative. Source still uses the original collision mesh and Metrostroi child props, so this first version deforms the rendered carbody without pretending that the underlying Source collision model is a BeamNG-style soft body.

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
