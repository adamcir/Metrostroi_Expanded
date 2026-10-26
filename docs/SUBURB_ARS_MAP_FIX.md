# Custom suburb map: ARS code and EPK diagnosis

Map: `gm_suburb_construct_metrostroi_v1`. The supplied signal definitions are not formatted like the known working `gm_mustox_neocrimson_line_a` set.

## Confirmed from the supplied files and Metrostroi code

**1) Speed profiles.** All 26 custom map signals use one-element JSON tables (`["4"]` or `["6"]`) for `ARSCodes`. In `gmod_track_signal/init.lua`, `ARSLogic` evaluates `ARSCodes[FreeBS+1]` and `ARSCodes[#ARSCodes]`. With one element, a section never has a lower-speed code to select as block occupancy changes: 40 stays 40 and 60 stays 60. The working map instead uses string profiles such as `"04"` and `"046"`. The GMod signaling tool also expects a string.

**2) No-frequency indicator (ОЧ).** No custom map section is assigned speed code `1`. `sys_als_ars.lua` treats `GetARS(1)` or a missing detectable ARS signal as no frequency. Code `0` means ARS 0, **not** no frequency. For intentionally no-frequency sections, explicitly set `ARSCodes: "1"` on the selected signal(s). Never blanket-convert ordinary stations to code 1: no frequency is a restrictive safety condition.

**3) Server convar.** `metrostroi_ars_independent 1` forces the LAST code of any profile, making even a correct `"04"` profile stick at 40. For block-dependent signals, use `metrostroi_ars_independent 0` in the **server** console.

**4) Loop topology needs separate verification.** The two main original track paths overlap their own starts at their ends by approximately 186 and 287 Source units and are not trivially represented as graph rings. In `sv_railnetwork.lua`, `GetPositionOnTrack(..., {ignore_path=path})` excludes self-connections when finding path joins. More importantly, `Metrostroi.ScanTrack("ars", ...)` **does not scan branch links**, only `node.next`/`node.prev`. Therefore simply adding a tiny connector path is **not a fix for ARS continuity**. No automatic track rewrite is included; verify runtime `GetARSJoint` results and then repair track graph using a tested topology-specific solution.

**5) EPK is separate from the visible speed code.** `sys_als_ars.lua` can set `EmergencyValveEPK` because of unconfirmed brakes (`LKT`), disabled ARS, expired timers, etc. A visible 40 code alone does not prove the reason for EPK. Observe the live server event via the MEX ARS monitor.

## Correct only the proven signal-profile formatting

```bash
python3 tools/fix_suburb_ars_signals.py \
  signs_gm_suburb_construct_metrostroi_v1.txt \
  signs_fixed.txt
```

This makes `["4"]` into `"04"` and `["6"]` into `"046"` while retaining signal locations and configured next-signal names. It does **not** assign ОЧ to unnamed stations. When the precise intentional no-frequency block has been identified, specify its name explicitly as `--oc ARSxxx`.

Make a backup before installing a new `garrysmod/data/metrostroi_data/signs_gm_suburb_construct_metrostroi_v1.txt`. Reload the map, then check the live train.

## In-game read-only diagnostics

```text
metrostroi_ars_independent 0
mex_ars_map_check
mex_ars_map_train <train_entity_id>
mex_ars_status <train_entity_id>
```

`mex_ars_map_check` reports every signal's route codes, type, track position/path, direction, `NextSignalLink`, occupancy and current effective ARS code. `mex_ars_map_train` calls the original `GetARSJoint` for the train and reports the next and previous signal it actually reads.

A very high brake cylinder pressure or active `PneumaticNo2` is not sufficient proof of an EPK vent. Confirm `EmergencyValveEPK` and an event beginning `[MEX ARS] EPK ACTIVATED` in the **server** log.

References: `metrostroi-repo/metrostroi_beta`: `gmod_track_signal/init.lua`, `sys_als_ars.lua`, `sv_railnetwork.lua`.
