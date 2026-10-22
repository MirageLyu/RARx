#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/build/RARx.app"
DEST="/Applications/RARx.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: RARx installs on macOS only" >&2
    exit 1
fi

if [[ ! -d "$SOURCE" ]]; then
    echo "App not built yet; building..."
    "$ROOT/scripts/build-app.sh"
fi

codesign --verify --deep --strict "$SOURCE"

# Stop any running copy. A running extraction is cancelled by the app's normal
# termination path, but replacing the bundle requires the process to exit.
pkill -x RARx 2>/dev/null || true
for _ in $(seq 1 30); do
    pgrep -x RARx >/dev/null 2>&1 || break
    sleep 0.1
done
if pgrep -x RARx >/dev/null 2>&1; then
    echo "warning: RARx is still running; sending SIGKILL" >&2
    pkill -9 -x RARx 2>/dev/null || true
    sleep 0.2
fi

TMP="/Applications/.RARx.app.installing.$$"
BACKUP="/Applications/.RARx.app.backup.$$"
cleanup() {
    rm -rf "$TMP"
}
trap cleanup EXIT

# Ditto preserves code signatures and extended attributes.
ditto "$SOURCE" "$TMP"
xattr -cr "$TMP" 2>/dev/null || true

if [[ -e "$DEST" ]]; then
    mv "$DEST" "$BACKUP"
fi

if ! mv "$TMP" "$DEST"; then
    if [[ -e "$BACKUP" ]]; then
        mv "$BACKUP" "$DEST"
    fi
    echo "error: could not install to $DEST" >&2
    exit 1
fi
rm -rf "$BACKUP"
trap - EXIT

# Refresh LaunchServices, remove the development copy from the registry, then
# explicitly assign the UTI handler. This avoids Finder launching build/RARx.app.
"$LSREGISTER" -f "$DEST"
"$LSREGISTER" -u "$ROOT/build/RARx.app" >/dev/null 2>&1 || true

echo "Registering RARx as the default .rar handler..."
"$DEST/Contents/MacOS/RARx" --set-default
"$DEST/Contents/MacOS/RARx" --handler-status
"$DEST/Contents/MacOS/RARx" --verify-default

echo
echo "Installed: $DEST"
echo "RARx is installed. Double-click a .rar in Finder to extract it alongside the archive."
