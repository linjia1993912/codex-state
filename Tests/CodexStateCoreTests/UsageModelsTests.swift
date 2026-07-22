import XCTest
@testable import CodexStateCore

final class UsageModelsTests: XCTestCase {
    func testDeltaReturnsCurrentUsageWhenCumulativeCounterResets() {
        let previous = TokenUsage(input: 100, cachedInput: 80, output: 60, total: 240)
        let current = TokenUsage(input: 20, cachedInput: 10, output: 5, total: 35)

        XCTAssertEqual(current.delta(from: previous), current)
    }

    func testDeltaReturnsDifferencesWhenCumulativeCounterIncreases() {
        let previous = TokenUsage(input: 100, cachedInput: 80, output: 60, total: 240)
        let current = TokenUsage(input: 140, cachedInput: 100, output: 90, total: 330)

        XCTAssertEqual(
            current.delta(from: previous),
            TokenUsage(input: 40, cachedInput: 20, output: 30, total: 90)
        )
    }
}
