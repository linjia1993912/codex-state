import Foundation

public struct SessionUsageResult: Sendable {
    public let contributions: [UsageContribution]
    public let malformedLineCount: Int

    public init(contributions: [UsageContribution], malformedLineCount: Int) {
        self.contributions = contributions
        self.malformedLineCount = malformedLineCount
    }
}

public final class SessionUsageRepository: @unchecked Sendable {
    private let cacheURL: URL
    private let parser: (Data) throws -> ParseResult

    public init(
        cacheURL: URL,
        parser: @escaping (Data) throws -> ParseResult = { try SessionLogParser().parse(data: $0) }
    ) {
        self.cacheURL = cacheURL
        self.parser = parser
    }

    public func load(home: URL, calendar: Calendar) throws -> SessionUsageResult {
        // 日边界由后续聚合使用，保留参数可让调用方固定该边界。
        _ = calendar
        let cached = loadCache()
        var files: [String: CachedFile] = [:]

        for url in sessionFiles(home: home) {
            let fingerprint = try FileFingerprint(url: url)
            let path = url.standardizedFileURL.path
            let result = cached.files[path]?.fingerprint == fingerprint
                ? cached.files[path]!.result
                : try parser(Data(contentsOf: url))
            files[path] = CachedFile(fingerprint: fingerprint, result: result)
        }

        try saveCache(Cache(files: files))
        let results = files.keys.sorted().compactMap { files[$0]?.result }
        return SessionUsageResult(
            contributions: results.flatMap(\.contributions),
            malformedLineCount: results.reduce(0) { $0 + $1.malformedLineCount }
        )
    }

    public static func aggregate(
        contributions: [UsageContribution],
        calendar: Calendar,
        catalog: ModelPriceCatalog
    ) -> [DailyUsage] {
        var grouped: [Date: [String: TokenUsage]] = [:]
        for contribution in contributions {
            let day = calendar.startOfDay(for: contribution.date)
            grouped[day, default: [:]][contribution.model, default: .zero] =
                grouped[day, default: [:]][contribution.model, default: .zero] + contribution.tokens
        }

        return grouped.map { date, tokensByModel in
            let tokens = tokensByModel.values.reduce(.zero, +)
            let estimatedCostUSD = tokensByModel.reduce(Decimal.zero as Decimal?) { total, modelAndTokens in
                guard let total, let cost = catalog.estimate(tokens: modelAndTokens.value, model: modelAndTokens.key) else {
                    return nil
                }
                return total + cost
            }
            return DailyUsage(
                date: date,
                tokens: tokens,
                estimatedCostUSD: estimatedCostUSD,
                tokensByModel: tokensByModel
            )
        }.sorted { $0.date < $1.date }
    }

    private func sessionFiles(home: URL) -> [URL] {
        var files: [URL] = []
        for directory in ["sessions", "archived_sessions"] {
            let url = home.appendingPathComponent(directory, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    files.append(file)
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func loadCache() -> Cache {
        guard let data = try? Data(contentsOf: cacheURL) else { return Cache(files: [:]) }
        return (try? JSONDecoder().decode(Cache.self, from: data)) ?? Cache(files: [:])
    }

    private func saveCache(_ cache: Cache) throws {
        // 缓存仅保存解析后的用量；原子替换避免半写入，且绝不持久化会话正文。
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
    }
}

private struct Cache: Codable {
    let files: [String: CachedFile]
}

private struct CachedFile: Codable {
    let fingerprint: FileFingerprint
    let contributions: [UsageContribution]
    let malformedLineCount: Int

    init(fingerprint: FileFingerprint, result: ParseResult) {
        self.fingerprint = fingerprint
        contributions = result.contributions
        malformedLineCount = result.malformedLineCount
    }

    var result: ParseResult {
        ParseResult(contributions: contributions, malformedLineCount: malformedLineCount)
    }
}

private struct FileFingerprint: Codable, Equatable {
    let size: Int64
    let modificationDate: Date

    init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values.fileSize, let modificationDate = values.contentModificationDate else {
            throw CocoaError(.fileReadUnknown)
        }
        self.size = Int64(size)
        self.modificationDate = modificationDate
    }
}
