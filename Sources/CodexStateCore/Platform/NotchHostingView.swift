import AppKit
import SwiftUI

/// 自定义 NSHostingView，重写 hitTest 让透明区域点击穿透。
///
/// 参考 CodexIsland 的 IslandHostingView：只在当前状态的可视矩形内返回 super.hitTest，
/// 透明区域（如顶部连接带、collapsed 状态的胶囊外区域）返回 nil，使点击穿透到下层窗口。
///
/// 与 NotchPanelController 的全局 mouseMoved 监听配合使用：
/// - hitTest 阻止 panel 内部视图接收岛外点击
/// - ignoresMouseEvents 阻止窗口在岛外 steal focus
final class NotchHostingView<Root: View>: NSHostingView<Root> {
    /// 当前状态的可视内容矩形（在 hostingView bounds 坐标系内）。
    /// 只有此矩形内的点会接收鼠标事件，其余穿透。
    var visibleRectProvider: () -> NSRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let rect = visibleRectProvider()
        return rect.contains(point) ? super.hitTest(point) : nil
    }

    // 参考 CodexIsland：非 key 窗口默认第一次点击只激活窗口不触发手势，
    // 返回 true 让光标悬停后的第一次点击就能展开面板，无需先点一下激活。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
