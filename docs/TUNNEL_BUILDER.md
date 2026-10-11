# Metrostroi Expanded — Track & Tunnel Builder

## Refactored system (October 2026)

The Track Builder **no longer assembles prefabricated straight/turn tunnel
models**, no longer scans Track Pack directories, and no longer creates
additional networked visual props or invisible original-physics proxies.

The running track uses only the original Metrostroi
`models/metrostroi/tracks/railroad16.mdl`. This model must be installed
through the base Metrostroi content (it is not redistributed by MEX).

### Visual rendering

- Route control points are interpolated to create a smooth path.
- The path is subdivided into bounded static chords, including long straight
  segments; the Metrostroi network keeps its independently sampled points.
- A single cached `ClientsideModel` per chord draws copies of the original
  16-SU tile with the orientation of that chord.
- The client sets large render bounds **during entity initialization**,
  avoiding Source culling long paths using the tiny backing model's OBB.
- Each tile is positioned with `SetPos` / `SetAngles` and updates its bones
  before drawing. Reusing `SetRenderOrigin` for the same model in successive
  draw calls can produce identical / stale positions in Source.
- The asymmetric third/contact rail affects the model's OBB. The renderer
  does not align the track from the horizontal OBB center or anchor the rail
  base from the maximum vertical bound.
- Double-track routes draw the same original tile on both lane centerlines.
- Tunnels are optional, generated as a **shell only**. They do not draw
  duplicate running rails, sleepers, clips or contact-rail meshes.

### Physics and train placement

Each bounded chord has **one frozen multi-convex physics body**. It includes
separate running rails at the standard 85.8-SU center-to-center separation,
low sleeper hulls and a separate outboard contact-rail hull. The hulls do
not create an invisible solid bed that would hold a bogey above the rail.

Contact-rail hull offsets are approximate and must be calibrated to the
specific installed railroad16 model in live GMod. Drawing a power rail does
not automatically integrate it with the Metrostroi 750-V electrical system.

The existing route graph and MEX rerail compatibility are preserved.
Minimum turn-radius checks continue to reject unsafe bends; this applies to
left- and right-hand curves without requiring a matching prefabricated turn.

### How to use

Open **Q → Tools → Metrostroi Expanded → Track Builder**. All tool labels
and error messages are in English.

- **LMB:** place or snap a route point.
- **RMB:** finish a route.
- **R / Reload:** undo one point, or reopen an aimed saved route and undo.
- **Advanced:** choose an optional tunnel shell, fixed-length straight
  construction, snapping density or the automatic loop builder.
- **`mex_track_builder_model_status` (client):** verify that the original
  railroad16.mdl is mounted.
- **`mex_track_builder_collision_status` (server):** count live static
  rail physics bodies.

Old saved route points and tunnel types can be loaded again. Settings for
removed long prefabs, stock-only matching and the Track Pack selector are
ignored; the route is built using the unified tiled renderer.

### Testing and known limitations

**Not tested inside a running Garry's Mod instance in this environment.**
Before publishing, build a 256-SU straight, a slow left/right curve and a
double track. Verify railroad16 alignment, the actual contact-rail location,
wheel height and rerail behaviour with Ečs and 81-717. Confirm that physics
can be hit by traces, that R removes only one control point, that routes
reappear after map reload, and that FPS is acceptable on long networks.

A GMod TOOL cannot cut openings through compiled BSP walls/terrain.
