import Foundation
import Testing
@testable import CodexStateCore

struct SessionLogParserTests {
    @Test
    func testParsesTokenDeltasAcrossModelChangesAndSkipsMalformedLines() throws {
        let jsonl = """
        {"timestamp":"2026-07-22T10:00:00Z","type":"turn_context","payload":{"model":"gpt-5.6-sol","prompt":"private"}}
        {"timestamp":"2026-07-22T10:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":70,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":99,"total_tokens":100}},"message":"private"}}
        {"timestamp":"2026-07-22T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":30,"output_tokens":20,"total_tokens":150}}}}
        {"timestamp":"2026-07-22T10:00:03Z","type":"turn_context","payload":{"model":"gpt-5.6-terra"}}
        not-json
        {"timestamp":"2026-07-22T10:00:04Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":45,"output_tokens":35,"total_tokens":230}}}}
        """

        let result = try SessionLogParser().parse(data: Data(jsonl.utf8))

        #expect(result.contributions.map(\.tokens.total) == [100, 50, 80])
        #expect(result.contributions.map(\.model) == ["gpt-5.6-sol", "gpt-5.6-sol", "gpt-5.6-terra"])
        #expect(result.malformedLineCount == 1)
    }
}
