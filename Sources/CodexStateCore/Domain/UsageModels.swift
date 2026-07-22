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

    public init(input: Int64, cachedInput: Int64, output: Int64, total: Int64) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
        self.total = total
    }

    public static let zero = TokenUsage(input: 0, cachedInput: 0, output: 0, total: 0)

    public func delta(from previous: TokenUsage) -> TokenUsage {
        // 累计总量回退表示来源已重置；此时不能把当前读数当作负增量丢弃。
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

    public init(date: Date, model: String, tokens: TokenUsage) {
        self.date = date
        self.model = model
        self.tokens = tokens
    }
}

public struct DailyUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let tokens: TokenUsage
    public let estimatedCostUSD: Decimal?
    public let tokensByModel: [String: TokenUsage]

    public init(
        date: Date,
        tokens: TokenUsage,
        estimatedCostUSD: Decimal? = nil,
        tokensByModel: [String: TokenUsage] = [:]
    ) {
        self.date = date
        self.tokens = tokens
        self.estimatedCostUSD = estimatedCostUSD
        self.tokensByModel = tokensByModel
    }
}

public struct ModelShare: Equatable, Identifiable, Sendable {
    public var id: String { model }
    public let model: String
    public let tokens: TokenUsage
    public let fraction: Double

    public init(model: String, tokens: TokenUsage, fraction: Double) {
        self.model = model
        self.tokens = tokens
        self.fraction = fraction
    }
}

public struct AccountSummary: Equatable, Sendable {
    public let email: String?
    public let plan: String?

    public init(email: String?, plan: String?) {
        self.email = email
        self.plan = plan
    }

    public var maskedEmail: String? {
        guard let email, let atIndex = email.firstIndex(of: "@") else { return email }
        return "\(email[..<atIndex].prefix(3))***\(email[atIndex...])"
    }
}

public struct QuotaWindow: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let durationMinutes: Int?

    public init(
        id: String,
        title: String,
        usedPercent: Double,
        resetsAt: Date? = nil,
        durationMinutes: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
    }
}

public enum UsageWarning: Equatable, Sendable {
    case staleData
    case malformedLogRecords(Int)
    case unknownPrice(String)
}

public struct UsageSnapshot: Equatable, Sendable {
    public let account: AccountSummary?
    public let quotaWindows: [QuotaWindow]
    public let dailyUsage: [DailyUsage]
    public let topModels: [ModelShare]
    public let selectedRange: UsageRange
    public let refreshedAt: Date?
    public let isStale: Bool
    public let warnings: [UsageWarning]

    public init(
        account: AccountSummary?,
        quotaWindows: [QuotaWindow],
        dailyUsage: [DailyUsage],
        topModels: [ModelShare],
        selectedRange: UsageRange,
        refreshedAt: Date?,
        isStale: Bool,
        warnings: [UsageWarning]
    ) {
        self.account = account
        self.quotaWindows = quotaWindows
        self.dailyUsage = dailyUsage
        self.topModels = topModels
        self.selectedRange = selectedRange
        self.refreshedAt = refreshedAt
        self.isStale = isStale
        self.warnings = warnings
    }

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
