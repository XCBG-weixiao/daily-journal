#!/bin/bash
set -euo pipefail
apple_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(dirname "$apple_dir")"
sdk_path="${MACOS_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
check_dir="$repo_dir/work/native-compat"
mkdir -p "$check_dir"
swift run --package-path "$apple_dir" --sdk "$sdk_path" JournalChecks "$repo_dir/examples/content" "$check_dir"
cd "$repo_dir"
npx --no-install tsx scripts/check-native-compat.ts "$check_dir/native-entry.md" "$repo_dir/examples/content"
swift run --package-path "$apple_dir" --sdk "$sdk_path" JournalChecks "$repo_dir/examples/content" "$check_dir" "$check_dir/web-roundtrip.md"
