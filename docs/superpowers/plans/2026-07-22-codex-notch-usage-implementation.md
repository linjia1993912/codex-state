# Codex 刘海用量应用实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个原生 macOS 刘海应用，通过 Codex CLI RPC 展示账号和动态额度窗口，并从本地会话日志统计 1、7、14、30 天 Token、估算成本和常用模型。

**Architecture:** 使用 Swift Package 管理一个 `CodexStateCore` 库目标和一个极薄的 `CodexState` 可执行目标。核心库包含纯数据模型、日志增量扫描、价格估算、Codex JSON-RPC、统一状态、屏幕定位和 SwiftUI/AppKit 界面；可执行目标只负责启动 accessory 应用和装配依赖。

**Tech Stack:** Swift 6.0、SwiftUI、AppKit、Foundation、XCTest、Swift Package Manager；不引入第三方依赖。

## 全局约束

- 最低系统版本为 macOS 14。
- 只支持单个 Codex 账号，不实现多提供商或多账号切换。
- 不硬编码“5 小时额度”；界面只渲染 RPC 实际返回的额度窗口。
- 统计周期固定为 1、7、14、30 天，默认 7 天。
- 成本为美元估算值，不代表 ChatGPT/Codex 订阅的实际账单。
- 不抓网页、不读浏览器 Cookie、不使用 WebView、不上传会话数据。
- 只读取 Token、模型和时间字段，忽略提示词、回复正文和文件内容。
- MVP 使用非 Mac App Store 分发并关闭 App Sandbox。
- 核心逻辑使用中文注释解释“为什么”；避免解释语法本身。
- 每个任务严格先写失败测试，再写最小实现。

---

## 文件结构

```text
Package.swift
README.md
Sources/
├── CodexState/
│   └── CodexStateApp.swift
└── CodexStateCore/
    ├── Domain/
    │   └── UsageModels.swift
    ├── Pricing/
    │   ├── ModelPriceCatalog.swift
    │   └── Resources/ModelPrices.json
    ├── Sessions/
    │   ├── SessionLogParser.swift
    │   └── SessionUsageRepository.swift
    ├── RPC/
    │   └── CodexRPCClient.swift
    ├── State/
    │   └── UsageStore.swift
    ├── Platform/
    │   ├── ScreenPlacement.swift
    │   ├── NotchPanelController.swift
    │   └── GlobalHotKey.swift
    └── UI/
        ├── NotchRootView.swift
        ├── PeekUsageView.swift
        └── ExpandedUsageView.swift
Tests/
└── CodexStateCoreTests/
    ├── UsageModelsTests.swift
    ├── ModelPriceCatalogTests.swift
    ├── SessionLogParserTests.swift
    ├── SessionUsageRepositoryTests.swift
    ├── CodexRPCClientTests.swift
    ├── UsageStoreTests.swift
    └── ScreenPlacementTests.swift
Resources/
└── Info.plist
Scripts/
└── package_app.sh
docs/superpowers/
├── specs/2026-07-22-codex-notch-usage-design.md
└── plans/2026-07-22-codex-notch-usage-implementation.md
```

---

### 任务 1：建立 Swift 包和领域模型

**Files:**
- Create: `Package.swift`
- Create: `Sources/CodexStateCore/Domain/UsageModels.swift`
- Create: `Tests/CodexStateCoreTests/UsageModelsTests.swift`

**Interfaces:**
- Produces: `UsageRange`、`TokenUsage`、`UsageContribution`、`DailyUsage`、`ModelShare`、`AccountSummary`、`QuotaWindow`、`UsageSnapshot`。

- [ ] **Step 1: 创建包清单和失败测试**

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "codex-state",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexStateCore", targets: ["CodexStateCore"]),
    ],
    targets: [
        .target(name: "CodexStateCore"),
        .testTarget(name: "CodexStateCoreTests", dependencies: ["CodexStateCore"]),
    ]
)
```

```swift
// Sources/CodexStateCore/Domain/UsageModels.swift（失败测试阶段）
import Foundation
```

```swift
// Tests/CodexStateCoreTests/UsageModelsTests.swift
import XCTest
@testable import CodexStateCore

final class UsageModelsTests: XCTestCase {
    func testTokenUsageDeltaClampsCounterReset() {
        let previous = TokenUsage(input: 100, cachedInput: 40, output: 20, total: 120)
        let current = TokenUsage(input: 30, cachedInput: 10, output: 5, total: 35)

        XCTAssertEqual(current.delta(from: previous), current)
    }

    func testTokenUsageDeltaUsesCumulativeDifference() {
        let previous = TokenUsage(input: 100, cachedInput: 40, output: 20, total: 120)
        let current = TokenUsage(input: 150, cachedInput: 60, output: 30, total: 180)

        XCTAssertEqual(
            current.delta(from: previous),
            TokenUsage(input: 50, cachedInput: 20, output: 10, total: 60)
        )
    }
}
```

- [ ] **Step 2: 运行测试，确认因类型缺失而失败**

Run: `swift test --filter UsageModelsTests`

Expected: FAIL，包含 `cannot find 'TokenUsage' in scope`。

- [ ] **Step 3: 实现最小领域模型**

```swift
// Sources/CodexStateCore/Domain/UsageModels.swift
import Foundation

public enum UsageRange: Int, CaseIterable, Codable, Sendable {
    case day = 1
    case week = 7
    case fortnight = 14
    case month = 30
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var input: Int64
    public var cachedInput: Int64
    public var output: Int64
    public var total: Int64

    public static let zero = TokenUsage(input: 0, cachedInput: 0, output: 0, total: 0)

    public init(input: Int64, cachedInput: Int64, output: Int64, total: Int64) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.total = total
    }

    public func delta(from previous: TokenUsage) -> TokenUsage {
        // Codex 进程重启或日志拼接会使累计计数器回退；此时当前值本身就是新一段增量。
        guard total >= previous.total else { return self }
        return TokenUsage(
            input: max(0, input - previous.input),
            cachedInput: max(0, cachedInput - previous.cachedInput),
            output: max(0, output - previous.output),
            total: max(0, total - previous.total)
        )
    }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            cachedInput: lhs.cachedInput + rhs.cachedInput,
            output: lhs.output + rhs.output,
            total: lhs.total + rhs.total
        )
    }
}

public struct UsageContribution: Codable, Equatable, Sendable {
    public let date: Date
    public let model: String
    public let tokens: TokenUsage
}

public struct DailyUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let tokens: TokenUsage
    public let estimatedCostUSD: Decimal?
    public let tokensByModel: [String: TokenUsage]
}

public struct ModelShare: Equatable, Identifiable, Sendable {
    public var id: String { model }
    public let model: String
    public let tokens: Int64
    public let fraction: Double
}

public struct AccountSummary: Equatable, Sendable {
    public let email: String?
    public let plan: String?

    public var maskedEmail: String? {
        guard let email, let at = email.firstIndex(of: "@") else { return email }
        let domain = email[at...]
        let prefix = email.prefix(3)
        return "\(prefix)***\(domain)"
    }
}

public struct QuotaWindow: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Int
    public let resetsAt: Date?
    public let durationMinutes: Int?
}

public enum UsageWarning: Equatable, Sendable {
    case staleData
    case malformedLogRecords(Int)
    case unknownPrice(String)
}

