import SwiftUI
import Testing
@testable import CodexStateCore

@MainActor
struct NotchViewConstructionTests {
    @Test
    func rootViewCanBeConstructed() {
        let store = makeStore()

        _ = NotchRootView(store: store, presentation: .constant(.collapsed))
    }

    @Test
    func expandedRootViewCanBeConstructedWithoutAccount() {
        _ = NotchRootView(store: makeStore(), presentation: .constant(.expanded))
    }

    @Test
    func expandedRootViewCanBeConstructedWithPartialCostData() async {
        let store = makeStore()
        await store.refresh(force: true)

        #expect(store.snapshot.dailyUsage.last?.estimatedCostUSD != nil)
        #expect(store.snapshot.dailyUsage.last?.unknownPriceModels.contains("codex-auto-review") == true)
        #expect(store.snapshot.quotaWindows.count == 2)
        #expect(store.snapshot.topModels.count == 4)
        #expect((store.snapshot.visibleWarnings.first?.message.count ?? 0) > 60)

        _ = NotchRootView(store: store, presentation: .constant(.expanded))
    }

    @Test
    func failedGlobalHotKeyRegistrationReturnsNil() {
        var registrationAttempted = false

        let hotKey = GlobalHotKey.registerIfAvailable(action: {}) { _ in
            registrationAttempted = true
            throw TestError.registrationFailed
        }

        #expect(registrationAttempted)
        #expect(hotKey == nil)
    }

    private func makeStore() -> UsageStore {
        let date = Date()
        return UsageStore(
            remoteLoader: {
                CodexRemoteSnapshot(
                    account: nil,
                    quotaWindows: [
                        QuotaWindow(
                            id: "primary",
                            title: "5 小时额度",
                            usedPercent: 42,
                            resetsAt: date.addingTimeInterval(3_600)
                        ),
                        QuotaWindow(
                            id: "secondary",
                            title: "每周额度",
                            usedPercent: 75,
                            resetsAt: date.addingTimeInterval(86_400)
                        ),
                    ]
                )
            },
            sessionLoader: {
                SessionUsageResult(
                    contributions: [
                        UsageContribution(
                            date: date,
                            model: "gpt-5.6-terra",
                            tokens: TokenUsage(input: 1_000, cachedInput: 200, output: 100, total: 1_100)
                        ),
                        UsageContribution(
                            date: date,
                            model: "codex-auto-review",
                            tokens: TokenUsage(input: 500, cachedInput: 0, output: 50, total: 550)
                        ),
                        UsageContribution(
                            date: date,
                            model: "a-very-long-unknown-model-name-for-warning-layout-regression",
                            tokens: TokenUsage(input: 900, cachedInput: 0, output: 0, total: 900)
                        ),
                        UsageContribution(
                            date: date,
                            model: "unknown-model-three",
                            tokens: TokenUsage(input: 700, cachedInput: 0, output: 0, total: 700)
                        ),
                        UsageContribution(
                            date: date,
                            model: "unknown-model-four",
                            tokens: TokenUsage(input: 600, cachedInput: 0, output: 0, total: 600)
                        ),
                    ],
                    malformedLineCount: 0
                )
            },
            catalog: ModelPriceCatalog(
                prices: [
                    "gpt-5.6-terra": ModelPrice(input: 1.25, cachedInput: 0.125, output: 10),
                ]
            ),
            now: { date }
        )
    }
}

private enum TestError: Error {
    case registrationFailed
}
