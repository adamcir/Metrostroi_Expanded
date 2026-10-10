# In-game Tunnel Builder (first implementation)

The existing **Metrostroi Expanded → Track Builder** tool now supports the tunnel profile of each newly created rail route. No Hammer compilation or replacement BSP is required; all geometry is generated as static Lua entities in the running map.

## Usage

1. Open **Q → Tools → Metrostroi Expanded → Track Builder**.
2. Keep **FAST static rail meshes** enabled (default).
3. Choose **Tunnel type**: `None`, `Round`, `Rectangular`, or `Wide`.
4. Set the round inner radius or rectangular width/height and lining thickness.
5. Click with LMB to create control points, RMB to finish, R to undo the latest point. An auto-loop inherits the chosen tunnel profile.
6. Routes/tunnel settings are persisted in `data/metrostroi_expanded/tracks_<map>.txt`.

## Fix: distorted / badly mapped tunnel textures (October 2026)

The old Track Builder used `u = x/128 + z/256` and
`v = y/128 + z/128` for **every** face of a tunnel or rail mesh. On
vertical walls, this sheared/twisted the texture along its height; on
rounded tunnel sections it broke the texture at every small triangle.

The updated generator now projects wall surfaces in **X/Z**, flat floors
and ceilings in **X/Y**, and end caps in **Y/Z**, each at a consistent
128-SU repeat scale. Circular liners are UV-unwrapped using their real
circumference/angle, with no orientation changes between faces. The UV
distance also advances continuously across adjacent physical segments,
rather than restarting at each segment origin.

The old choice of `tunnelwall_002` or `railroad_001/002` for unrelated
procedural boxes was also problematic: those can be model-specific
textures/atlases, giving giant wooden/plank-like walls and brightly colored
rail parts. Procedural walls now prefer Metrostroi's **tileable
`metro/metroconcrete001` concrete**, then stock Source concrete. Rails,
ties, and contact-rail guards use consistent opaque metal/concrete shades.
**Original unmodified Metrostroi and Track Pack MDLs retain their own
original material/UV mapping**.

The fix affects existing saved layouts after reloading the map; it does
not change collision geometry, track centers, rails, train speed, or
Metrostroi's rail-path data. After updating, restart GMod/reload the map
to rebuild and release client-side cached meshes.

## Realistic Metro tunnel rendering and third contact rail

The tunnel used to render as a completely black shell, and the rails/pieces
could show pink checkerboards when incompatible/missing materials were used.
The fast renderer now resolves textures from the installed **original Metrostroi**
material set:

- `materials/models/metrostroi_tunnels/tunnelwall_002.vtf` – textured lining
- `materials/models/metrostroi_tunnels/tunnelfloor_001.vtf` – floor/deck
- `materials/models/metrostroi_tunnels/railroad_001.vtf` – rail bed
- `materials/metrostroi/metro_contactrail_001.vtf` – contact rail

The runtime uses toned UnlitGeneric material variants so that walls still
have visible detail when a construction map has **no baked tunnel lighting**.
On original straight native MDLs, **Illuminate stock MDL tunnels on dark maps**
temporarily suppresses the missing baked lighting and tints the model to
match the procedural sections.
If the installed source texture is missing, it falls back to a neutral engine
white material instead of the error checkerboard. All stock materials and
native models are referenced from the player's installed Metrostroi content,
not bundled or redistributed by this repository.

**Classic Metrostroi** appearance includes tubbing seams, side service
walkways, a floor deck that hides grass below the bore, and the characteristic
circular or rectangular profile. **Basic geometry** suppresses the panel seam
ribs. The shell is still a procedural approximation on freely curved track.

**Real installed Metrostroi MDLs**: a straight tunnel of the correct native
length will automatically use mounted stock `tunnel64.mdl`,
`tunnel256.mdl`, `tunnel1024.mdl` and their matching rectangular or double
variants, without deforming the model. Straight routes are split into native
lengths only when they are truly straight. Missing/incompatible models, curves,
and route remainders fall back to textured procedural geometry. This is
toggleable via **Use real Metrostroi models on exact straight sections**.
On fixed station sections you can instead select a valid custom Track Pack
MDL via the existing on-demand scanner.

