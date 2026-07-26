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
        var cacheChanged = false
        let discovered = sessionFiles(home: home)
        var failedFileCount = discovered.resourceFailureCount

        for url in discovered.urls {
            do {
                let fingerprint = try FileFingerprint(url: url)
                let path = url.standardizedFileURL.path
                let result: ParseResult
                if let cachedFile = cached.files[path], cachedFile.fingerprint == fingerprint {
                    result = cachedFile.result
                } else {
                    result = try parser(Data(contentsOf: url))
                    cacheChanged = true
                }
                files[path] = CachedFile(fingerprint: fingerprint, result: result)
            } catch {
                // 单个日志不可读或不可解析时只标记该文件，不能抹掉其他日志的有效贡献。
                failedFileCount += 1
            }
        }

        // 缓存只是性能优化；所有文件未变时跳过整份编码和原子替换写入。
        if cacheChanged || cached.files.count != files.count {
            try? saveCache(Cache(files: files))
        }
        let results = files.keys.sorted().compactMap { files[$0]?.result }
        return SessionUsageResult(
            contributions: results.flatMap(\.contributions),
            malformedLineCount: failedFileCount + results.reduce(0) { $0 + $1.malformedLineCount }
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
            var knownCost = Decimal.zero
            var knownCostCount = 0
            var unknownPriceModels: [String] = []
            for (model, modelTokens) in tokensByModel.sorted(by: { $0.key < $1.key }) {
                if let cost = catalog.estimate(tokens: modelTokens, model: model) {
                    knownCost += cost
                    knownCostCount += 1
                } else {
                    unknownPriceModels.append(model)
                }
            }
            return DailyUsage(
                date: date,
                tokens: tokens,
                estimatedCostUSD: knownCostCount == 0 ? nil : knownCost,
                tokensByModel: tokensByModel,
                unknownPriceModels: unknownPriceModels
            )
        }.sorted { $0.date < $1.date }
    }

    private func sessionFiles(home: URL) -> (urls: [URL], resourceFailureCount: Int) {
        var files: [URL] = []
        var resourceFailureCount = 0
        for directory in ["sessions", "archived_sessions"] {
            let url = home.appendingPathComponent(directory, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                do {
                    guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                    files.append(file)
                } catch {
                    resourceFailureCount += 1
                }
            }
        }
        return (files.sorted { $0.path < $1.path }, resourceFailureCount)
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
