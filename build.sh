#!/bin/bash
# Compila o Foco.app do zero. Uso: ./build.sh [--install]
#   --install  copia para /Applications e abre o app
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Foco.app
ARCH=$(uname -m)
TARGET="$ARCH-apple-macos15.0"

echo "→ Gerando ícone"
mkdir -p build
swiftc -O -target "$TARGET" Tomate.swift gerador/main.swift -o build/gerar-icone
build/gerar-icone build/icone_1024.png
rm -rf build/Foco.iconset && mkdir build/Foco.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s build/icone_1024.png --out build/Foco.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icone_1024.png --out build/Foco.iconset/icon_${s}x${s}@2x.png >/dev/null
done

echo "→ Montando $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
iconutil -c icns build/Foco.iconset -o "$APP/Contents/Resources/Foco.icns"

echo "→ Compilando"
swiftc -parse-as-library -O -target "$TARGET" Tomate.swift App.swift -o "$APP/Contents/MacOS/Foco"
codesign -s - --force "$APP"
echo "✓ Pronto: $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Foco 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Foco.app
  cp -R "$APP" /Applications/
  open /Applications/Foco.app
  echo "✓ Instalado em /Applications/Foco.app"
fi
