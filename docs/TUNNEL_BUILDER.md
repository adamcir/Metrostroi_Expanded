# Metrostroi Expanded — Track & Tunnel Builder

## Current construction mode

The English-language Track Builder prioritizes **original Metrostroi** models.
Open **Q → Tools → Metrostroi Expanded → Track Builder**, select a tunnel
profile, the number of tracks, and **Fixed module** or **Flexible route**.
The **Original models ONLY** option is ON for newly created routes.

- **LMB**: pick a beginning point, add a point or extend to an attachment node.
- **RMB**: finish the route.
- **R / Reload**: undo the last point.
- The advanced panel retains gauge, radius, segment precision, snapping,
  prefab selection, and performance options.

## Original Metrostroi models only (new default)

New routes do **not** generate their own concrete boxes, sleepers, or
third/contact rail. Native stock track pieces include all those visual parts
already. Instead, a requested layout must be representable by original
models installed on the server:

| Layout | Supported native modules |
| --- | --- |
| Surface, single track | `railroad4096.mdl`, `railroad1024.mdl` |
| Round, single | `tunnel64.mdl`, `tunnel256.mdl`, `tunnel1024.mdl` |
| Rectangular, single | `tunnel64_rect.mdl`, `tunnel256_rect.mdl`, `tunnel1024_rect.mdl` |
| Round, double | `tunnel1024_double.mdl` |
| Rectangular/wide, double | `tunnel1024_double.mdl` (native profile; check clearances) |

All real stock assets must be installed separately. The addon does not
redistribute Metrostroi or Track Pack content.

The legacy procedural renderer is retained **only for old saved routes** or
legacy configurations where Original models ONLY was off. New model-only
routes reject sections that cannot be represented by the original assets,
instead of quietly creating fake tunnels.

### Native curved tunnel modules (EXPERIMENTAL)

The fitting system searches genuine, compiled `turn1.mdl` pieces on nearly
horizontal right-hand curves. The initial supported radii are **3072, 4096,
and 8192 Source units** for available profile types. An original curved
prefab has a fixed **radius, sweep angle and local origin**. Matching checks
tangent alignment, radial deviation, endpoint distance, grade and the
original model's presence. The generated fine spline remains the train path,
but each matched curve is rendered by ONE actual MDL.

A minimum safe turn radius defaults to **3072 SU**. Double track is checked
using its *inside* centerline. Curves below that radius are refused before
route saving. To create a curve in native-only mode, select Flexible route
and choose control points matching a supported native right-hand bend.

**Unsupported angles / left-hand / nonstandard radii are rejected** in
native-only mode. In particular, a prefab that does not fit the requested
angles is never scaled, stretched, or substituted with a plain box.

These curved prefab transformations are not yet tested in a live
Garry's Mod session and must be inspected before using the layout for
production operations.

## Native model height and true physics collisions

The original Metrostroi model is now lifted **5 SU** on new native-only
routes, with identical offsets for rendering and collision. The
Metrostroi path graph and rerailer also receive the same rail elevation
adjustment. Older saved routes preserve their historical alignment.

Original Metrostroi `.mdl` pieces include the third/contact rail and
sleepers. Every supported original also has a matching compiled **`.phy`
collision model**. MEX now creates a transparent static collision entity
from that same model, with the exact same position and orientation as
the visible prefab. That native collision, rather than crude approximate
long blocks, is authoritative for the **rails, sleepers, third rail and tunnel
lining**. Multiple tiny MEX track physics hulls are removed on sections
covered by an authentic native collider so they do not make train bogies
bounce or hover.

The collision entities are frozen, networked, never rendered
(their scripted entity has an empty Draw hook), and removed with
their owning route. The Physgun and most tools cannot move them;
Track Builder can still interact with their owning track and its
delete/undo actions resolve an invisible collider to the owning route.

**Important:** This depends on the real stock `.phy` quality and game
physics behavior. The absence of a matching installed `.phy` prevents
new model-only route construction. Exact rolling-stock wheel-to-rail
clearance still requires a live in-game test; the compiled collision may
contain details different from its visible mesh.

## Route persistence, performance and testing

MEX saves its own track/control points independently of GMod and Metrostroi
base map data. The 1-track/2-track network and attachment nodes are
regenerated after restart.

The original MDL/PHY strategy avoids thousands of generated tunnel
meshes and keeps the Metrostroi route graph densely sampled. However, a
large number of separate `prop_physics` collision proxies can still affect
performance, and simply using stock models does **not** guarantee stable
frame times.

To verify:
1. Run `mex_track_builder_model_status` in GMod console to check mounted
   stock prefabs and experimental curved models. Then run
   `mex_track_builder_collision_status` to count live original-physics
   proxies and reveal missing/unusable collision entities.
2. Build one 256-SU original rectangular tunnel and check its actual
   model, sleepers and contact rail (no duplicate yellow rail).
3. Aim at the original model with Track Builder and confirm you can
   extend, undo and delete the owning saved route.
4. Check that stepping on sleepers and the contact rail collides with
   the native model's geometry. Try Ečs and 81-717 to detect clearance
   issues, bogey bouncing or floating.
5. Construct a gentle native curved prefab at the supported radius,
   verify the resulting angle and real physics, and check that tighter
   unsafe turns are rejected.
6. Reload the map and verify route appearance, save restoration and
   collision proxies. Measure FPS before using the system at scale.

### Known limitations

- Custom Track Pack models without calibrated axes/PHY placement are
  **not** automatically treated as genuine native tunnel segments.
- No digging/cutting into compiled BSP terrain.
- Original contact rail collision is geometric only. Drawing or colliding
  with it does not by itself add 750V supply, shoe-current collection or
  electrical section simulation.
- This revision was committed to the main branch without being launched
  in a live Garry's Mod map. Curved model orientation and actual PHY
  contacts are experimental and require user verification.
