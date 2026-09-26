# Metrostroi Expanded – Crash / Deformation Model

Damage System version: **0.4.2**

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
