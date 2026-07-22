import Foundation
import Observation

@MainActor
@Observable
public final class UsageStore {
    public typealias RemoteLoader = @Sendable () throws -> CodexRemoteSnapshot
    public typealias SessionLoader = @Sendable () throws -> SessionUsageResult

    public private(set) var snapshot = UsageSnapshot.empty
    public private(set) var isRefreshing = false

    public var todayUsage: DailyUsage {
        snapshot.dailyUsage.first { calendar.isDate($0.date, inSameDayAs: now()) }
            ?? DailyUsage(date: calendar.startOfDay(for: now()), tokens: .zero, estimatedCostUSD: .zero)
    }

    private let remoteLoader: RemoteLoader
    private let sessionLoader: SessionLoader
    private let catalog: ModelPriceCatalog
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var contributions: [UsageContribution] = []
    private var malformedLineCount = 0

    public init(
        remoteLoader: @escaping RemoteLoader,
        sessionLoader: @escaping SessionLoader,
        catalog: ModelPriceCatalog,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.remoteLoader = remoteLoader
        self.sessionLoader = sessionLoader
        self.catalog = catalog
        self.calendar = calendar
        self.now = now
    }

    public func refresh(force: Bool = false) async {
        guard !isRefreshing, force || !isFresh else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let remoteLoader = remoteLoader
        let sessionLoader = sessionLoader
        async let remoteLoadResult: Result<CodexRemoteSnapshot, Error> = Self.load(remoteLoader)
        async let sessionLoadResult: Result<SessionUsageResult, Error> = Self.load(sessionLoader)
        let (remoteResult, sessionResult) = await (remoteLoadResult, sessionLoadResult)

        let remoteFailed: Bool
        switch remoteResult {
        case let .success(remote):
            snapshot = UsageSnapshot(
                account: remote.account,
                quotaWindows: remote.quotaWindows,
                dailyUsage: snapshot.dailyUsage,
                topModels: snapshot.topModels,
                selectedRange: snapshot.selectedRange,
                refreshedAt: snapshot.refreshedAt,
                isStale: snapshot.isStale,
                warnings: snapshot.warnings
            )
            remoteFailed = false
        case .failure:
            // 远端短暂不可用时保留上次账号与额度，避免把已知状态误显示为空。
            remoteFailed = true
        }

        let sessionFailed: Bool
        if case let .success(result) = sessionResult {
            contributions = result.contributions
            malformedLineCount = result.malformedLineCount
            sessionFailed = false
        } else {
            sessionFailed = true
        }

        rebuildSnapshot(
            refreshedAt: remoteFailed || sessionFailed ? snapshot.refreshedAt : now(),
            isStale: remoteFailed || sessionFailed
        )
    }

    public func selectRange(_ range: UsageRange) {
        guard UsageRange.allCases.contains(range) else { return }
        snapshot = UsageSnapshot(
            account: snapshot.account,
            quotaWindows: snapshot.quotaWindows,
            dailyUsage: snapshot.dailyUsage,
            topModels: snapshot.topModels,
            selectedRange: range,
            refreshedAt: snapshot.refreshedAt,
            isStale: snapshot.isStale,
            warnings: snapshot.warnings
        )
        rebuildSnapshot(refreshedAt: snapshot.refreshedAt, isStale: snapshot.isStale)
    }

    private var isFresh: Bool {
        guard let refreshedAt = snapshot.refreshedAt, !snapshot.isStale else { return false }
        return now().timeIntervalSince(refreshedAt) < 60
    }

    private nonisolated static func load<Value: Sendable>(
        _ loader: @escaping @Sendable () throws -> Value
    ) async -> Result<Value, Error> {
        await Task.detached {
            Result { try loader() }
        }.value
    }

    private func rebuildSnapshot(refreshedAt: Date?, isStale: Bool) {
        let rangeStart = calendar.date(
            byAdding: .day,
            value: 1 - snapshot.selectedRange.rawValue,
            to: calendar.startOfDay(for: now())
        )!
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now()))!
        let dailyUsage = SessionUsageRepository.aggregate(
            contributions: contributions,
            calendar: calendar,
            catalog: catalog
        ).filter { $0.date >= rangeStart && $0.date < rangeEnd }
        let tokensByModel = dailyUsage.reduce(into: [String: TokenUsage]()) { totals, day in
            for (model, tokens) in day.tokensByModel {
                totals[model, default: .zero] = totals[model, default: .zero] + tokens
            }
        }
        let total = tokensByModel.values.reduce(.zero, +).total
        let shares = tokensByModel.sorted { lhs, rhs in
            lhs.value.total == rhs.value.total ? lhs.key < rhs.key : lhs.value.total > rhs.value.total
        }.map { ModelShare(model: $0.key, tokens: $0.value, fraction: total == 0 ? 0 : Double($0.value.total) / Double(total)) }
        let topModels = Array(shares.prefix(3)) + (shares.count > 3
            ? [ModelShare(
                model: "其他",
                tokens: shares.dropFirst(3).map(\.tokens).reduce(.zero, +),
                fraction: shares.dropFirst(3).map(\.fraction).reduce(0, +)
            )]
            : [])
        var warnings = tokensByModel.keys.sorted().compactMap { model in
            catalog.estimate(tokens: .zero, model: model) == nil ? UsageWarning.unknownPrice(model) : nil
        }
        if malformedLineCount > 0 { warnings.append(.malformedLogRecords(malformedLineCount)) }
        if isStale { warnings.append(.staleData) }

        snapshot = UsageSnapshot(
            account: snapshot.account,
            quotaWindows: snapshot.quotaWindows,
            dailyUsage: dailyUsage,
            topModels: topModels,
            selectedRange: snapshot.selectedRange,
            refreshedAt: refreshedAt,
            isStale: isStale,
            warnings: warnings
        )
    }
}
