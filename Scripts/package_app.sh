#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

# CommandLineTools 环境下 sandbox-exec 受限，需禁用 SwiftPM 沙箱才能编译 manifest
swift build -c release --disable-sandbox
bin_dir="$(swift build -c release --disable-sandbox --show-bin-path)"
app_dir="$project_dir/build/CodexState.app"
resource_bundle="$(find "$bin_dir" -maxdepth 1 -type d -name '*CodexStateCore.bundle' -print -quit)"

if [[ -z "$resource_bundle" ]]; then
    echo "未找到 CodexStateCore 资源 bundle" >&2
    exit 1
fi

# 使用 Swift 工具生成 AppIcon（透明背景 + 圆角矩形遮罩）
iconset_dir="$project_dir/build/AppIcon.iconset"
rm -rf "$iconset_dir"
mkdir -p "$iconset_dir"

icon_gen_dir="$project_dir/Scripts/IconGen"
icon_gen_bin=""
if [[ -f "$icon_gen_dir/Package.swift" ]]; then
    cd "$icon_gen_dir"
    echo "Building icon generator..."
    if swift build -c release --disable-sandbox 2>&1; then
        icon_gen_bin="$(swift build -c release --disable-sandbox --show-bin-path)/CodexStateIconGen"
        echo "Icon generator built: $icon_gen_bin"
    else
        echo "warning: failed to build icon generator" >&2
    fi
    cd "$project_dir"
fi

if [[ -x "$icon_gen_bin" ]]; then
    echo "Generating icons to: $iconset_dir"
    "$icon_gen_bin" "$iconset_dir"
else
    echo "warning: icon generator not available, skipping icon generation" >&2
fi

# 使用 iconutil 生成 icns
if command -v iconutil &> /dev/null && [[ -d "$iconset_dir" ]] && [[ -n "$(ls -A "$iconset_dir" 2>/dev/null)" ]]; then
    iconutil -c icns "$iconset_dir" -o "$project_dir/build/AppIcon.icns"
    echo "Generated AppIcon.icns"
else
    echo "warning: iconutil not found or iconset empty, skipping icns generation"
fi

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
install -m 755 "$bin_dir/CodexState" "$app_dir/Contents/MacOS/CodexState"
install -m 644 Resources/Info.plist "$app_dir/Contents/Info.plist"

# 安装图标（如果生成成功）
if [[ -f "$project_dir/build/AppIcon.icns" ]]; then
    install -m 644 "$project_dir/build/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
fi

app_resource_bundle="$app_dir/Contents/Resources/$(basename "$resource_bundle")"
ditto "$resource_bundle" "$app_resource_bundle"
test -f "$app_resource_bundle/ModelPrices.json"
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
