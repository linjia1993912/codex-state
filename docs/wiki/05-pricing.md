# 05 · 价格估算

> 文件：
> - `Sources/CodexStateCore/Pricing/ModelPriceCatalog.swift`
> - `Sources/CodexStateCore/Pricing/Resources/ModelPrices.json`

价格层提供**只读**的模型单价表，UI 与 `SessionUsageRepository` 都通过 `ModelPriceCatalog` 估算成本。

## 1. `ModelPrice`

```swift
public struct ModelPrice: Codable, Equatable, Sendable {
    public let input: Decimal          // 每百万 token 的输入单价（USD）
    public let cachedInput: Decimal    // 每百万 token 的缓存输入单价
    public let output: Decimal         // 每百万 token 的输出单价
}
```

- 所有价格单位统一为 **USD / 1M tokens**，与 OpenAI 官方报价保持一致。
- `cachedInput` 通常显著低于 `input`，用于支持 prompt caching 的模型。

## 2. `ModelPriceCatalog`

```swift
public struct ModelPriceCatalog: Sendable {
    public init(prices: [String: ModelPrice])
    public func estimate(tokens: TokenUsage, model: String) -> Decimal?
    public static func bundled() throws -> ModelPriceCatalog
}
```

### 2.1 `estimate(tokens:model:)`

公式：

```
let cachedInput = min(tokens.input, tokens.cachedInput)
let cost = Decimal(tokens.input - cachedInput) * price.input
        + Decimal(cachedInput) * price.cachedInput
        + Decimal(tokens.output) * price.output
return cost / 1_000_000
```

- 缓存 Token 被视为输入 Token 的子集，使用 `min` 截断避免负数或重复计费。
- 若 `prices[model] == nil`，返回 `nil`，调用方据此把模型记入 `unknownPriceModels`。
- 返回的 `Decimal` 已除以 `1_000_000`，可直接用于 UI 显示（如 `$\(cost)`）。

### 2.2 `bundled()`

资源加载按以下顺序：

1. `Bundle.main.resourceURL/codex-state_CodexStateCore.bundle/ModelPrices.json`（打包后 App 的标准位置）。
2. `Bundle.module.url(forResource:"ModelPrices", withExtension:"json")`（SwiftPM 测试与裸运行的回退）。
3. 都没有 → 抛 `ModelPriceCatalogError.resourceNotFound`。

> **资源打包**：见 [构建与运行](./10-build-and-run.md)。`Scripts/package_app.sh` 会把 SwiftPM 生成的 `*CodexStateCore.bundle` 拷贝到 `App/Contents/Resources/`，从而让步骤 1 在打包后生效。

## 3. `ModelPrices.json`

```json
{
  "updatedAt": "2026-07-22",
  "models": {
    "gpt-5.6":          { "input": 5,   "cachedInput": 0.5,  "output": 30 },
    "gpt-5.6-sol":      { "input": 5,   "cachedInput": 0.5,  "output": 30 },
    "gpt-5.6-terra":    { "input": 2.5, "cachedInput": 0.25, "output": 15 },
    "gpt-5.6-luna":     { "input": 1,   "cachedInput": 0.1,  "output": 6 }
  }
}
```

- `updatedAt` 为价格表刷新日期，仅供文档与 UI 引用。
- 价格来源：[OpenAI API Pricing](https://developers.openai.com/api/docs/pricing)。
- 更新价格时必须同时：
  1. 替换本文件中的 `input / cachedInput / output`。
  2. 更新 `updatedAt` 与 `README.md` 中的"价格表更新日期"。

## 4. 在 UI 中的表达

- `DailyUsage.estimatedCostUSD == nil` → UI 展示为 `—`。
- 同一日存在未知模型时，UI 会在"估算成本"卡片下追加副标题"未含 N 个未知模型"。
- 顶部摘要"今日估算"在没有窗口数据时也会展示该字段。

## 5. 测试覆盖

`Tests/CodexStateCoreTests/ModelPriceCatalogTests.swift` 验证：

- 缓存输入截断逻辑。
- 未知模型返回 `nil`。
- `bundled()` 在测试 Bundle 中能正确解析 `ModelPrices.json`。
