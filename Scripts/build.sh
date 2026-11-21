#!/usr/bin/env bash
# Builds Sleepable.app (universal: Apple Silicon + Intel) without an Xcode project.
#   Scripts/build.sh            → build/Sleepable.app
#   Scripts/build.sh --package  → also build/Sleepable.zip and build/Sleepable.dmg
set -euo pipefail

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = ad-hoc
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
APP="$OUT/Sleepable.app"
APPEX="$APP/Contents/PlugIns/SleepableControl.appex"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCHS=(arm64 x86_64)

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

echo "▸ Compiling Sleepable"
for arch in "${ARCHS[@]}"; do
  xcrun swiftc -O -swift-version 5 -parse-as-library \
    -target "$arch-apple-macos14.0" -sdk "$SDK" \
    "$ROOT"/Sources/Sleepable/*.swift "$ROOT"/Sources/Shared/*.swift \
    -o "$OUT/Sleepable-$arch"
done
lipo -create "${ARCHS[@]/#/$OUT/Sleepable-}" -output "$APP/Contents/MacOS/Sleepable"

echo "▸ Compiling Control Center extension"
for arch in "${ARCHS[@]}"; do
  xcrun swiftc -O -swift-version 5 -parse-as-library -application-extension \
    -target "$arch-apple-macos26.0" -sdk "$SDK" \
    "$ROOT"/Sources/SleepableControl/*.swift "$ROOT"/Sources/Shared/*.swift \
    -o "$OUT/SleepableControl-$arch"
done
lipo -create "${ARCHS[@]/#/$OUT/SleepableControl-}" -output "$APPEX/Contents/MacOS/SleepableControl"
rm -f "$OUT"/Sleepable-* "$OUT"/SleepableControl-*

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
cp "$OUT/icon-1024.png" "$ROOT/docs/icon.png" 2>/dev/null || true
rm -rf "$ICONSET" "$OUT/icon-1024.png"

echo "▸ Signing ($SIGN_IDENTITY)"
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" \
  --entitlements "$ROOT/Resources/Control.entitlements" "$APPEX"
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

if [[ "${1:-}" == "--package" ]]; then
  echo "▸ Packaging"
  (cd "$OUT" && ditto -c -k --keepParent Sleepable.app Sleepable.zip)
  DMG_SRC="$OUT/dmg"
  mkdir -p "$DMG_SRC"
  cp -R "$APP" "$DMG_SRC/"
  ln -s /Applications "$DMG_SRC/Applications"
  hdiutil create -quiet -volname "Sleepable" -srcfolder "$DMG_SRC" -ov -format UDZO "$OUT/Sleepable.dmg"
  rm -rf "$DMG_SRC"
fi

echo "✓ Built $APP"
