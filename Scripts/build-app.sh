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

# With the Command Line Tools, SwiftPM's Swift Build engine records the deployment target as the
# SDK version (e.g. "sdk 14.0"). AppKit picks the app's look from that field, so the app would be
# drawn in the pre-Liquid Glass style. Write back the SDK it was really built against.
min_os=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" Resources/Info.plist)
vtool -set-build-version macos "$min_os" "$(xcrun --show-sdk-version)" -replace \
    -output "$app/Contents/MacOS/AudioShare" "$app/Contents/MacOS/AudioShare"
cp Resources/AppIcon.icns Resources/*.png "$app/Contents/Resources/"
cp -R Resources/*.lproj "$app/Contents/Resources/"

# Ad-hoc signature: enough to run locally and to get a Bluetooth permission prompt.
codesign --force --sign - --timestamp=none "$app"

echo "Built $app"
