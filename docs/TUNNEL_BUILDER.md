# Metrostroi Expanded — Original Model Catalog & Track Builder

The Track Builder uses **original, installed Metrostroi / Track Pack MDL
files only**. The old tunnel-type, track-length and curve-radius prefab
selectors have been removed. There is no auto-substitution, invented
track geometry, scaled stock model, or bundled third-party asset.

## Open the catalog

**Q → Tools → Metrostroi Expanded → Track Builder → OPEN ORIGINAL MODEL CATALOG**

The catalog scans and includes the **complete installed MDL inventory**
under Metrostroi / Track Pack model folders, not merely filenames that
contain "rail" or "track". This includes tracks, tunnels, bends, switches,
signals, platforms, trains and accessory models when those assets are
mounted in GMod.

The visual catalog contains:
- Original model **thumbnail grid** (30 MDLs per page), pagination, live
  search by model path/name, and type/source filters.
- Click an icon to inspect its actual **3D model preview**, full path,
  original source and category. Double-click or **USE SELECTED MODEL**
  to close the browser.
- The selected MDL stays in **Selected original model** when reopening the
  tool. There is no preselected model or automatic prefab family.
- **Reverse model direction** uses the opposite authored rail endpoint
  without mirroring, deforming or stretching the original MDL.
- For an explicitly surveyed turnout/crossing, **Junction output port**
  picks a valid registered branch; no unsurveyed switch geometry is guessed.
- **Show measured rail centerline overlay** shows a cyan editor-only path
  extracted from the original running rails (not a rail model).

## Construction controls

| Input | Action |
|---|---|
| LMB (first click) | Pick an available rail-end node, or start a new route |
| LMB (next clicks) | Append exactly the currently selected original MDL |
| RMB | Finish and save the currently built route |
| R | Remove **only the module under the crosshair** |
| Shift + R | Undo the last unsaved module |
| Reverse model direction | Connect via the original model's other end |

The original MDL preview is translucent grey. Actual free rail-end
connectors appear in green/orange at the **running rail surface**. Their
crossbars mark the gauge across the *real* end face. MEX hides internal
joined connectors, rejects selection in the middle of a long curved
module, and prevents choosing already occupied nodes.

The client and server use the **same server-measured model profile**, so
the grey preview and committed placement share exact end coordinates and
entry/exit tangents. Each original curve can have a unique centerline
rather than a shared artificial circular radius.

## Source catalog discovery

After installing new content, press **Rescan model catalog**. You can
also run the admin command on the game server:

```text
mex_native_rescan_models
```

Scans look in mounted `models/metrostroi`, `models/trackpack`,
`models/track_pack`, common other track-pack root folders and other
top-level folders with Metrostroi/Track Pack naming. To add an unusual
pack under an arbitrary folder, a superadmin can register that root:

```text
mex_native_catalog_root models/my_custom_track_pack
```

The root list persists under
`data/metrostroi_expanded/native_catalog_roots.json`. A scan is bounded
to protect GMod from extremely large unrelated asset trees.

Catalog entries have intentionally **not** been filtered to claim every
MDL is a working rail. Train bodies, signs, platforms or decoration models
are visible as original catalog assets. Only genuine rails with measured
endpoints and compatible physics are valid as Track Builder routes.
Unavailable or unmeasurable track geometry is rejected with a message
instead of drawing a fake replacement.

## Per-model rail calibration

For selected actual two-ended track models, MEX reads the installed MDL's
render-rail mesh when supported and locates pairs of running railheads
approximately 85.8 SU apart. It samples the original track centerline and
records both *separate* end position, tangent and curvature. That means
straight, eased transition, and curved models get different actual ports.

**Straight-track validation:** Metrostroi texture atlases often cover
sleepers, a protective third rail and tunnel walls as well as the running
rails. An overly permissive material scan could mistakenly interpret those
surfaces as a curved centerline even when the selected original MDL was
straight. The current analyzer verifies that a model classified as a
straight has collinear end stations, nearly identical end tangents and
no sharp local kinks (small tolerance for mesh precision). When valid,
its path is the straight line between its *real measured rail end faces*.
If the mesh is inconsistent, placement fails rather than fabricating
a turn or corrupting later snap nodes.

Previously saved sections are NOT silently moved. To repair previously
placed sections affected by bad measurements, a server admin can use:

```text
mex_native_realign_routes
```

Each execution creates a **new timestamped backup** of the original
per-map native-track JSON data before realigning models. If the newly
measured rails cannot be validated, those sections are left untouched;
inspect the particular selected MDL using `mex_native_model_info`.

View a specific model's measurements from the server console:

```text
mex_native_model_info models/metrostroi/tracks/tunnel3072_turn1.mdl
```

For a third-party pack that uses unrecognized rail material names, a
superadmin can provide **verified model-local running rail centerline
measurements** rather than accept an arbitrary radius:

```text
mex_native_register_model_path models/my_custom_track_pack/example.mdl "0,0,5;0,64,5;-4,128,5;-13,192,5"
```

Those per-model overrides persist in
`data/metrostroi_expanded/native_model_ports.json`. Curved models need
more than two points. If a model has multiple separate tracks, the
current single-centerline analyzer **cannot safely infer** both lanes.

For compatibility, historical **model-specific** measurements for a few
classic Metrostroi `turn1` MDLs are retained when engine mesh access is
unavailable; these are not presented as new-construction prefab presets.

## Original switches and crossings

A turnout or diamond is not made by overlapping two unrelated straight
MDLs. A genuine junction needs **registered model-local ports and
traversable links**. The catalog shows every model (including junction
candidates) but rejects construction of uncalibrated switches/crossings.

Register an installed original MDL and its *measured* ports:

```text
mex_native_register_junction <id> <switch|crossing> <model.mdl> "<x,y,z,yaw;x,y,z,yaw;...>" "<1-2;1-3;...>"
```

- Switch: three ports with links 1–2 and 1–3.
- Crossing: four ports forming two independent paths, generally 1–2
  and 3–4.
- Optional precise centerline via
  `mex_native_set_junction_path <id> <port_a> <port_b> "<x,y,z;...>"`.
- Matching original, compatible switch position MDLs/PHYs can be
  registered with
  `mex_native_set_switch_variants <id> <main.mdl> <diverge.mdl>`.
  Switching when occupied by a train is blocked.

Junction configurations persist under
`data/metrostroi_expanded/native_junctions.json`.

## Persistence & migration

Completed native routes are stored by map in
`data/metrostroi_expanded/native_tracks_<map>.json`.
Original model path, orientation, measured centerline and connector
positions are retained. Routes reload after map restart/cleanup, and
their measured paths are fed into the existing Metrostroi network rebuild.

Older pre-catalog saved routes remain readable. Do not silently move
already committed track sections; a manual repair command is available:

```text
mex_native_realign_routes
```

This takes a backup of the saved data before modifying old route
connections.

**Limitations:** This code cannot cut holes in compiled BSP terrain.
Non-track MDLs are browsable but not fabricated into working rails.
The client/server mesh inspection, actual .phy contact and rerailing
still require testing against the specific Metrostroi and Track Pack
content versions mounted in Garry's Mod. No live GMod test has been
performed as part of this change.
