#!/bin/bash
set -euo pipefail
apple_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(dirname "$apple_dir")"
sdk_path="${MACOS_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
check_dir="$repo_dir/work/native-compat"
mkdir -p "$check_dir"
swift run --package-path "$apple_dir" --sdk "$sdk_path" JournalChecks "$repo_dir/examples/content" "$check_dir"
cd "$repo_dir"
npx --no-install tsx scripts/check-native-compat.ts "$check_dir/native-entry.md" "$repo_dir/examples/content" "$check_dir/native-management"
swift run --package-path "$apple_dir" --sdk "$sdk_path" JournalChecks "$repo_dir/examples/content" "$check_dir" "$check_dir/web-roundtrip.md"
xcrun swiftc -sdk "$sdk_path" -parse-as-library "$apple_dir/Sources/JournalMac/TextEditor.swift" "$apple_dir/EditorChecks/main.swift" -o "$check_dir/editor-checks"
"$check_dir/editor-checks"
