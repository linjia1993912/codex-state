import Foundation

public struct ModelPrice: Codable, Equatable, Sendable {
    public let input: Decimal
    public let cachedInput: Decimal
    public let output: Decimal

    public init(input: Decimal, cachedInput: Decimal, output: Decimal) {
        self.input = input
        self.cachedInput = cachedInput
        self.output = output
    }
}

public struct ModelPriceCatalog: Sendable {
    private let prices: [String: ModelPrice]

    public init(prices: [String: ModelPrice]) {
        self.prices = prices
    }

    public func estimate(tokens: TokenUsage, model: String) -> Decimal? {
        guard let price = prices[model] else { return nil }

        // 缓存 Token 是输入 Token 的子集，截断可避免重复计费或出现负的非缓存输入。
        let cachedInput = min(tokens.input, tokens.cachedInput)
        let cost = Decimal(tokens.input - cachedInput) * price.input
            + Decimal(cachedInput) * price.cachedInput
            + Decimal(tokens.output) * price.output
        return cost / 1_000_000
    }

    public static func bundled() throws -> ModelPriceCatalog {
        let appResourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("codex-state_CodexStateCore.bundle", isDirectory: true)
            .appendingPathComponent("ModelPrices.json")
        let url: URL
        if let appResourceURL, FileManager.default.fileExists(atPath: appResourceURL.path) {
            url = appResourceURL
        } else if Bundle.main.bundleURL.pathExtension != "app",
                  let moduleURL = Bundle.module.url(forResource: "ModelPrices", withExtension: "json") {
            // SwiftPM 测试和直接运行可执行文件时，资源仍由 Bundle.module 管理。
            url = moduleURL
        } else {
            throw ModelPriceCatalogError.resourceNotFound
        }

        let catalog = try JSONDecoder().decode(BundledPrices.self, from: Data(contentsOf: url))
        return ModelPriceCatalog(prices: catalog.models)
    }
}

private enum ModelPriceCatalogError: LocalizedError {
    case resourceNotFound

    var errorDescription: String? { "未找到内置模型价格资源 ModelPrices.json" }
}

private struct BundledPrices: Decodable {
    let updatedAt: String
    let models: [String: ModelPrice]
}
