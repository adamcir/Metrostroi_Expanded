# Metrostroi Expanded

**Metrostroi Expanded** is an unofficial open-source expansion for the Garry's Mod addon **Metrostroi Subway Simulator**.

The project is intended to grow into a larger realism/gameplay layer for Metrostroi. The first implemented module is the passenger-seat system.

## Passenger Seats

Current passenger-seat module version: **0.2.0**

It adds usable invisible `models/nova/jeep_seat.mdl` vehicle seats to the real passenger benches without modifying Metrostroi itself.

Supported official Metrostroi release classes include:

- 81-501 / 81-502
- 81-702 / 81-702 int
- 81-703 / 81-703 int
- 81-714 MVM / LVZ
- 81-717 MVM / LVZ
- 81-718 / 81-719
- 81-720 / 81-721
- 81-722 / 81-723 / 81-724
- Em508T
- Ezh / Ezh1 / Ezh3 (81-710)

Compatible third-party and future `gmod_subway_*` trains can also receive seats automatically when they expose Metrostroi's `GetStandingArea()` metadata.

The Tatra T3 entity is intentionally excluded because the current Metrostroi release does not expose enough passenger-saloon metadata to place seats reliably.

### Using a passenger seat

Walk up to a passenger bench, aim at the seat and press **E**.

Press **E** again to leave. The addon moves the player back into the aisle after exiting.

### Commands

- `mps_status` — show number of supported live trains and passenger seats
- `mps_rescan` — rescan already spawned trains
- `mps_debug_seats 1` — show passenger-seat interaction positions
- `mps_debug_seats 0` — hide debug positions


## Damage System

Current damage-system module version: **0.10.3**

Metrostroi Expanded now includes a first simple crash-damage system for all `gmod_subway_*` trains.

It currently provides:

- front, rear, left-side, right-side, roof and underframe/floor structural damage zones
- a **1000 ms spawn grace period** so Metrostroi initialization/coupling is never counted as a crash
- primary crash detection from Garry's Mod `PhysicsCollide`, using the actual contact position and pre-impact relative velocity
- velocity-change detection only as a fallback
- no global whole-wagon `RenderMultiply` scaling
- local front/rear crush, side intrusion and roof/floor contact deformation with a survival-space threshold: light impacts stay near the contact structure, severe impacts can intrude deeper into the cab/salon
- **bone-based mesh deformation** through `BuildBonePositions` + `SetBoneMatrix` wherever the existing MDL has usable weighted bones
- the main train body and structural ClientEnt models use the same deformation field
- full-length salon/interior shells remain at the train origin and may deform only through their own bones, so the entire interior cannot slide away from the carbody
- localized parts such as cab shells, front masks, doors, lamps and similar pieces remain rigid but follow their deformed mounting point
- interactive `ButtonMap` panels are shallow-cloned per wagon (nested Metrostroi runtime tables are not copied) and their generated buttons move with the same rigid panel transform, keeping controls usable
- train lights follow their deformed mounting points
- **server-authoritative breakaway components**: doors, lamps, switches, buttons, handles, brake wheels, covers, seats/fixtures and other localized mounted ClientEnt parts may tear off independently according to local deformation around their own mounting point
- detached components are real networked `mex_damage_debris` physics entities, visible to all players and manipulable with the Physgun/Gravity Gun
- debris physics is always recentered on the visible model geometry instead of the original Metrostroi model origin; this prevents detached parts from appearing to hang in mid-air while an offset collision hull rests on the ground
- combined passenger-door models are split into independent leaf models across the stock door families used by 81-710/Ezh/Em, 81-502, 81-702, 81-703, 81-717/714, 81-718/719, 81-720/721 and 81-722/723/724; addon trains also get a naming-convention fallback for `door_right/door_left` and `door_l/door_r` assets
- each component has a deterministic individual mounting threshold, so a crash can tear off only one nearby button or several components depending on impact location and severity
- **local mounting impacts** from crowbar/melee, bullets, buckshot, crush/vehicle contact and explosions resolve against the real ClientEnt geometry around the hit point; a normal pistol/crowbar hit usually releases only the nearest mounted component
- small controls are prioritized over the backing panel/case at the same hit location, preventing an entire dashboard plate from being selected when the player actually hit one switch/button
- fragile controls now release after very small local structural displacement, instead of travelling away together as one rigid ButtonMap cluster
- detached controls are blocked in the server-side `ButtonEvent` path, so neither mouse clicks nor Metrostroi keyboard shortcuts can operate a control after its physical part has torn off
- **keyboard alias expansion** automatically maps generated ButtonMap IDs back to related KeyMap events (for example `KDLSet` ↔ `KDL`, or pneumatic brake direct positions ↔ up/down events), so every generated button with a shortcut loses that shortcut when its physical control detaches
- standalone brake-valve hardware (`334`, `013`, brake/train/driver-valve disconnect cocks, EPK/EPV valves) is now treated as a control even when it is not a generated ButtonMap prop
- detached standalone controls also search nearby 3D ButtonMap hit targets and remove those local clickable regions; the server guard additionally wraps `OnButtonPress`/`OnButtonRelease`, so direct event paths cannot bypass a destroyed control
- detaching the main KV/GRKV controller blocks `KVUp`, `KVDown` and direct KV position shortcuts; detaching the driver brake valve blocks `PneumaticBrakeUp/Down` and the direct pneumatic-brake positions
- debris captures the component sequence/cycle/`position` pose at the moment of detachment, sets playback rate to zero and remains physically/visually static apart from rigid-body motion
- separate glass/window ClientEnts are treated as fragile components: local impacts can hide the intact pane, play a glass-break effect/sound and spawn physics glass shards
- cab/cabine/pult/panel structural ClientEnts receive a stronger local end deformation field than ordinary interior decorations while still avoiding whole-wagon scaling
- parking/manual-brake controls receive explicit fallback button blocking (`ParkingBrakeToggle`, `ParkingBrakeLeft`, `ParkingBrakeRight`) when their wheel/handle detaches
- detached lamp/headlight assemblies also disable nearby Metrostroi client light sources, preventing an invisible detached lamp from continuing to illuminate the world
- detached button hit targets are removed from the per-wagon panel copy so a button that physically tore off is no longer clickable; the corresponding server ButtonEvent IDs remain disabled until `mex_damage_reset`
- sparks, impact decals and smoke for harder impacts
- structural-health and generic electrical/door/equipment damage states
- `mex_damage_bones` to inspect the actual bone structure of the selected train and its structural ClientEnt models
- `mex_damage_debug 1` to show impact centres

