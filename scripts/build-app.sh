#!/bin/bash
# Builds "Pixel Workers Hub.app" into build/. Needs only Xcode's Command Line Tools.
#   UNIVERSAL=1 scripts/build-app.sh   builds for both Apple silicon and Intel (needs full Xcode).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Pixel Workers Hub.app"
VERSION="$(tr -d '[:space:]' < VERSION)"
ARCHS=()
[[ "${UNIVERSAL:-}" == 1 ]] && ARCHS=(--arch arm64 --arch x86_64)

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"
cp "$BIN/PixelWorkersHub" "$APP/Contents/MacOS/"
sed "s/__VERSION__/$VERSION/g" Support/Info.plist > "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/"
cp Web/panel.html Web/panel.css Web/panel.js Web/sprites.js "$APP/Contents/Resources/web/"

# An ad-hoc signature: enough for macOS to run it and remember its permissions on this Mac.
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP ($VERSION)"
