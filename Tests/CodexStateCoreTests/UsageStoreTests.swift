import Foundation
import Testing
@testable import CodexStateCore

@MainActor
struct UsageStoreTests {
    @Test
    func refreshFailurePreservesPreviousAccountAndMarksSnapshotStale() async {
        let loader = TestLoader()
        let now = referenceDate
        let store = UsageStore(
            remoteLoader: loader.loadRemote,
            sessionLoader: loader.loadSessions,
            catalog: ModelPriceCatalog(prices: [:]),
            calendar: utcCalendar,
            now: { now }
        )

        await store.refresh(force: true)
        loader.shouldFail = true
        await store.refresh(force: true)

        #expect(store.snapshot.account == AccountSummary(email: "user@example.com", plan: "Plus"))
        #expect(store.snapshot.isStale)
        #expect(store.snapshot.warnings.contains(.staleData))
    }

    @Test
    func todayUsageIsZeroWhenThereAreNoLogs() async {
        let loader = TestLoader()
        let now = referenceDate
        let store = UsageStore(
            remoteLoader: loader.loadRemote,
            sessionLoader: loader.loadSessions,
            catalog: ModelPriceCatalog(prices: [:]),
            calendar: utcCalendar,
            now: { now }
        )

        await store.refresh(force: true)

        #expect(store.todayUsage.tokens == .zero)
        #expect(store.todayUsage.date == utcCalendar.startOfDay(for: referenceDate))
    }

    @Test
    func weekRangeFillsMissingDaysWithZeroUsage() async {
        let calendar = utcCalendar
        let now = referenceDate
        let firstDay = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        let fourthDay = calendar.date(byAdding: .day, value: 3, to: firstDay)!
        let contributions = [
            UsageContribution(
                date: firstDay.addingTimeInterval(3_600),
                model: "known",
                tokens: TokenUsage(input: 10, cachedInput: 0, output: 5, total: 15)
            ),
            UsageContribution(
                date: fourthDay.addingTimeInterval(3_600),
                model: "known",
                tokens: TokenUsage(input: 20, cachedInput: 0, output: 10, total: 30)
            ),
        ]
        let store = UsageStore(
            remoteLoader: { CodexRemoteSnapshot(account: nil, quotaWindows: []) },
            sessionLoader: { SessionUsageResult(contributions: contributions, malformedLineCount: 0) },
            catalog: ModelPriceCatalog(prices: [:]),
            calendar: calendar,
            now: { now }
        )

        await store.refresh(force: true)

        #expect(store.snapshot.dailyUsage.map(\.date) == (0..<7).map {
            calendar.date(byAdding: .day, value: $0, to: firstDay)!
        })
        let missingDay = store.snapshot.dailyUsage[1]
        #expect(missingDay.tokens == .zero)
        #expect(missingDay.estimatedCostUSD == nil)
        #expect(missingDay.tokensByModel.isEmpty)
        #expect(missingDay.unknownPriceModels.isEmpty)
    }

    @Test
    func freshSnapshotSkipsSecondNonForcedRemoteRefresh() async {
        let loader = TestLoader()
        let now = referenceDate
        let store = UsageStore(
            remoteLoader: loader.loadRemote,
            sessionLoader: loader.loadSessions,
            catalog: ModelPriceCatalog(prices: [:]),
            calendar: utcCalendar,
            now: { now }
        )

        await store.refresh(force: false)
        await store.refresh(force: false)

        #expect(loader.remoteCallCount == 1)
    }

    @Test
    func concurrentRefreshesStartOnlyOneRemoteLoad() async {
        let loader = BlockingLoader()
        let now = referenceDate
        let store = UsageStore(
            remoteLoader: loader.loadRemote,
            sessionLoader: loader.loadSessions,
            catalog: ModelPriceCatalog(prices: [:]),
            calendar: utcCalendar,
            now: { now }
        )

        async let firstRefresh: Void = store.refresh(force: true)
        await loader.waitUntilFirstRemoteLoadStarts()
        async let secondRefresh: Void = store.refresh(force: true)
        await Task.yield()

        #expect(loader.remoteCallCount == 1)
        loader.unblockFirstRemoteLoad()
        await firstRefresh
        await secondRefresh
        #expect(loader.remoteCallCount == 1)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_784_736_000)
    }
}

private final class TestLoader: @unchecked Sendable {
    var shouldFail = false
    private(set) var remoteCallCount = 0

    func loadRemote() throws -> CodexRemoteSnapshot {
        remoteCallCount += 1
        if shouldFail { throw TestError.failed }
        return CodexRemoteSnapshot(
            account: AccountSummary(email: "user@example.com", plan: "Plus"),
            quotaWindows: []
        )
    }

    func loadSessions() throws -> SessionUsageResult {
        SessionUsageResult(contributions: [], malformedLineCount: 0)
    }
}

private enum TestError: Error {
    case failed
}

private final class BlockingLoader: @unchecked Sendable {
    private let lock = NSLock()
    private let unblockFirstLoad = DispatchSemaphore(value: 0)
    private var callCount = 0
    private var firstLoadStarted = false
    private var firstLoadWaiters: [CheckedContinuation<Void, Never>] = []

    var remoteCallCount: Int {
        lock.withLock { callCount }
    }

    func loadRemote() -> CodexRemoteSnapshot {
        let (isFirstLoad, waiters): (Bool, [CheckedContinuation<Void, Never>]) = lock.withLock {
            callCount += 1
            guard callCount == 1 else { return (false, []) }
            firstLoadStarted = true
            let waiters = firstLoadWaiters
            firstLoadWaiters = []
            return (true, waiters)
        }
        if isFirstLoad {
            waiters.forEach { $0.resume() }
            unblockFirstLoad.wait()
        }
        return CodexRemoteSnapshot(account: nil, quotaWindows: [])
    }

    func loadSessions() -> SessionUsageResult {
        SessionUsageResult(contributions: [], malformedLineCount: 0)
    }

    func waitUntilFirstRemoteLoadStarts() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if firstLoadStarted { return true }
                firstLoadWaiters.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func unblockFirstRemoteLoad() {
        unblockFirstLoad.signal()
    }
}
