import Foundation

/// 统一的用量与价格格式化工具，确保全 UI 展示一致。
public enum UsageFormat {
    /// Token 用量格式化：>99.9M 使用一位小数的“亿”，其余保持 K/M 的既有格式。
    public static func tokens(_ value: Int64) -> String {
        if value > 99_900_000 {
            String(format: "%.1f亿", Double(value) / 100_000_000)
        } else if value >= 1_000_000 {
            String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            String(format: "%.0fK", Double(value) / 1_000)
        } else {
            "\(value)"
        }
    }

    /// 价格估算格式化：始终保留 2 位小数，带 "$" 前缀。
    public static func cost(_ value: Decimal) -> String {
        let rounded = (value as NSDecimalNumber).rounding(accordingToBehavior:
            NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
        )
        return String(format: "$%.2f", rounded.doubleValue)
    }
}
