# StormFox 2 train-weather integration

Optional module: `lua/autorun/metrostroi_expanded_stormfox2.lua`

This module is loaded by MEX itself and detects **StormFox 2** at runtime. It does not require StormFox 2 to be installed for MEX to run. StormFox 1 / Source `func_precipitation` continue to work with the original long-term damage simulation.

## Weather response

- **Rain:** Exterior wetness is still simulated mechanically under the open sky. It affects adhesion, battery corrosion and long-term neglect, but **not window glass**. No rain drops, refraction, streaks, tinting or weather-based glass overlays are rendered. Wetness evaporates with time, wind and warmth.
- **Freezing:** No frost, ice or other temperature-based effects are rendered on glass. The temperature still affects mechanical adhesion and may freeze passenger-door opening commands when a train is wet and parked outdoors. Closing and unrelated controls are not intentionally blocked.
- **Snow:** No snow accumulates or renders on the train. StormFox 2 snowfall can still affect rail adhesion and the original MEX neglect/weathering simulation.
- **Adhesion:** Wet/icy/snowy track conditions lower effective traction and pneumatic braking **force** for Metrostroi bogeys. The simulation temporarily scales bogey forces only while its physics `Think` runs; it restores the baseline values immediately afterwards, rather than modifying the brake cylinder pressure, the cab gauge or permanent bogey configuration. MEX exposes `MEX.Weather.Adhesion` (0.64–1).
- **Electrical / neglect:** Extended heavy rain causes very gradual battery corrosion, and precipitation increases the existing MEX neglect accumulation only for outdoor wagons. Unused wagons age much faster than operated ones. Snow and freezing moisture are counted at lower rates than sustained rain. Repairs/reset use the normal MEX damage state.
- **Lightning:** During StormFox 2 thunderstorms, an occasional eligible train with sky exposure and no clearly taller nearby solid entity can be targeted using `StormFox2.Thunder.Strike`. Strikes are **globally** rate-limited and can cause battery/electrical damage when electrical damage is enabled.

The sky-exposure check is approximate and based on a sky trace from the roof. A nearby brush-world building outside the roof trace is not always measurable.

## Glass

**The weather module does not draw or modify train glass.** Rain refraction, droplets and sliding water trails, frost, ice, snow and other weather-glass effects have been removed. The previous `PostDrawTranslucentRenderables` hook is also explicitly removed during client Lua reload. Legacy clients are sent `MEX.Weather.Visuals=false` as an extra compatibility guard. The old `mex_weather_visuals` and `mex_weather_quality` settings no longer control anything and are no longer registered by this module.

This does **not** disable physically broken windows or the separate, long-term train-neglect/damage system. It only removes glass reacting visually to StormFox 2 weather.

## ConVars (server)

| ConVar | Default | Meaning |
| --- | --- | --- |
| `mex_weather_enabled` | `1` | Master StormFox 2 weather simulation |
| `mex_weather_mechanics` | `1` | Low adhesion, iced door commands and slow battery corrosion |
| `mex_weather_lightning` | `1` | Occasional train lightning strikes |

Original MEX settings such as `mex_damage_electrical_enabled`, `mex_damage_neglect_enabled` and `mex_damage_neglect_scale` continue to control their respective damage features.

## Testing

1. Subscribe to/install StormFox 2 (not StormFox 1 at the same time). Open the StormFox 2 controller with `stormfox2_controller`.
2. Spawn Metrostroi wagons outside and under a station/roof. Run `mex_weather_status` in the server/admin console to see detected temperature, rain/snow, thunder, and wagon outdoor counts.
3. Trigger rain, frost and snow: verify that all train glass stays visually unchanged (no refraction, droplets, streaks, snow or frost). Adhesion, door mechanics and battery wear may still react.
4. Observe `MEX.Weather.Wet`, `MEX.Weather.Frost` (mechanics only), `MEX.Weather.Snow` (cleared to zero for compatibility), `MEX.Weather.Adhesion`, `MEX.Weather.DoorsIced` and `MEX.Weather.Exposed` as NW2 train variables when diagnosing the simulation.
5. Repair the wagon with the full Train Fixer / `mex_damage_reset` and check that accumulated deposits reset.

Lightning is random during real StormFox 2 thunder, not guaranteed on demand. To test a bolt independently, use StormFox 2's own lightning controls. Since the gameplay effects are implemented in Lua against external addons, test both the single-player and dedicated-server paths in Garry's Mod.
