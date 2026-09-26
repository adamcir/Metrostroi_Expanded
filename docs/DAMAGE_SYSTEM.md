# Metrostroi Expanded – Crash / Deformation Model

Damage System version: **0.4.4**

This document describes the reasoning behind the v0.4 rewrite.

## Why v0.1-v0.3 were replaced

The old implementation used a render matrix to scale/compress the complete wagon model. That can make a Source model look as if the cab, windows and interior have been cut apart or as if the complete carbody has shrunk. This is not a useful approximation of railway crash behaviour.

v0.4 therefore does **not** globally scale the carbody.

## Physical model used by the addon

The implementation is intentionally simplified for Garry's Mod, but follows these crashworthiness ideas:

1. **Local load path**
   - A collision starts at the contact point.
   - Front/rear impacts first affect the end structure.
   - Side impacts produce local side-wall intrusion around the contact.
   - The affected volume grows with impact severity instead of instantly deforming the complete wagon.

2. **Occupied / survival volume**
   - Moderate impacts are kept closer to the end or side structure.
   - Heavy damage can progressively intrude into the cab or passenger volume.
   - The far end of the vehicle is not scaled just because the front was hit.

3. **Structural attachment**
   - Interior shells and mounted equipment use the same deformation field as the surrounding structure.
   - A full-length interior model is never translated away from the train as a single object.
   - Local rigid components follow their mounting point.
   - Button panels and their generated ClientEnt controls share one rigid panel transform.

4. **Existing Source bones**
   - The addon uses `BuildBonePositions` and `SetBoneMatrix`.
   - Every usable non-root bone is moved according to its position inside the deformation field.
   - Bone orientation follows the local slope of the deformed structure.
   - Existing animations are preserved because the transformation is applied after Source builds the normal animation matrices.

5. **No invented vertex weights**
   - A compiled MDL whose body vertices are all weighted to one root bone cannot acquire a local dent from Lua alone.
   - In that case v0.4 leaves the large shell rigid rather than applying an unrealistic whole-model scale.
   - A future per-train deformable-model pipeline can add dedicated deformation bones/weights locally without redistributing Metrostroi's original model assets.

## Crash detection

v0.4 uses the physics collision callback as the primary source of crash data:

- collision position
- surface/contact normal
- our pre-impact velocity
- other object's pre-impact velocity
- relative impact velocity

Very low-speed contacts are ignored. The old velocity-delta detector remains as a fallback for cases where the Source physics callback is not delivered to the train entity.

## Metrostroi controls

Metrostroi calculates button aiming against each `ButtonMap` plane.

To keep controls working, v0.4:

- makes a **shallow per-wagon copy** of the panel table only,
- keeps the original button/config/runtime objects,
- deforms the panel position and angle,
- moves generated panel ClientEnts with exactly the same rigid transform.

This avoids the v0.3 deep-copy problem while letting a damaged cab panel remain clickable.

## Runtime inspection

Aim at a train and run:

```text
mex_damage_bones
```

The command prints the body bones and the bone counts/names of structural client models such as salon, cabin, body, panel and door models.

Enable impact markers with:

```text
mex_damage_debug 1
```

## References used for the model

- U.S. Federal Railroad Administration – Passenger Rail Equipment / Structural Crashworthiness
  - https://railroads.fra.dot.gov/train-occupant-protection/equipment/passenger-rail-equipment-overview
- FRA – Crash Energy Management one/two-car impact tests
  - https://railroads.fra.dot.gov/elibrary/crash-energy-management-one-and-two-car-passenger-rail-impact-tests-summary-structural-and
- FRA – Interior Occupant Protection
  - https://railroads.fra.dot.gov/train-occupant-protection/passenger-protection/interior-occupant-protection
- FRA – Crash Energy Management projects
  - https://railroads.fra.dot.gov/research-development/program-areas/rolling-stock/current-projects/crash-energy-management-projects
- Garry's Mod Wiki – Entity:SetBoneMatrix
  - https://wiki.facepunch.com/gmod/Entity:SetBoneMatrix
