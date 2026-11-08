#!/usr/bin/env bash
#
# HeroTrak — macOS release build automation.
#
# Builds a universal (arm64 + x86_64) release bundle and packages it for
# distribution:
#
#   1. App icon: icon/HeroTrakIcon.svg -> AppIcon.icns (via rsvg-convert,
#      sips and iconutil) into macos/Runner/Assets.xcassets.
#   2. Clean build artifacts (flutter clean / flutter pub get).
#   3. Verify build readiness (flutter analyze / flutter test).
#   4. flutter build macos --release --target-platform macos-universal.
#   5. Package HeroTrak.app into dist/HeroTrak-macOS-Universal.zip.
#
# Usage: ./scripts/build_macos_release.sh
set -euo pipefail

# Always run from the repository root.
cd "$(dirname "$0")/.."

ICON_SVG="icon/HeroTrakIcon.svg"
ICONSET_DIR="build/AppIcon.iconset"
ICON_SOURCE="build/AppIcon.source.png"
ICNS_TARGET="macos/Runner/Assets.xcassets/AppIcon.appiconset/AppIcon.icns"
APP_BUNDLE="build/macos/Build/Products/Release/HeroTrak.app"
DIST_ZIP="dist/HeroTrak-macOS-Universal.zip"

# ---------------------------------------------------------------------------
# 1. App icon (optional): SVG -> iconset -> icns.
# ---------------------------------------------------------------------------
if [[ -f "$ICON_SVG" ]]; then
  if command -v rsvg-convert >/dev/null 2>&1; then
    echo "==> Building AppIcon.icns from $ICON_SVG"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    # Render the vector source once at 1024px...
    rsvg-convert -w 1024 -h 1024 "$ICON_SVG" -o "$ICON_SOURCE"

    # ...then scale every iconset slot from it with sips.
    render() {
      sips -z "$1" "$1" "$ICON_SOURCE" --out "$ICONSET_DIR/$2.png" >/dev/null
    }
    render 16   icon_16x16
    render 32   icon_16x16@2x
    render 32   icon_32x32
    render 64   icon_32x32@2x
    render 128  icon_128x128
    render 256  icon_128x128@2x
    render 256  icon_256x256
    render 512  icon_256x256@2x
    render 512  icon_512x512
    render 1024 icon_512x512@2x

    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_TARGET"
    rm -rf "$ICONSET_DIR" "$ICON_SOURCE"
    echo "==> Installed $ICNS_TARGET"
  else
    echo "==> rsvg-convert not found; skipping icon generation"
  fi
else
  echo "==> $ICON_SVG not found; skipping icon generation"
fi

# ---------------------------------------------------------------------------
# 2. Clean build artifacts.
# ---------------------------------------------------------------------------
echo "==> Cleaning build artifacts"
flutter clean
flutter pub get

# ---------------------------------------------------------------------------
# 3. Verify build readiness.
# ---------------------------------------------------------------------------
echo "==> Verifying build readiness"
flutter analyze
flutter test

# ---------------------------------------------------------------------------
# 4. Universal macOS release build.
# ---------------------------------------------------------------------------
echo "==> Building universal macOS release"
flutter build macos --release

# ---------------------------------------------------------------------------
# 5. Package the app bundle for distribution.
# ---------------------------------------------------------------------------
echo "==> Packaging $DIST_ZIP"
mkdir -p dist
rm -f "$DIST_ZIP"
# ditto preserves bundle symlinks and signatures that plain zip drops.
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST_ZIP"

echo "==> Done: $DIST_ZIP"