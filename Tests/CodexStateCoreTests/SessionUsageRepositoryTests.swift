import Foundation
import Testing
@testable import CodexStateCore

struct SessionUsageRepositoryTests {
    @Test
    func loadKeepsValidFilesWhenOneParseFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data("good".utf8).write(to: sessions.appendingPathComponent("good.jsonl"))
        try Data("bad".utf8).write(to: sessions.appendingPathComponent("bad.jsonl"))
        let contribution = UsageContribution(
            date: Date(timeIntervalSince1970: 1_784_736_000),
            model: "gpt-5.6-sol",
            tokens: TokenUsage(input: 1, cachedInput: 0, output: 0, total: 1)
        )
        let repository = SessionUsageRepository(
            cacheURL: directory.appendingPathComponent("usage-cache.json"),
            parser: { data in
                guard data == Data("good".utf8) else { throw RepositoryTestError.parseFailed }
                return ParseResult(contributions: [contribution], malformedLineCount: 0)
            }
        )

        let result = try repository.load(home: directory, calendar: .current)

        #expect(result.contributions == [contribution])
        #expect(result.malformedLineCount == 1)
    }

    @Test
    func cacheWriteFailureDoesNotDiscardUsage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data("good".utf8).write(to: sessions.appendingPathComponent("good.jsonl"))
        let cacheParent = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: cacheParent)
        let contribution = UsageContribution(
            date: Date(timeIntervalSince1970: 1_784_736_000),
            model: "gpt-5.6-sol",
            tokens: TokenUsage(input: 1, cachedInput: 0, output: 0, total: 1)
        )
        let repository = SessionUsageRepository(
            cacheURL: cacheParent.appendingPathComponent("usage-cache.json"),
            parser: { _ in ParseResult(contributions: [contribution], malformedLineCount: 0) }
        )

        let result = try repository.load(home: directory, calendar: .current)

        #expect(result.contributions == [contribution])
    }

    @Test
    func testReusesCachedParseResultWhenFileIsUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: sessions.appendingPathComponent("session.jsonl"))

        var parseCount = 0
        let repository = SessionUsageRepository(
            cacheURL: directory.appendingPathComponent("usage-cache.json"),
            parser: { _ in
                parseCount += 1
                return ParseResult(contributions: [], malformedLineCount: 0)
            }
        )

        _ = try repository.load(home: directory, calendar: .current)
        _ = try repository.load(home: directory, calendar: .current)

        #expect(parseCount == 1)
    }

    @Test
    func testAggregatesUTCContributionsByInjectedLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let formatter = ISO8601DateFormatter()
        let contributions = [
            UsageContribution(
                date: formatter.date(from: "2026-07-22T15:59:59Z")!,
                model: "gpt-5.6-sol",
                tokens: TokenUsage(input: 10, cachedInput: 0, output: 0, total: 10)
            ),
            UsageContribution(
                date: formatter.date(from: "2026-07-22T16:00:00Z")!,
                model: "gpt-5.6-sol",
                tokens: TokenUsage(input: 20, cachedInput: 0, output: 0, total: 20)
            )
        ]

        let dailyUsage = SessionUsageRepository.aggregate(
            contributions: contributions,
            calendar: calendar,
            catalog: ModelPriceCatalog(prices: [:])
        )

        #expect(dailyUsage.map(\.tokens.total) == [10, 20])
    }
}

private enum RepositoryTestError: Error {
    case parseFailed
}
