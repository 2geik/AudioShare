#!/bin/zsh
# Regenerates Resources/AppIcon.icns and the menu bar template PNGs from Design/*.svg.
set -euo pipefail
cd "$(dirname "$0")/.."

render() { swift Scripts/render-svg.swift "$@"; }

iconset=$(mktemp -d)/AppIcon.iconset
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    render Design/AppIcon.svg "$iconset/icon_${size}x${size}.png" $size
    render Design/AppIcon.svg "$iconset/icon_${size}x${size}@2x.png" $((size * 2))
done
iconutil --convert icns "$iconset" --output Resources/AppIcon.icns

for name in MenuBarIcon MenuBarIconActive; do
    render Design/$name.svg Resources/${name}Template.png 22 18
    render Design/$name.svg Resources/${name}Template@2x.png 44 36
done

echo "Icons written to Resources/"