- Garry's Mod Wiki – Entity callbacks / BuildBonePositions / PhysicsCollide
  - https://wiki.facepunch.com/gmod/Entity_Callbacks
- Garry's Mod Wiki – CollisionData
  - https://wiki.facepunch.com/gmod/Structures/CollisionData
- 81-717/714 construction overview
  - https://nashemetro.ru/carriages/81-717/


## Breakaway components

Version 0.4.2 promotes detached components to real server-side physics entities:

- detached doors, lamps, controls and other mounted ClientEnt parts become `mex_damage_debris`
- debris is networked and can be manipulated with the Physgun and Gravity Gun
- each component is evaluated at its own geometric anchor, not merely at the model origin
- individual mounting thresholds allow one button to tear off while nearby controls remain attached
- a detached control's server-side `ButtonEvent` IDs are blocked, which also blocks Metrostroi keyboard shortcuts
- parking/manual brake controls explicitly block the common parking-brake button IDs when their physical wheel/handle tears off
- detached light assemblies disable nearby client light sources
- `mex_damage_reset` removes debris, clears blocked controls and restores the undamaged component state

The server validates detach requests against the damaged zone near the component's actual geometry anchor and validates requested Button IDs against the train's KeyMap/systems before disabling them.


### Local mounting impacts

Version 0.4.3 adds a separate local mounting-impact path for damage that should not globally deform the train body:

- crowbar/melee (`DMG_CLUB` / `DMG_SLASH`)
- bullets and buckshot
- local crush/vehicle contact
- explosions

The server stores a short-lived local impact around the actual damage/contact point. Clients resolve the visible Metrostroi `ClientEnts` around that point and request only the nearest eligible mounted components. The server then independently validates the request against the recent impact.

For low-energy local hits, the detach budget is normally one component. Large crush/blast impacts receive a larger radius and detach budget.

Small controls have priority over a backing panel/case occupying the same area, so hitting one button should not detach the full dashboard panel.

Structural deformation also uses much lower individual mounting thresholds for fragile controls. This prevents the old failure mode where a complete group of buttons could stay rigidly attached to a deformed `ButtonMap` and move across the cab as one cluster.


### Passenger-door leaf separation

The current 81-717 Metrostroi release renders each passenger doorway as one combined ClientEnt model (`81-717_doors_pos*.mdl`). Older individual leaf models (`door_right_spb.mdl` and `door_left_spb.mdl`) still exist in the content but their original ClientProp creation code is commented out upstream.

Damage System 0.4.4 uses those individual leaf models when a combined 81-717 passenger door tears off. The combined attached ClientEnt is hidden and two separate server-side debris entities are spawned with independent impulses and angular velocities.

If an installation does not contain the individual leaf models, the system falls back to detaching the combined door model instead of silently refusing the failure.

### Debris origin and animation

Metrostroi ClientEnt models may be authored with their model origin far away from the actual visible geometry. Damage debris therefore:

- places the physics entity at the real visual-geometry centre,
- creates a centred, slightly reduced box collision around the model extents,
- renders the MDL with an inverse model-centre offset,
- captures the current sequence, cycle and `position` pose parameter at detachment,
- freezes playback after detachment.

This keeps the visible debris aligned with its physics body and prevents detached controls/doors from continuing normal Metrostroi animation.

### Functional controller failures

Certain standalone ClientEnts do not have their own ButtonMap entry even though keyboard shortcuts operate the same physical device.

0.4.4 adds explicit functional mappings:

- KV/GRKV controller: `KVUp`, `KVDown`, unlock and direct KV positions are disabled when the physical controller detaches.
- driver brake valve/crane: `PneumaticBrakeUp`, `PneumaticBrakeDown`, direct brake positions and emergency braking input are disabled when the physical brake-valve model detaches.
- parking brake and disconnect valves retain their existing explicit mappings.

All of these are enforced by the server-side `ButtonEvent` guard, not only by hiding the clickable ClientEnt.