The **third (contact) rail** is enabled by default for new routes, configurable
per route, and separate from the running rail gauge:

- Side: **Outside**, Left, Right, or Both.
- Offset from the **individual track center**: default **112 SU**.
- Contact height above the spline baseline: default **20 SU**.
- It draws a metal contact conductor, insulating feet every ~128 SU,
  and a dark protective top/side guard. Outside places one rail at the
  exterior of *each* lane in double-track sections.
- The **circular shell and rectangular clearance are enlarged automatically**
  if necessary to fit the side-mounted conductor/cover: the default round
  two-track profile can be significantly bigger than a normal single-bore
  tunnel. Use **Wide/Rectangular** when a more plausible double-track tunnel
  envelope is desired.
- Contact rails are also rendered next to original/native tunnel MDLs,
  which by design do not include the separate third rail.
- **Visual only:** electric power distribution, safety/shock effects,
  current collection, conductor-rail gaps and proper contact-rail collisions
  are not yet simulated. For now there is NO additional rail physics hull
  that could cause train bogeys to bounce.

In open grassy maps, a circular tube can intersect world terrain because its
bottom extends ~55 SU below the baseline, and Lua cannot cut BSP holes.
Place the route above ground if you want the *whole round exterior* visible;
the new tunnel deck hides most of the map ground from the inside.

## Real double-track tunnels

Choose **Track count → DOUBLE**. This is a REAL pair of independently
spaced running tracks (four rails, two sleeper lines, four rail collision
hulls). The generated Metrostroi rail-network file has **two separate
paths**, so each track can rerail/route a train separately.

- **Track centre spacing** defaults to 240 SU (editable 180–400).
- **Two nodes per end** (one per track), plus intermediate nodes on each
  track, are drawn by the existing snapping preview.
- For **DOUBLE → DOUBLE**, aim near either lane's connection node with DOUBLE
  selected: the next tunnel is placed on the **same centreline**, not shifted
  sideways onto one track. Spacing and tunnel dimensions/type are inherited by
  default to avoid mismatched connections.
- For **SINGLE → DOUBLE**, choosing SINGLE attaches one new single track to
  the selected lane. A complete physical split/transition prefab is still
  unsupported and must be built separately.
- Snapping to a middle node does not create a mechanical turnout. Treat the
  node as a geometric attachment point only.

Double-track rectangular/round tunnel profiles automatically expand when
needed for clearance. A wide tunnel is no longer a single-track-only shell.

## Rigid / stationary stations

**Rigid section** constructs ONE straight section between two points.
LMB picks start, second LMB picks end, **RMB finishes**. Additional control
points are not allowed on that rigid section, so later spline operations can
never deform it. To continue the track, uncheck Rigid, select a compatible
track type and click either endpoint node as the beginning of a new route.

**Rigid section length**: set 0 to use the exact distance between clicks,
or select 64 / 256 / 1024 SU to place a native straight prefab length.
Snapping to another saved endpoint takes priority over automatic fixed length.

## Mounted Track Pack models

**Track Pack by Alex Skayler (Workshop item 3536801478) is optional, not
shipped or rehosted in MEX.** If installed and mounted, the Track Builder
can draw one **REAL compiled MDL** on a rigid straight route without
stretching/warping it. The procedural MEX rails remain authoritative for
physics and routing.

Click **Scan installed rail / tunnel models** in the tool panel to search
the selected mounted GAME models folder. Search starts at `models`; set a
narrower **Model scan root** if needed. Paths come from files actually
mounted in GMod, rather than imaginary hard-coded prefab names. Select an
entry from the detected-model dropdown, or paste its exact file name into
**Track Pack model path**. The server checks that the requested .mdl exists.

The rigid section's length must match the MDL's horizontal axis length
(roughly within 6%, minimum 8 SU). E.g., a 1024-SU prefab needs a 1024-SU
rigid section. **Pack MDL height adjustment** compensates for model-specific
origin conventions. Models that do not meet the constraints fall back to
procedural tunnel/track graphics.

