#!/bin/bash
set -euo pipefail
apple_dir="$(cd "$(dirname "$0")/.." && pwd)"
sdk_path="${MACOS_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
configuration="${BUILD_CONFIGURATION:-release}"
swift build --package-path "$apple_dir" --configuration "$configuration" --product DailyJournal --sdk "$sdk_path"
bin_dir="$(swift build --package-path "$apple_dir" --configuration "$configuration" --sdk "$sdk_path" --show-bin-path)"
app_dir="$apple_dir/build/日常.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/DailyJournal" "$app_dir/Contents/MacOS/DailyJournal"
cp "$apple_dir/Config/JournalInfo.plist" "$app_dir/Contents/Info.plist"
cp "$apple_dir/Config/THIRD-PARTY-NOTICES.txt" "$app_dir/Contents/Resources/THIRD-PARTY-NOTICES.txt"
# Build the app icon from a vector drawing; no generated image dependency.
xcrun swift -sdk "$sdk_path" "$apple_dir/scripts/make-icon.swift" "$apple_dir/build/AppIcon.iconset"
iconutil -c icns "$apple_dir/build/AppIcon.iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
# Ad-hoc signing supports this Mac's local build and sandbox. It is not notarized distribution.
codesign --force --sign - --entitlements "$apple_dir/Config/macOS.entitlements" "$app_dir"
codesign --verify --strict --verbose=2 "$app_dir"
printf '\nBuilt: %s\n' "$app_dir"
