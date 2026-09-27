# Metrostroi Expanded – Crash / Deformation Model

Damage System version: **0.6.3**

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


## Damage System 0.5.0

### Door coverage across trains

Passenger-door splitting is no longer specific to 81-717.

Known stock combined-door families are resolved to their original individual leaf assets for:

- 81-710 / Ezh / Em family
- 81-502 family
- 81-702 family
- 81-703 family
- 81-717 / 81-714 family
- 81-718 / 81-719 family
- 81-720 / 81-721 family
- 81-722 / 81-723 / 81-724 family

For Metrostroi-derived addon trains, the damage system also probes common sibling asset naming conventions next to a `*_doors_posN.mdl` model:

- `door_right.mdl` / `door_left.mdl`
- `door_l.mdl` / `door_r.mdl`

When no split leaf assets exist, the combined door still detaches as one physical object.

### Cab deformation

Cab/cabine/pult/panel models are tagged as cab structure and receive a stronger local deformation multiplier near a damaged vehicle end.

- existing weighted bones use the stronger local deformation field
- local cab shells and equipment mounts follow the stronger attachment displacement
- ButtonMap planes near a damaged cab end follow the same stronger deformation
- full-length salon shells still stay at the train origin and deform only through existing bones

This still cannot invent new bones or vertex weights in a compiled MDL.

### Glass

Separate glass/window ClientEnts are treated as fragile components.

A local hit can:

- remove/hide the intact glass ClientEnt
- emit a GlassImpact effect
- play a large-sheet glass break sound
- spawn short-lived networked physics glass shards

Controls such as `GlassWasher` and `GlassCleaner` are explicitly excluded from glass detection.

When a window is baked directly into the main carbody MDL/material and is not a separate ClientEnt/bodygroup, Lua cannot remove only that local pane without a prepared model/material variant.

### Keyboard shortcut failure

Generated Metrostroi button props use `config.name` or `button.ID`. The damage system maps a detached prop back to its ButtonMap ID and then expands related aliases from the train KeyMap.

Examples:

- `KDLSet` -> `KDL`
- `PneumaticBrakeSet1..7` -> the same pneumatic-brake control family
- Toggle/Set/Up/Down/Left/Right/On/Off variants are normalized into one control family

All matched events are server-blocked through the train's `ButtonEvent` wrapper, so a detached physical control cannot be operated by a keyboard shortcut.


### Standalone pneumatic controls

0.5.1 fixes controls whose visible hardware is not generated from a ButtonMap prop.

Examples include:

- `brake_valve_334`
- `brake_valve_013`
- `brake_disconnect`
- `train_disconnect`
- `valve_disconnect`
- EPK/EPV disconnect valves

These ClientEnts are classified as controls directly from their hardware/model identity even without a ButtonMap parent.

When such a part detaches, the client additionally searches ButtonMap button centres near the physical component anchor and removes the matching local hit targets. The corresponding IDs are sent to the server and expanded through the train KeyMap.

The server guards `ButtonEvent`, `OnButtonPress` and `OnButtonRelease`. This prevents mouse, keyboard, direct button-event paths and train-specific button handlers from continuing to operate a destroyed physical control.

A detached 334/013 driver's brake valve explicitly disables the complete `PneumaticBrake*` control family. Driver-valve, brake-line and train-line disconnect cocks disable their matching disconnect events.


## Damage System 0.6.0

### Structural crash model

0.6.0 changes the structural approximation from a simple smooth displacement field into a local load-path / collapse approximation.

Front/rear impacts now contain:

- an end crush zone around the contact point
- an axial attenuation into the vehicle
- a stronger deformation region near the crush/survival-volume boundary
- local bowing of side posts, roof and floor structure
- a small alternating fold term that becomes visible only where the MDL has enough weighted bones

Side impacts add a local wall crease around the intrusion field. Roof/floor impacts remain local to the contact zone.

This is deliberately not a soft-body solver. The goal is to make available Source bones/ClientEnt parts behave more like a rail carbody collapse while preserving the occupied volume for moderate impacts.

### Failure state is independent from deformation state

A component can now fail from a local crowbar/bullet/blast hit without requiring the whole train to enter a structural crush state.

Client failure state stores:

