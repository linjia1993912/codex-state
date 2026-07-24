import AppKit

/// 物理刘海尺寸检测结果，用于让黑色胶囊与硬件刘海对齐融合。
///
/// 参考 CodexIsland 的 NotchInfo：高度取菜单栏可见高度（visibleFrame 比 frame
/// 矮 1pt 的差值已校正），宽度由 auxiliaryTopLeftArea/auxiliaryTopRightArea
/// 反推；非刘海屏退化为菜单栏胶囊。
public struct NotchInfo: Equatable, Sendable {
    public let width: CGFloat
    public let height: CGFloat
    public let hasNotch: Bool

    /// 非刘海屏使用的回退宽度（与物理刘海量级接近）。
    public static let fallbackWidth: CGFloat = 200

    public init(width: CGFloat, height: CGFloat, hasNotch: Bool) {
        self.width = width
        self.height = height
        self.hasNotch = hasNotch
    }

    public static func detect(from screen: NSScreen?) -> NotchInfo {
        guard let screen else {
            return NotchInfo(
                width: fallbackWidth,
                height: menuBarHeight(
                    safeTop: 0,
                    visibleFrameDelta: 0,
                    statusBarThickness: NSStatusBar.system.thickness
                ),
                hasNotch: false
            )
        }
        let safeTop = screen.safeAreaInsets.top
        let visualHeight = visibleMenuBarHeight(of: screen)
        if safeTop > 0 {
            let leftW = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightW = screen.auxiliaryTopRightArea?.width ?? 0
            let width: CGFloat = (leftW > 0 && rightW > 0)
                ? screen.frame.width - leftW - rightW
                : fallbackWidth
            return NotchInfo(width: width, height: visualHeight, hasNotch: true)
        }
        return NotchInfo(width: fallbackWidth, height: visualHeight, hasNotch: false)
    }

    private static func visibleMenuBarHeight(of screen: NSScreen) -> CGFloat {
        menuBarHeight(
            safeTop: screen.safeAreaInsets.top,
            visibleFrameDelta: screen.frame.maxY - screen.visibleFrame.maxY,
            statusBarThickness: NSStatusBar.system.thickness
        )
    }

    /// 纯高度规则，与 NSScreen 解耦以便测试。
    ///
    /// visibleFrame.maxY 位于菜单栏底边下方 1pt（AppKit 保留的间隙），
    /// 直接用 frame/visibleFrame 差值会高估 1pt，需校正；并用 safeTop 钳制，
    /// 防止登录或屏幕唤醒时陈旧的 visibleFrame 把胶囊推到真实菜单栏下方。
    public static func menuBarHeight(
        safeTop: CGFloat,
        visibleFrameDelta: CGFloat,
        statusBarThickness: CGFloat
    ) -> CGFloat {
        let fromVisibleFrame = visibleFrameDelta - 1
        if fromVisibleFrame > 0 {
            return safeTop > 0 ? min(fromVisibleFrame, safeTop) : fromVisibleFrame
        }
        if safeTop > 0 { return safeTop }
        return statusBarThickness > 0 ? statusBarThickness : 24
    }
}
