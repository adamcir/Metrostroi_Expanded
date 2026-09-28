#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ADDON_NAME="metrostroi-expanded"

GMOD_ROOT="${1:-${GMOD_DIR:-}}"

if [[ -z "$GMOD_ROOT" ]]; then
    CANDIDATES=(
        "$HOME/.steam/steam/steamapps/common/GarrysMod"
        "$HOME/.local/share/Steam/steamapps/common/GarrysMod"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/GarrysMod"
    )

    for candidate in "${CANDIDATES[@]}"; do
        if [[ -d "$candidate/garrysmod" ]]; then
            GMOD_ROOT="$candidate"
            break
        fi
    done
fi

if [[ -z "$GMOD_ROOT" || ! -d "$GMOD_ROOT/garrysmod" ]]; then
    echo "Garry's Mod installation was not found."
    echo
    echo "Usage:"
    echo "  ./tools/install.sh /path/to/GarrysMod"
    echo
    echo "or:"
    echo "  GMOD_DIR=/path/to/GarrysMod ./tools/install.sh"
    exit 1
fi

ADDONS_DIR="$GMOD_ROOT/garrysmod/addons"
DEST="$ADDONS_DIR/$ADDON_NAME"
LEGACY="$ADDONS_DIR/metrostroi-passenger-seats"

mkdir -p "$ADDONS_DIR"

if [[ "$(readlink -f "$REPO_DIR")" == "$(readlink -m "$DEST")" ]]; then
    echo "Metrostroi Extended is already located in Garry's Mod addons:"
    echo "  $DEST"
    exit 0
fi

if [[ -d "$LEGACY" ]]; then
    echo "Removing legacy Metrostroi Passenger Seats addon to prevent duplicate loading:"
    echo "  $LEGACY"
    rm -rf "$LEGACY"
fi

echo "Installing Metrostroi Extended..."
echo "Source:      $REPO_DIR"
echo "Destination: $DEST"

rm -rf "$DEST"
mkdir -p "$DEST"

for file in addon.json README.md LICENSE; do
    if [[ -f "$REPO_DIR/$file" ]]; then
        cp -a "$REPO_DIR/$file" "$DEST/"
    fi
done

for dir in lua materials models sound scripts resource particles; do
    if [[ -d "$REPO_DIR/$dir" ]]; then
        cp -a "$REPO_DIR/$dir" "$DEST/"
    fi
done

echo
echo "Installed successfully."
echo "Restart Garry's Mod or change/restart the map before testing."
echo "Passenger seat status command: mps_status"