public struct UsageSnapshot: Equatable, Sendable {
    public var account: AccountSummary?
    public var quotaWindows: [QuotaWindow]
    public var dailyUsage: [DailyUsage]
    public var topModels: [ModelShare]
    public var selectedRange: UsageRange
    public var refreshedAt: Date?
    public var isStale: Bool
    public var warnings: [UsageWarning]

    public static let empty = UsageSnapshot(
        account: nil,
        quotaWindows: [],
        dailyUsage: [],
        topModels: [],
        selectedRange: .week,
        refreshedAt: nil,
        isStale: false,
        warnings: []
    )
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift test --filter UsageModelsTests`

Expected: PASS，2 tests。

- [ ] **Step 5: 提交**

```bash
git add Package.swift Sources/CodexStateCore/Domain/UsageModels.swift Tests/CodexStateCoreTests/UsageModelsTests.swift
git commit -m "feat: add usage domain models"
```

---

### 任务 2：实现模型价格表与成本估算

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CodexStateCore/Pricing/ModelPriceCatalog.swift`
- Create: `Sources/CodexStateCore/Pricing/Resources/ModelPrices.json`
- Create: `Tests/CodexStateCoreTests/ModelPriceCatalogTests.swift`

**Interfaces:**
- Consumes: `TokenUsage`。
- Produces: `ModelPriceCatalog.estimate(tokens:model:) -> Decimal?`、`ModelPriceCatalog.bundled()`。

- [ ] **Step 1: 写失败测试**

```swift
// Tests/CodexStateCoreTests/ModelPriceCatalogTests.swift
import XCTest
@testable import CodexStateCore

final class ModelPriceCatalogTests: XCTestCase {
    func testEstimateSeparatesCachedInput() throws {
        let catalog = ModelPriceCatalog(prices: [
            "gpt-5.6-sol": ModelPrice(input: 5, cachedInput: 0.5, output: 30),
        ])
        let tokens = TokenUsage(input: 1_000, cachedInput: 200, output: 100, total: 1_100)

        XCTAssertEqual(catalog.estimate(tokens: tokens, model: "gpt-5.6-sol"), Decimal(string: "0.0071"))
    }

    func testUnknownModelReturnsNil() {
        let catalog = ModelPriceCatalog(prices: [:])
        XCTAssertNil(catalog.estimate(tokens: .zero, model: "unknown"))
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter ModelPriceCatalogTests`

Expected: FAIL，包含 `cannot find 'ModelPriceCatalog' in scope`。

- [ ] **Step 3: 实现价格模型和估算器**

先把 `Package.swift` 中的核心 target 改为：

```swift
.target(
    name: "CodexStateCore",
    resources: [.process("Pricing/Resources")]
),
```

```swift
// Sources/CodexStateCore/Pricing/ModelPriceCatalog.swift
import Foundation

public struct ModelPrice: Codable, Equatable, Sendable {
    public let input: Decimal
    public let cachedInput: Decimal
    public let output: Decimal

    public init(input: Decimal, cachedInput: Decimal, output: Decimal) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
    }
}

public struct ModelPriceCatalog: Sendable {
    private struct FilePayload: Decodable {
        let updatedAt: String
        let models: [String: ModelPrice]
    }

    private let prices: [String: ModelPrice]

    public init(prices: [String: ModelPrice]) {
        self.prices = prices
    }

    public static func bundled() throws -> ModelPriceCatalog {
        let url = Bundle.module.url(forResource: "ModelPrices", withExtension: "json")!
        let payload = try JSONDecoder().decode(FilePayload.self, from: Data(contentsOf: url))
        return ModelPriceCatalog(prices: payload.models)
    }

    public func estimate(tokens: TokenUsage, model: String) -> Decimal? {
        guard let price = prices[model] else { return nil }
        let cached = min(tokens.input, tokens.cachedInput)
        let uncached = tokens.input - cached
        let million = Decimal(1_000_000)
        return (
            Decimal(uncached) * price.input
                + Decimal(cached) * price.cachedInput
                + Decimal(tokens.output) * price.output
        ) / million
    }
}
```

```json
{
  "updatedAt": "2026-07-22",
  "models": {
    "gpt-5.6": { "input": 5.0, "cachedInput": 0.5, "output": 30.0 },
    "gpt-5.6-sol": { "input": 5.0, "cachedInput": 0.5, "output": 30.0 },
    "gpt-5.6-terra": { "input": 2.5, "cachedInput": 0.25, "output": 15.0 },
    "gpt-5.6-luna": { "input": 1.0, "cachedInput": 0.1, "output": 6.0 }
  }
}
```

价格来源：OpenAI 官方模型页面，单位为每 100 万 Token。实现时在 README 中保留对应链接和更新时间。

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift test --filter ModelPriceCatalogTests`

Expected: PASS，2 tests。

- [ ] **Step 5: 提交**

```bash
git add Package.swift Sources/CodexStateCore/Pricing Tests/CodexStateCoreTests/ModelPriceCatalogTests.swift
git commit -m "feat: estimate token cost by model"
```

---

### 任务 3：解析 Codex JSONL 会话日志

**Files:**
- Create: `Sources/CodexStateCore/Sessions/SessionLogParser.swift`
- Create: `Tests/CodexStateCoreTests/SessionLogParserTests.swift`

**Interfaces:**
- Consumes: Codex `turn_context` 与 `event_msg/token_count` JSONL 行。
- Produces: `SessionLogParser.parse(data:) -> ParseResult`，其中 `ParseResult.contributions` 为增量用量，`malformedLineCount` 为坏行数。

- [ ] **Step 1: 写累计计数器与模型切换测试**

```swift
// Tests/CodexStateCoreTests/SessionLogParserTests.swift
import XCTest
@testable import CodexStateCore

final class SessionLogParserTests: XCTestCase {
    func testParsesCumulativeCountersAsDeltas() throws {
        let jsonl = """
        {"timestamp":"2026-07-21T23:59:00Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
        {"timestamp":"2026-07-21T23:59:10Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":20,"reasoning_output_tokens":10,"total_tokens":100}}}}
        {"timestamp":"2026-07-21T23:59:20Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120,"cached_input_tokens":30,"output_tokens":30,"reasoning_output_tokens":12,"total_tokens":150}}}}
        {"timestamp":"2026-07-22T00:01:00Z","type":"turn_context","payload":{"model":"gpt-5.6-terra"}}
        {"timestamp":"2026-07-22T00:01:10Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":180,"cached_input_tokens":50,"output_tokens":50,"reasoning_output_tokens":20,"total_tokens":230}}}}
        bad-json
        """

        let result = try SessionLogParser().parse(data: Data(jsonl.utf8))

        XCTAssertEqual(result.contributions.map(\.tokens.total), [100, 50, 80])
        XCTAssertEqual(result.contributions.map(\.model), ["gpt-5.6-sol", "gpt-5.6-sol", "gpt-5.6-terra"])
        XCTAssertEqual(result.malformedLineCount, 1)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter SessionLogParserTests`

Expected: FAIL，包含 `cannot find 'SessionLogParser' in scope`。

- [ ] **Step 3: 实现只读取所需字段的解析器**

```swift
// Sources/CodexStateCore/Sessions/SessionLogParser.swift
import Foundation

public struct ParseResult: Equatable, Sendable {
    public let contributions: [UsageContribution]
    public let malformedLineCount: Int
}

public struct SessionLogParser: Sendable {
    private struct Envelope: Decodable {
        let timestamp: Date
        let type: String
        let payload: Payload
    }

    private struct Payload: Decodable {
        let type: String?
        let model: String?
        let info: Info?
    }

    private struct Info: Decodable {
        let totalTokenUsage: RawTokens?
        enum CodingKeys: String, CodingKey { case totalTokenUsage = "total_token_usage" }
    }

    private struct RawTokens: Decodable {
        let input: Int64
        let cachedInput: Int64
        let output: Int64
        let total: Int64

        enum CodingKeys: String, CodingKey {
            case input = "input_tokens"
            case cachedInput = "cached_input_tokens"
            case output = "output_tokens"
            case total = "total_tokens"
        }

        var usage: TokenUsage {
            TokenUsage(input: input, cachedInput: cachedInput, output: output, total: total)
        }
    }

    public init() {}

    public func parse(data: Data) throws -> ParseResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var model = "unknown"
        var previous = TokenUsage.zero
        var contributions: [UsageContribution] = []
        var malformed = 0

        for bytes in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let envelope = try? decoder.decode(Envelope.self, from: Data(bytes)) else {
                malformed += 1
                continue
            }
            if envelope.type == "turn_context", let nextModel = envelope.payload.model {
                model = nextModel
                continue
            }
            guard envelope.type == "event_msg",
                  envelope.payload.type == "token_count",
                  let current = envelope.payload.info?.totalTokenUsage?.usage else { continue }

            let delta = current.delta(from: previous)
            previous = current
            guard delta.total > 0 else { continue }
            contributions.append(UsageContribution(date: envelope.timestamp, model: model, tokens: delta))
        }
        return ParseResult(contributions: contributions, malformedLineCount: malformed)
    }
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift test --filter SessionLogParserTests`

Expected: PASS，1 test。

- [ ] **Step 5: 提交**

```bash
git add Sources/CodexStateCore/Sessions/SessionLogParser.swift Tests/CodexStateCoreTests/SessionLogParserTests.swift
git commit -m "feat: parse codex session token logs"
```

---

### 任务 4：增加文件级增量缓存与日聚合

**Files:**
- Create: `Sources/CodexStateCore/Sessions/SessionUsageRepository.swift`
- Create: `Tests/CodexStateCoreTests/SessionUsageRepositoryTests.swift`

**Interfaces:**
- Consumes: `SessionLogParser.parse(data:)`、Codex home 路径、`ModelPriceCatalog`。
- Produces: `SessionUsageRepository.load(home:calendar:) -> SessionUsageResult`。

- [ ] **Step 1: 写只重扫变更文件的测试**

```swift
// Tests/CodexStateCoreTests/SessionUsageRepositoryTests.swift
import XCTest
@testable import CodexStateCore

final class SessionUsageRepositoryTests: XCTestCase {
    func testReusesUnchangedFileContribution() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = root.appendingPathComponent("sessions/2026/07/22")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout.jsonl")
        try Data("{}\n".utf8).write(to: file)
        var parseCount = 0
        let contribution = UsageContribution(
            date: Date(timeIntervalSince1970: 1_753_132_800),
            model: "gpt-5.6-sol",
            tokens: TokenUsage(input: 8, cachedInput: 2, output: 2, total: 10)
        )
        let repository = SessionUsageRepository(
            cacheURL: root.appendingPathComponent("cache.json"),
            parse: { _ in parseCount += 1; return ParseResult(contributions: [contribution], malformedLineCount: 0) }
        )

