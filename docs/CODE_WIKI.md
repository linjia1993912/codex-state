# Codex State — Code Wiki

> 原生 macOS 14+ 刘海用量工具的代码知识库。本 Wiki 基于仓库当前实现整理，用于帮助贡献者快速理解项目结构、关键类与函数以及运行方式。

## 文档索引

| 编号 | 主题 | 内容 |
| --- | --- | --- |
| [01](./wiki/01-architecture.md) | 项目架构总览 | 分层、模块依赖、数据流、运行约束 |
| [02](./wiki/02-domain-models.md) | 领域模型 | `TokenUsage` / `DailyUsage` / `QuotaWindow` / `UsageSnapshot` 等 |
| [03](./wiki/03-rpc-layer.md) | Codex RPC 客户端 | `CodexRPCClient` 与 JSON-RPC 帧解析 |
| [04](./wiki/04-sessions.md) | 会话日志 | `SessionLogParser` 与 `SessionUsageRepository` 增量缓存 |
| [05](./wiki/05-pricing.md) | 价格估算 | `ModelPriceCatalog` 与 `ModelPrices.json` |
| [06](./wiki/06-state-store.md) | 状态层 | `@MainActor` `UsageStore` 及其派生快照 |
| [07](./wiki/07-platform.md) | 平台层 | `NotchPanelController` / `GlobalHotKey` / `ScreenPlacement` |
| [08](./wiki/08-ui.md) | UI 视图 | `NotchRootView` / `PeekUsageView` / `ExpandedUsageView` / `DailyTrendView` |
| [09](./wiki/09-app-entry.md) | 应用入口 | `CodexStateApp` 与依赖装配 |
| [10](./wiki/10-build-and-run.md) | 构建与运行 | SwiftPM 命令、测试、打包脚本 |

## 关键概念速查

- **三态窗口**：`NotchPresentation` 定义 `.collapsed`（静默）/ `.peek`（悬停）/ `.expanded`（展开）。
- **数据来源**：远端（Codex `app-server` JSON-RPC） + 本地（`CODEX_HOME` 下的 `sessions` / `archived_sessions` JSONL 日志）。
- **隐私边界**：仅读取账号、额度、Token 计数、模型与时间戳；不持久化任何提示词、回复或令牌。
- **失败降级**：远端或本地任意一条失败都保留最近一次有效快照，并附加 `UsageWarning`。
- **MVP 边界**：单账号、单台 macOS、无云端、无 WebView、无 App Sandbox（依赖本机 Codex 子进程与 `~/.codex` 目录）。

## 仓库布局

```
codex-state/
├── Package.swift                # SwiftPM 清单（Swift 6、macOS 14+）
├── Resources/Info.plist         # 打包 Info.plist
├── Scripts/package_app.sh       # ad-hoc 签名打包脚本
├── Sources/
│   ├── CodexState/              # 应用入口
│   └── CodexStateCore/          # 领域、RPC、Sessions、Pricing、State、Platform、UI
├── Tests/CodexStateCoreTests/   # Swift Testing 测试套件
└── docs/                        # 设计与实施计划（spec / plan）
```

## 关联文档

- [README.md](../../README.md) — 用户可见说明。
- [AGENTS.md](../../AGENTS.md) — 仓库内贡献约束与目录职责。
- [设计文档](../superpowers/specs/2026-07-22-codex-notch-usage-design.md) — 产品与架构设计。
- [实施计划](../superpowers/plans/2026-07-22-codex-notch-usage-implementation.md) — 历史实施任务清单。
