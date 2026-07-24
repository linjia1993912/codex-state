# Codex State 开发指南

## 项目概览

- 这是一个 macOS 14+ 原生刘海用量工具，使用 Swift 6、SwiftUI 与 AppKit。
- `CodexStateCore` 承担领域模型、价格估算、Codex RPC、会话聚合、状态与面板逻辑；`CodexState` 仅负责应用启动和依赖组装。
- 不引入第三方依赖。优先使用 Swift 标准库、Foundation、SwiftUI、AppKit 和 Carbon。

## 常用命令

```bash
swift test
swift test --filter <测试套件名>
swift build -c release
./Scripts/package_app.sh
```

打包脚本会重建 `build/CodexState.app`、进行 ad-hoc 签名并校验签名；不要手工修改其产物。

## 目录职责

| 路径 | 职责 |
| --- | --- |
| `Sources/CodexState/` | App 入口、依赖组装、定时刷新生命周期。 |
| `Sources/CodexStateCore/Domain/` | 不依赖 UI 的用量、额度、账号和警告模型。 |
| `Sources/CodexStateCore/RPC/` | 本机 Codex `app-server` 的 JSON-RPC 调用与解码。 |
| `Sources/CodexStateCore/Sessions/` | JSONL 日志解析、增量缓存和每日用量聚合。 |
| `Sources/CodexStateCore/Pricing/` | 内置模型价格与成本估算。 |
| `Sources/CodexStateCore/State/` | `@MainActor` 的 `UsageStore` 与展示范围派生状态。 |
| `Sources/CodexStateCore/Platform/` | 面板定位、悬浮窗和全局快捷键。 |
| `Sources/CodexStateCore/UI/` | SwiftUI 的静默、悬停、展开与趋势视图。 |
| `Tests/CodexStateCoreTests/` | 使用 Swift Testing 的行为回归测试。 |

## 数据、隐私与产品边界

- 额度与账号只能通过本机 Codex `app-server` 读取；`account/read` 必须保持 `refreshToken: false`。
- 本地用量只扫描 `CODEX_HOME`（未设置时 `~/.codex`）中的 `sessions` 与 `archived_sessions` JSONL；只聚合 Token、模型与时间，绝不保存提示词、回复或访问令牌。
- 禁止网页抓取、WebView、浏览器 Cookie、云同步、遥测和远程数据库。
- 费用是基于内置价格表的估算，不是订阅账单。未知模型仍统计 Token，不能伪造价格或把未知成本当作零。
- 额度仅展示 RPC 返回的比例和重置时间；不要推算订阅的绝对 Token 上限。

## 实现约定

- 保持 Swift 6 严格并发语义：UI、`UsageStore` 和面板控制器运行在 `@MainActor`；跨线程数据模型保持 `Sendable`。
- UI 与用户可见文案、关键注释及项目文档使用中文；注释说明原因，不重复代码含义。
- 复用现有领域模型和 `UsageStore`，不要在视图中读取文件、启动进程或自行计算跨日聚合。
- 失败时保留最后一次有效数据并通过 `UsageWarning` 表达降级；不要因可选能力（例如快捷键注册）失败而阻断应用。
- 保持界面无障碍语义、`Esc`/外部点击收起和“减少动态效果”支持。

## 测试与验收

- 每次修改先运行最相关的 `swift test --filter`，完成后运行 `swift test`；涉及打包时再运行 `./Scripts/package_app.sh`。
- 新测试放在对应的 `Tests/CodexStateCoreTests/*Tests.swift`，使用 `import Testing`、`@Test` 和 `#expect`，覆盖可观察行为而非私有实现。
- 面板位置、悬停稳定性、刘海遮挡、外接屏、VoiceOver 和减少动态效果无法完全自动化；变更这些区域时，按 `README.md` 的手工图形验收清单在真实 macOS 会话验证。

## 修改范围

- 只修改实现当前需求所需的文件；保留工作区内用户已有的未提交变更。
- 更新模型价格时，同时更新 `ModelPrices.json` 的日期和 README 中的价格表日期与来源说明。
