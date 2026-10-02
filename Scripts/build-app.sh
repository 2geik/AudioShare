#!/bin/zsh
# Builds AudioShare.app with nothing but the Command Line Tools (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

config=${CONFIG:-release}
app=build/AudioShare.app

swift build -c "$config"
binary="$(swift build -c "$config" --show-bin-path)/AudioShare"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/AudioShare"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/*.png "$app/Contents/Resources/"
cp -R Resources/*.lproj "$app/Contents/Resources/"

# Ad-hoc signature: enough to run locally and to get a Bluetooth permission prompt.
codesign --force --sign - --timestamp=none "$app"

echo "Built $app"
