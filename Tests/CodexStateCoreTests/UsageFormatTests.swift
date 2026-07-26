import Testing
@testable import CodexStateCore

struct UsageFormatTests {
    @Test
    func tokensUseYiAboveNinetyNinePointNineMillion() {
        #expect(UsageFormat.tokens(99_900_000) == "99.9M")
        #expect(UsageFormat.tokens(99_900_001) == "1.0亿")
        #expect(UsageFormat.tokens(543_300_000) == "5.4亿")
    }
}