        _ = try repository.load(home: root, calendar: Calendar(identifier: .gregorian))
        _ = try repository.load(home: root, calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(parseCount, 1)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter SessionUsageRepositoryTests`

Expected: FAIL，包含 `cannot find 'SessionUsageRepository' in scope`。

- [ ] **Step 3: 实现发现、缓存和聚合**

```swift
// Sources/CodexStateCore/Sessions/SessionUsageRepository.swift
import Foundation

public struct SessionUsageResult: Sendable {
    public let contributions: [UsageContribution]
    public let malformedLineCount: Int
}

public final class SessionUsageRepository: @unchecked Sendable {
    private struct Fingerprint: Codable, Equatable {
        let size: Int64
        let modifiedAt: Date
    }

    private struct CachedFile: Codable {
        let fingerprint: Fingerprint
        let contributions: [UsageContribution]
        let malformedLineCount: Int
    }

    private let cacheURL: URL
    private let parse: (Data) throws -> ParseResult

    public init(
        cacheURL: URL,
        parse: @escaping (Data) throws -> ParseResult = { try SessionLogParser().parse(data: $0) }
    ) {
        self.cacheURL = cacheURL
        self.parse = parse
    }

    public func load(home: URL, calendar: Calendar) throws -> SessionUsageResult {
        var cache = loadCache()
        let files = discoverFiles(home: home)
        var next: [String: CachedFile] = [:]

        for file in files {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let fingerprint = Fingerprint(
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
            let key = file.path
            if let cached = cache[key], cached.fingerprint == fingerprint {
                next[key] = cached
                continue
            }
            let result = try parse(Data(contentsOf: file))
            next[key] = CachedFile(
                fingerprint: fingerprint,
                contributions: result.contributions,
                malformedLineCount: result.malformedLineCount
            )
        }
        cache = next
        try saveCache(cache)
        return SessionUsageResult(
            contributions: cache.values.flatMap(\.contributions),
            malformedLineCount: cache.values.reduce(0) { $0 + $1.malformedLineCount }
        )
    }

    private func discoverFiles(home: URL) -> [URL] {
        [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")]
            .flatMap { root in
                guard let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { return [] }
                return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
            }
    }

    private func loadCache() -> [String: CachedFile] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [:] }
        return (try? JSONDecoder().decode([String: CachedFile].self, from: data)) ?? [:]
    }

    private func saveCache(_ cache: [String: CachedFile]) throws {
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
    }
}
```

在同一文件加入日聚合函数：

```swift
public func aggregate(
    contributions: [UsageContribution],
    calendar: Calendar,
    catalog: ModelPriceCatalog
) -> [DailyUsage] {
    var grouped: [Date: [String: TokenUsage]] = [:]
    for contribution in contributions {
        let day = calendar.startOfDay(for: contribution.date)
        grouped[day, default: [:]][contribution.model, default: .zero] =
            grouped[day, default: [:]][contribution.model, default: .zero] + contribution.tokens
    }

    return grouped.map { day, byModel in
        var cost: Decimal = 0
        var hasUnknownPrice = false
        var total = TokenUsage.zero
        for (model, tokens) in byModel {
            total = total + tokens
            if let estimate = catalog.estimate(tokens: tokens, model: model) {
                cost += estimate
            } else {
                hasUnknownPrice = true
            }
        }
        return DailyUsage(
            date: day,
            tokens: total,
            estimatedCostUSD: hasUnknownPrice ? nil : cost,
            tokensByModel: byModel
        )
    }
    .sorted { $0.date < $1.date }
}
```

在测试文件加入跨日断言：

```swift
func testAggregateUsesInjectedCalendarDayBoundary() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
    let catalog = ModelPriceCatalog(prices: [
        "gpt-5.6-sol": ModelPrice(input: 5, cachedInput: 0.5, output: 30),
    ])
    let values = aggregate(
        contributions: [
            UsageContribution(
                date: ISO8601DateFormatter().date(from: "2026-07-21T15:59:00Z")!,
                model: "gpt-5.6-sol",
                tokens: TokenUsage(input: 10, cachedInput: 0, output: 0, total: 10)
            ),
            UsageContribution(
                date: ISO8601DateFormatter().date(from: "2026-07-21T16:01:00Z")!,
                model: "gpt-5.6-sol",
                tokens: TokenUsage(input: 20, cachedInput: 0, output: 0, total: 20)
            ),
        ],
        calendar: calendar,
        catalog: catalog
    )
    XCTAssertEqual(values.count, 2)
    XCTAssertEqual(values.map(\.tokens.total), [10, 20])
}
```

- [ ] **Step 4: 运行缓存和全量测试**

Run: `swift test --filter SessionUsageRepositoryTests && swift test`

Expected: 两条命令均 PASS；第二次加载 `parseCount == 1`。

- [ ] **Step 5: 提交**

```bash
git add Sources/CodexStateCore/Sessions/SessionUsageRepository.swift Tests/CodexStateCoreTests/SessionUsageRepositoryTests.swift
git commit -m "feat: cache and aggregate session usage"
```

---

### 任务 5：实现 Codex app-server JSON-RPC 客户端

**Files:**
- Create: `Sources/CodexStateCore/RPC/CodexRPCClient.swift`
- Create: `Tests/CodexStateCoreTests/CodexRPCClientTests.swift`

**Interfaces:**
- Produces: `CodexRPCClient.fetch() throws -> CodexRemoteSnapshot`。
- RPC methods: `initialize`、`account/read`、`account/rateLimits/read`。
- `CodexRemoteSnapshot` 包含 `AccountSummary?` 与 `[QuotaWindow]`。

- [ ] **Step 1: 写响应解码和动态窗口测试**

```swift
// Tests/CodexStateCoreTests/CodexRPCClientTests.swift
import XCTest
@testable import CodexStateCore

final class CodexRPCClientTests: XCTestCase {
    func testDecodesOnlyReturnedQuotaWindows() throws {
        let data = Data("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex","limitName":"Codex","planType":"plus","primary":null,"secondary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1753747200}}}}
        """.utf8)

        let windows = try CodexRPCCodec.decodeRateLimits(data)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].id, "secondary")
        XCTAssertEqual(windows[0].title, "每周额度")
        XCTAssertEqual(windows[0].usedPercent, 42)
    }

    func testDecodesChatGPTAccount() throws {
        let data = Data("""
        {"id":2,"result":{"account":{"type":"chatgpt","email":"lin@example.com","planType":"plus"},"requiresOpenaiAuth":true}}
        """.utf8)
        XCTAssertEqual(
            try CodexRPCCodec.decodeAccount(data),
            AccountSummary(email: "lin@example.com", plan: "plus")
        )
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter CodexRPCClientTests`

Expected: FAIL，包含 `cannot find 'CodexRPCCodec' in scope`。

- [ ] **Step 3: 实现协议 DTO、纯解码器和进程客户端**

```swift
// Sources/CodexStateCore/RPC/CodexRPCClient.swift
import Foundation

public struct CodexRemoteSnapshot: Equatable, Sendable {
    public let account: AccountSummary?
    public let quotaWindows: [QuotaWindow]
}

public enum CodexRPCError: LocalizedError {
    case executableNotFound
    case timeout
    case invalidResponse
    case server(String)
}

public enum CodexRPCCodec {
    private struct AccountResponse: Decodable {
        struct Result: Decodable {
            struct Account: Decodable { let type: String; let email: String?; let planType: String? }
            let account: Account?
        }
        let result: Result
    }

    private struct LimitsResponse: Decodable {
        struct Result: Decodable {
            struct Snapshot: Decodable {
                struct Window: Decodable {
                    let usedPercent: Int
                    let windowDurationMins: Int?
                    let resetsAt: Int64?
                }
                let primary: Window?
                let secondary: Window?
            }
            let rateLimits: Snapshot
        }
        let result: Result
    }

    public static func decodeAccount(_ data: Data) throws -> AccountSummary? {
        let account = try JSONDecoder().decode(AccountResponse.self, from: data).result.account
        guard let account, account.type == "chatgpt" else { return nil }
        return AccountSummary(email: account.email, plan: account.planType)
    }

    public static func decodeRateLimits(_ data: Data) throws -> [QuotaWindow] {
        let snapshot = try JSONDecoder().decode(LimitsResponse.self, from: data).result.rateLimits
        return [("primary", snapshot.primary), ("secondary", snapshot.secondary)].compactMap { id, window in
            guard let window else { return nil }
            return QuotaWindow(
                id: id,
                title: title(duration: window.windowDurationMins, fallback: id),
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                durationMinutes: window.windowDurationMins
            )
        }
    }

    private static func title(duration: Int?, fallback: String) -> String {
        guard let duration else { return fallback == "primary" ? "短周期额度" : "每周额度" }
        if duration >= 10_080 { return "每周额度" }
        if duration % 1_440 == 0 { return "\(duration / 1_440) 天额度" }
        if duration % 60 == 0 { return "\(duration / 60) 小时额度" }
        return "额度"
    }
}
```

在同一文件继续加入可超时的行读取器和进程客户端：

```swift
private final class JSONLineInbox: @unchecked Sendable {
    private let condition = NSCondition()
    private let handle: FileHandle
    private var buffer = Data()
    private var lines: [Data] = []

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] readable in
            self?.append(readable.availableData)
        }
    }

    deinit { handle.readabilityHandler = nil }

    func response(id: Int, timeout: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let index = lines.firstIndex(where: { data in
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return false }
                return (object["id"] as? NSNumber)?.intValue == id
            }) {
                return lines.remove(at: index)
            }
            guard condition.wait(until: deadline) else { throw CodexRPCError.timeout }
        }
    }

    private func append(_ data: Data) {
        guard !data.isEmpty else { return }
        condition.lock()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if !line.isEmpty { lines.append(line) }
        }
        condition.broadcast()
        condition.unlock()
    }
}

public final class CodexRPCClient: @unchecked Sendable {
    private let explicitExecutableURL: URL?
    private let timeout: TimeInterval

    public init(executableURL: URL? = nil, timeout: TimeInterval = 8) {
        explicitExecutableURL = executableURL
        self.timeout = timeout
    }

    public func fetch() throws -> CodexRemoteSnapshot {
        guard let executableURL = locateExecutable() else { throw CodexRPCError.executableNotFound }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executableURL
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do { try process.run() } catch { throw CodexRPCError.server(error.localizedDescription) }
        let inbox = JSONLineInbox(handle: output.fileHandleForReading)
        defer {
            input.fileHandleForWriting.closeFile()
            output.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }

        try write(
            id: 1,
            method: "initialize",
            params: [
                "clientInfo": ["name": "codex-state", "title": "Codex State", "version": "0.1.0"],
                "capabilities": ["experimentalApi": false],
            ],
            to: input.fileHandleForWriting
        )
        _ = try inbox.response(id: 1, timeout: timeout)

        try write(
            id: 2,
            method: "account/read",
            params: ["refreshToken": false],
            to: input.fileHandleForWriting
        )
        let accountData = try inbox.response(id: 2, timeout: timeout)

        try write(
            id: 3,
            method: "account/rateLimits/read",
            params: [:],
            to: input.fileHandleForWriting
        )
        let limitsData = try inbox.response(id: 3, timeout: timeout)
        return CodexRemoteSnapshot(
            account: try CodexRPCCodec.decodeAccount(accountData),
            quotaWindows: try CodexRPCCodec.decodeRateLimits(limitsData)
        )
    }

    private func locateExecutable() -> URL? {
        if let explicitExecutableURL { return explicitExecutableURL }
        let manager = FileManager.default
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
        let fixedCandidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        return (pathCandidates + fixedCandidates).first { manager.isExecutableFile(atPath: $0.path) }
    }

    private func write(id: Int, method: String, params: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: [
            "id": id,
            "method": method,
            "params": params,
        ])
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }
}
```

- [ ] **Step 4: 运行单元测试并做本机只读诊断**

Run: `swift test --filter CodexRPCClientTests`

Expected: PASS，2 tests。

Run: `swift test`

Expected: PASS。实际 RPC 进程检查留到任务 9 的应用手工验收，避免单元测试依赖登录态和网络。

- [ ] **Step 5: 提交**

```bash
git add Sources/CodexStateCore/RPC/CodexRPCClient.swift Tests/CodexStateCoreTests/CodexRPCClientTests.swift
git commit -m "feat: read codex account and rate limits"
```

---

### 任务 6：实现统一状态、刷新和展示聚合

**Files:**
- Create: `Sources/CodexStateCore/State/UsageStore.swift`
- Create: `Tests/CodexStateCoreTests/UsageStoreTests.swift`

**Interfaces:**
- Consumes: `() throws -> CodexRemoteSnapshot`、`() throws -> SessionUsageResult`、`ModelPriceCatalog`。
- Produces: `@MainActor @Observable UsageStore`，公开 `snapshot`、`refresh(force:)`、`selectRange(_:)`、`todayUsage`。

- [ ] **Step 1: 写额度缺失和范围切换测试**

```swift
// Tests/CodexStateCoreTests/UsageStoreTests.swift
import XCTest
@testable import CodexStateCore

@MainActor
final class UsageStoreTests: XCTestCase {
    func testKeepsLastRemoteDataWhenRefreshFails() async {
        final class Flag: @unchecked Sendable { var value = false }
        let shouldFail = Flag()
        let remote = CodexRemoteSnapshot(
            account: AccountSummary(email: "lin@example.com", plan: "plus"),
            quotaWindows: []
        )
        let store = UsageStore(
            loadRemote: { if shouldFail.value { throw CodexRPCError.timeout }; return remote },
            loadSessions: { SessionUsageResult(contributions: [], malformedLineCount: 0) },
            catalog: ModelPriceCatalog(prices: [:]),
            now: { Date(timeIntervalSince1970: 1_753_200_000) }
        )

        await store.refresh(force: true)
        shouldFail.value = true
        await store.refresh(force: true)

        XCTAssertEqual(store.snapshot.account, remote.account)
        XCTAssertTrue(store.snapshot.isStale)
        XCTAssertTrue(store.snapshot.warnings.contains(.staleData))
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter UsageStoreTests`

Expected: FAIL，包含 `cannot find 'UsageStore' in scope`。

- [ ] **Step 3: 实现状态存储**

```swift
// Sources/CodexStateCore/State/UsageStore.swift
import Foundation
import Observation

@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshot = UsageSnapshot.empty
    public private(set) var isRefreshing = false

    private let loadRemote: @Sendable () throws -> CodexRemoteSnapshot
    private let loadSessions: @Sendable () throws -> SessionUsageResult
    private let catalog: ModelPriceCatalog
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var allDailyUsage: [DailyUsage] = []

    public init(
        loadRemote: @escaping @Sendable () throws -> CodexRemoteSnapshot,
        loadSessions: @escaping @Sendable () throws -> SessionUsageResult,
        catalog: ModelPriceCatalog,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.loadRemote = loadRemote
        self.loadSessions = loadSessions
        self.catalog = catalog
        self.calendar = calendar
        self.now = now
    }

    public var todayUsage: DailyUsage {
        let today = calendar.startOfDay(for: now())
        return allDailyUsage.first(where: { calendar.isDate($0.date, inSameDayAs: today) })
            ?? DailyUsage(date: today, tokens: .zero, estimatedCostUSD: 0, tokensByModel: [:])
    }

    public func selectRange(_ range: UsageRange) {
        snapshot.selectedRange = range
        rebuildDerivedValues()
    }

    public func refresh(force: Bool = false) async {
        if !force, let last = snapshot.refreshedAt, now().timeIntervalSince(last) < 60 { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let remoteLoader = loadRemote
            let sessionLoader = loadSessions
            let remoteTask = Task.detached(priority: .utility) { try remoteLoader() }
            let sessionTask = Task.detached(priority: .utility) { try sessionLoader() }
            let remoteValue = try await remoteTask.value
            let sessionValue = try await sessionTask.value
            snapshot.account = remoteValue.account
            snapshot.quotaWindows = remoteValue.quotaWindows
            snapshot.refreshedAt = now()
            snapshot.isStale = false
            snapshot.warnings = sessionValue.malformedLineCount > 0
                ? [.malformedLogRecords(sessionValue.malformedLineCount)] : []
            apply(sessionValue.contributions)
        } catch {
            // 保留最后一次成功快照比清空界面更可用，但必须明确标记已过期。
            snapshot.isStale = true
            if !snapshot.warnings.contains(.staleData) { snapshot.warnings.append(.staleData) }
        }
    }

    private func apply(_ contributions: [UsageContribution]) {
        allDailyUsage = aggregate(contributions: contributions, calendar: calendar, catalog: catalog)
        let today = calendar.startOfDay(for: now())
        if !allDailyUsage.contains(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            allDailyUsage.append(
                DailyUsage(date: today, tokens: .zero, estimatedCostUSD: 0, tokensByModel: [:])
            )
            allDailyUsage.sort { $0.date < $1.date }
        }
        rebuildDerivedValues()
    }

    private func rebuildDerivedValues() {
        let today = calendar.startOfDay(for: now())
        let start = calendar.date(
            byAdding: .day,
            value: 1 - snapshot.selectedRange.rawValue,
            to: today
        )!
        let selected = allDailyUsage.filter { $0.date >= start && $0.date <= today }
        snapshot.dailyUsage = selected

        var totals: [String: Int64] = [:]
        for day in selected {
            for (model, tokens) in day.tokensByModel { totals[model, default: 0] += tokens.total }
        }
        let sorted = totals.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        let grandTotal = max(1, sorted.reduce(Int64(0)) { $0 + $1.value })
        var shares = sorted.prefix(3).map {
            ModelShare(model: $0.key, tokens: $0.value, fraction: Double($0.value) / Double(grandTotal))
        }
        let otherTokens = sorted.dropFirst(3).reduce(Int64(0)) { $0 + $1.value }
        if otherTokens > 0 {
            shares.append(
                ModelShare(model: "其他", tokens: otherTokens, fraction: Double(otherTokens) / Double(grandTotal))
            )
        }
        snapshot.topModels = shares
    }
}
```

在同一测试文件增加以下具体测试：

```swift
func testTodayUsageIsZeroWhenThereAreNoLogs() {
    let store = UsageStore(
        loadRemote: { CodexRemoteSnapshot(account: nil, quotaWindows: []) },
        loadSessions: { SessionUsageResult(contributions: [], malformedLineCount: 0) },
        catalog: ModelPriceCatalog(prices: [:]),
        now: { Date(timeIntervalSince1970: 1_753_200_000) }
    )
    XCTAssertEqual(store.todayUsage.tokens, .zero)
}

func testFreshSnapshotSkipsSecondNonForcedRefresh() async {
    final class Counter: @unchecked Sendable { var value = 0 }
    let counter = Counter()
    let store = UsageStore(
        loadRemote: { counter.value += 1; return CodexRemoteSnapshot(account: nil, quotaWindows: []) },
        loadSessions: { SessionUsageResult(contributions: [], malformedLineCount: 0) },
        catalog: ModelPriceCatalog(prices: [:]),
        now: { Date(timeIntervalSince1970: 1_753_200_000) }
    )
    await store.refresh(force: false)
    await store.refresh(force: false)
    XCTAssertEqual(counter.value, 1)
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `swift test --filter UsageStoreTests && swift test`

Expected: PASS；失败刷新后账号仍存在且 `isStale == true`。

- [ ] **Step 5: 提交**

```bash
git add Sources/CodexStateCore/State/UsageStore.swift Tests/CodexStateCoreTests/UsageStoreTests.swift
git commit -m "feat: coordinate usage refresh and ranges"
```

---

### 任务 7：实现自适应悬停策略和屏幕定位

**Files:**
- Create: `Sources/CodexStateCore/Platform/ScreenPlacement.swift`
- Create: `Tests/CodexStateCoreTests/ScreenPlacementTests.swift`

**Interfaces:**
- Produces: `NotchPresentation`、`PeekMetric`、`NotchLayoutPolicy.metrics(snapshot:)`、`ScreenPlacement.panelOrigin(...)`。

- [ ] **Step 1: 写自适应指标测试**

```swift
// Tests/CodexStateCoreTests/ScreenPlacementTests.swift
import XCTest
@testable import CodexStateCore

final class ScreenPlacementTests: XCTestCase {
    func testPeekShowsWeeklyAndTodayWhenShortWindowMissing() {
        let weekly = QuotaWindow(
            id: "secondary", title: "每周额度", usedPercent: 42,
            resetsAt: nil, durationMinutes: 10_080
        )
        var snapshot = UsageSnapshot.empty
        snapshot.quotaWindows = [weekly]
        snapshot.dailyUsage = [DailyUsage(
            date: Date(),
            tokens: TokenUsage(input: 800, cachedInput: 200, output: 200, total: 1_000),
            estimatedCostUSD: 0.01,
            tokensByModel: [:]
        )]

        XCTAssertEqual(
            NotchLayoutPolicy.metrics(snapshot: snapshot).map(\.kind),
            [.quota, .todayTokens]
        )
    }

    func testPeekShowsTodayTokensAndCostWhenNoQuotaExists() {
        XCTAssertEqual(
            NotchLayoutPolicy.metrics(snapshot: .empty).map(\.kind),
            [.todayTokens, .todayCost]
        )
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter ScreenPlacementTests`

Expected: FAIL，包含 `cannot find 'NotchLayoutPolicy' in scope`。

- [ ] **Step 3: 实现纯布局策略和屏幕坐标计算**

```swift
// Sources/CodexStateCore/Platform/ScreenPlacement.swift
import AppKit
import Foundation

public enum NotchPresentation: Sendable { case collapsed, peek, expanded }

public struct PeekMetric: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case quota, todayTokens, todayCost }
    public let kind: Kind
    public let title: String
    public let value: String
    public let progress: Double?
}

public enum NotchLayoutPolicy {
    public static func metrics(snapshot: UsageSnapshot) -> [PeekMetric] {
        let windows = snapshot.quotaWindows
        if windows.count >= 2 {
            return windows.prefix(2).map {
                PeekMetric(
                    kind: .quota,
                    title: $0.title,
                    value: "\($0.usedPercent)%",
                    progress: Double($0.usedPercent) / 100
                )
            }
        }
        let today = snapshot.dailyUsage.last
        let tokenMetric = PeekMetric(
            kind: .todayTokens,
            title: "今日 Tokens",
            value: formatTokens(today?.tokens.total ?? 0),
            progress: nil
        )
        if let weekly = windows.first {
            return [
                PeekMetric(
                    kind: .quota,
                    title: weekly.title,
                    value: "\(weekly.usedPercent)%",
                    progress: Double(weekly.usedPercent) / 100
                ),
                tokenMetric,
            ]
        }
        let cost = today?.estimatedCostUSD.map { "$\($0)" } ?? "—"
        return [
            tokenMetric,
            PeekMetric(kind: .todayCost, title: "今日估算", value: cost, progress: nil),
        ]
    }

    private static func formatTokens(_ value: Int64) -> String {
        value >= 1_000_000 ? String(format: "%.2fM", Double(value) / 1_000_000) : "\(value)"
    }
}

public enum ScreenPlacement {
    public static func panelOrigin(screenFrame: NSRect, panelSize: NSSize) -> NSPoint {
        NSPoint(x: screenFrame.midX - panelSize.width / 2, y: screenFrame.maxY - panelSize.height)
    }
}
```

- [ ] **Step 4: 运行测试和编译**

Run: `swift test --filter ScreenPlacementTests && swift build`

Expected: PASS；build 无 Swift 6 并发警告。

- [ ] **Step 5: 提交**

```bash
git add Sources/CodexStateCore/Platform/ScreenPlacement.swift Tests/CodexStateCoreTests/ScreenPlacementTests.swift
git commit -m "feat: add adaptive notch layout policy"
```

---

### 任务 8：实现 SwiftUI 三态界面并装配应用

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CodexStateCore/Platform/NotchPanelController.swift`
- Create: `Sources/CodexStateCore/Platform/GlobalHotKey.swift`
- Create: `Sources/CodexStateCore/UI/NotchRootView.swift`
- Create: `Sources/CodexStateCore/UI/PeekUsageView.swift`
- Create: `Sources/CodexStateCore/UI/ExpandedUsageView.swift`
- Create: `Sources/CodexState/CodexStateApp.swift`
- Create: `Tests/CodexStateCoreTests/NotchViewConstructionTests.swift`

**Interfaces:**
- Consumes: `UsageStore`、`NotchLayoutPolicy`、`NotchPanelController`。
- Produces: 可启动的 accessory macOS 应用。

- [ ] **Step 1: 写三态 View 构造测试**

```swift
// Tests/CodexStateCoreTests/NotchViewConstructionTests.swift
import XCTest
@testable import CodexStateCore

@MainActor
final class NotchViewConstructionTests: XCTestCase {
    func testRootViewCanBeConstructedForPeek() {
        let store = UsageStore(
            loadRemote: { CodexRemoteSnapshot(account: nil, quotaWindows: []) },
            loadSessions: { SessionUsageResult(contributions: [], malformedLineCount: 0) },
            catalog: ModelPriceCatalog(prices: [:])
        )
        _ = NotchRootView(
            store: store,
            presentation: .peek,
            onExpand: {},
            onCollapse: {},
            onHoverChanged: { _ in }
        )
    }
}
```

- [ ] **Step 2: 运行测试，确认因 View 尚未实现而失败**

Run: `swift test --filter NotchViewConstructionTests`

Expected: FAIL，包含 `cannot find 'NotchRootView' in scope`。

- [ ] **Step 3: 实现三态 View**

```swift
// Sources/CodexStateCore/UI/NotchRootView.swift
import SwiftUI

public struct NotchRootView: View {
    @Bindable private var store: UsageStore
    let presentation: NotchPresentation
    let onExpand: () -> Void
    let onCollapse: () -> Void
    let onHoverChanged: (Bool) -> Void

    public init(
        store: UsageStore,
        presentation: NotchPresentation,
        onExpand: @escaping () -> Void,
        onCollapse: @escaping () -> Void,
        onHoverChanged: @escaping (Bool) -> Void
    ) {
        self.store = store
        self.presentation = presentation
        self.onExpand = onExpand
        self.onCollapse = onCollapse
        self.onHoverChanged = onHoverChanged
    }

    public var body: some View {
        Group {
            switch presentation {
            case .collapsed: Color.black
            case .peek: PeekUsageView(snapshot: store.snapshot).onTapGesture(perform: onExpand)
            case .expanded: ExpandedUsageView(store: store, onClose: onCollapse)
            }
        }
        .background(.black)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .accessibilityElement(children: .contain)
        .onHover(perform: onHoverChanged)
    }
}
```

```swift
// Sources/CodexStateCore/UI/PeekUsageView.swift
import SwiftUI

public struct PeekUsageView: View {
    let snapshot: UsageSnapshot

    public var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(NotchLayoutPolicy.metrics(snapshot: snapshot).enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.title).font(.caption2).foregroundStyle(.secondary)
                    Text(metric.value).font(.system(size: 19, weight: .semibold, design: .rounded))
                    if let progress = metric.progress {
                        ProgressView(value: progress).tint(.mint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
    }
}
```

```swift
// Sources/CodexStateCore/UI/ExpandedUsageView.swift
import SwiftUI

public struct ExpandedUsageView: View {
    @Bindable var store: UsageStore
    let onClose: () -> Void

    private var totalTokens: Int64 {
        store.snapshot.dailyUsage.reduce(0) { $0 + $1.tokens.total }
    }

    private var totalCost: Decimal? {
        let costs = store.snapshot.dailyUsage.map(\.estimatedCostUSD)
        guard costs.allSatisfy({ $0 != nil }) else { return nil }
        return costs.compactMap { $0 }.reduce(0, +)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.snapshot.account?.plan?.capitalized ?? "Codex")
                        .font(.headline)
                    Text(store.snapshot.account?.maskedEmail ?? "未连接账号")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.snapshot.isStale { Text("数据已过期").font(.caption).foregroundStyle(.orange) }
                Button("关闭", systemImage: "xmark", action: onClose).labelStyle(.iconOnly)
            }

            ForEach(store.snapshot.quotaWindows) { window in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(window.title); Spacer(); Text("\(window.usedPercent)%") }
                    ProgressView(value: Double(window.usedPercent) / 100).tint(.blue)
                    if let reset = window.resetsAt {
                        Text(reset, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }

            Picker("统计周期", selection: Binding(
                get: { store.snapshot.selectedRange },
                set: { store.selectRange($0) }
            )) {
                ForEach(UsageRange.allCases, id: \.rawValue) { range in
                    Text("\(range.rawValue) 天").tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                metric(title: "Tokens", value: formatTokens(totalTokens))
                metric(title: "估算成本", value: totalCost.map(formatCost) ?? "—")
            }

            HStack(alignment: .bottom, spacing: 4) {
                let maximum = max(1, store.snapshot.dailyUsage.map(\.tokens.total).max() ?? 1)
                ForEach(store.snapshot.dailyUsage) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.blue.opacity(0.8))
                        .frame(height: max(4, 62 * Double(day.tokens.total) / Double(maximum)))
                        .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue("\(day.tokens.total) Tokens")
                }
            }
            .frame(height: 64, alignment: .bottom)

            Text("常用模型").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(store.snapshot.topModels) { model in
                    Text("\(model.model) · \(Int(model.fraction * 100))%")
                        .font(.caption2).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.white.opacity(0.08), in: Capsule())
                }
            }
        }
        .padding(16)
        .foregroundStyle(.white)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption); Text(value).font(.title3.bold()) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatTokens(_ value: Int64) -> String {
        value >= 1_000_000 ? String(format: "%.2fM", Double(value) / 1_000_000) : "\(value)"
    }

    private func formatCost(_ value: Decimal) -> String {
        String(format: "$%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }
}
```

- [ ] **Step 4: 实现 Panel 状态机和全局快捷键**

```swift
// Sources/CodexStateCore/Platform/GlobalHotKey.swift
import Carbon

@MainActor
public final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: @MainActor () -> Void

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in owner.action() }
                return noErr
            },
            1,
            &event,
            pointer,
            &eventHandler
        )
        var identifier = EventHotKeyID(signature: OSType(0x4344_5853), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_U),
            UInt32(cmdKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
```

```swift
// Sources/CodexStateCore/Platform/NotchPanelController.swift
import AppKit
import QuartzCore
import SwiftUI

@MainActor
public final class NotchPanelController: NSWindowController {
    public private(set) var presentation: NotchPresentation = .collapsed
    private let store: UsageStore
    private var transitionTask: Task<Void, Never>?
    private var clickMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var hotKey: GlobalHotKey?

    public init(store: UsageStore) {
        self.store = store
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        super.init(window: panel)
        render()
        reposition()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                if self?.presentation == .expanded { self?.collapse() }
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.reposition() } }
        hotKey = GlobalHotKey { [weak self] in self?.toggleExpanded() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    public func hoverChanged(_ inside: Bool) {
        inside ? mouseEntered() : mouseExited()
    }

    public func mouseEntered() {
        transitionTask?.cancel()
        guard presentation == .collapsed else { return }
        transitionTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            setPresentation(.peek)
        }
    }

    public func mouseExited() {
        transitionTask?.cancel()
        guard presentation == .peek else { return }
        transitionTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            setPresentation(.collapsed)
        }
    }

    public func toggleExpanded() {
        setPresentation(presentation == .expanded ? .collapsed : .expanded)
    }

    public func collapse() { setPresentation(.collapsed) }

    private func setPresentation(_ next: NotchPresentation) {
        transitionTask?.cancel()
        presentation = next
        render()
        reposition(animated: true)
        if next == .expanded { Task { await store.refresh(force: false) } }
    }

    private func render() {
        window?.contentView = NSHostingView(rootView: NotchRootView(
            store: store,
            presentation: presentation,
            onExpand: { [weak self] in self?.setPresentation(.expanded) },
            onCollapse: { [weak self] in self?.collapse() },
            onHoverChanged: { [weak self] in self?.hoverChanged($0) }
        ))
    }

    private func reposition(animated: Bool = false) {
        guard let panel = window, let screen = preferredScreen() else { return }
        let size: NSSize = switch presentation {
        case .collapsed: NSSize(width: 150, height: 30)
        case .peek: NSSize(width: 300, height: 80)
        case .expanded: NSSize(width: 368, height: 410)
        }
        let origin = ScreenPlacement.panelOrigin(screenFrame: screen.frame, panelSize: size)
        let frame = NSRect(origin: origin, size: size)
        guard animated else { panel.setFrame(frame, display: true); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}
```

- [ ] **Step 5: 装配应用入口**

先把 `Package.swift` 的 products 和 targets 分别增加：

```swift
.executable(name: "CodexState", targets: ["CodexState"]),
```

```swift
.executableTarget(name: "CodexState", dependencies: ["CodexStateCore"]),
```

```swift
// Sources/CodexState/CodexStateApp.swift
import AppKit
import CodexStateCore

@main
final class CodexStateApp: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController!
    private var refreshTask: Task<Void, Never>?

    static func main() {
        let app = NSApplication.shared
        let delegate = CodexStateApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rpc = CodexRPCClient()
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexState")
        let repository = SessionUsageRepository(cacheURL: appSupport.appendingPathComponent("sessions-v1.json"))
        let defaultHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0).standardizedFileURL } ?? defaultHome
        let catalog = (try? ModelPriceCatalog.bundled()) ?? ModelPriceCatalog(prices: [:])
        let store = UsageStore(
            loadRemote: { try rpc.fetch() },
            loadSessions: { try repository.load(home: codexHome, calendar: .autoupdatingCurrent) },
            catalog: catalog
        )
        panelController = NotchPanelController(store: store)
        panelController.showWindow(nil)
        Task { await store.refresh(force: true) }
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .minutes(5))
                await store.refresh(force: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }
}
```

- [ ] **Step 6: 编译并运行全量测试**

Run: `swift build && swift test`

Expected: 两条命令 PASS；无第三方包下载。

- [ ] **Step 7: 提交**

```bash
git add Package.swift Sources/CodexStateCore/UI Sources/CodexStateCore/Platform Sources/CodexState/CodexStateApp.swift Tests/CodexStateCoreTests/NotchViewConstructionTests.swift
git commit -m "feat: build notch usage interface"
```

---

### 任务 9：打包、文档和端到端验证

**Files:**
- Create: `.gitignore`
- Create: `Resources/Info.plist`
- Create: `Scripts/package_app.sh`
- Modify: `README.md`
- Copy: `docs/superpowers/specs/2026-07-22-codex-notch-usage-design.md`
- Copy: `docs/superpowers/plans/2026-07-22-codex-notch-usage-implementation.md`

**Interfaces:**
- Produces: `build/CodexState.app`。

- [ ] **Step 1: 创建 Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>CodexState</string>
  <key>CFBundleIdentifier</key><string>com.local.codex-state</string>
  <key>CFBundleName</key><string>Codex State</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

- [ ] **Step 2: 创建最小打包脚本**

```bash
#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
bin_dir="$(cd "$project_dir" && swift build -c release --show-bin-path)"
app_dir="$project_dir/build/CodexState.app"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
install -m 755 "$bin_dir/CodexState" "$app_dir/Contents/MacOS/CodexState"
install -m 644 "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

resource_bundle="$(find "$bin_dir" -maxdepth 1 -name '*CodexStateCore.bundle' -print -quit)"
if [[ -n "$resource_bundle" ]]; then
  ditto "$resource_bundle" "$app_dir/Contents/Resources/$(basename "$resource_bundle")"
fi

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
```

Run: `chmod +x Scripts/package_app.sh && ./Scripts/package_app.sh`

Expected: 输出仓库内 `build/CodexState.app` 的绝对路径。

- [ ] **Step 3: 更新 README**

```gitignore
.build/
build/
.DS_Store
```

````markdown
# codex-state

Codex State 是一个原生 macOS 刘海用量工具。悬停刘海查看动态额度与今日 Token，点击后查看 1、7、14、30 天 Token、估算成本和常用模型。

## 要求

- macOS 14+
- 已安装并登录 Codex CLI：`codex login status`

## 开发

```bash
swift test
./Scripts/package_app.sh
open build/CodexState.app
```

应用通过 Codex `app-server` 读取账号和额度，只扫描 `~/.codex/sessions` 与 `~/.codex/archived_sessions` 的 Token、模型和时间字段。聚合缓存位于 `~/Library/Application Support/CodexState/`。

成本按 OpenAI API 公开单价估算，不代表 ChatGPT/Codex 订阅的实际账单。价格表更新时间与来源见 `Sources/CodexStateCore/Pricing/Resources/ModelPrices.json`：

- https://developers.openai.com/api/docs/models/gpt-5.6-sol
- https://developers.openai.com/api/docs/models/gpt-5.6-terra
- https://developers.openai.com/api/docs/models/gpt-5.6-luna

应用不上传会话数据、不抓网页、不读取浏览器 Cookie。MVP 需要启动本机 Codex 子进程并读取已知日志目录，因此采用非 Mac App Store 分发。
````

- [ ] **Step 4: 运行自动验证**

Run: `swift test`

Expected: 全部 PASS。

Run: `swift build -c release`

Expected: PASS，无 warning。

Run: `plutil -lint Resources/Info.plist`

Expected: `Resources/Info.plist: OK`。

Run: `codesign --verify --deep --strict build/CodexState.app`

Expected: exit 0。

- [ ] **Step 5: 运行手工验收**

1. 先运行 `codex login status`，确认当前账号已登录。
2. 打开 `build/CodexState.app`，确认没有 Dock 图标。
3. 带刘海屏幕：静默态顶部居中并与刘海贴合。
4. 悬停：120ms 后只出现两项；无短周期额度时为“每周额度 + 今日 Token”。
5. 点击：展开账号、动态额度、周期、Token、估算成本、趋势和常用模型。
6. 切换 1、7、14、30 天，确认汇总和柱状趋势同步变化。
7. 断网后刷新，确认旧数据保留且显示“数据已过期”。
8. 连接无刘海外接屏，确认胶囊自动移动到主屏幕顶部。
9. 在全屏应用和不同 Space 中确认可见且不抢焦点。
10. 开启“减少动态效果”和 VoiceOver，确认淡入淡出、标签和 `⌥⌘U` 可用。

- [ ] **Step 6: 最终提交**

```bash
git add .gitignore Resources Scripts README.md docs/superpowers
git commit -m "docs: add packaging and verification guide"
```

---

## 计划自检结果

- 设计覆盖：账号、动态额度、今日 Token、1/7/14/30 天统计、成本、常用模型、三态刘海、无刘海降级、多显示器、错误处理、隐私、性能和可访问性均有对应任务。
- 占位符检查：没有 `TBD`、`TODO` 或“稍后实现”步骤。
- 类型一致性：所有后续任务使用任务 1 定义的领域类型；RPC、日志、状态和 UI 接口名称一致。
- 范围检查：未加入多账号、多提供商、网页抓取、云端服务、第三方依赖和自动更新。