Design notes and the crashworthiness references used for the rewrite are in [docs/DAMAGE_SYSTEM.md](docs/DAMAGE_SYSTEM.md).

The outer skin can only form a true local dent when the compiled Source model has vertices weighted to suitable bones. Version 0.4.2 keeps the stronger local crush/intrusion field from v0.4 while avoiding any global wagon scaling, and detects whether the selected body has non-root bones in the front region and prints a clear warning when true front-sheet denting is not available on the stock MDL. Garry's Mod can change existing bone matrices clientside, but it cannot add new bones/vertex weights to an already compiled MDL at runtime. On a single-root-bone shell, v0.4 deliberately leaves that shell rigid instead of producing the unrealistic stretched/cut-open wagon seen in the old global-scaling versions. For a full BeamNG-style skin on such a model, a locally prepared deformable MDL with additional deformation bones and weights is required.

### Damage test commands

Aim at a Metrostroi train and use:

```text
mex_damage_test front 0.25
mex_damage_test rear 0.25
mex_damage_test left 0.25
mex_damage_test right 0.25
mex_damage_status
mex_damage_reset
```

The amount is from `0.01` to `1.0`.

The module also exposes the `MetrostroiExpandedTrainDamaged` hook so future electrical, pneumatic, bogey and door-failure modules can react to the same crash event.

## Development installation

### Linux

```bash
git clone https://github.com/adamcir/Metrostroi_Expanded.git
cd Metrostroi_Expanded
chmod +x tools/install.sh
./tools/install.sh
```

The Linux installer automatically checks common Steam locations, including:

```text
~/.steam/steam/steamapps/common/GarrysMod
~/.local/share/Steam/steamapps/common/GarrysMod
```

You can also provide the Garry's Mod path explicitly:

```bash
./tools/install.sh /path/to/GarrysMod
```

or:

```bash
GMOD_DIR=/path/to/GarrysMod ./tools/install.sh
```


### Windows

Clone the repository and run:

```bat
tools\install.bat
```

The Windows installer checks the usual Steam installation, Steam registry entries and additional Steam libraries from `libraryfolders.vdf`.

You can also pass the Garry's Mod directory explicitly:

```bat
tools\install.bat "D:\SteamLibrary\steamapps\common\GarrysMod"
```

