#!/usr/bin/env bash
# Builds "build/Spider Solitaire.app" (release), signs it and zips it to build/SpiderSolitaire.zip.
# Run on macOS 14+ with Xcode 15+ or the Command Line Tools.
#
#   scripts/package.sh                  # native architecture, ad-hoc signed
#   UNIVERSAL=1 scripts/package.sh      # arm64 + x86_64 (needs full Xcode)
#   VERSION=1.2.0 scripts/package.sh    # CFBundleShortVersionString (default 1.0.0)
#   SIGN_IDENTITY="Developer ID Application: Daniel Sailer (595TEE9LSF)" scripts/package.sh
#                                       # Developer ID: hardened runtime and secure timestamp, ready
#                                       # for notarization (the Release workflow notarizes and staples)
#   SIGN_KEYCHAIN=/path/x.keychain-db   # look the identity up in this keychain only (CI)
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

# SwiftPM resource bundle with the Classic card faces. `swift build` makes a flat bundle; a signed
# app needs the standard Contents/{Info.plist,Resources} layout, so it is rebuilt that way. The app
# looks for it in Contents/Resources (see ClassicCardArt.bundleCandidates).
RES_BUNDLE="SpiderSolitaire_SpiderSolitaire.bundle"
SRC_BUNDLE="$BIN_DIR/$RES_BUNDLE"
DEST_BUNDLE="$APP/Contents/Resources/$RES_BUNDLE"
if [[ ! -d "$SRC_BUNDLE" ]]; then
    echo "error: resource bundle not found at $SRC_BUNDLE" >&2
    exit 1
fi
mkdir -p "$DEST_BUNDLE/Contents/Resources"
if [[ -d "$SRC_BUNDLE/Contents/Resources" ]]; then
    cp -R "$SRC_BUNDLE/Contents/Resources/." "$DEST_BUNDLE/Contents/Resources/"
else
    for item in "$SRC_BUNDLE"/*; do
        [[ "$(basename "$item")" == "Info.plist" ]] && continue
        cp -R "$item" "$DEST_BUNDLE/Contents/Resources/"
    done
fi
cat > "$DEST_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleIdentifier</key>
	<string>com.dansailer.SpiderSolitaire.resources</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>SpiderSolitaire_SpiderSolitaire</string>
	<key>CFBundlePackageType</key>
	<string>BNDL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD_NUMBER</string>
</dict>
</plist>
PLIST
CARD_COUNT="$(find "$DEST_BUNDLE/Contents/Resources/Cards" -name '*.png' | wc -l | tr -d ' ')"
if [[ "$CARD_COUNT" != "52" ]]; then
    echo "error: expected 52 card images in $DEST_BUNDLE, found $CARD_COUNT" >&2
    exit 1
fi
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    "$ROOT/Packaging/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
plutil -lint "$DEST_BUNDLE/Contents/Info.plist" >/dev/null

# Inside out, without --deep: the resource bundle first, then the app (which seals its executable
# and resources). The bundle holds no code, but signing it keeps the app's seal over a signed bundle.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "==> Signing (ad hoc)"
    SIGN_ARGS=(--force --sign -)
else
    echo "==> Signing with $SIGN_IDENTITY (hardened runtime, secure timestamp)"
    SIGN_ARGS=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
    if [[ -n "${SIGN_KEYCHAIN:-}" ]]; then
        SIGN_ARGS+=(--keychain "$SIGN_KEYCHAIN")
    fi
fi
codesign "${SIGN_ARGS[@]}" "$DEST_BUNDLE"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Zipping"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Done: $ZIP"
echo "$APP"
