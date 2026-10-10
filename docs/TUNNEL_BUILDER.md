# In-game Tunnel Builder (first implementation)

The existing **Metrostroi Expanded → Track Builder** tool now supports the tunnel profile of each newly created rail route. No Hammer compilation or replacement BSP is required; all geometry is generated as static Lua entities in the running map.

## Usage

1. Open **Q → Tools → Metrostroi Expanded → Track Builder**.
2. Keep **FAST static rail meshes** enabled (default).
3. Choose **Tunnel type**: `None`, `Round`, `Rectangular`, or `Wide`.
4. Set the round inner radius or rectangular width/height and lining thickness.
5. Click with LMB to create control points, RMB to finish, R to undo the latest point. An auto-loop inherits the chosen tunnel profile.
6. Routes/tunnel settings are persisted in `data/metrostroi_expanded/tracks_<map>.txt`.

The first release builds a **single track centered in each tunnel**. The `Wide` preset is only a *wide tunnel profile* for now: it does NOT automatically lay two tracks. Two tracks must be laid as separate routes, and a future double-track profile must place one large envelope around both.

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

- **Smooth spline sampling** controls rail-network path precision; **Physical chord length/deviation** controls the optimized render/physics geometry. Never set a very large physical deviation on tight curves, or the collision rails can diverge from the finer graph.
- For highly curved sections, reduce physical max length to 96–128 SU and deviation to 0.25 SU. This increases collision bodies.
- Tunnel segments follow straight optimized chords, not dynamically deforming `.mdl` meshes. Small seams can appear at sharp bends; the ends overlap slightly to reduce cracks. This is the first prototype, not a finished tubbing / portal system.
- Models provided by Metrostroi are still usable through **legacy model mode** (disable FAST), but this is considerably heavier; legacy models do not draw the new tunnel profile.
- This cannot dig a hole into BSP terrain or exceed Source's map boundaries. Build within an empty / compatible map, or use separate editable terrain later.
- Long routes and closely spaced tunnel geometry can still strain Source physics, especially with many train cars. FPS may also drop because of other addons, heavy physics, lights or expensive Metrostroi simulations. Fast meshes help but **do not guarantee fixed FPS**.

## Quick verification in GMod

1. Test on a flat empty map, with a short 1000–2000 SU straight route using **None**.
2. Spawn an Ečs/81-717 and check bogey contact and rerailing, before and after rebuilding the Metrostroi network.
3. Create another route with **Round** (170 SU radius), and walk through it, confirming that side walls and roof collide but the bore is hollow.
4. Test a long straight and a 3072-SU-radius curve. Compare `cl_showfps 1` and `net_graph 1` where supported with and without fast geometry.
5. Restart map to verify saved route and tunnel type. Aim at the route, press R, then continue from the recovered endpoint to verify undo.

### Status

This has been implemented in the repository but **not in-game tested** in this environment. In particular, the wall/collision clearances and GPU shader materials should be validated with each rolling-stock family before treating it as production-ready.