- detached ClientEnt names
- permanently disabled ButtonMap IDs
- disabled light sources
- broken glass material overrides

These are re-applied every update until `mex_damage_reset`.

This fixes the old case where the physical model disappeared but the next no-damage Think restored the original ButtonMap and left an invisible clickable switch/door/valve.

### Impact impulse and detached physics

Each local impact contains:

- impact point in train-local space
- impulse direction/magnitude in train-local space
- influence radius
- damage power
- detach budget
- whether the event is an explosion

When a mounting fails, the detached networked physics entity inherits train velocity and then receives an off-centre impulse at the actual impact point. This naturally adds both translation and torque.

Passenger-door leaves are treated independently after a combined Metrostroi door model is split.

### Explosion approximation

Explosion handling is a gameplay-scale impulse approximation, not CFD/FEA.

For each visible mounted ClientEnt inside the blast radius:

1. distance falloff is calculated from the blast centre
2. blast impulse is combined with radial direction away from the pressure centre
3. a component-type compliance factor estimates relative mounting movement
4. fragile glass/controls require very little predicted movement to fail
5. doors and larger mounted hardware require more movement
6. once predicted relative movement exceeds the mounting threshold, the part is detached and becomes independent physics debris

The same blast field is also applied to available structural bones / mounted ClientEnts, producing a local directional push and small wrinkle term instead of scaling the entire wagon.

### Embedded glass fallback

Many older Metrostroi trains do not expose cab windows as separate ClientEnt models. When the impacted body/cab model has material slots whose names look like glass/window/stekl, 0.6.0 stores their original submaterial overrides and replaces those glass slots with a transparent client material.

On reset, the original submaterial overrides are restored.

If the glass is baked into the same opaque material/mesh as the surrounding metal and has no separable material/bodygroup, Lua cannot create a true local hole in that compiled MDL. Such models require a prepared damage variant for fully physical glazing loss.


## Damage System 0.6.1

### Authoritative dead controls

A detached control now keeps two independent failure records:

1. server-side blocked ButtonEvent/KeyMap IDs
2. client-side dead ButtonMap hitboxes

The exact client-resolved ButtonMap IDs are accepted after the server validates the physical detach request against the real model, local anchor and recent impact. This covers old mouse-only controls that are absent from KeyMap.

Client hitboxes are not merely deleted. A private copy is replaced by a zero-size hitbox at an unreachable coordinate. This prevents temporary/cached Metrostroi references from keeping an invisible control interactive.

### Glazing classification

The embedded-glass fallback no longer treats every material containing the word `glass` as a window.

Only explicit window-like material paths are eligible, for example:

- window / windows
- windscreen / windshield
- stekl / stec

Panel, lamp, gauge, meter, indicator, button, display and screen material names are excluded.

Broken embedded glazing uses `tools/toolsnodraw`, avoiding the white opaque lenses produced by the former custom alpha material.

Passenger side-window impacts are detected separately from cab-window impacts. Shared body/salon window material slots can therefore be removed after a hit in the passenger compartment. A true per-pane hole still requires separate per-window geometry/materials in the source MDL.

### Detached door stability

Door debris uses a centred physics box but now receives a deliberate off-centre tipping impulse along its longest body axis after mount failure. Two short delayed wake-up checks prevent a tall thin leaf from going to sleep while balanced on its lower edge.

### Fallback local shell deformation

When a localized structural ClientEnt is available but its MDL has insufficient child bones, 0.6.1 applies a small crush matrix only to that localized shell. This is restricted to structural cab/body/mask/interior pieces and excludes doors, controls, lamps and panels.

No matrix is ever applied to scale the complete train entity.


## Damage System 0.6.2

Hotfix for Lua lexical scoping introduced during the 0.6.x rewrite.

`ApplyBreakawayImpulse` was defined before the local `LocalDirectionToWorld` declaration, so Lua resolved the name as a global inside that closure. The same issue affected `ApplyLocalStructuralCrushMatrix` and the later `ContainsAnyWord` helper/word tables.

The helpers/dependencies are now ordered before their first use (or made self-contained), eliminating the runtime `attempt to call global ... (a nil value)` errors.


## Damage System 0.6.3

