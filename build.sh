#!/bin/zsh
set -eu
cd "${0:A:h}"
appdir="Skjermgardin.app/Contents"
mkdir -p "$appdir/MacOS" "$appdir/Resources"
icon="$appdir/Resources/Skjermgardin.icns"
if [[ ! -f "$icon" || Assets/Curtain.png -nt "$icon" ]]; then
    scratch=$(mktemp -d)
    trap 'rm -rf "$scratch"' EXIT
    iconset="$scratch/Skjermgardin.iconset"
    mkdir "$iconset"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" Assets/Curtain.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" Assets/Curtain.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset" -o "$icon"
fi
cp Info.plist "$appdir/Info.plist"
xcrun swiftc -O -target "$(uname -m)-apple-macos14.0" Sources/*.swift -o "$appdir/MacOS/Skjermgardin"
codesign --force --sign - --options runtime "Skjermgardin.app"
codesign --verify --strict "Skjermgardin.app"
