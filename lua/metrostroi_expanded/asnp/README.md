# MEX Custom ASNP

MEX owns all announcer initialization, Metrostroi registration, compatibility with train spawners, and train display localization. Content addons contain only a line file and optionally one language file.

## Content addon structure

```text
lua/mex_asnp/
  lines/loopline.lua
  languages/ad.lua
sound/your_asnp/...
```

MEX discovers all `lua/mex_asnp/languages/*.lua` and `lua/mex_asnp/lines/*.lua` files and loads them on both realms. No autorun script or include/initialization code is required in the content addon.

## Line file

```lua
MEXASNP.RegisterPack("my_line", {
    name = "My ASNP",
    language = "en", -- en/cs built in; AD supplied by content addon
    maps = {"gm_my_map_"},
    lineName = "Line A",
    loop = false,
    soundRoot = "my_asnp",
    sounds = {
        next = {"common/next.wav", 2.0},
        arr = {"common/arr.wav", 2.0},
        station_101 = {"stations/101.wav", 2.0},
        station_102 = {"stations/102.wav", 2.0}
    },
    stations = {
        {id=101,name="Central"},
        {id=102,name="Terminal"}
    }
})
```

Station order is the array order; MEX generates Metrostroi arrival/departure announcements, direction-specific next stations and circular wraparound when `loop=true`. Specify gong, last, and doors_closing sounds as needed.

## Optional language file

```lua
MEXASNP.RegisterLanguage("xx", {
    ["route.number"]="Route",
    ["station.current"]="Current station",
    ["arrival.short"]="Arr:",
    ["departure.short"]="Dep:",
    ["error.unknown"]="Unknown phrase"
})
```

EN and CS live in MEX. MEX maps known original Metrostroi display strings to **semantic marks** in `API.Marks`, then looks up selected pack language. Unknown Cyrillic is logged and shown with `error.unknown`; add a new mapping in MEX's parser to support it. It does not transliterate Russian into another language. Display localization applies only to trains using a registered custom ASNP.

Other optional `MEXASNP.RegisterPack` fields: `routes` for advanced custom Metrostroi route structures and `led` for line LED configuration. WAV lengths are read from their headers with the configured duration as a fallback. Existing click1/click2/click3 messages are replaced with silent delays.

Install MEX alongside Metrostroi and the content addon; test in GMod after updating.
