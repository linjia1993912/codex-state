import Foundation
import Testing
@testable import CodexStateCore

struct ScreenPlacementTests {
    @Test
    func peekShowsQuotaAndTodayTokensForOneWindow() {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
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
                date: now,
                tokens: TokenUsage(input: 800, cachedInput: 200, output: 200, total: 1_000),
                estimatedCostUSD: 0.01
            )],
            topModels: [],
            selectedRange: .week,
            refreshedAt: nil,
            isStale: false,
            warnings: []
        )

        let metrics = NotchLayoutPolicy.metrics(snapshot: snapshot, now: now)

        #expect(metrics.map(\.kind) == [.quota, .todayTokens])
        #expect(metrics[0].title == "每周剩余")
        #expect(metrics[0].value == "58%")
        #expect(metrics[0].progress == 0.58)
        #expect(metrics[1].value == "1K")
    }

    @Test
    func quotaRemainingUsesTheInverseOfUsedPercent() {
        let quota = QuotaWindow(id: "secondary", title: "每周额度", usedPercent: 42)

        #expect(quota.remainingPercent == 58)
        #expect(quota.remainingTitle == "每周剩余")
    }

    @Test
    func peekMetricWarnsOnlyWhenRemainingQuotaIsAtMostTenPercent() {
        let lowRemaining = PeekMetric(kind: .quota, title: "每周剩余", value: "10%", progress: 0.1)
        let highRemaining = PeekMetric(kind: .quota, title: "每周剩余", value: "90%", progress: 0.9)

        #expect(lowRemaining.usesWarningTint)
        #expect(!highRemaining.usesWarningTint)
    }

    @MainActor
    @Test
    func windowSizeIsFixedAndLayoutSizesMonotonicallyIncrease() {
        // 固定窗口尺寸：不随状态变化，避免 NSWindow frame 动画与 SwiftUI 动画不同步
        #expect(NotchPanelController.windowSize == CGSize(width: 500, height: 360))

        let layout = IslandLayout(notch: NotchInfo(width: 200, height: 32, hasNotch: true))
        let compact = layout.compactSize
        let peek = layout.peekSize
        let expanded = IslandLayout.expandedSize

        // 三态尺寸单调递增，从小到大丝滑过渡
        #expect(compact.width < peek.width)
        #expect(peek.width <= expanded.width)
        #expect(compact.height < peek.height)
        #expect(peek.height < expanded.height)
    }

    @Test
    func peekShowsTodayTokensAndCostWithoutQuota() {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        let metrics = NotchLayoutPolicy.metrics(snapshot: .empty, now: now)

        #expect(metrics.map(\.kind) == [.todayTokens, .todayCost])
        #expect(metrics.map(\.value) == ["0", "—"])

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let historicalSnapshot = UsageSnapshot(
            account: nil,
            quotaWindows: [],
            dailyUsage: [DailyUsage(
                date: yesterday,
                tokens: TokenUsage(input: 800, cachedInput: 200, output: 200, total: 1_000),
                estimatedCostUSD: 0.01
            )],
            topModels: [],
            selectedRange: .week,
            refreshedAt: nil,
            isStale: false,
            warnings: []
        )
        let historicalMetrics = NotchLayoutPolicy.metrics(snapshot: historicalSnapshot, now: now)

        #expect(historicalMetrics.map(\.value) == ["0", "—"])
        #expect(
            ScreenPlacement.panelOrigin(
                screenFrame: CGRect(x: 100, y: 200, width: 1_440, height: 900),
                panelSize: CGSize(width: 300, height: 80)
            ) == CGPoint(x: 670, y: 1_020)
        )
    }
}
