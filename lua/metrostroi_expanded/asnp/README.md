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

## Universal ASNP train support

MEX exposes custom ASNP voices in the original Metrostroi Train Spawner for
**every compatible ASNP-equipped train**, not only Ezh3. Native 81-71 ASNP
devices in Ezh, Ezh3 (81-710), 81-717 MVM and 81-720 are supported; subclasses
of these are supported as well. More third-party train classes are detected
automatically after a live train demonstrates an ASNP device using
`AnnouncementsASNP`. A third-party addon may register its compatible train
class earlier with `MEXASNP.RegisterASNPTrainClass("gmod_subway_example")`.

MEX preserves the native option values: Ezh3 reserves UI option 1 for its RRI
cassette (ASNP IDs are offset by one), while other train classes use the ASNP
index directly. The stock server-side spawner callbacks and ASNP/RRI mode
selection are retained. Classes running RRI, UPO or Sarmat UPO *without* ASNP
are not modified, even if they have a similarly named Announcer option.

Known stock ASNP-equipped train classes expose the announcer selector **before
spawning their first train**, including Metrostroi variants whose spawner omits
the Announcer menu entirely. Third-party classes without a known ASNP system
can be detected after a real compatible train spawns, or registered explicitly.
Close and reopen the Train Spawner after new packs sync or new classes are
detected, as its option list is built when the UI opens.

On a multiplayer client, use `mex_asnp_spawner_status` to inspect Ezh3, or
`mex_asnp_spawner_status gmod_subway_81-717_mvm` (replace the argument with
the train class). It prints each available voice ID, whether the server's ASNP
data arrived and whether the Adamovian language dictionary was loaded.

Install/update the MEX core on both the dedicated server and clients. The
custom content addon (e.g. Adamovian Metro) must be installed on the server
with the sound WAVs. On joining, clients receive the matching route, announcer
ID and translation dictionary from the server.

**Map dependency:** Train support does not create a route on every map. A voice
appears only when a compatible custom ASNP line pack matches the current map;
Adamovian Metro currently supplies its own line packs for its configured maps.
Use `mex_asnp_spawner_status gmod_subway_81-717_mvm` to see whether the missing
menu comes from train compatibility, server synchronization, or an unsupported
map. Do not force a mismatched route onto another map: station announcements
would be wrong.
