#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/vendor/unrar/unrar"
OUT_DIR="$ROOT/build/engine"
OUT="$OUT_DIR/unrar"
MIN_MACOS="13.0"

if [[ ! -f "$SOURCE/makefile" || ! -f "$SOURCE/license.txt" ]]; then
    echo "error: UnRAR source not found at $SOURCE" >&2
    exit 1
fi

if [[ -x "$OUT" ]]; then
    if [[ "$OUT" -nt "$SOURCE/version.hpp" ]] && lipo -info "$OUT" 2>/dev/null | grep -q "arm64" && lipo -info "$OUT" 2>/dev/null | grep -q "x86_64"; then
        echo "UnRAR engine is up to date: $OUT"
        exit 0
    fi
fi

rm -rf "$ROOT/build/engine-arm64" "$ROOT/build/engine-x86_64"
mkdir -p "$OUT_DIR"

for ARCH in arm64 x86_64; do
    WORK="$ROOT/build/engine-$ARCH"
    mkdir -p "$WORK"
    ditto "$SOURCE/" "$WORK/"
    echo "Building UnRAR for ${ARCH}…"
    make -C "$WORK" -j"$(sysctl -n hw.ncpu)" \
        CXX="clang++ -arch $ARCH -mmacosx-version-min=$MIN_MACOS" \
        unrar >"$ROOT/build/unrar-$ARCH.log" 2>&1
    test -x "$WORK/unrar"
done

lipo -create \
    "$ROOT/build/engine-arm64/unrar" \
    "$ROOT/build/engine-x86_64/unrar" \
    -output "$OUT"
chmod +x "$OUT"
strip -x "$OUT" 2>/dev/null || true
cp "$SOURCE/license.txt" "$OUT_DIR/LICENSE.txt"

echo "Built $OUT"
file "$OUT"
lipo -info "$OUT"
