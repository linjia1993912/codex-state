# 06 · 状态层：`UsageStore`

> 文件：`Sources/CodexStateCore/State/UsageStore.swift`

`UsageStore` 是 UI 的唯一数据源。它在 `@MainActor` 下以 `@Observable` 暴露 `snapshot` 与 `isRefreshing`，并把远端 RPC 与本地会话聚合合并为 `UsageSnapshot`。

## 1. 类型定义

```swift
@MainActor
@Observable
public final class UsageStore {
    public typealias RemoteLoader = @Sendable () throws -> CodexRemoteSnapshot
    public typealias SessionLoader = @Sendable () throws -> SessionUsageResult

    public private(set) var snapshot = UsageSnapshot.empty
    public private(set) var isRefreshing = false

    public var todayUsage: DailyUsage { ... }
}
```

- `RemoteLoader` / `SessionLoader` 都是 `@Sendable` 闭包，便于在 `Task.detached` 中执行。
- `todayUsage` 是基于 `now()` 的便捷派生，UI 顶部"今日 Tokens"使用。

## 2. 初始化

```swift
public init(
    remoteLoader: @escaping RemoteLoader,
    sessionLoader: @escaping SessionLoader,
    catalog: ModelPriceCatalog,
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = Date.init
)
```

- `catalog` 必须为只读 `ModelPriceCatalog`。
- `calendar` / `now` 注入便于测试。
- App 入口在 [CodexStateApp](./09-app-entry.md) 中注入 `codexHome` 路径与 `cacheURL`。

## 3. 核心方法

### 3.1 `refresh(force: Bool = false) async`

```swift
public func refresh(force: Bool = false) async
```

执行逻辑：

1. 若已在刷新中 → 直接返回。
2. 若不强制刷新且 60 秒内已成功刷新（`isFresh`）→ 直接返回，避免重复 IO。
3. 设置 `isRefreshing = true`。
4. 用 `async let` 并行加载远端和本地数据。
5. 远端成功 → 仅更新 `account` 与 `quotaWindows`；远端失败 → 保留旧值并标记 `remoteFailed = true`。
6. 本地成功 → 更新 `contributions` 与 `malformedLineCount`；失败 → `sessionFailed = true`。
7. 调用 `rebuildSnapshot(refreshedAt:isStale:)` 重新计算 `dailyUsage` / `topModels` / `warnings`。
8. `defer` 关闭 `isRefreshing`。

`load<Value>(_:)` 静态辅助统一把 `throws` 闭包装成 `Result`：

```swift
private nonisolated static func load<Value: Sendable>(
    _ loader: @escaping @Sendable () throws -> Value
) async -> Result<Value, Error>
```

- `Task.detached` 把同步阻塞的 RPC / 文件 IO 移到非主 actor；
- `Result` 包装避免 `async let` 抛错中断另一条并行任务。

### 3.2 `selectRange(_:)`

```swift
public func selectRange(_ range: UsageRange)
```

- 校验 `UsageRange.allCases.contains(range)`，忽略非法值。
- 替换 `selectedRange` 后重新 `rebuildSnapshot`，**不**触发数据 IO。
- 用于展开面板的 `Picker`。

## 4. `rebuildSnapshot(refreshedAt:isStale:)`

把 `contributions` + `selectedRange` + `catalog` 合并为 `UsageSnapshot`：

1. 调用 `SessionUsageRepository.aggregate(contributions:calendar:catalog:)` 得到所有天的 `DailyUsage`。
2. 取 `>= rangeStart` 的子集填入 `usageByDate`。
3. 构造 `dailyUsage`：长度恰好等于 `selectedRange.rawValue`，缺位补空 `DailyUsage`。
4. 合并 `tokensByModel` 得到 `topModels`：
   - 按 `tokens.total` 降序。
   - 前 3 名进入 `topModels`。
   - 剩余名按 `tokens` / `fraction` 合并为"其他"。
5. 派生 `warnings`：
   - 每个无价格的模型 → `UsageWarning.unknownPrice(model)`。
   - `malformedLineCount > 0` → 追加 `.malformedLogRecords`。
   - `isStale` → 追加 `.staleData`。

## 5. 派生属性

| 属性 | 说明 |
| --- | --- |
| `snapshot` | 当前完整快照（外部只读） |
| `isRefreshing` | `refresh` 正在执行 |
| `todayUsage` | 当天 `DailyUsage`；缺失时返回当日零值 |
| `isFresh` | 内部判定：60 秒内且未陈旧 |
| `contributions` / `malformedLineCount` | 私有内部状态，用于重建 |

## 6. 并发与失败语义

- `isRefreshing` + `isFresh` 双闸门防止快速重复刷新。
- 远端与本地各自独立的失败标志：UI 永远看到"最后一次成功"的数据，但 `warnings` 暴露异常。
- 远端短时间不可用不会清空 `account` / `quotaWindows`；本地 IO 失败不会清空 `contributions`。
- `defer { isRefreshing = false }` 保证抛错后状态也会复位。

## 7. 测试覆盖

`Tests/CodexStateCoreTests/UsageStoreTests.swift` 覆盖：

- 远端失败时仍保留旧的 `account`。
- 本地失败时 `warnings` 包含 `staleData`。
- `selectRange` 改变 `dailyUsage` 长度而不重置 `account`。
- `topModels` 排序与"其他"合并。
- 未知价格模型触发 `UsageWarning.unknownPrice`。
