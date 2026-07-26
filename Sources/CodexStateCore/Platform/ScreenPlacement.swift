import AppKit
import Foundation
import Observation

public enum NotchPresentation: Equatable, Sendable {
    case collapsed
    case peek
    case expanded
}

/// 刘海岛视图状态：presentation 变化时通过 @Observable 通知 SwiftUI 自动重渲染。
/// 参考 codex-island 的 IslandModel（ObservableObject + @Published state）。
@MainActor
@Observable
public final class NotchViewModel {
    public var presentation: NotchPresentation = .collapsed
    public var notchInfo: NotchInfo

    public init(presentation: NotchPresentation = .collapsed, notchInfo: NotchInfo) {
        self.presentation = presentation
        self.notchInfo = notchInfo
    }
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

    public var usesWarningTint: Bool {
        kind == .quota && (progress ?? 1) <= 0.1
    }
}

public enum NotchLayoutPolicy {
    /// Peek 预览指标：每周剩余额度 + 今日 Token 用量。
    /// 额度不可用时回退为今日 Token + 今日估算成本。
    public static func metrics(snapshot: UsageSnapshot, now: Date = Date()) -> [PeekMetric] {
        // 优先选择周级别额度窗口
        let weeklyQuota = snapshot.quotaWindows.first { window in
            (window.durationMinutes ?? 0) >= 7 * 24 * 60 || window.title.contains("周")
        } ?? snapshot.quotaWindows.first

        let today = snapshot.dailyUsage.first { Calendar.current.isDate($0.date, inSameDayAs: now) }
        let tokenMetric = PeekMetric(
            kind: .todayTokens,
            title: "今日 Tokens",
            value: UsageFormat.tokens(today?.tokens.total ?? 0),
            progress: nil
        )

        if let quota = weeklyQuota {
            return [quotaMetric(quota), tokenMetric]
        }

        // 无额度数据时回退为今日 Token + 今日估算
        let cost = today?.estimatedCostUSD.map { UsageFormat.cost($0) } ?? "—"
        return [
            tokenMetric,
            PeekMetric(kind: .todayCost, title: "今日估算", value: cost, progress: nil),
        ]
    }

    private static func quotaMetric(_ window: QuotaWindow) -> PeekMetric {
        PeekMetric(
            kind: .quota,
            title: window.remainingTitle,
            value: String(format: "%.0f%%", window.remainingPercent),
            progress: window.remainingPercent / 100
        )
    }
}

public enum ScreenPlacement {
    public static func panelOrigin(screenFrame: NSRect, panelSize: NSSize) -> NSPoint {
        NSPoint(x: screenFrame.midX - panelSize.width / 2, y: screenFrame.maxY - panelSize.height)
    }
}

/// 刘海岛尺寸计算：基于物理刘海推导 compact/peek/expanded 三态尺寸。
///
/// 参考 CodexIsland 的 IslandModel：三态宽度单调递增，从小到大丝滑过渡。
/// - compact：刘海宽度 + 两侧 logo 标签（容纳 ChatGPT 图标）
/// - peek：比 compact 宽，能舒适显示两列指标（周限额 + 今日 token）
/// - expanded：固定面板尺寸，展示完整详情
public struct IslandLayout: Sendable {
    /// 单侧 logo 标签宽度，容纳 ChatGPT 图标及内边距。
    public static let logoTabWidth: CGFloat = 38
    /// peek 向下延伸的内容区高度。
    public static let peekContentHeight: CGFloat = 76
    /// peek 内容区宽度需求：两列指标（每列约 120pt）+ 间距 + padding。
    public static let peekContentWidth: CGFloat = 300
    /// expanded 面板固定宽度。
    public static let expandedWidth: CGFloat = 380
    /// expanded 面板固定高度。
    public static let expandedHeight: CGFloat = 400
    /// expanded 面板固定尺寸。
    public static var expandedSize: CGSize { CGSize(width: expandedWidth, height: expandedHeight) }

    public let notch: NotchInfo

    public init(notch: NotchInfo) { self.notch = notch }

    /// compact：刘海宽度 + 两侧 logo 标签 × 刘海高度。
    public var compactSize: CGSize {
        CGSize(width: notch.width + Self.logoTabWidth * 2, height: notch.height)
    }

    /// peek：比 compact 宽（容纳两列指标），比 expanded 窄。
    /// 取 compact 宽度与内容需求宽度的较大值，保证从小到大单调递增。
    public var peekSize: CGSize {
        CGSize(width: max(compactSize.width, Self.peekContentWidth), height: notch.height + Self.peekContentHeight)
    }

    /// 按展示状态返回内容尺寸。
    public func size(for presentation: NotchPresentation) -> CGSize {
        switch presentation {
        case .collapsed: compactSize
        case .peek: peekSize
        case .expanded: Self.expandedSize
        }
    }
}
