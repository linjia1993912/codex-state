import SwiftUI
import Testing
@testable import CodexStateCore

@MainActor
struct NotchViewConstructionTests {
    @Test
    func rootViewCanBeConstructed() {
        let store = UsageStore(
            remoteLoader: { CodexRemoteSnapshot(account: nil, quotaWindows: []) },
            sessionLoader: { SessionUsageResult(contributions: [], malformedLineCount: 0) },
            catalog: ModelPriceCatalog(prices: [:])
        )

        _ = NotchRootView(store: store, presentation: .constant(.collapsed))
    }
}
