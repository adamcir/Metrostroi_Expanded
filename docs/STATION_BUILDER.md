# Metrostroi Expanded – Station Builder

Station Builder is a separate GMod Toolgun tool for constructing **real, walkable metro stations**, rather than placing station markers on track routes. Its geometry is made of modular static collision bodies rendered with concrete, tile, brick and accent finishes. It works alongside the existing native Metrostroi / Track Pack Track Builder and does **not modify the original railway meshes**.

## First run

1. Install/update Metrostroi Expanded and load a Sandbox map.
2. Build a straight rail section with **Metrostroi Expanded → Track Builder**.
3. Select **Metrostroi Expanded → Station Builder** from the Toolgun.
4. Select **Left**, **Right**, **Island**, **Two outside platforms**, or **Platforms on both sides**. For twin rails, aim between the rails and set **Two-track rail separation** to match their actual separation.
5. Configure platform width, clearance, platform height, ceiling clearance, style, wall cladding, lighting, stair entrances, station name and accent color.
6. **LMB** near the starting location. The tool looks up the existing original-MDL rail centerline for alignment and elevation. A wireframe preview appears.
7. Aim in the station's longitudinal direction and press **LMB** again. The resulting station length snaps to 256 Source-unit segments (min 512, max 4096). Alternatively select **Fixed station length**.
8. To redesign an existing station, change its parameters in the Toolgun menu, aim at a solid station part and press **RMB**; it retains its position and length. **R** removes the entire station. While positioning a station, **RMB** or **R** cancels placement.

## Architecture generated

- Physical platform slabs and tactile safety stripes that leave the rail bed open.
- Side and island platform configurations with realistic rail-edge clearances.
- Structural walls, continuous roof, crossbeams and platform columns.
- Changeable architecture: classic, modern, industrial; tiles, concrete or brick.
- Accent-colored trim, wall panels, benches and station-name signs.
- Optional ceiling lamps with dynamic lights.
- Straight 11-SU stair risers with guard walls and upper landings at the start, end or both ends. Stairs are not automatically connected to an external map entrance.

The platform is 44 SU above the original railhead by default. Track surfaces and station geometry are separated: neither tunnel models nor platform slabs are created across the train's path.

## Save and commands

Station layouts are saved on the server to `garrysmod/data/metrostroi_expanded/stations_<map>.json`. Existing saved stations are reconstructed on map load and after `cleanup`. Original track route saves remain separate.

- `mex_station_list`: show saved stations in the console/chat.
- `mex_station_reload`: rebuild station modules from the map's saved layout. Use after a manual Lua reload if necessary.

Building, editing and deleting stations require admin permissions. Station parts are protected against physgun pickup and ordinary Toolgun mutations.

## Limitations

Station modules follow a **straight station axis**. When building next to a curve, the starting tangent can be measured, but the generated platform does not bend to track geometry. Use a suitably long straight rail section for a proper station.

The generator creates structural station geometry, **not** the track rails, underground excavation, navigation meshes, NPC passengers, turnstile fare validation or a completed street-level entrance. To embed a station inside terrain, build the station within a suitable Hammer-map void or compatible map environment. The stair landings may need further scenery or map geometry.

Only modules with confirmed original Metrostroi / Track Pack rail paths are used for automatic rail snapping. If the needed original model's rails cannot be measured, station construction can still be oriented manually.

## Validation checklist in GMod

- Single side platform fits the existing train body without hitting its wheels, third rail or bogies.
- Island platform stays between two separately positioned rails and has at least 160 SU available width.
- The generated floor, stairs and landing can be walked on without moving or falling through.
- Train passes through the station tunnel with adequate roof and wall clearance.
- Wall cladding, accent trim, station-name boards and lamp brightness are visible in daylight and underground lighting.
- Change configuration via RMB: all old modules disappear and new ones load without doubling collisions.
- Exit and reload map, then use `mex_station_list`. Use map cleanup to verify restoration.
