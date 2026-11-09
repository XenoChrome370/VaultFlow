#!/bin/bash
# build.sh — builds VaultFlow.app (native slice, or arm64 + x86_64 with
# UNIVERSAL=1), with its icon, Info.plist and an ad-hoc signature so it can run
# locally without a developer certificate.
#
#   ./Support/build.sh            # release build → dist/VaultFlow.app
#   ./Support/build.sh debug      # debug build
#   ./Support/build.sh release install   # also copy to /Applications
#   UNIVERSAL=1 ./Support/build.sh       # arm64 + x86_64 (needs both SDK slices)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
INSTALL="${2:-}"
APP_NAME="VaultFlow"
BUILD_DIR="$ROOT/.build-app"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

# The sandbox on some machines blocks the default clang module caches.
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/vaultflow-module-cache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-/tmp/vaultflow-module-cache}"
export TMPDIR="${TMPDIR:-/tmp}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

echo "▸ Building $APP_NAME ($CONFIGURATION)…"
cd "$ROOT"
swift build --disable-sandbox -c "$CONFIGURATION" \
    --cache-path "$ROOT/.build-app/cache" \
    --scratch-path "$BUILD_DIR" 2>&1 | sed 's/^/  /'

BIN_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" \
    --cache-path "$ROOT/.build-app/cache" --scratch-path "$BUILD_DIR" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"
[ -f "$BINARY" ] || { echo "✗ built binary not found at $BINARY"; exit 1; }

if [ "${UNIVERSAL:-0}" = "1" ]; then
    echo "▸ Building x86_64 slice…"
    X86_DIR="$BUILD_DIR/x86_64"
    swift build --disable-sandbox -c "$CONFIGURATION" --arch x86_64 \
        --cache-path "$ROOT/.build-app/cache-x86" --scratch-path "$X86_DIR" 2>&1 | sed 's/^/  /'
    X86_BIN_DIR="$(swift build --disable-sandbox -c "$CONFIGURATION" --arch x86_64 \
        --cache-path "$ROOT/.build-app/cache-x86" --scratch-path "$X86_DIR" --show-bin-path)"
    if [ -f "$X86_BIN_DIR/$APP_NAME" ]; then
        lipo -create "$BINARY" "$X86_BIN_DIR/$APP_NAME" -output "$BUILD_DIR/$APP_NAME.universal"
        BINARY="$BUILD_DIR/$APP_NAME.universal"
    else
        echo "  (x86_64 slice unavailable — keeping the native binary)"
    fi
fi

echo "▸ Assembling bundle…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Info.plist uses $(MARKETING_VERSION)/$(CURRENT_PROJECT_VERSION); Xcode expands
# them at build time, so do the same here.
APP_CONFIG="$ROOT/Config/VaultFlowApp.xcconfig"
MARKETING_VERSION="$(sed -n 's/^MARKETING_VERSION *= *//p' "$APP_CONFIG")"
CURRENT_PROJECT_VERSION="$(sed -n 's/^CURRENT_PROJECT_VERSION *= *//p' "$APP_CONFIG")"
plutil -replace CFBundleShortVersionString -string "$MARKETING_VERSION" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$CURRENT_PROJECT_VERSION" "$APP_DIR/Contents/Info.plist"

# Icon: render AppIcon.icns from the project's PNG when iconutil is available.
ICON_SOURCE="$ROOT/../VaultFlowIcon.png"
if [ -f "$ICON_SOURCE" ] && command -v iconutil >/dev/null 2>&1; then
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    cp "$APP_DIR/Contents/Resources/AppIcon.icns" "$BUILD_DIR/AppIcon.icns"
    echo "  icon → AppIcon.icns"
fi

echo "▸ Code signing (ad-hoc)…"
codesign --force --deep --sign - --timestamp=none "$APP_DIR" 2>&1 | sed 's/^/  /' || \
    echo "  (ad-hoc signing skipped)"

echo "▸ Verifying…"
codesign --verify --verbose=2 "$APP_DIR" 2>&1 | sed 's/^/  /' || true
plutil -lint "$APP_DIR/Contents/Info.plist" | sed 's/^/  /'
lipo -info "$APP_DIR/Contents/MacOS/$APP_NAME" | sed 's/^/  /'

if [ "$INSTALL" = "install" ]; then
    echo "▸ Installing to /Applications…"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
fi

echo "✓ $APP_DIR"
