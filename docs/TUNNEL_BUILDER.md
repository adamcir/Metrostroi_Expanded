# Metrostroi Expanded — Original Model Catalog & Track Builder

The Track Builder uses **original, installed Metrostroi / Track Pack MDL
files only**. The old tunnel-type, track-length and curve-radius prefab
selectors have been removed. There is no auto-substitution, invented
track geometry, scaled stock model, or bundled third-party asset.

## Streamlined original railway model catalog

**Q → Tools → Metrostroi Expanded → Track Builder → OPEN TRACK MODEL CATALOG**

The catalog contains original **railway segment** models from mounted
Metrostroi/Track Pack content, not unrelated trains, signs, scenery, signal
models, or individual sleepers. The MDLs are used in-place, without copied
assets or procedurally generated rail replacements.

The browser has search and railway type/source filters, a continuous
**scrolling grid (no Prev/Next buttons)**, and a large working 3-D preview.
Scroll the large preview to zoom and drag to rotate the genuine MDL. The
original GMod `DModelPanel` paint method handles its own camera/render
state rather than calling model rendering without a viewport. Only visible
thumbnail models are instantiated so scrolling a large pack stays responsive.

Type filtering offers straight, curved, **double-track**, uphill/downhill
and junction models. Real double-track MDLs require two separately measured
running-rail centerlines and all four rail-end ports. An uncertain
double-track module cannot fall back to an invented rail separation.

### Two single-track modules after a double-track tunnel

Enable **2x single rails** in the Track Builder panel and select a mounted
**single-track** MDL. Aim at either of the two *free* end connectors of a
double-track model. MEX reads **both** real physical double end ports, then
places two ordinary, unscaled single-track originals — one on each lane.
Both sides remain separate endpoints and may continue through additional
2x pieces. Turn on **Split paired curves outward** with an original curved
single-track MDL to send the two tracks in opposing directions using its
forward and reverse geometry. No bending or scaling of the MDLs is done.

You can also start paired rails on empty ground with the **2x spacing**
slider (default 264 Source units). When paired construction is finished,
save with RMB and continue either single lane from its own open port.
**Shift+R** removes both modules of the last paired placement as one step.

### Uphill and downhill construction

The tool offers **Track grade (+up / -down), degrees** (default 0).
For a new free route, it tilts the **original** railway model and compiled
physics in 3-D; it does not bend mesh vertices or generate wedges.
When connecting to existing track, its actual end grade is inherited.
Authentic ramp/gradient MDLs keep their measured ascending/descending
Z profile and endpoint tangents.

A flat model joined to a steeply tilted piece may form an abrupt vertical
kink. Use original **ramp / gradient / ascend / descend / slope** MDLs for
smooth and driveable elevation transitions. The end pitch of the original
model becomes the next module's start pitch. Exact mesh and physics fitting
of third-party pitched models still needs in-game validation.

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
endpoints are valid as Track Builder routes. Models with their own .phy
use that original collision. When a valid two-ended MDL lacks its compiled
.phy, MEX can build narrow local rail-strip collisions from its measured
railheads; it never uses a massive rectangular collision around a tunnel.
A model without either usable native PHY or a reliable rail profile is
rejected with a specific error.
Unavailable or unmeasurable track geometry is rejected with a message
instead of drawing a fake replacement.

## Per-model rail calibration

For selected actual two-ended track models, MEX reads the installed MDL's
render-rail mesh when supported and locates pairs of running railheads
approximately 85.8 SU apart. Explicit double-track model profiles detect
four original railhead strips and store two individual lane paths. It samples the original track centerline and
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
more than two points. For unusual **double-track** models whose textures prevent automatic
railhead detection, register **two measured original rail centerlines**,
with the SAME number of stations in each lane:

```text
mex_native_register_double_model_path models/my_pack/double_track.mdl "0,0,0;0,256,0|264,0,0;264,256,0"
```

The numbers above demonstrate the file format only; **replace them with
measured local coordinates from your actual MDL**. MEX verifies the two
lanes' separation and tracks the physical end faces independently. After
registering an override, refresh the model catalog for updated metadata.

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

## Natural track and tunnel lighting

Committed Metrostroi / Track Pack original MDLs use **normal Source engine
studio lighting and entity shadows**. The old per-model fixed fullbright
lighting (`render.SuppressEngineLighting(true)` /
`render.ResetModelLighting(0.85, ...)`) has been removed: tracks should not
glow unnaturally at night or inside a tunnel.

- `DrawShadow(true)` enables Source entity shadows for solid placed rail
  and tunnel pieces. Transparent, unsaved grey ghost models **do not** cast
  permanent shadows.
- The lighting origin for both committed models and ghost previews is
  sampled roughly **74 SU above the actual running-rail centerline**,
  instead of inside a flatgrass/BSP floor or at an arbitrary MDL pivot.
  Underlying ground therefore does not spuriously block the model's
  lighting probe.
- A lightweight, cached upward visibility trace detects solid ceilings,
  terrain overhead and roof-bearing original tunnel prefabs. Covered
  pieces are darkened, including rails underneath a separate tunnel
  roof. The trace starts well above rail level; ground *beneath* the rail
  cannot block it. Actual map and dynamic lights remain handled by
  the Source renderer instead of a manually forced white lightbox.
- Cover tests run about once every 1.35–2 seconds per visible model;
  there are no extra spotlights, custom geometry or per-frame traces.
  The legacy `mex_native_outdoor_brightness` fill slider is obsolete
  and no longer changes track illumination.

If the map is already loaded when Lua code updates, use the **server/admin**
command below to refresh shadows and the rail-lighting probes for existing
modules without deleting or rebuilding them:

```text
mex_native_refresh_lighting
```

**Engine limitation:** GMod cannot automatically rebake a map's BSP
lightmaps when a tunnel is spawned. Engine dynamic entity shadows and
localized model darkness are supported, but fully accurate cast shadows
on every face of the underlying map terrain require baking lighting
with Hammer or a separate rendering/shadow system. Whether Source
projects shadows for very large MDLs depends on the map and client
shadow configuration. This change does not claim physically accurate
GI or lightmap regeneration.

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
