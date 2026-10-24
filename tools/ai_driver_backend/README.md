# MEX AI Driver backend

Standalone Node.js 18+ NDJSON/TCP-to-Ollama bridge for Metrostroi Expanded.
No npm dependencies. Ollama makes high-level decisions; train actuation stays inside the addon.

## Install

### Required server-side LuaSocket module

The Lua bridge uses `require("socket")` to connect to the Node.js TCP backend. **LuaSocket is not included in GMod or in the MEX addon.** The addon now checks for it before calling `require`, so a missing module is handled without the engine's `Couldn't include file 'includes\\modules\\socket.lua'` error. AI attachment stays disabled until the dependency is usable; other MEX features remain available.

Install [gmod_luasocket](https://github.com/danielga/gmod_luasocket) into the **Garry\'s Mod server instance** (for singleplayer, this is your local Garry\'s Mod installation):

- Copy its `includes/modules/` Lua files to `garrysmod/lua/includes/modules/`, including `socket.lua`.
- Install the matching **server-side** LuaSocket binary modules (including `socket.core`) in `garrysmod/lua/bin/`. You need a build matching the actual server OS and architecture (`gmsv_` prefix), not a client-only `gmcl_` build.
- Restart GMod or the dedicated server. Check from the **server** console with `mex_ai_status`: it must show `LuaSocket=OK` before attaching an AI driver.

Placing `socket.lua` under an addon or copying only the Lua part is not enough; the native `socket.core` module is also required. An installed Node.js backend does not provide the in-game LuaSocket module by itself. When MEX prints `LuaSocket is not installed on the server`, check the paths above. A failed `require("socket")` is not a Metrostroi train or ASNP/RPI error.

### Install Node.js backend

From repository root on Windows (PowerShell):
  powershell -ExecutionPolicy Bypass -File .\scripts\install_ai_backend.ps1

On Linux:
  sh ./scripts/install_ai_backend.sh

Default installation paths:
- Windows: %LOCALAPPDATA%\MetrostroiExpanded\AIBackend
- Linux: ~/.local/share/metrostroi-expanded/ai-backend (or XDG_DATA_HOME)

Run generated start_backend.cmd or start_backend.sh. Pull the model beforehand: ollama pull qwen3:8b.
An existing driver_guide.md is preserved on upgrades by default. Explicitly use
-ForceGuide (PowerShell) or --force-guide (shell) to replace it.

Run node --test from backend folder to check the protocol.

## Environment

MEX_AI_HOST=127.0.0.1, MEX_AI_PORT=3002, OLLAMA_URL=http://127.0.0.1:11434,
OLLAMA_MODEL=qwen3:8b, MEX_AI_TIMEOUT_MS=20000, MEX_AI_MAX_ACTIVE=2.

Only set MEX_AI_HOST to a trusted local-LAN IP when needed; no authentication or encryption.
One JSON request per connection terminated with newline; JSON response with newline.
