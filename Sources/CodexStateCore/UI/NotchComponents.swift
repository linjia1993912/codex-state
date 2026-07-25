import SwiftUI

/// 黑色 silhouette + 钴色光晕 + 旋转扫描。参考 codex-island GlowLayer。
///
/// expanded 装饰（白色描边 + 黑色阴影）通过延迟动画渐入：
/// 形状 spring 展开期间保持隐藏，220ms 后才渐入，
/// 避免阴影先出现在矮形状底部形成"底部边框"残影。
struct GlowLayer: View {
    let isExpanded: Bool

    var body: some View {
        ZStack {
            LoadingSweep(active: true, tint: IslandColor.cobalt)

            IslandShape()
                .fill(.black)
                .overlay {
                    IslandShape()
                        .strokeBorder(
                            .white.opacity(isExpanded ? 0.12 : 0),
                            lineWidth: 0.5
                        )
                        // 顶部贴屏幕物理边缘，裁掉顶部描边避免形成可见边框；
                        // 底部与两侧描边保留
                        .mask(Rectangle().padding(.top, 1))
                        .animation(decorAnimation, value: isExpanded)
                }
                .shadow(color: IslandColor.cobalt.opacity(0.35), radius: 14, y: 0)
                // expanded 黑色阴影用独立 overlay 承载，配合延迟动画：
                // 形状 spring 展开期间阴影保持隐藏，220ms 后才渐入，
                // 避免阴影先出现在矮形状底部形成"底部边框"残影；
                // 收起时 delay=0 立即渐出，比形状收缩快。
                .overlay {
                    IslandShape()
                        .fill(.clear)
                        .shadow(
                            color: isExpanded ? .black.opacity(0.5) : .clear,
                            radius: 20, y: 10
                        )
                        .animation(decorAnimation, value: isExpanded)
                }
        }
    }

    /// expanded 装饰动画：进入时延迟 220ms（等形状 spring 基本完成）再 180ms 渐入；
    /// 离开时立即渐出。
    private var decorAnimation: Animation {
        .easeOut(duration: 0.18).delay(isExpanded ? 0.22 : 0)
    }
}

/// 钴色角度扫描：30Hz TimelineView 驱动 AngularGradient 旋转，形成沿轮廓流动的光晕。
/// 参考 codex-island LoadingSweep。
private struct LoadingSweep: View {
    let active: Bool
    let tint: Color

    var body: some View {
        if active {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let rotation = (t * 100).truncatingRemainder(dividingBy: 360)
                IslandShape()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: tint.opacity(0.0), location: 0.55),
                                .init(color: tint, location: 0.78),
                                .init(color: .white.opacity(0.95), location: 0.92),
                                .init(color: tint.opacity(0.0), location: 1.00),
                            ]),
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: 4
                    )
                    .blur(radius: 3)
            }
        }
    }
}
