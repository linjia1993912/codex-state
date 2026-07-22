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
