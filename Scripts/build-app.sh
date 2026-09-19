#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
version="${VERSION:-1.0.0}"
build_number="${BUILD_NUMBER:-1}"
identity="${DEVELOPER_ID_APPLICATION:--}"
app="$root/dist/ViKey.app"

cd "$root"
swift build -c "$configuration"
bin_path="$(swift build --show-bin-path -c "$configuration")"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_path/ViKey" "$app/Contents/MacOS/ViKey"
cp "$root/Scripts/Info.plist" "$app/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"

if [[ "$identity" == "-" ]]; then
    codesign --force --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --deep --strict --verbose=2 "$app"

echo "Built $app"