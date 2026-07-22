#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/build/CodexState.app"
resource_bundle="$(find "$bin_dir" -maxdepth 1 -type d -name '*CodexStateCore.bundle' -print -quit)"

if [[ -z "$resource_bundle" ]]; then
    echo "未找到 CodexStateCore 资源 bundle" >&2
    exit 1
fi

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
install -m 755 "$bin_dir/CodexState" "$app_dir/Contents/MacOS/CodexState"
install -m 644 Resources/Info.plist "$app_dir/Contents/Info.plist"
ditto "$resource_bundle" "$app_dir/Contents/Resources/$(basename "$resource_bundle")"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
