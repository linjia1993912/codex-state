# 02 · 领域模型

> 文件：`Sources/CodexStateCore/Domain/UsageModels.swift`

所有领域模型均实现 `Sendable`，可在跨 actor 边界与 `async let` 之间安全传递。它们不引用 UIKit / SwiftUI / AppKit，可在任何层被复用。

## 1. 枚举

### `UsageRange`

```swift
public enum UsageRange: Int, CaseIterable, Codable, Sendable {
    case day = 1
    case week = 7
    case fortnight = 14
    case month = 30
}
```

- 视图层 `Picker` 直接遍历 `UsageRange.allCases`，因此新增档位需同时考虑 UI 文案与聚合下界。
- `rawValue` 同时被 `UsageStore.rebuildSnapshot` 用作回溯天数。

### `UsageWarning`

```swift
public enum UsageWarning: Equatable, Sendable {
    case staleData
    case malformedLogRecords(Int)
    case unknownPrice(String)
}
```

- `staleData` 由 `UsageStore` 在远端或本地失败时追加。
- `malformedLogRecords` 来自 `SessionUsageRepository` 统计的不可读文件 + 不可解析行。
- `unknownPrice(model)` 来自 `ModelPriceCatalog` 查不到价格的模型。
- `message` 提供本地化文案，UI 优先展示 `visibleWarnings.first`。

## 2. 值类型

### `TokenUsage`

```swift
public struct TokenUsage: Codable, Equatable, Sendable {
    public var input: Int64
    public var cachedInput: Int64
    public var output: Int64
    public var total: Int64
}
```

- `delta(from:)` 计算与上一读数的差值；如果当前 `total` 小于上一读数（来源重置）则返回 `self`，避免把当前值误当作负增量丢弃。
- `+` 运算符按字段相加，用于按日聚合。
- 提供 `.zero` 静态成员便于空值场景。

### `UsageContribution`

```swift
public struct UsageContribution: Codable, Equatable, Sendable {
    public let date: Date
    public let model: String
    public let tokens: TokenUsage
}
```

`SessionLogParser` 的输出单位：每条 JSONL 中的 `token_count` 事件还原成一个增量贡献。

### `DailyUsage`

```swift
public struct DailyUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let tokens: TokenUsage
    public let estimatedCostUSD: Decimal?
    public let tokensByModel: [String: TokenUsage]
    public let unknownPriceModels: [String]
}
```

- `estimatedCostUSD == nil` 表示该日全部模型均无价格；UI 展示为 `—`。
- `unknownPriceModels` 仅列出当日出现过的未知模型，按字母序排序。
- `Identifiable` 的 `id` 直接复用 `date`，便于 `ForEach` 与 SwiftUI 图表绑定。

### `ModelShare`

```swift
public struct ModelShare: Equatable, Identifiable, Sendable {
    public var id: String { model }
    public let model: String
    public let tokens: TokenUsage
    public let fraction: Double
}
```

`UsageStore.rebuildSnapshot` 输出：按 `tokens.total` 降序排序，前三名进入 `topModels`，其余合并为 `其他`。

### `AccountSummary`

```swift
public struct AccountSummary: Equatable, Sendable {
    public let email: String?
    public let plan: String?
    public var maskedEmail: String?
}
```

- 邮箱脱敏仅保留前 3 个字符 + `***@domain`，防止敏感信息显示在悬浮面板。
- 仅当 `email` 含 `@` 时脱敏；缺失或异常时返回原始字符串。

### `QuotaWindow`

```swift
public struct QuotaWindow: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let durationMinutes: Int?
    public var remainingPercent: Double
    public var remainingTitle: String
}
```

- `id` 是 `"primary"` / `"secondary"`，由 RPC 解码器从 `LimitsResponse` 中产出。
- `remainingPercent` 是 `100 - usedPercent` 并夹紧到 `[0, 100]`。
- `remainingTitle` 智能把"`X额度`"后缀替换为"`X剩余`"。

## 3. 快照

### `UsageSnapshot`

```swift
public struct UsageSnapshot: Equatable, Sendable {
    public let account: AccountSummary?
    public let quotaWindows: [QuotaWindow]
    public let dailyUsage: [DailyUsage]
    public let topModels: [ModelShare]
    public let selectedRange: UsageRange
    public let refreshedAt: Date?
    public let isStale: Bool
    public let warnings: [UsageWarning]
    public static let empty: UsageSnapshot
    public var visibleWarnings: [UsageWarning]
}
```

- 视图层唯一读取对象。
- `isStale` 与 `warnings` 共同决定降级提示；`visibleWarnings` 在 `isStale == true` 且未声明 `staleData` 时自动补齐。
- `.empty` 提供一个零值默认，避免 `Optional<UsageSnapshot>`。

## 4. 设计约定

- 所有模型不可变（`let`）或 `var` 但由 `UsageStore` 整体替换，避免局部状态被多个 actor 共享修改。
- `Sendable` 是强制要求；任何引入的新类型都必须能跨 actor 传递。
- UI 不直接构造领域对象；构造集中在 `UsageStore.rebuildSnapshot` 与 `SessionUsageRepository.aggregate`。
