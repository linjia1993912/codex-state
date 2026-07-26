import Testing
@testable import CodexStateCore

struct UsageFormatTests {
    @Test
    func tokensUseYiOnlyAboveOneHundredMillion() {
        #expect(UsageFormat.tokens(100_000_000) == "100.0M")
        #expect(UsageFormat.tokens(543_300_000) == "5.43亿")
    }
}
