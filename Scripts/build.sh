#!/usr/bin/env bash
# Builds Dozex.app (universal: Apple Silicon + Intel) without an Xcode project.
#   Scripts/build.sh            → build/Dozex.app
#   Scripts/build.sh --package  → also build/Dozex.zip, build/Dozex.dmg and the legacy build/Sleepable.zip
set -euo pipefail

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = ad-hoc
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
APP="$OUT/Dozex.app"
APPEX="$APP/Contents/PlugIns/DozexControl.appex"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCHS=(arm64 x86_64)

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

echo "▸ Compiling Dozex"
for arch in "${ARCHS[@]}"; do
  xcrun swiftc -O -swift-version 5 -parse-as-library \
    -target "$arch-apple-macos14.0" -sdk "$SDK" \
    "$ROOT"/Sources/Dozex/*.swift "$ROOT"/Sources/Shared/*.swift \
    -o "$OUT/Dozex-$arch"
done
lipo -create "${ARCHS[@]/#/$OUT/Dozex-}" -output "$APP/Contents/MacOS/Dozex"

echo "▸ Compiling Control Center extension"
for arch in "${ARCHS[@]}"; do
  xcrun swiftc -O -swift-version 5 -parse-as-library -application-extension \
    -target "$arch-apple-macos26.0" -sdk "$SDK" \
    "$ROOT"/Sources/DozexControl/*.swift "$ROOT"/Sources/Shared/*.swift \
    -o "$OUT/DozexControl-$arch"
done
lipo -create "${ARCHS[@]/#/$OUT/DozexControl-}" -output "$APPEX/Contents/MacOS/DozexControl"
rm -f "$OUT"/Dozex-* "$OUT"/DozexControl-*

echo "▸ Assembling bundle"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" "$ROOT/Resources/ControlInfo.plist" > "$APPEX/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
xcrun swift "$ROOT/Scripts/make-icon.swift" "$OUT/icon-1024.png" >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s "$OUT/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$OUT/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$OUT/icon-1024.png" "$ROOT/website/public/assets/icon.png" 2>/dev/null || true
rm -rf "$ICONSET" "$OUT/icon-1024.png"

echo "▸ Signing ($SIGN_IDENTITY)"
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" \
  --entitlements "$ROOT/Resources/Control.entitlements" "$APPEX"
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

if [[ "${1:-}" == "--package" ]]; then
  echo "▸ Packaging"
  (cd "$OUT" && ditto -c -k --keepParent Dozex.app Dozex.zip)
  # Sleepable 1.1.0 and older look for Sleepable.zip containing Sleepable.app.
  # Same app under the old folder name; Dozex renames itself on first launch.
  LEGACY="$OUT/legacy"
  mkdir -p "$LEGACY" && ditto "$APP" "$LEGACY/Sleepable.app"
  (cd "$LEGACY" && ditto -c -k --keepParent Sleepable.app "$OUT/Sleepable.zip")
  rm -rf "$LEGACY"
  # Installer window: background art + icon layout, via dmgbuild (writes the
  # window settings directly, so no Finder scripting is needed).
  TOOLS="$ROOT/.build-tools"
  if [[ ! -x "$TOOLS/bin/dmgbuild" ]]; then
    echo "▸ Installing dmgbuild into .build-tools (one time)"
    python3 -m venv "$TOOLS" && "$TOOLS/bin/pip" install -q "dmgbuild==1.6.5"
  fi
  xcrun swift "$ROOT/Scripts/make-dmg-background.swift" "$OUT" >/dev/null
  tiffutil -cathidpicheck "$OUT/background.png" "$OUT/background@2x.png" -out "$OUT/background.tiff" 2>/dev/null
  "$TOOLS/bin/dmgbuild" -s "$ROOT/Scripts/dmg-settings.py" -D app="$APP" -D background="$OUT/background.tiff" \
    "Dozex" "$OUT/Dozex.dmg" >/dev/null
  rm -f "$OUT"/background*.png "$OUT/background.tiff"
fi

echo "✓ Built $APP"
