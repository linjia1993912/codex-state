import Testing
@testable import CodexStateCore

@MainActor
struct DailyTrendSelectionTests {
    @Test
    func selectionClampsToFirstAndLastBar() {
        #expect(DailyTrendSelection.index(for: -1, width: 300, count: 7) == 0)
        #expect(DailyTrendSelection.index(for: 0, width: 300, count: 7) == 0)
        #expect(DailyTrendSelection.index(for: 299, width: 300, count: 7) == 6)
        #expect(DailyTrendSelection.index(for: 600, width: 300, count: 7) == 6)
    }

    @Test
    func selectionReturnsNilForNoBarsOrNoWidth() {
        #expect(DailyTrendSelection.index(for: 20, width: 0, count: 7) == nil)
        #expect(DailyTrendSelection.index(for: 20, width: 300, count: 0) == nil)
    }

    @Test
    func costTextOmitsUnknownModelDisclaimer() {
        let day = DailyUsage(
            date: .now,
            tokens: .zero,
            unknownPriceModels: ["unknown-a", "unknown-b"]
        )

        #expect(DailyTrendView.costText(for: day) == "估算成本：—")
    }
}
