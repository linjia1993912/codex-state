# 10 · 构建、测试与打包

> 工具：Swift 6 + SwiftPM，运行环境 macOS 14+，仅依赖 Xcode Command Line Tools。

## 1. 常用命令

```bash
swift test                                 # 全部测试
swift test --filter UsageStoreTests        # 单个套件
swift build -c release                     # Release 构建
./Scripts/package_app.sh                   # 打包为 build/CodexState.app
open build/CodexState.app                  # 启动
```

> 工作流建议（见 `AGENTS.md`）：每次修改先跑最相关的 `swift test --filter`，完成后再跑完整 `swift test`；涉及打包时再运行 `Scripts/package_app.sh`。

## 2. `Package.swift` 概览

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "codex-state",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexStateCore", targets: ["CodexStateCore"]),
        .executable(name: "CodexState", targets: ["CodexState"]),
    ],
    targets: [
        .target(name: "CodexStateCore", resources: [.process("Pricing/Resources")]),
        .executableTarget(name: "CodexState", dependencies: ["CodexStateCore"]),
        .testTarget(
            name: "CodexStateCoreTests",
            dependencies: ["CodexStateCore"],
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ]
        )
    ]
)
```

要点：

- 仅一个 `CodexStateCore` 库 + `CodexState` 可执行 + 1 个测试 target。
- 测试 target 通过 `-F` 指向 CommandLineTools 的框架目录，确保 `XCTest` 与 `Observation` 框架可用。
- `resources: [.process("Pricing/Resources")]` 让 `Bundle.module` 在测试与裸运行时能定位 `ModelPrices.json`。
- 不使用第三方依赖。

## 3. 测试套件速览

| 测试文件 | 覆盖范围 |
| --- | --- |
| `UsageModelsTests.swift` | `TokenUsage.delta`、邮箱脱敏、`QuotaWindow.remainingTitle` |
| `ModelPriceCatalogTests.swift` | `estimate`、缓存输入截断、`bundled()` 资源加载 |
| `SessionLogParserTests.swift` | `turn_context` / `token_count` 解析、坏行计数、模型切换增量 |
| `SessionUsageRepositoryTests.swift` | 指纹缓存、目录枚举、跨日聚合与价格合成 |
| `CodexRPCClientTests.swift` | 可执行文件解析（含 nvm）、超时与无效响应、账号/额度解码 |
| `UsageStoreTests.swift` | 远端/本地失败降级、`selectRange`、`topModels` 排序、警告派生 |
| `ScreenPlacementTests.swift` | 屏幕居中坐标计算 |
| `DailyTrendSelectionTests.swift` | 悬停坐标 → 列索引映射（含越界收敛） |
| `NotchViewConstructionTests.swift` | 视图在给定快照下能成功构建 |

所有测试基于 Swift Testing（`import Testing`、`@Test`、`#expect`）。

## 4. 打包脚本 `Scripts/package_app.sh`

```bash
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
app_resource_bundle="$app_dir/Contents/Resources/$(basename "$resource_bundle")"
ditto "$resource_bundle" "$app_resource_bundle"
test -f "$app_resource_bundle/ModelPrices.json"
codesign --force --deep --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"

echo "$app_dir"
```

执行步骤：

1. `swift build -c release` 产出可执行文件与资源 bundle。
2. 找到 `*CodexStateCore.bundle`（SwiftPM 生成）。
3. 组装 `build/CodexState.app/Contents/{MacOS,Resources,Info.plist}`：
   - `CodexState` 可执行放入 `MacOS/`。
   - `Info.plist` 标记 `LSUIElement = true`、`LSMinimumSystemVersion = 14.0`、`NSHighResolutionCapable = true`。
   - 资源 bundle 通过 `ditto` 拷贝到 `Resources/`，并校验 `ModelPrices.json` 存在。
4. `codesign --force --deep --sign -` 进行 ad-hoc 签名。
5. `codesign --verify --deep --strict` 校验签名。

> **不要手工修改 `build/` 下的产物** — 任何修改都会被下次打包覆盖。
> **不要提交 `build/`** — 仓库 `.gitignore` 已忽略。

## 5. 环境要求

| 项目 | 要求 |
| --- | --- |
| macOS | 14.0 及以上 |
| Xcode Command Line Tools | 任意当前支持版本 |
| Codex CLI | 已安装并通过 `codex login status` 登录 |
| 第三方依赖 | 无 |

## 6. 调试小贴士

- 调整 `UsageStore` 时使用 `swift test --filter UsageStoreTests` 快速验证。
- 想观察 `NotchPanelController` 的屏幕选择逻辑，可在 `ScreenPlacementTests` 中加用例。
- 若要修改快捷键：只改 `GlobalHotKey.init` 中的 `kVK_ANSI_U` 与修饰键常量；注意同时更新 `README.md` 中的描述。
- 价格表变更后，**必须**同步更新 `Sources/CodexStateCore/Pricing/Resources/ModelPrices.json` 的 `updatedAt` 与 `README.md` 中的"价格表更新日期"。
- 任何对会话聚合的改动都应在 `SessionUsageRepositoryTests` 中新增"指纹缓存命中"与"价格合成"两类用例。