Or run the PowerShell installer directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\install.ps1 "D:\SteamLibrary\steamapps\common\GarrysMod"
```

Both installers copy the addon to:

```text
garrysmod/addons/metrostroi-expanded
```

If the old standalone `metrostroi-passenger-seats` addon is present, the installer removes it to prevent the same passenger-seat module from loading twice.

## Dependency

Metrostroi Expanded requires **Metrostroi Subway Simulator** to be installed separately.

Original Metrostroi code, train models, textures and other assets are not redistributed by this repository and remain under their respective licenses.

## License

Metrostroi Expanded's own source code is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE).


### Damage 0.5.2 fixes

- adds an `OnKeyEvent` guard before Metrostroi can execute `OnKeyPress/OnKeyRelease`, fixing controls such as pneumatic F/R that could react before the existing `ButtonEvent` blocker
- restricts geometry-nearest ButtonMap matching to standalone valve/controller hardware; arbitrary props no longer steal nearby large door hitboxes
- explicitly excludes `FrontDoor`, `RearDoor`, `CabinDoor` and `PassengerDoor` from paired passenger-door leaf splitting; only true `doorNx0/doorNx1` side-door ClientEnts are eligible


### Damage 0.6.0 – impulse/failure rewrite

Damage 0.6.0 separates **structural deformation** from **component failure**.

- detached components remain permanently hidden and non-interactive until `mex_damage_reset`, even when the hit did not create enough structural crush to keep a deformation state alive
- disabled ButtonMap IDs are stored separately from the deformation field and are re-applied every client update, preventing an invisible control from becoming clickable again
- older manual door props such as `door1` / `door2` can be associated with nearby `FrontDoor` / `RearDoor` / `CabinDoor` hit targets, but the spatial association is restricted to button IDs containing `Door` so it cannot steal unrelated controls
- collision and explosion events now carry a local impulse vector in addition to damage/radius
- released physics debris receives its impulse through `PhysObj:ApplyForceOffset` at the actual impact point, producing both translation and rotation instead of a generic random kick
- split passenger-door leaves receive independent impulses so both leaves can physically separate
- explosion damage uses radial distance falloff and a predicted relative movement threshold; if blast loading would move a mounted component even slightly, its mounting is considered failed and the component detaches
- blast events can release many nearby components independently rather than using a tiny fixed detach count
- separate glass ClientEnts still shatter normally; for glass baked into a larger cab/body model the addon now attempts to hide dedicated glass/window material slots with a client material override and emits glass impact/shard effects
- front/rear deformation now includes a local crush-boundary buckle/crease, while side impacts include local wall creasing; explosion pressure adds a local directional displacement/wrinkle field
- the solver still never globally scales the whole wagon

The visual body deformation remains limited by the bones and vertex weights present in the compiled MDL. If a stock body uses only one root bone for a large sheet, Lua cannot create new local vertex weights at runtime.


### Damage 0.6.1 fixes

- exact mouse-only ButtonMap IDs from a server-verified detached component are blocked even when they do not exist in the server KeyMap
- disabled client hitboxes are replaced with private zero-size dead hitboxes at an unreachable panel coordinate, so cached Metrostroi button references cannot remain clickable
- detach requests can carry up to 48 resolved button IDs instead of 16
- embedded glazing now uses `tools/toolsnodraw`; the old custom white transparent material was removed
- embedded-glass fallback only targets explicit window/windscreen/stekl material names and excludes panel/light/gauge/indicator/display materials, preventing broken indicator lenses from turning white
- passenger-compartment side window hits are now detected independently from cab-window hits and can remove shared passenger-window material slots on the body/salon shell
- detached doors receive an off-centre tipping moment plus short wake-up checks so tall leaves do not remain balanced upright on their bottom edge
- localized structural ClientEnt shells such as cab masks/body shells get a small per-piece crush matrix when the underlying stock MDL does not expose enough useful deformation bones; the whole wagon is still never globally scaled


### Damage 0.6.2 hotfix

- fixes a Lua lexical-scope crash where `ApplyBreakawayImpulse` referenced `LocalDirectionToWorld` before its local declaration
- fixes the same class of bug in `ApplyLocalStructuralCrushMatrix`, which referenced later-local `ContainsAnyWord` / breakaway word tables
- direction-conversion helpers now live before their first use and the local structural-crush filter no longer depends on later declarations
- a full-file scan for local-function calls before declaration found no remaining forward-reference hazards except an intentionally nested local helper


### Damage 0.6.3 – attached vs detached control semantics

Controls now follow one strict rule:

- while the original physical ClientEnt is still attached/visible, the control remains fully usable
- only after the server confirms that exact physical component detached does mouse/keyboard interaction get disabled
- generated ButtonMap controls use only their exact physical prop -> button ID relationship; no nearest-neighbour inference is allowed for them
- spatial fallback is used only for legacy standalone hardware without a direct prop binding, and only the nearest matching control is considered
- related keyboard aliases are still disabled after confirmed detachment of the same physical control
- neighbouring controls which remain physically attached stay functional


### Damage 0.6.4 – physical attachment is the source of truth

- a generated ButtonMap control with an exact physical ClientEnt binding never uses nearest-neighbour inference
- while that ClientEnt is visible and not detached, its original hitbox is restored and the control remains usable
- only after the server confirms that exact ClientEnt as detached is its mouse hitbox and related keyboard control disabled
- standalone legacy hardware without a direct ButtonMap prop link still uses a nearest-control fallback
- server blocked controls are rebuilt from the set of currently physically detached components instead of accumulating stale blocked IDs


### Damage 0.6.5 – exact physical control ownership

- exact ButtonMap controls now use per-binding dead state (panel + button slot + physical ClientEnt), not a global disabled ButtonEvent ID
- if two attached physical controls share one ButtonEvent, detaching one kills only its own hitbox; the shared function remains available through the other attached control
- the server blocks a shared ButtonEvent only after the last exact physical provider is detached
- standalone hardware such as brake valves, disconnect cocks and legacy manual doors remains authoritative by itself; logical/invisible ButtonMap hit targets are not allowed to keep a visibly detached mechanism functional
- doors use the same rule: attached physical door/control parts remain usable, detached physical door/control parts are non-interactive


### Damage 0.6.7 – ButtonMap/door state rewrite

- fixes a systemic ButtonMap cloning bug: damaged per-wagon panels now get a private `buttons` container, so replacing a damaged button no longer mutates the original Metrostroi ButtonMap definition
- exact dead physical bindings are enforced even when the global standalone-control disabled-ID list is empty
- detached controls also use Metrostroi's native `Hidden.button` state, which its own `findAimButton()` checks for tooltip and mouse interaction every frame
- shared ButtonEvent IDs are hidden globally only when no other attached physical provider remains
- legacy doors/mechanisms can resolve their physical ClientEnt through `button.model.var` (for example `FrontDoor` -> `door1`) when that ClientEnt exists
- reset restores all native Hidden overrides recorded by the damage system


### Damage 0.6.8 – reverser key isolation

- fixes the keyboard damage guard so modifier tables are no longer treated as one giant failure group
- only the event actually selected by the current key/modifier combination is checked for damage
- key releases always pass through so a control cannot remain latched after breaking
- traction-controller damage no longer disables reverser-key insertion/removal or `KV_Unlock`
- `KVWrenchKV`, `KVWrenchKV9`, `KVWrenchKRU`, `WrenchKRO`, `WrenchKRR`, `WrenchNone` and related reverser movement events are disabled only when a physical reverser/reverser-wrench mechanism detaches
- classic `reverser` / `krureverser` / `rcureverser` and modern `KRO` / `KRR` hardware are recognized separately from the traction controller


### Damage 0.6.9 – control hierarchy and valve reliability

- generated control accessories now have one-way ownership: `*_pl`, `*_lamp*` and `*_label*` can detach independently without disabling the parent switch
- detaching the actual parent switch/control automatically requests detachment of its attached label/plomb/lamp/cap children
- a precise crowbar/pistol/rifle hit selects one physical root component only; spare detach capacity is reserved for that root's children, preventing a hit on a label from also ripping out the switch underneath it
- healthy ButtonMap slots are no longer copied/replaced every render frame; only previously dead bindings are reconciled, improving click reliability of undamaged switches after any damage event
- parking/manual/hand-brake hardware disables its complete parking-brake event family after physical detachment
- classic `FrontBrake`, `FrontTrain`, `RearBrake`, `RearTrain` valve props are bound directly to their corresponding line-isolation events
- `brake_disconnect`, `train_disconnect`, `EPK_disconnect` and `EPV_disconnect` are handled as independent physical valve failures


### Damage 0.6.10 – authoritative pneumatic hardware failure

- detached 81-717 `brake334` / `brake013` handles are recognized as the physical 334/013 driver's brake valve, not merely as nearby cabin props
- losing the driver's pneumatic brake valve blocks `PneumaticBrakeUp`, `PneumaticBrakeDown`, positions 1–7 and emergency-brake input paths
- front/rear brake-line and train-line isolation cocks are re-derived from the validated detached component on the server, so their original interaction cannot survive a missing client-side ButtonMap association
- cab shut-off valves (`brake_disconnect`, `train_disconnect`, `valve_disconnect`, EPK/EPV) and parking-brake hardware use the same authoritative fallback
- the client still kills the corresponding ButtonMap hitboxes, while the server independently rejects keyboard/ButtonEvent paths


### Damage 0.6.11 – driver cab shut-off valves

- classic cab shut-off valves now bind their real ClientProp to the ButtonMap through `model.sndid` when available
- `DriverValveBLDisconnectToggle` is physically owned by `brake_disconnect`
- `DriverValveTLDisconnectToggle` is physically owned by `train_disconnect`
- `DriverValveDisconnectToggle` is physically owned by `valve_disconnect`
- EPK/EPV and parking/emergency-brake valve aliases also resolve to the currently visible physical ClientProp
- after that physical valve detaches, its exact ButtonMap hitbox is replaced by a dead hitbox and the server-side event remains blocked


### Damage 0.6.12 – cab valve resolver scope fix

- fixed a Lua scope error where `BuildPanelPropMap()` could call `GetButtonPhysicalPropName` as an undefined global
- the physical-control resolver is now forward-declared and assigned in the same client-side local scope


### Damage 0.6.13 – 81-717 driver BL/TL valve back-door fix

- generated `DriverValveBLDisconnect*` and `DriverValveTLDisconnect*` names are now recognized as the same physical cab cocks as `brake_disconnect` / `train_disconnect`
- detaching either 334 cab cock blocks its own direct ButtonMap action
- it also blocks the shared `DriverValveDisconnect` keyboard action used by 81-717 MVM (`NUM0` / `Shift+L`), because that path otherwise toggles both BL and TL valves together
- the other physically intact cab cock remains independently usable through its own ButtonMap


### Damage 0.7.0 – front bone crumple deformation

- front impacts now add a dedicated plastic deformation layer on top of the existing structural deformation field
- weighted front bones are progressively pushed inward according to crash severity and depth into the carbody
- off-centre hits pull and twist the nose toward the impact point instead of producing a perfectly symmetric flat crush
- neighbouring bones receive deterministic crease/fold offsets, creating an accordion-like crumple effect when the MDL has enough weighted bones
- light impacts remain concentrated in the sacrificial front structure; severe impacts propagate deeper toward the cab survival space
- deformation is deterministic and persistent until `mex_damage_reset`; it does not jitter or accumulate every rendered frame
- this is visual mesh deformation only: Source collision meshes remain unchanged


### Damage 0.7.1 – weapon and physgun impact deformation

- bullets, buckshot and melee hits now feed the structural damage accumulator instead of only detaching individual ClientProps
- weapon hits use the real impact position for the deformation centre; the fallback aim trace was extended from 160 SU to 32768 SU
- PhysicsCollide now uses `collisionData.Speed` in addition to old velocity vectors, which is important for physgun-driven motion
- entities currently held or recently thrown with the physgun are tracked and use a lower collision threshold plus a stronger impact response
- physgun collisions may register more frequently than ordinary train collisions so repeated destructive testing produces visible progressive crush
- front structural ClientEnt shells receive stronger longitudinal compression as a fallback when the stock MDL has too few weighted front bones


### Damage 0.7.2 – physical button resolver ordering fix

- `GetButtonPhysicalPropName()` is now defined completely before `BuildPanelPropMap()`
- removed the forward-declaration / later-assignment pattern that could still leave the resolver nil at runtime
- fixes `attempt to call global 'GetButtonPhysicalPropName' (a nil value)` from `BuildPanelPropMap`


### Damage 0.7.3 – remove early panel resolver dependency

- `BuildPanelPropMap()` no longer calls `GetButtonPhysicalPropName()`; it resolves the small set of early physical-provider hints locally
- this removes the exact crash path `BuildPanelPropMap -> GetButtonPhysicalPropName nil` even under hot reload / older initialization ordering
- the damage module now prints its version and source path when loaded
- added `mex_damage_version` so a running GMod instance can show the exact loaded module version and file path


### Damage 0.8.0 – real main-body front crumple fallback

- 81-717/714 front deformation no longer depends only on weighted MDL bones
- properly rigged models still use the existing bone deformation path
- rigid stock bodies now build a deformed copy of the main visual MDL with `util.GetModelMeshes` and render it through a per-entity `RenderOverride`
- front vertices are pushed inward from the actual hit position with depth/radial falloff, impact-bowl pull and an accordion-like crush boundary
- the main body mesh is rebuilt only when the accumulated front damage / impact centre / skin / bodygroup state changes
- large material meshes are split below the 65535-vertex IMesh limit
- if a workshop bodygroup mask cannot be read, the mesh loader retries with the default bodygroup layout instead of silently disabling deformation
- `mex_damage_bones` now reports whether the mesh fallback is active
- added `mex_damage_mesh_status` for exact client-side deformation diagnostics
- collision geometry is unchanged; this remains a visual deformation system


### Damage 0.8.1 – glue front equipment to the crumpled shell

- front ClientEnts now sample the exact same visual deformation field as the generated main-body crumple mesh
- masks, cab doors, windows, lamps, covers, cab shells and other localized front assemblies therefore stay attached to the deformed body instead of floating at their original coordinates
- ButtonMap panel planes use the same deformed position and orientation, keeping clickable areas aligned with moved controls
- dynamic Metrostroi light positions/angles follow the crushed shell as well
- larger localized cab/front assemblies that exceeded the old 230 SU local-piece cutoff can now follow the front deformation, while full-length saloon/interior shells remain protected from being moved as one rigid object


### Damage 0.9.0 – vertex-deform the visible front mask

- the large 81-717 front `mask_*` ClientProps are no longer moved only as rigid panels
- selected large front shell ClientProps (mask/cab shell/nose-style models) are converted to their own deformed IMesh and warped in train-local space with the same field as the main body
- this fixes the visually dominant front panel staying almost perfectly flat while the main carbody behind it was already crumpled
- front crush reach, radial area and longitudinal displacement were increased so medium accumulated damage is clearly visible
- smaller lamps, windows, controls and other front equipment continue to follow the final damaged surface as mounted rigid parts
- `mex_damage_mesh_status` now lists all ClientProps with an active vertex-deformation mesh


### Damage 0.10.0 – cumulative crush and whole-wagon scrap phase

- logical subsystem damage still stays normalized to 0..1, but each damage zone now also tracks separate plastic crush energy up to 6.0
- further crashes, bullets, buckshot, blasts and physgun impacts keep increasing crush after logical damage has already reached 1.0
- normal local denting is still front-focused, but once overall crush exceeds the critical range the wagon enters a whole-body scrap phase
- scrap deformation progressively pushes the crush boundary through the entire carbody, accordion-compresses its length, pulls the sides inward and lowers the roof toward a thin slab
- at very high crush energy a wagon can be visually compressed to a small fraction of its original length/height instead of freezing at one final dent
- large structural ClientProps are selected by geometry as well as model/name heuristics, improving compatibility with custom trains that split the shell into arbitrary ClientProps
- large body panels and doors are kept attached longer so they deform with the shell before being allowed to tear away; small glass, lights, covers and controls can still fail earlier
- added `mex_damage_scrap_test [energy]` (default 3.0, max 6.0) for quickly testing deep crush without repeatedly hitting the train
- `mex_damage_status` / `mex_damage_mesh_status` expose crush energy for debugging


### Damage 0.10.2 – interior and seat attachment during scrap crush

- once whole-wagon scrap deformation starts, remaining cabin/saloon ClientProps no longer use the old local-piece/full-length cutoff
- seats, benches, couches, handrails, cabinets and other interior fixtures now follow the same crushed mounting field as the body
- long seat rows and large interior assemblies may be vertex-deformed in the scrap phase instead of remaining at their original coordinates
- only true running gear such as bogies, wheels, axles, couplers and traction/mechanical equipment stays on the original physics chassis
- interior fixtures are kept attached much deeper into the scrap phase so they crumple with the cabin instead of becoming floating debris too early


### Damage 0.10.3 – Utilities damage settings

- added **Utilities → Metrostroi Expanded → Damage**
- added a server-wide **Enable damage** checkbox
- added a server-wide **Enable deformation** checkbox
- deformation can only be enabled while damage itself is enabled
- disabling damage also disables deformation and resets current Metrostroi Expanded damage/debris state on spawned trains
- damage disabled: collisions, weapons, physgun impacts and detach requests no longer feed the damage system
- deformation disabled while damage remains enabled: subsystem failures, detached controls and damage state remain active, but carbody/interior visual deformation is cleared
- settings are archived replicated server ConVars: `mex_damage_enabled` and `mex_damage_deformation_enabled`
- Utilities controls are editable by server admins; clients still see the current replicated state
