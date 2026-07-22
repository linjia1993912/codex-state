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
        guard let url = Bundle.module.url(forResource: "ModelPrices", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let catalog = try JSONDecoder().decode(BundledPrices.self, from: Data(contentsOf: url))
        return ModelPriceCatalog(prices: catalog.models)
    }
}

private struct BundledPrices: Decodable {
    let updatedAt: String
    let models: [String: ModelPrice]
}
