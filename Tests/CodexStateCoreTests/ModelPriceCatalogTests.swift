import Foundation
import Testing
@testable import CodexStateCore

struct ModelPriceCatalogTests {
    @Test
    func testEstimatesBundledModelCost() throws {
        let catalog = try ModelPriceCatalog.bundled()
        let tokens = TokenUsage(input: 1_000, cachedInput: 200, output: 100, total: 1_300)

        #expect(catalog.estimate(tokens: tokens, model: "gpt-5.6-sol") == Decimal(string: "0.0071"))
    }

    @Test
    func testReturnsNilForUnknownModel() throws {
        let catalog = try ModelPriceCatalog.bundled()

        #expect(catalog.estimate(tokens: .zero, model: "unknown") == nil)
    }
}
