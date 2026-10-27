#!/usr/bin/env bash
# Builds "build/Spider Solitaire.app" (release), ad-hoc signs it and zips it to
# build/SpiderSolitaire.zip. Run on macOS 14+ with Xcode 15+ or the Command Line Tools.
#
#   scripts/package.sh                  # native architecture
#   UNIVERSAL=1 scripts/package.sh      # arm64 + x86_64 (needs full Xcode)
#   VERSION=1.2.0 scripts/package.sh    # CFBundleShortVersionString (default 1.0.0)
#
# Works with macOS's stock bash 3.2 (no bash 4 features).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: package.sh must run on macOS (needs sips, iconutil, codesign, ditto)." >&2
    exit 1
fi
for tool in swift sips iconutil codesign ditto plutil; do
    command -v "$tool" >/dev/null 2>&1 || { echo "error: '$tool' not found." >&2; exit 1; }
done

APP_NAME="Spider Solitaire"
EXECUTABLE="SpiderSolitaire"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
ZIP="$BUILD_DIR/SpiderSolitaire.zip"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> swift build -c release"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --product "$EXECUTABLE"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --product SpiderIcon
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

mkdir -p "$BUILD_DIR"

echo "==> Rendering icon"
ICON_PNG="$BUILD_DIR/AppIcon-1024.png"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
"$BIN_DIR/SpiderIcon" "$ICON_PNG"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD_DIR/AppIcon.icns"

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
chmod 755 "$APP/Contents/MacOS/$EXECUTABLE"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    "$ROOT/Packaging/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Signing (ad hoc)"
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Zipping"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Done: $ZIP"
echo "$APP"
