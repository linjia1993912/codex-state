# 01 · 项目架构总览

## 1. 设计目标

Codex State 是一款 macOS 14+ 原生工具，围绕本机已登录的 Codex CLI 提供：

- 刘海融合的悬浮用量指示器（静默 / 悬停 / 展开三态）。
- 通过本机 Codex `app-server` 子进程拉取账号与额度，不刷新登录令牌。
- 扫描 `CODEX_HOME` 下的 `sessions` / `archived_sessions` JSONL 统计 Token、估算成本与常用模型。
- 全程本地计算，零网络外发，无 WebView、无浏览器 Cookie、无云同步。

## 2. 模块分层

| 层 | 目标模块 | 职责 |
| --- | --- | --- |
| App 入口 | `Sources/CodexState/CodexStateApp.swift` | 启动 accessory App、装配依赖、定时刷新 |
| 领域模型 | `Sources/CodexStateCore/Domain/UsageModels.swift` | 不依赖 UI 的纯数据模型与 `UsageWarning` |
| 远端 RPC | `Sources/CodexStateCore/RPC/CodexRPCClient.swift` | 启动 `app-server`、JSON-RPC 帧解析、协议编解码 |
| 会话聚合 | `Sources/CodexStateCore/Sessions/*` | JSONL 解析、增量缓存、每日聚合 |
| 价格估算 | `Sources/CodexStateCore/Pricing/*` | 内置 `ModelPrices.json` 与成本计算 |
| 状态层 | `Sources/CodexStateCore/State/UsageStore.swift` | `@MainActor` `@Observable`，合并远端与本地数据，发布 `UsageSnapshot` |
| 平台层 | `Sources/CodexStateCore/Platform/*` | NSPanel、屏幕定位、全局快捷键（Carbon HIToolbox） |
| UI 层 | `Sources/CodexStateCore/UI/*` | SwiftUI 三态视图与每日趋势图 |

依赖方向（除 App 入口引用 Core 外）：

```
UI ─▶ State ─▶ Sessions ─▶ Domain
                └─▶ Pricing ─▶ Domain
            ─▶ RPC   ─▶ Domain
Platform ─▶ State / UI
App ─▶ State / Sessions / RPC / Pricing / Platform / UI
```

`CodexStateCore` 是一个 SwiftPM 库 target，可独立编译和测试；`CodexState` 是薄的可执行 target。

## 3. 关键数据流

```
                       ┌────────────────────────┐
   Codex app-server ◀──▶│ CodexRPCClient        │ ─▶ CodexRemoteSnapshot
   (stdin/stdout JSON-RPC)│                      │      (account + quotaWindows)
                       └────────────────────────┘
                                          │
                                          ▼
                       ┌────────────────────────┐
                       │ UsageStore (@MainActor)│ ◀─── ModelPriceCatalog
                       │                        │ ◀─── SessionUsageRepository
                       │  refresh() 并行拉取    │      (本地 JSONL 增量缓存)
                       │  失败保留 last-known  │
                       └──────────┬─────────────┘
                                  ▼
                          UsageSnapshot
                          (account / quotaWindows /
                           dailyUsage / topModels /
                           warnings / refreshedAt)
                                  │
                                  ▼
                       ┌────────────────────────┐
                       │ SwiftUI Views          │ ◀── NotchPanelController
                       │ (NotchRootView etc.)   │     (NSPanel 状态机)
                       └────────────────────────┘
```

要点：

- `UsageStore.refresh(force:)` 用 `async let` 并行调用 `remoteLoader` 与 `sessionLoader`，避免任一端卡顿拖慢另一端。
- 远端或本地任意一条失败都不会清空已有的 `snapshot`；通过 `UsageWarning` 标记降级。
- 视图层只消费 `UsageSnapshot`，不再触达文件系统或子进程。

## 4. 并发与状态约束

- `UsageStore` 与 `NotchPanelController` 均为 `@MainActor`，符合 Swift 6 严格并发。
- 跨线程模型（`TokenUsage`、`UsageSnapshot` 等）实现 `Sendable`，便于 `async let` 传递。
- `CodexRPCClient`、`SessionUsageRepository`、`GlobalHotKey` 等使用 `@unchecked Sendable`，因为内部对 `Process` / `FileManager` / 状态机做了线程隔离。
- `JSONRPCLineReader` 使用 `NSLock` 保护缓冲与等待队列；`waiters[id]` 与 `responses[id]` 通过信号量解耦。

## 5. 安全与产品边界

| 主题 | 行为 |
| --- | --- |
| 登录 | 不刷新令牌（`account/read` 强制 `refreshToken: false`） |
| 网络 | 禁止网页抓取、WebView、浏览器 Cookie、遥测、远程数据库 |
| 本地数据 | 仅 `CODEX_HOME`（默认 `~/.codex`）下的 `sessions` / `archived_sessions` JSONL |
| 缓存 | `~/Library/Caches/CodexState/usage-cache.json` 只保存聚合用量与文件指纹 |
| 成本 | 基于 `ModelPrices.json` 的估算值，UI 中明示非订阅账单；未知模型不计入成本但仍统计 Token |
| 额度 | 仅展示 RPC 返回的 `usedPercent` 与 `resetsAt`，不推算订阅绝对 Token 上限 |
| 沙箱 | MVP 不启用 App Sandbox，因需要启动本机 `codex` 子进程并读取用户目录 |

## 6. 运行约束

- macOS 14+（`Package.swift` 中 `platforms: [.macOS(.v14)]`）。
- 已安装 Codex CLI，且 `codex login status` 已登录。
- 应用不替代用户登录；只读取 `app-server` 提供的状态。

## 7. 下一步

- 阅读 [领域模型](./02-domain-models.md) 了解 `UsageSnapshot` 结构。
- 阅读 [状态层](./06-state-store.md) 了解 `UsageStore` 的合并与派生逻辑。
- 阅读 [构建与运行](./10-build-and-run.md) 了解本地调试与打包方式。
