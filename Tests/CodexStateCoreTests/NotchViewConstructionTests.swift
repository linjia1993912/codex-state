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

        #expect(store.snapshot.dailyUsage.first?.estimatedCostUSD != nil)
        #expect(store.snapshot.dailyUsage.first?.unknownPriceModels == ["codex-auto-review"])

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
            remoteLoader: { CodexRemoteSnapshot(account: nil, quotaWindows: []) },
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
