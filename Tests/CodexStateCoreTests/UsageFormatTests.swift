import Testing
@testable import CodexStateCore

struct UsageFormatTests {
    @Test
    func tokensUseWanUntilOneHundredMillion() {
        #expect(UsageFormat.tokens(12_300_000) == "1230万")
        #expect(UsageFormat.tokens(99_999_999) == "10000万")
        #expect(UsageFormat.tokens(100_000_000) == "1.0亿")
        #expect(UsageFormat.tokens(543_300_000) == "5.4亿")
    }
}
