# MEX universal ASNP loader

MEX registers ASNP announcers provided by other GMod addons. Install MEX and Metrostroi; content addons can register languages and line packs without editing MEX itself.

## API

```lua
MEXASNP.RegisterLanguage("xx", {
    next = "Next station",
    arr = "Arriving at"
})

MEXASNP.RegisterPack("my_city_line", {
    name = "My city ASNP",
    language = "xx",
    maps = {"gm_mycity_"},
    soundRoot = "my_city_asnp",
    sounds = {
        next = {"common/next.wav", 2.5},
        arr = {"common/arr.wav", 2.5},
        station_101 = {"line1/101.wav", 2.0}
    },
    routes = function(pack)
        return {{
            Name = "Line 1", Loop = false,
            {101, "Central", "Central",
             arr = {{"arr","station_101"},{"arr","station_101"}}}
        }}
    end
})
```

Register on **both server and client**. `maps` are prefixes of `game.GetMap()`. `soundRoot` is relative to `garrysmod/sound/`, and the numeric sound duration is only used when the WAV header cannot be read. The framework automatically adds silent click keys, adds a small gap after files, retries registration as Metrostroi starts, and exposes each registered pack in legacy train spawners. English (`en`) and Czech (`cs`) are bundled.

`MEXASNP.Translate(language, key)` resolves a phrase from the registered language dictionary, with an English fallback. Packages can use it for their own UI; they remain responsible for any special display hooks or other train-specific behavior.

For independent addons, register using a retry timer if MEXASNP has not loaded yet. Do not edit the built-in English/Czech dictionaries to add your own language.

Adamovian Metro includes an example: `adamovsky-asnp/languages/ad.lua` and `adamovsky-asnp/maps/loopline_pack.lua`.
