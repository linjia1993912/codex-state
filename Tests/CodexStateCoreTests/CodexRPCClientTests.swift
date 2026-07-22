import Foundation
import Testing
@testable import CodexStateCore

struct CodexRPCClientTests {
    @Test
    func testDecodesChatGPTAccount() throws {
        let data = Data("""
        {"id":2,"result":{"account":{"type":"chatgpt","email":"ada@example.com","planType":"plus"}}}
        """.utf8)

        #expect(try CodexRPCCodec.decodeAccount(data) == AccountSummary(email: "ada@example.com", plan: "plus"))
    }

    @Test
    func testDecodesOnlySecondaryWeeklyWindow() throws {
        let data = Data("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex","limitName":"Codex","planType":"plus","primary":null,"secondary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1753747200}}}}
        """.utf8)

        #expect(try CodexRPCCodec.decodeRateLimits(data) == [
            QuotaWindow(
                id: "secondary",
                title: "每周额度",
                usedPercent: 42,
                resetsAt: Date(timeIntervalSince1970: 1_753_747_200),
                durationMinutes: 10_080
            )
        ])
    }
}
