# MEX AI Driver backend

Standalone Node.js 18+ NDJSON/TCP-to-Ollama bridge for Metrostroi Expanded.
No npm dependencies. Ollama makes high-level decisions; train actuation stays inside the addon.

## Install

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
