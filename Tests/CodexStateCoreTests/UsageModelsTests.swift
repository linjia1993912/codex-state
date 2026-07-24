import Testing
@testable import CodexStateCore

struct UsageModelsTests {
    @Test
    func visibleWarningsKeepExistingWarningsAndIncludeStaleState() {
        let snapshot = UsageSnapshot(
            account: nil,
            quotaWindows: [],
            dailyUsage: [],
            topModels: [],
            selectedRange: .week,
            refreshedAt: nil,
            isStale: true,
            warnings: [.malformedLogRecords(2), .unknownPrice("custom-model")]
        )

        #expect(snapshot.visibleWarnings == [
            .malformedLogRecords(2),
            .unknownPrice("custom-model"),
            .staleData,
        ])
    }

    @Test
    func testDeltaReturnsCurrentUsageWhenCumulativeCounterResets() {
        let previous = TokenUsage(input: 100, cachedInput: 80, output: 60, total: 240)
        let current = TokenUsage(input: 20, cachedInput: 10, output: 5, total: 35)

        #expect(current.delta(from: previous) == current)
    }

    @Test
    func testDeltaReturnsDifferencesWhenCumulativeCounterIncreases() {
        let previous = TokenUsage(input: 100, cachedInput: 80, output: 60, total: 240)
        let current = TokenUsage(input: 140, cachedInput: 100, output: 90, total: 330)

        #expect(
            current.delta(from: previous)
                == TokenUsage(input: 40, cachedInput: 20, output: 30, total: 90)
        )
    }
}
