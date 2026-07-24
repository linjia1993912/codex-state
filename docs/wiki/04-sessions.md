# 04 · 会话日志解析与聚合

> 文件：
> - `Sources/CodexStateCore/Sessions/SessionLogParser.swift`
> - `Sources/CodexStateCore/Sessions/SessionUsageRepository.swift`

会话层把 `CODEX_HOME`（默认 `~/.codex`）下的 `sessions` 和 `archived_sessions` 两个目录中的 `*.jsonl` 解析为 `UsageContribution`，并通过文件指纹缓存避免重复扫描。

## 1. `SessionLogParser`

```swift
public struct SessionLogParser: Sendable {
    public init()
    public func parse(data: Data) throws -> ParseResult
}
```

### 1.1 输出

```swift
public struct ParseResult: Equatable, Sendable {
    public let contributions: [UsageContribution]
    public let malformedLineCount: Int
}
```

### 1.2 解析策略

按行扫描 JSONL，逐行交给 `LogRecord` 解码：

```swift
private struct LogRecord: Decodable {
    enum Action {
        case modelChanged(String)
        case tokenCount(String, TokenUsage)
        case irrelevant
    }
}
```

支持的事件类型：

| `type` | 处理方式 |
| --- | --- |
| `turn_context` | 读取 `payload.model`，作为后续 `token_count` 事件归属的模型名 |
| `event_msg` | 当 `payload.type == "token_count"` 时读取 `payload.info.total_token_usage` |
| 其它 | 视为 `irrelevant`，跳过 |

`tokenCount` 事件通过 `TokenUsage.delta(from: previousUsage)` 转为增量：

- 累计基线 `previousUsage` 跨整个会话保留；模型切换后仍沿用，避免重复计算历史 Token。
- 若 `delta.total == 0`（例如纯心跳事件），不写入 `contributions`，但 `previousUsage` 仍要更新。
- `ISO8601DateFormatter` 支持带与不带毫秒两种格式。

### 1.3 错误处理

- 单行 JSON 失败 → `malformedLineCount += 1`。
- 纯空白行 → 直接跳过，不计入错误。
- 时间戳缺失或解析失败 → 计入 `malformedLineCount`，并 `continue`。
- 整个文件的 `try parser(...)` 抛错由外层 `SessionUsageRepository.load` 转为 `failedFileCount` 计数。

## 2. `SessionUsageRepository`

```swift
public final class SessionUsageRepository: @unchecked Sendable {
    public init(cacheURL: URL,
                parser: @escaping (Data) throws -> ParseResult = ...)
    public func load(home: URL, calendar: Calendar) throws -> SessionUsageResult
    public static func aggregate(contributions:calendar:catalog:) -> [DailyUsage]
}
```

`@unchecked Sendable` 因为内部对 `FileManager` 做了线程隔离（实际使用全部在 `Task.detached` 中执行）。

### 2.1 缓存

```swift
private struct Cache: Codable { let files: [String: CachedFile] }
private struct CachedFile: Codable {
    let fingerprint: FileFingerprint
    let contributions: [UsageContribution]
    let malformedLineCount: Int
}
private struct FileFingerprint: Codable, Equatable {
    let size: Int64
    let modificationDate: Date
}
```

- 缓存路径：`~/Library/Caches/CodexState/usage-cache.json`。
- 写入采用 `JSONEncoder().encode(...).write(to:options: .atomic)`，避免半写文件。
- 缓存只保存解析后的贡献与文件指纹；**不会**保存任何 JSONL 原文或提示词。
- 单个文件加载失败仅递增 `failedFileCount`，不抹掉其它文件的有效贡献。
- 缓存写入失败也只 `try?`，不阻断本次结果。

### 2.2 `load(home:calendar:)`

1. 读取已有缓存。
2. 枚举 `sessions/` 和 `archived_sessions/` 下的所有 `*.jsonl`（递归）。
3. 对每个文件：
   - 计算 `FileFingerprint`（`fileSize` + `contentModificationDate`）。
   - 若缓存中文件指纹一致 → 直接复用缓存结果。
   - 否则调用 `parser` 重新解析并覆盖。
4. 写回缓存。
5. 汇总 `contributions` 与 `malformedLineCount`。

### 2.3 `aggregate(contributions:calendar:catalog:)`

按 `calendar.startOfDay` 把 `UsageContribution` 分桶，再按模型汇总 `TokenUsage`，最后用 `ModelPriceCatalog.estimate(...)` 计算每日估算成本：

- `estimatedCostUSD` 字段：若该日**所有**模型均无价格则返回 `nil`，否则返回已知价格之和。
- `unknownPriceModels`：该日出现但无价格的模型名（按字母序）。
- 排序：按 `date` 升序返回 `[DailyUsage]`。

## 3. 隐私边界

- 只读取 `payload` 中的 `model` 与 `total_token_usage`，忽略 `prompt`、`content`、工具调用等字段。
- 缓存只含派生数据。
- 不写任何网络请求。
- 文件名或路径不暴露在 UI 中。

## 4. 测试覆盖

- `SessionLogParserTests` — 校验 `turn_context` 模型切换、`token_count` 增量、坏行计数。
- `SessionUsageRepositoryTests` — 校验指纹缓存、目录枚举、跨日聚合与价格合成。