### Physical control state is authoritative

A control is considered usable while its original physical ClientEnt is attached and visible.

For generated ButtonMap controls, the damage system first resolves an exact physical binding using `PropName`, generated model name, or lamp prop name. If an exact binding exists, no spatial-neighbour inference is performed.

Only after `MEX.ComponentDetached` confirms that exact component has become independent debris are its ButtonMap hitbox and related server-side keyboard aliases disabled.

Legacy standalone hardware such as driver valves/controllers may still require spatial association because upstream Metrostroi does not expose a direct ButtonMap prop link. That fallback now uses only the nearest candidate, preventing one detached item from disabling multiple neighbouring controls that remain physically attached.


## Front bone crumple deformation

Damage System 0.7.0 adds a front-only plastic crumple layer driven by existing MDL bones.

The deformation is evaluated in train-local space from the accumulated front damage and the stored front impact position. Bones near the front receive:

- progressive longitudinal crush
- local pull toward the impact centre
- crease/buckle displacement near the crush boundary
- small deterministic per-bone folding
- pitch/yaw/roll from off-centre impacts

The effect is intentionally plastic: the same damage state always produces the same deformed shape and remains until the wagon is reset.

This system can only deform vertices that are actually weighted to movable bones in the source MDL. A model with only a root bone cannot gain BeamNG-style soft-body deformation from Lua alone. Use `mex_damage_bones` while aiming at a train to inspect available body and front-region bones.

Physics/collision are not changed by this visual bone deformation.


## Weapon and physgun deformation inputs

Damage System 0.7.1 makes the front crumple system react to more than train-on-train crashes.

Weapon damage now contributes a small permanent structural deformation amount at the actual hit position. Repeated bullets, buckshot and melee strikes therefore progressively deform the front instead of only breaking detachable controls.

Physgun-driven impacts are detected through both old velocity vectors and Source's collision `Speed` value. The addon also tracks entities currently held or recently released by the physgun, because their old velocity values can be unreliable while the physgun moves them kinematically.

When a stock model does not contain enough weighted front bones, local structural ClientEnt shells use a stronger longitudinal crush fallback. This does not alter the collision mesh.


## Main body mesh fallback

Damage System 0.8.0 adds a vertex-mesh fallback for rigid stock train bodies, especially the 81-717/714 family.

The normal path still uses existing MDL bones. If the visible front shell is part of a rigid main model, the addon retrieves the model's visual triangle data, deforms the front vertices using the same persistent crash state, builds IMesh render parts, and installs an entity-specific RenderOverride for the damaged body.

The deformation uses the stored front impact centre and accumulated front damage to calculate:

- longitudinal crush depth
- radial falloff around the contact point
- local pull toward the impact bowl
- deeper propagation for severe crashes
- a fold/crease around the crush boundary

The original server collision mesh is not modified.

Useful client commands:

- `mex_damage_bones` — body/front bone capability plus mesh fallback state
- `mex_damage_mesh_status` — front damage, bone counts, mesh build state and render-part count
- `mex_damage_version` — exact loaded module version and source path


## Deformed-body attachments

Damage System 0.8.1 makes mounted front equipment follow the same final deformation field as the main-body mesh fallback.

This applies to localized ClientEnt assemblies such as masks, cab doors/windows, lamp groups, covers and cab shells. Their rigid anchor position and orientation are evaluated from the same crushed surface used by the deformed body mesh.

ButtonMap panel transforms and dynamic light transforms also use that field, so the visual control, clickable area and emitted light stay together after a front crash.

Full-length salon/interior shells are intentionally not translated as one rigid object.


## Front ClientProp vertex meshes

Damage System 0.9.0 extends the mesh fallback to large front ClientProps.

On trains such as the 81-717, the visible front mask is a separate rigid model. Moving that model as one attachment cannot produce a visibly crumpled nose. The addon now retrieves the mask/cab-shell triangle data, converts every vertex into train-local coordinates, applies the same front deformation field used by the main body, and renders the resulting IMesh through the ClientProp's RenderOverride.

The front deformation field in 0.9.0 also has increased crush depth and radial reach so medium damage is easier to see.

Use `mex_damage_mesh_status` to list currently active vertex-deformed ClientProps.
