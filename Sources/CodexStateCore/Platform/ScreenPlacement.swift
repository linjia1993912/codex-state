import AppKit
import Foundation

public enum NotchPresentation: Equatable, Sendable {
    case collapsed
    case peek
    case expanded
}

public struct PeekMetric: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case quota
        case todayTokens
        case todayCost
    }

    public let kind: Kind
    public let title: String
    public let value: String
    public let progress: Double?

    init(kind: Kind, title: String, value: String, progress: Double?) {
        self.kind = kind
        self.title = title
        self.value = value
        self.progress = progress
    }
}

public enum NotchLayoutPolicy {
    public static func metrics(snapshot: UsageSnapshot) -> [PeekMetric] {
        let windows = snapshot.quotaWindows
        if windows.count >= 2 {
            // 只消费服务端实际给出的窗口，避免把已消失的短周期额度显示为占位项。
            return windows.prefix(2).map(quotaMetric)
        }

        let today = snapshot.dailyUsage.last
        let tokenMetric = PeekMetric(
            kind: .todayTokens,
            title: "今日 Tokens",
            value: formatTokens(today?.tokens.total ?? 0),
            progress: nil
        )

        if let window = windows.first {
            return [quotaMetric(window), tokenMetric]
        }

        let cost = today?.estimatedCostUSD.map { "$\($0)" } ?? "—"
        return [
            tokenMetric,
            PeekMetric(kind: .todayCost, title: "今日估算", value: cost, progress: nil),
        ]
    }

    private static func quotaMetric(_ window: QuotaWindow) -> PeekMetric {
        PeekMetric(
            kind: .quota,
            title: window.title,
            value: "\(window.usedPercent)%",
            progress: window.usedPercent / 100
        )
    }

    private static func formatTokens(_ value: Int64) -> String {
        value >= 1_000_000 ? String(format: "%.2fM", Double(value) / 1_000_000) : "\(value)"
    }
}

public enum ScreenPlacement {
    public static func panelOrigin(screenFrame: NSRect, panelSize: NSSize) -> NSPoint {
        NSPoint(x: screenFrame.midX - panelSize.width / 2, y: screenFrame.maxY - panelSize.height)
    }
}
