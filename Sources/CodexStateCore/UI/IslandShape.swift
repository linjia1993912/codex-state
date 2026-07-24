import SwiftUI

/// 刘海胶囊形状：顶部平直（与屏幕顶边贴合），底部圆角（与物理刘海内曲线匹配）。
///
/// 参考 CodexIsland 的 IslandShape：使用 `.continuous`（squircle）让圆角曲率渐变，
/// 匹配 Apple 硬件刘海与灵动岛的视觉。普通圆弧在此尺度下会在切点处出现可见折角。
struct IslandShape: InsettableShape {
    var inset: CGFloat = 0
    var bottomRadius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        return UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: bottomRadius,
                bottomTrailing: bottomRadius,
                topTrailing: 0
            ),
            style: .continuous
        ).path(in: r)
    }

    func inset(by amount: CGFloat) -> IslandShape {
        var s = self
        s.inset += amount
        return s
    }
}

/// 颜色与动画令牌，参考 CodexIsland 的 Theme。
enum IslandColor {
    /// #0047AB —— 钴色，用于刘海光晕与刷新扫描动画。
    static let cobalt = Color(red: 0/255, green: 71/255, blue: 171/255)
}

extension Animation {
    /// 形态展开弹簧（进入稍慢，用户在跟踪形态变化）。
    static let islandOpen = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// 形态收起弹簧（退出更利落）。
    static let islandClose = Animation.spring(response: 0.30, dampingFraction: 0.88)
}

/// ChatGPT / OpenAI 图标：六瓣花瓣形六重对称标记，纯代码绘制。
///
/// 项目约定不引入第三方资源；此处用 6 片透镜花瓣组成六重对称花纹，
/// 呼应 OpenAI 标志的六边形结拓扑。在黑色胶囊上以白色渲染，配合钴色光晕，
/// 视觉上读作“ChatGPT 在线”。
struct ChatGPTLogo: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2
        guard r > 0 else { return path }
        let outerRadius = r
        let innerRadius = r * 0.42
        let bow = r * 0.62

        for k in 0..<6 {
            let angle = Double(k) * .pi / 3
            let dx = cos(angle)
            let dy = sin(angle)
            // 切向（垂直于径向）
            let tx = -dy
            let ty = dx
            let outer = CGPoint(x: cx + outerRadius * dx, y: cy + outerRadius * dy)
            let inner = CGPoint(x: cx - innerRadius * dx, y: cy - innerRadius * dy)

            var petal = Path()
            petal.move(to: outer)
            petal.addCurve(
                to: inner,
                control1: CGPoint(x: outer.x + tx * bow, y: outer.y + ty * bow),
                control2: CGPoint(x: inner.x + tx * bow, y: inner.y + ty * bow)
            )
            petal.addCurve(
                to: outer,
                control1: CGPoint(x: inner.x - tx * bow, y: inner.y - ty * bow),
                control2: CGPoint(x: outer.x - tx * bow, y: outer.y - ty * bow)
            )
            path.addPath(petal)
        }
        return path
    }
}
