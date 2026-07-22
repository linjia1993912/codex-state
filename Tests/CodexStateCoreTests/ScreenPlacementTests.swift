import Foundation
import Testing
@testable import CodexStateCore

struct ScreenPlacementTests {
    @Test
    func peekShowsQuotaAndTodayTokensForOneWindow() {
        let weekly = QuotaWindow(
            id: "secondary",
            title: "每周额度",
            usedPercent: 42,
            durationMinutes: 10_080
        )
        let snapshot = UsageSnapshot(
            account: nil,
            quotaWindows: [weekly],
            dailyUsage: [DailyUsage(
                date: Date(),
                tokens: TokenUsage(input: 800, cachedInput: 200, output: 200, total: 1_000),
                estimatedCostUSD: 0.01
            )],
            topModels: [],
            selectedRange: .week,
            refreshedAt: nil,
            isStale: false,
            warnings: []
        )

        let metrics = NotchLayoutPolicy.metrics(snapshot: snapshot)

        #expect(metrics.map(\.kind) == [.quota, .todayTokens])
        #expect(metrics[0].progress == 0.42)
        #expect(metrics[1].value == "1000")
    }

    @Test
    func peekShowsTodayTokensAndCostWithoutQuota() {
        let metrics = NotchLayoutPolicy.metrics(snapshot: .empty)

        #expect(metrics.map(\.kind) == [.todayTokens, .todayCost])
        #expect(metrics.map(\.value) == ["0", "—"])
        #expect(
            ScreenPlacement.panelOrigin(
                screenFrame: CGRect(x: 100, y: 200, width: 1_440, height: 900),
                panelSize: CGSize(width: 300, height: 80)
            ) == CGPoint(x: 670, y: 1_020)
        )
    }
}
