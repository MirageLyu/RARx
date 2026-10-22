#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/RARx.app"
ENGINE="$BUILD/engine/unrar"
MIN_MACOS="13.0"
VERSION="1.1.0"

cd "$ROOT"

if [[ ! -x "$ENGINE" ]]; then
    "$ROOT/scripts/build-engine.sh"
fi
if [[ ! -f "$BUILD/icons/AppIcon.icns" || ! -f "$BUILD/icons/RARFile.icns" ]]; then
    swift "$ROOT/scripts/make-icons.swift" "$ROOT"
fi

rm -rf "$BUILD/RARx-arm64" "$BUILD/RARx-x86_64"
for ARCH in arm64 x86_64; do
    echo "Compiling RARx for ${ARCH}..."
    swiftc -O -whole-module-optimization -swift-version 5 \
        -target "$ARCH-apple-macos$MIN_MACOS" \
        -framework AppKit \
        -framework SwiftUI \
        -framework CoreServices \
        -framework UniformTypeIdentifiers \
        "$ROOT"/Sources/Core/*.swift \
        "$ROOT"/Sources/App/*.swift \
        -o "$BUILD/RARx-$ARCH"
done

lipo -create "$BUILD/RARx-arm64" "$BUILD/RARx-x86_64" -output "$BUILD/RARx-universal"

# Exact destination path is derived from the repository root.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/engine"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$BUILD/RARx-universal" "$APP/Contents/MacOS/RARx"
chmod 755 "$APP/Contents/MacOS/RARx"
cp "$ENGINE" "$APP/Contents/Resources/engine/unrar"
chmod 755 "$APP/Contents/Resources/engine/unrar"
cp "$ROOT/build/engine/LICENSE.txt" "$APP/Contents/Resources/engine/LICENSE.txt"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.txt" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
for LOCALIZATION in en zh-Hans; do
    mkdir -p "$APP/Contents/Resources/$LOCALIZATION.lproj"
    cp "$ROOT/Resources/$LOCALIZATION.lproj/Localizable.strings" "$APP/Contents/Resources/$LOCALIZATION.lproj/Localizable.strings"
    cp "$ROOT/Resources/$LOCALIZATION.lproj/InfoPlist.strings" "$APP/Contents/Resources/$LOCALIZATION.lproj/InfoPlist.strings"
done
cp "$BUILD/icons/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$BUILD/icons/RARFile.icns" "$APP/Contents/Resources/RARFile.icns"

xattr -cr "$APP" 2>/dev/null || true

codesign --force --options runtime --sign - "$APP/Contents/Resources/engine/unrar"
codesign --force --options runtime --sign - "$APP"

plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP"
file "$APP/Contents/MacOS/RARx"
lipo -info "$APP/Contents/MacOS/RARx"
echo "Version: $VERSION"
