#!/bin/sh
# MEX AI Driver backend installer (Linux / POSIX shell)
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/tools/ai_driver_backend"
DEST=""
FORCE=0
PULL=0
START=0
MODEL="qwen3:8b"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dir) [ "$#" -ge 2 ] || { echo "--dir requires path" >&2; exit 2; }; DEST=$2; shift 2 ;;
        --model) [ "$#" -ge 2 ] || { echo "--model requires value" >&2; exit 2; }; MODEL=$2; shift 2 ;;
        --force-guide) FORCE=1; shift ;;
        --pull-model) PULL=1; shift ;;
        --start) START=1; shift ;;
        *) echo "Unknown option $1" >&2; exit 2 ;;
    esac
done
case "$MODEL" in *[!a-zA-Z0-9_./:-]*|"") echo "Invalid model name" >&2; exit 2 ;; esac
command -v node >/dev/null 2>&1 || { echo "Node.js >=18 required" >&2; exit 1; }
MAJOR=$(node -p 'parseInt(process.versions.node.split(".")[0],10)')
[ "$MAJOR" -ge 18 ] || { echo "Node.js >=18 required" >&2; exit 1; }
if [ -z "$DEST" ]; then
    BASE="${XDG_DATA_HOME:-}"
    if [ -z "$BASE" ]; then BASE="$HOME/.local/share"; fi
    DEST="$BASE/metrostroi-expanded/ai-backend"
fi
[ -f "$SRC/mex_ai_server.js" ] || { echo "Source backend missing: $SRC" >&2; exit 1; }
mkdir -p "$DEST/test"
for ITEM in mex_ai_server.js driver_guide.md chat_guide.md package.json example_request.json README.md test/server.test.js test/chat.test.js; do
    if { [ "$ITEM" = driver_guide.md ] || [ "$ITEM" = chat_guide.md ]; } && [ -f "$DEST/$ITEM" ] && [ "$FORCE" -eq 0 ]; then
        echo "Preserving customized driver_guide.md"
    else
        cp "$SRC/$ITEM" "$DEST/$ITEM"
        echo "Installed $ITEM"
    fi
done
printf '#!/bin/sh\nset -eu\ncd "$(dirname "$0")"\nif [ -z "${OLLAMA_MODEL:-}" ]; then OLLAMA_MODEL="%s"; fi\nexport OLLAMA_MODEL\nexec node mex_ai_server.js\n' "$MODEL" > "$DEST/start_backend.sh"
chmod +x "$DEST/start_backend.sh"
if ! command -v ollama >/dev/null 2>&1; then
    echo "Warning: Ollama not found." >&2
elif [ "$PULL" -eq 1 ]; then
    ollama pull "$MODEL"
fi
echo "Installed to $DEST (TCP 127.0.0.1:3002)"
if [ "$START" -eq 1 ]; then
    cd "$DEST"
    OLLAMA_MODEL="$MODEL" node mex_ai_server.js
else
    echo "Start with $DEST/start_backend.sh"
fi
