# Metrostroi Expanded — Original Track & Tunnel Builder

The **Track Builder** now uses **real Metrostroi model assets**, not generated
track/tunnel meshes or interpolated decorative substitutes. All Lua code, UI
labels and console messages are English.

## Construction

Open **Q → Tools → Metrostroi Expanded → Track Builder**.

1. Choose an original model family (round, rectangular, double/wide tunnel,
   or surface track) and Single/Double.
2. Choose a module: **Straight**, **Curve left**, **Curve right**,
   **Turnout** or **Rail crossing**.
3. **LMB** selects the first start point; aiming at a free orange/green connector
   snaps exactly to the existing native track end. The selected end determines
   the heading, not an arbitrary guessed spline.
4. Move the cursor: a **grey semi-transparent original model** appears before
   placement. For straight routes the builder greedily combines real nominal
   lengths; it does not rescale stock models to fill an arbitrary gap.
5. **LMB** adds the displayed piece(s). Previously selected unfinished pieces
   remain ghosted, with collision disabled, until the route is finished.
6. **RMB** commits the route. MEX creates networked original-model static
   entities with the matching original **compiled .phy collision**.
7. **R** removes **only the exact native module under the crosshair**,
   whether a saved section or an unsaved grey module. The selected model
   receives a red/orange highlight and contextual on-screen text.
   Deleting a module in the middle preserves all other pieces and creates
   two free connection endpoints at the gap.
8. **Shift+R** undoes only the last **unsaved** module while building.
   It never removes the last saved route or edits a different route.
9. **Cancel** discards the unfinished grey preview without touching saved
   rails. The advanced button **Delete entire aimed route** is separate
   from the selective **R** delete action.

Green markers indicate available starts, orange markers indicate free ends.
These include both ends of **original curved track sections**. Node markers
are rendered over the actual **running rail endpoints**, not at a fictional
circular-arc control point. The world-space construction baseline is stored
independently of the +10 SU visual marker height, preventing steps after
clicking a connector. Double-track curves expose two rail connectors per end,
based on their OWN unique model pivot, not a copied straight-track pivot.
Internal joined ports are hidden.

### Original stock model catalog

Models are referenced by path under `models/metrostroi/tracks/`.
They are **not copied or redistributed by MEX**.

| Type | Original nominal module models |
|---|---|
| Surface | `railroad1024.mdl`, `railroad4096.mdl` |
| Round single | `tunnel64.mdl`, `tunnel256.mdl`, `tunnel1024.mdl` |
| Rectangular single | `tunnel64_rect.mdl`, `tunnel256_rect.mdl`, `tunnel1024_rect.mdl` |
| Round/wide double | `tunnel1024_double.mdl` |
| Round curves | `tunnel3072_turn1.mdl`, `tunnel4096_turn1.mdl`, `tunnel8192_turn1.mdl` |
| Double round curves | `tunnel4096_double_turn1.mdl`, `tunnel8192_double_turn1.mdl` |
| Rectangular curve | `tunnel3072_rect_turn1.mdl` |

The available catalog depends on installed Metrostroi content. Missing
original files cause an explicit construction error, **not** a fallback
generated model. For a requested radius not mounted, the tool selects the
**closest radius with a real installed original matching curved MDL** and
displays the effective radius. If no real curved MDL exists for the selected
tunnel layout, the preview shows an error rather than a misleading straight
module. Use `mex_native_curve_assets` or the matching Track Builder button
to list actual model availability.

**Important:** The original `turn1` MDLs are *transition* pieces, not
perfect constant-radius circular arcs. Their real track end positions and
exit tangents were extracted from running-rail vertices in the original
PhoenixBlack/Metrostroi compiled `.mdl/.vvd` files. For example, the
single-track `tunnel3072_turn1.mdl` ends at approximately **local
(-297.195, 1623.610)** and exits at **24.494°**, NOT at the endpoint of
a 30° radius-3072 circle. The 4096 and 8192 pieces have different
noncircular endpoints; the double/rectangular models have their own rail
positions. MEX now aligns the *authored rail ports* and tracks the measured
centerline rather than guessing from the radius in the filename.

Authoring orientation: the stock `turn1` prefab curves to the **left**
of local +Y. MEX keeps that orientation for left bends; right bends traverse
the same original model **in reverse**, using its physical end as the
world-space starting connector. No geometry is mirrored or rescaled.

**Important:** Source model port values were measured from historical
original Metrostroi mesh data. Workshop/Metrostroi revisions may use
different geometry; compare the final rail ends and wheel contacts against
the actual models mounted in Garry's Mod. This implementation has not been
playtested inside GMod here. The model lift stays +5 SU; double track
center spacing is 264 SU but the authored pivot differs between straight
and curved prefabs.

### Save, restore and Metrostroi network

