#!/bin/bash
# Builds Foco.app from scratch. Usage: ./build.sh [--install]
#   --install  copies the app to /Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Foco.app
ARCH=$(uname -m)
TARGET="$ARCH-apple-macos15.0"

echo "→ Generating icon"
mkdir -p build
swiftc -O -target "$TARGET" Tomato.swift icon-generator/main.swift -o build/icon-generator
build/icon-generator build/icon_1024.png
rm -rf build/Foco.iconset && mkdir build/Foco.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out build/Foco.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon_1024.png --out build/Foco.iconset/icon_${s}x${s}@2x.png >/dev/null
done

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
iconutil -c icns build/Foco.iconset -o "$APP/Contents/Resources/Foco.icns"

echo "→ Compiling"
swiftc -parse-as-library -O -target "$TARGET" Tomato.swift App.swift -o "$APP/Contents/MacOS/Foco"
codesign -s - --force "$APP"
echo "✓ Done: $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Foco 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Foco.app
  cp -R "$APP" /Applications/
  open /Applications/Foco.app
  echo "✓ Installed to /Applications/Foco.app"
fi
