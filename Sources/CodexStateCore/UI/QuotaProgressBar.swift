import SwiftUI

/// 自定义额度进度条。
///
/// 系统默认 `ProgressView` 在深色背景上轨道近乎不可见，且颜色与背景融合。
/// 这里用 `Capsule` + 几何比例手动绘制，确保轨道与填充都清晰可辨；
/// 颜色按剩余比例分级：充足为绿、偏低为橙、危险为红。
struct QuotaProgressBar: View {
    /// 剩余比例，范围 0...1。
    let remaining: Double
    var height: CGFloat = 6

    private var clamped: Double { min(max(remaining, 0), 1) }

    private var tint: Color {
        // 剩余 ≤10% 为红，≤30% 为橙，其余为绿。
        // 与 PeekMetric.usesWarningTint 的 10% 阈值保持一致。
        if clamped <= 0.1 { return .red }
        if clamped <= 0.3 { return .orange }
        return .green
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(tint).frame(width: max(width * clamped, height))
            }
        }
        .frame(height: height)
        .accessibilityLabel("剩余 \(Int(clamped * 100))%")
    }
}