**Important:** Hammer Track Pack curved pieces, junctions and turnouts cannot
simply be warped to match arbitrary curves. The current integration only draws
native straight models on rigid sections. For flexible curved connections,
MEX's procedural mesh is still used; actual Track Pack curved prefab
alignment will need additional model-specific topology/attachment metadata.


## Performance changes

Previously each 48-SU spline sample created one networked physics entity with two convex hulls, and the renderer repeated `railroad16.mdl` many times per segment. This caused hundreds/thousands of models and entities for long routes, excessive per-frame work, and unpredictable simulation stalls.

- The Metrostroi rail graph **still uses the high-resolution spline**.
- The *physical* and *visible* route is now **simplified independently** with maximum deviation (default 0.5 SU) and a maximum 192-SU chord; straight lines get far fewer entities.
- Default fast mode generates and caches **one GPU mesh per material per physical segment**, instead of creating a ClientsideModel for every 16 SU.
- Metrostroi rerail data searches nearby entities rather than every rail in the map.
- Physics rails overlap adjacent chord ends by 0.6 SU to reduce gaps.
- The Metrostroi rail graph has been aligned to the actual running height (**10 SU above the generated spline plane**, not the previous 15 SU).
- Tunnel collisions use **hollow static multi-convex walls**. There is no solid collision block filling the bore.

The rail/tunnel geometry is reconstructed after map cleanup and normal restart. Changing settings applies to **newly created routes**. Existing routes retain their saved per-route settings; respawning old tracks changes their renderer to the fast default unless they were explicitly saved with the legacy option.

## Adjustments and tradeoffs

- **Runtime validation still required**: test double-track train clearance,
  rerail in both lanes, the precise native .mdl alignment, and reopening saved
  rigid sections. This code was edited through GitHub and has not been loaded
  in a live GMod session here.


- **Smooth spline sampling** controls rail-network path precision; **Physical chord length/deviation** controls the optimized render/physics geometry. Never set a very large physical deviation on tight curves, or the collision rails can diverge from the finer graph.
- For highly curved sections, reduce physical max length to 96–128 SU and deviation to 0.25 SU. This increases collision bodies.
- Tunnel segments follow straight optimized chords, not dynamically deforming `.mdl` meshes. Small seams can appear at sharp bends; the ends overlap slightly to reduce cracks. This is the first prototype, not a finished tubbing / portal system.
- Models provided by Metrostroi are still usable through **legacy model mode** (disable FAST), but this is considerably heavier; legacy models do not draw the new tunnel profile.
- This cannot dig a hole into BSP terrain or exceed Source's map boundaries. Build within an empty / compatible map, or use separate editable terrain later.
- Long routes and closely spaced tunnel geometry can still strain Source physics, especially with many train cars. FPS may also drop because of other addons, heavy physics, lights or expensive Metrostroi simulations. Fast meshes help but **do not guarantee fixed FPS**.

## Fixing a dark stripe next to surface rails

On flatgrass the original procedural ties were buried at z <= 0,
with their top faces exactly co-planar with the map floor.
That caused depth-buffer fighting and repeated dark patterns along the track.
Ties are now drawn *above* the spline baseline. We also remove duplicate
ties at segment ends and disable projected shadows of the hidden backing MDL.

To isolate similar artifacts, toggle client-side console setting
`mex_track_builder_draw_sleepers 0` (hide ties) or
`mex_track_builder_draw_sleepers 1` (show ties).
The Track Builder settings panel exposes the same checkbox.
This changes only the visuals; it does not affect train physics.

## Quick verification in GMod

1. Test on a flat empty map, with a short 1000–2000 SU straight route using **None**.
2. Spawn an Ečs/81-717 and check bogey contact and rerailing, before and after rebuilding the Metrostroi network.
3. Create another route with **Round** (170 SU radius), and walk through it, confirming that side walls and roof collide but the bore is hollow.
4. Test a long straight and a 3072-SU-radius curve. Compare `cl_showfps 1` and `net_graph 1` where supported with and without fast geometry.
5. Restart map to verify saved route and tunnel type. Aim at the route, press R, then continue from the recovered endpoint to verify undo.

### Status

This has been implemented in the repository but **not in-game tested** in this environment. In particular, the wall/collision clearances and GPU shader materials should be validated with each rolling-stock family before treating it as production-ready.
