# Custom suburb map: ARS showing 40 where OC is expected

Map: `gm_suburb_construct_metrostroi_v1`. This is a **map-data issue**, not a reason to disable ARS safety globally.

## Verified against Metrostroi beta source

- `gmod_track_signal/init.lua`: `ENT:GetARS(ARSID)` returns the signal whose `ARSSpeedLimit` matches the ARS ID. `ARSLogic` selects `ARSCodes[FreeBS+1]`, or the last code with `metrostroi_ars_independent 1`.
- `sys_als_ars.lua`: `GetARS(4)` is 40 km/h; `GetARS(0)` indicates 0; `GetARS(1)` is no frequency (ОЧ). Train ARS also treats a missing joint as a lost frequency. EPK has multiple other activation conditions (braking confirmation, disabled ARS, timers and overspeed).
- `sv_railnetwork.lua`: the two tracks are separate path arrays and the loader uses `GetPositionOnTrack(..., {ignore_path=path})` when discovering joins. Thus it cannot directly join an endpoint back into the SAME path.
- The provided custom-map signs have **26 one-item arrays**, `["4"]` or `["6"]`, never `"0"` or `"1"`. With a one-item array and a 4/6 maximum, its signal cannot modulate from occupied (0) through speed limits as blocks free. It cannot emit ОЧ by configuration.
- The provided two long custom tracks were traced in order: path 1 ends 186 Source units beyond its own start, path 2 ends 287 units beyond its own start, in their respective directions. Both form **overlapping ends**, not true graph closures. Explicit `NextSignal` names do not repair this underlying topology.
- The independent speed-profile mode forces the last profile character: ensure **server** `metrostroi_ars_independent 0`.

The working `gm_mustox_neocrimson_line_a` definitions use **string** ARS profiles (e.g. `"04"`, `"046"`, `"0"`, `"1"`), automated next-signal lookup `"*"` where track topology supports it, and many more explicit graph paths.

## Tools, no edits to the base Metrostroi addon

```bash
python3 tools/fix_suburb_ars_signals.py \
  signs_gm_suburb_construct_metrostroi_v1.txt signs_fixed.txt

python3 tools/fix_suburb_track_loops.py \
  track_gm_suburb_construct_metrostroi_v1.txt track_fixed.txt
```

**Signals:** converts `["4"]` to `"04"` and `["6"]` to `"046"`, keeping signal locations and configured `NextSignal` links. This enables occupancy-dependent profiles, **not** automatic ОЧ. To designate an explicitly intended no-frequency section, use `--oc ARSxxx` on exactly the intended signal. A no-frequency section is a real restrictive condition and may require driver vigilance, not a cosmetic indicator.

**Track:** trims each overlapping loop end and adds one ~60-unit connector path, preserving original path indices 1/2. The restored graph connection is **experimental** until tested on the actual server. It must only be run on the original, unmodified, two-path file.

Place the resulting files under `garrysmod/data/metrostroi_data/` using the active map filenames, after backing up the originals. Reload the map and inspect the actual signal graph. This is preferable to an unconditional global override of EPK.

## In-game diagnosis

```text
metrostroi_ars_independent 0
mex_ars_map_check
mex_ars_map_train <train_id>
mex_ars_status <train_id>
```

The first command must run on the **server**. `mex_ars_map_check` prints every active signal's code profile, `TrackDir`, detected path, `NextSignalLink`, `ARSSpeedLimit`, occupancy and loop-end graph connections. `mex_ars_map_train` shows the current next/previous signal as selected by Metrostroi and the actual ARS/EPK fields.

Do not infer that a pneumatic hissing sound is specifically an EPK application. Verify `Pneumatic.EmergencyValveEPK` and the `[MEX ARS] EPK ACTIVATED` server log.

**Important:** We do not know which precise platform section(s) the user wants to emit ОЧ, so the default converter does not insert code 1 arbitrarily; forcing no-frequency into a normal passenger loop could cause genuine EPK protection.
