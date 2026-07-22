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
        UsageStore(
            remoteLoader: { CodexRemoteSnapshot(account: nil, quotaWindows: []) },
            sessionLoader: { SessionUsageResult(contributions: [], malformedLineCount: 0) },
            catalog: ModelPriceCatalog(prices: [:])
        )
    }
}

private enum TestError: Error {
    case registrationFailed
}
