import Foundation

public struct ParseResult: Equatable, Sendable {
    public let contributions: [UsageContribution]
    public let malformedLineCount: Int

    public init(contributions: [UsageContribution], malformedLineCount: Int) {
        self.contributions = contributions
        self.malformedLineCount = malformedLineCount
    }
}

public struct SessionLogParser: Sendable {
    public init() {}

    public func parse(data: Data) throws -> ParseResult {
        let decoder = JSONDecoder()
        // formatter 创建成本高；它们只在当前文件解析期间使用，既复用又不跨线程共享。
        let timestampFormatter = ISO8601DateFormatter()
        let fractionalTimestampFormatter = ISO8601DateFormatter()
        fractionalTimestampFormatter.formatOptions.insert(.withFractionalSeconds)
        var model = "unknown"
        var previousUsage = TokenUsage.zero
        var contributions: [UsageContribution] = []
        var malformedLineCount = 0

        for line in data.split(separator: 0x0A) {
            guard !line.allSatisfy({ $0 == 0x09 || $0 == 0x0D || $0 == 0x20 }) else { continue }

            do {
                switch try decoder.decode(LogRecord.self, from: Data(line)).action {
                case let .modelChanged(newModel):
                    model = newModel
                case let .tokenCount(timestamp, usage):
                    guard let date = timestampFormatter.date(from: timestamp)
                        ?? fractionalTimestampFormatter.date(from: timestamp) else {
                        malformedLineCount += 1
                        continue
                    }

                    // 累计基线属于整段会话，模型切换后仍需沿用，避免重复计算历史 Token。
                    let delta = usage.delta(from: previousUsage)
                    previousUsage = usage
                    guard delta.total > 0 else { continue }
                    contributions.append(UsageContribution(date: date, model: model, tokens: delta))
                case .irrelevant:
                    break
                }
            } catch {
                malformedLineCount += 1
            }
        }

        return ParseResult(contributions: contributions, malformedLineCount: malformedLineCount)
    }
}

private struct LogRecord: Decodable {
    enum Action {
        case modelChanged(String)
        case tokenCount(String, TokenUsage)
        case irrelevant
    }

    let action: Action

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case type
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decodeIfPresent(String.self, forKey: .type) {
        case "turn_context":
            let payload = try container.decodeIfPresent(ModelPayload.self, forKey: .payload)
            action = .modelChanged(payload?.model ?? "unknown")
        case "event_msg":
            let event = try container.decodeIfPresent(EventPayload.self, forKey: .payload)
            guard event?.type == "token_count" else {
                action = .irrelevant
                return
            }

            let timestamp = try container.decode(String.self, forKey: .timestamp)
            let payload = try container.decode(TokenPayload.self, forKey: .payload)
            action = .tokenCount(timestamp, payload.info.totalTokenUsage.tokenUsage)
        default:
            action = .irrelevant
        }
    }
}

private struct ModelPayload: Decodable {
    let model: String?
}

private struct EventPayload: Decodable {
    let type: String?
}

private struct TokenPayload: Decodable {
    let info: TokenInfo
}

private struct TokenInfo: Decodable {
    let totalTokenUsage: RawTokenUsage

    private enum CodingKeys: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
    }
}

private struct RawTokenUsage: Decodable {
    let input: Int64
    let cachedInput: Int64
    let output: Int64
    let total: Int64

    var tokenUsage: TokenUsage {
        TokenUsage(input: input, cachedInput: cachedInput, output: output, total: total)
    }

    private enum CodingKeys: String, CodingKey {
        case input = "input_tokens"
        case cachedInput = "cached_input_tokens"
        case output = "output_tokens"
        case total = "total_tokens"
    }
}