Committed native modules are stored by map in
`data/metrostroi_expanded/native_tracks_<map>.json`. Module records
include model, position, angle, route, turn and port geometry.

The builder builds network paths from the exact module centerlines,
including two independent lanes for double-track pieces, and merges
contiguous native end nodes. It also writes these paths to the existing
Metrostroi data workflow and requests a network rebuild on finish.
Map cleanup and map restart restore committed original modules.
Saved pre-v2 routes are migrated on map load to measured original-model
rail endpoints; subsequent originally connected modules are realigned.
A recovery copy is stored at
`data/metrostroi_expanded/native_tracks_<map>_before_native_ports_v2.json`.
To re-align already loaded old routes without restarting, admins can run
`mex_native_realign_routes`. That command also preserves a separate
`_before_manual_realign.json` backup.

The older MEX route file is preserved for compatibility but the Track
Builder UI creates **native modules only**. No original assets are modified.

## Switches and diamond crossings

A switch or a crossing is **not** made by overlapping two regular track
models. That would create wrong guard rails, double contacts, and invalid
bogey collision. MEX checks new route centerlines against existing MEX-native
routes and rejects accidental same-level crossings; only properly registered
original diamond/switch models provide legal junctions. It **must be one installed original junction asset** with
measured connector locations and real compiled physics.

Since the filenames and attachment pivots of third-party Metrostroi/Track
Pack junctions are not reliably standardized, MEX does **not invent**
a filename or connector geometry. Junction placement rejects missing or
uncalibrated profiles instead of creating an unsafe fake turnout.

### Registering an original junction

Server superadmins can register a model against measured local attachment
coordinates:

```text
mex_native_register_junction <id> <switch|crossing> <original_model.mdl> "<x,y,z,yaw;x,y,z,yaw;...>" "<1-2;1-3;...>"
```

Port coordinates are **model-local**. Yaw is the direction **out of** the
port, relative to the construction heading. The input is **port 1**.

- A **switch** requires exactly three ports and paths **1–2** (main) and
  **1–3** (diverging).
- A **crossing** requires exactly four ports and two independent rail
  paths, usually **1–2** and **3–4**.
- To follow a real curving branch instead of a straight connector chord,
  register measured intermediate local centerline waypoints:

```text
mex_native_set_junction_path <id> <port_a> <port_b> "<x,y,z;x,y,z;...>"
```

Original switch assets with fixed, non-moving geometry are locked to the
main route. If the workshop kit provides **two compatible original models**
with separately authored true .phy meshes for the main and diverging
positions, register them:

```text
mex_native_set_switch_variants <id> <original_main_model.mdl> <original_diverging_model.mdl>
```

They must share the same calibrated local origin and three attachment ports.
Press **E** on a committed switch to select its next original visual and
physics state; switching is blocked while a train/bogey is nearby. On each
state change MEX requests a rail-network update. This is **not yet a
replacement for Metrostroi's complete dispatch, point-locking and signalling
system**: special Metrostroi switch entities/control integration still
requires in-game testing.

Junction registry persists at
`data/metrostroi_expanded/native_junctions.json`, shared to joining clients.
The tool's **Registered junction profile ID** field uses that registry.

### Diagnostics

```text
mex_native_status
mex_native_list_junction_models
```

The second command looks for likely original crossing/switch model names in
installed stock/Track Pack folders; it only reports candidates, never assumes
their local pivots or path shapes. Missing `.phy` models are rejected on
finish. Check the GMod server console for full errors.

## Limitations / verification

- Only exact original pieces are used; unsupported arbitrary-radius bends,
  grades and lengths are not made to fit with fake geometry.
- An actual diamond crossing or moving turnout is only constructible after
  the relevant real model and **measured** ports are registered. There is no
  bundled, invented generic junction asset.
- Model lighting: original static-asset textures are preserved. Native model
  rendering adds scoped neutral fill illumination because long Source scripted
  entities often sample map lighting underneath terrain and appear black.
  Grey preview modules get brighter neutral illumination too. MEX checks
  for an unobstructed sky above the MDL at spawn time, so above-ground
  Metrostroi tunnel pieces receive daylight fill as well as standalone
  surface railway pieces. Buried tunnels retain softer fill illumination.
  The **Outdoor rail model brightness** slider adjusts the lighting without
  recoloring original textures; its client cvar is
  `mex_native_outdoor_brightness` (default 0.85).
- Current stock centerline assumptions and turn1 pivots are not verified live.
  First test a 64/256 SU single straight, a curve in each direction, a
  double-track module, then a registered crossing/switch on a test map.
- Train rerailing and ALS/ARS switch dispatch on new real-model junctions
  need validation against your specific Metrostroi build.
- A GMod TOOL cannot cut holes in compiled BSP terrain or walls.
