# MEX RPI / RRI announcements

MEX loads custom cassette-style RPI packs from content addons. Metrostroi internally calls the legacy system **RRI**; the MEX API is deliberately named **MEXRPI**.

## Content addon layout

```text
lua/mex_rpi/lines/adamovian.lua
sound/adamovsky_announcer/common/next.wav
sound/adamovsky_announcer/suburb/101.wav
```

MEX finds and includes `lua/mex_rpi/lines/*.lua` on server and client, as it does for ASNP. Do **not** add an autorun loader in the content addon.

## Share an ASNP pack (recommended)

```lua
MEXRPI.RegisterPack("my_route", {
    name = "My RPI",
    sourceASNP = "my_existing_asnp_route"
})
```

`sourceASNP` reuses that pack's map prefixes, stations, soundRoot, sound keys, lineName, loop and LED settings. The source ASNP pack may be loaded later; MEX retries after discovery.

## Standalone RPI pack

```lua
MEXRPI.RegisterPack("route_a", {
    name = "My RPI",
    maps = {"gm_my_map"},
    lineName = "Route A",
    loop = false,
    soundRoot = "my_announcer",
    sounds = {
        gong_1 = {"common/gong.wav", 2.0},
        arr = {"common/arr.wav", 3.0},
        next = {"common/next.wav", 4.0},
        doors_closing = {"common/doors.wav", 3.0},
        last = {"common/last.wav", 3.0},
        station_101 = {"stations/101.wav", 2.0},
        station_102 = {"stations/102.wav", 2.0}
    },
    stations = {
        {id = 101, name = "Central"},
        {id = 102, name = "Terminal"}
    }
})
```

The engine builds the two-direction `arr`, `dep` and `arrlast` cassette sequences from the stations. An advanced pack may supply `routes` (Metrostroi RRI route table or a function returning one). It queues numeric silent delays for unavailable WAV files rather than trying to play invalid keys.

**RRI limitation:** Metrostroi exposes one map-wide RRI cassette configuration. On a matching map, MEX installs the chosen RPI pack in place of the stock cassette; ASNP remains a separate selectable system. The train must already support RRI hardware. RPI does not alter the ASNP spawner list.

To inspect registration and missing files, run `mex_rpi_status` in the game console. Respawn existing RRI trains after addon updates or map reloads if they retained the old cassette table.


## Continuous circular lines (including Suburb Construct)

Use both `loop = true` and `continuousLoop = true` in the ASNP pack. If RPI
references that pack via `sourceASNP`, it inherits the same circle. MEX creates
normal arrival and departure announcements at *every* stop, including the
depot, without an artificial terminal. The Suburb Construct order is:

`Depo (101) -> Centrum (102) -> Prumyslova (103) -> Luka (104) -> Depo (101)`.

Pressing the RRI/ASNP announce button alternates departure/arrival. Thus
departing Luka should announce **Depo**, arriving at Depo should announce
**Depo**, and the next departure should announce **Centrum**. Existing trains
can retain the old Metrostroi route table; MEX now refreshes map-wide RRI
references without needing to delete or respawn those trains.

## Multiplayer

The content addon and MEX core must both be installed on the server.
On matching maps MEX adds available pack WAVs to Garry's Mod's download list,
reconciles ASNP announcer indexes with the server for each client, and sends
the custom voice playback events reliably (stock Metrostroi uses unreliable
messages). Clients may need to reconnect if their content was missing before
the server installed it.

Useful commands on both the server and each client:

- `mex_rpi_route_status` — live RPI cassette station order and WAV presence.
- `mex_asnp_route_status` — installed ASNP routes, IDs, and WAV presence.
- `mex_announcer_mp_status` — local/server pack IDs and current train
  announcement positions; use it on both sides to diagnose mismatches.

The successful check at the end of Suburb line A has four unique IDs
`101, 102, 103, 104`, `loop=true`, `continuous=true`. Existing stock
Metrostroi cabs still need real RRI/ASNP hardware.
