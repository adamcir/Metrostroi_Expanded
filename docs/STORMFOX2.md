# StormFox 2 train-weather integration

Optional module: `lua/autorun/metrostroi_expanded_stormfox2.lua`

This module is loaded by MEX itself and detects **StormFox 2** at runtime. It does not require StormFox 2 to be installed for MEX to run. StormFox 1 / Source `func_precipitation` continue to work with the original long-term damage simulation.

## Weather response

- **Rain:** Exterior wetness increases under the open sky. A subtle refractive wet-glass layer and small, moving refraction trails follow the real side-window gaps between doorways; no luminous beam droplets or opaque full-side cards. Wetness evaporates with time, wind and warmth.
- **Freezing:** Below 0 °C, side windows gradually develop translucent Source-engine frosted-glass refraction, particularly along the pane edges, using the stock `models/props_c17/frostedglass_01a` shader. Wet, very cold, parked trains can suffer frozen passenger-door opening commands. Closing and other unrelated controls are not intentionally blocked. Warm air melts frost.
- **Snow:** Snow collects on wagon roofs after they have been standing still in snowfall. It blows off at higher speed, melts above freezing, and gradually disappears under cover.
- **Adhesion:** Wet/icy/snowy track conditions lower effective traction and pneumatic braking **force** for Metrostroi bogeys. The simulation temporarily scales bogey forces only while its physics `Think` runs; it restores the baseline values immediately afterwards, rather than modifying the brake cylinder pressure, the cab gauge or permanent bogey configuration. MEX exposes `MEX.Weather.Adhesion` (0.64–1).
- **Electrical / neglect:** Extended heavy rain causes very gradual battery corrosion, and precipitation increases the existing MEX neglect accumulation only for outdoor wagons. Unused wagons age much faster than operated ones. Snow and freezing moisture are counted at lower rates than sustained rain. Repairs/reset use the normal MEX damage state.
- **Lightning:** During StormFox 2 thunderstorms, an occasional eligible train with sky exposure and no clearly taller nearby solid entity can be targeted using `StormFox2.Thunder.Strike`. Strikes are **globally** rate-limited and can cause battery/electrical damage when electrical damage is enabled.

The sky-exposure check is approximate and based on a sky trace from the roof. A nearby brush-world building outside the roof trace is not always measurable. Window positions are estimated between passenger-door ClientProps (such as `door0x1` and `door1x1`). If a model has no reliable door layout, its glass effect is deliberately skipped rather than painted onto random metal surfaces. Addon train authors can supply accurate local-glass rectangles using `train.MEXWeatherWindowPanels = {{x=0, y=65, z=40, w=100, h=42, side=1}, ...}` on the client. Roof snow still uses the wagon bounding box. No original model materials are replaced.

## Window rendering

The previous `debugwhite` frost rectangles and `effects/beam_generic01` light beams were removed from the window pipeline. The current path uses Source's existing refractive frosted-glass material, a lighter refractive rain material sharing its Source normal map, and clipped per-window rivulets in 3-D local coordinates. The framebuffer is refreshed at most once per 3-D render pass.

Client convar `mex_weather_quality`: `0` disables visual effects, `1` is the standard cap, `2` allows more detail. This changes only rendering.

## ConVars (server)

| ConVar | Default | Meaning |
| --- | --- | --- |
| `mex_weather_enabled` | `1` | Master StormFox 2 weather simulation |
| `mex_weather_visuals` | `1` | Network wetness/frost/snow render state |
| `mex_weather_mechanics` | `1` | Low adhesion, iced door commands and slow battery corrosion |
| `mex_weather_lightning` | `1` | Occasional train lightning strikes |

Original MEX settings such as `mex_damage_electrical_enabled`, `mex_damage_neglect_enabled` and `mex_damage_neglect_scale` continue to control their respective damage features.

## Testing

1. Subscribe to/install StormFox 2 (not StormFox 1 at the same time). Open the StormFox 2 controller with `stormfox2_controller`.
2. Spawn Metrostroi wagons outside and under a station/roof. Run `mex_weather_status` in the server/admin console to see detected temperature, rain/snow, thunder, and wagon outdoor counts.
3. Trigger rain, then change the temperature below 0 °C. Check window streams, frost and wet train behaviour. Stop a wagon during snow to see accumulation.
4. Observe `MEX.Weather.Wet`, `MEX.Weather.Frost`, `MEX.Weather.Snow`, `MEX.Weather.Adhesion`, `MEX.Weather.DoorsIced` and `MEX.Weather.Exposed` as NW2 train variables if diagnosing the simulation.
5. Repair the wagon with the full Train Fixer / `mex_damage_reset` and check that accumulated deposits reset.

Lightning is random during real StormFox 2 thunder, not guaranteed on demand. To test a bolt independently, use StormFox 2's own lightning controls. Since the gameplay effects are implemented in Lua against external addons, test both the single-player and dedicated-server paths in Garry's Mod.
