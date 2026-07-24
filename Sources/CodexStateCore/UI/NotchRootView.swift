import SwiftUI

/// 刘海岛根视图：compact 黑色 squircle 与物理刘海融合 + 右侧 ChatGPT 图标 + 钴色光晕扫描；
/// peek 向下扩展显示周限额与今日用量；expanded 展开完整面板。
///
/// 参考 codex-island 的 IslandRootView：
/// - 所有内容层叠在 ZStack 中，通过 opacity 渐入渐出（不用 switch 硬切换）
/// - 尺寸通过 model.size + spring 动画平滑变化，由小到大丝滑过渡
/// - contentVisible / pillsVisible 状态实现交错动画（形状先变，内容后现）
@MainActor
public struct NotchRootView: View {
    @Bindable private var model: NotchViewModel
    @Bindable private var store: UsageStore

    /// 内容可见性：peek/expanded 内容在形状变化后渐入，收起时先渐出再缩形
    @State private var contentVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: UsageStore, model: NotchViewModel) {
        self.store = store
        self.model = model
    }

    private var presentation: NotchPresentation { model.presentation }
    private var notchInfo: NotchInfo { model.notchInfo }
    private var layout: IslandLayout { IslandLayout(notch: notchInfo) }
    private var currentSize: CGSize { layout.size(for: presentation) }

    /// 形态展开弹簧（参考 codex-island .openMorph）
    private var openMorph: Animation {
        .spring(response: 0.42, dampingFraction: 0.82)
    }
    /// 形态收起弹簧（参考 codex-island .closeMorph）
    private var closeMorph: Animation {
        .spring(response: 0.30, dampingFraction: 0.88)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // GlowLayer 始终存在，尺寸跟随 currentSize 变化驱动 spring 动画。
                // collapsed 状态下 ZStack 只有 GlowLayer，确保胶囊与物理刘海干净融合。
                GlowLayer(isExpanded: presentation == .expanded)

                // peek/expanded 内容用条件渲染：避免 collapsed 状态下
                // PeekContent/ExpandedUsageView 被压缩到刘海高度导致布局异常。
                if presentation == .peek {
                    PeekContent(
                        snapshot: store.snapshot,
                        notchHeight: notchInfo.height
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(contentVisible ? 1 : 0)
                    .allowsHitTesting(contentVisible)
                } else if presentation == .expanded {
                    ExpandedUsageView(
                        store: store,
                        notchHeight: notchInfo.height
                    ) { setPresentation(.collapsed) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : -8)
                    .allowsHitTesting(contentVisible)
                }
            }
            .frame(width: currentSize.width, height: currentSize.height)
            .overlay(alignment: .topTrailing) {
                // ChatGPT 图标固定在 compact 右边缘位置，所有状态保持一致。
                // 展开后 ZStack 变宽，通过额外 trailing padding 抵消右边缘的位移，
                // 让图标锚点不随宽度变化滑动，避免视觉上产生"向左展开"的错觉。
                let extraTrailing = max(0, (currentSize.width - layout.compactSize.width) / 2)
                ChatGPTLogoOverlay(notchHeight: notchInfo.height)
                    .padding(.trailing, extraTrailing)
            }
            .contentShape(IslandShape())
            .onTapGesture {
                // 点击：从 peek 或 compact 展开到 expanded
                guard presentation == .peek || presentation == .collapsed else { return }
                setPresentation(.expanded)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Codex 用量")
        // 监听 presentation 变化驱动 contentVisible 交错动画。
        // 无论来源是 SwiftUI 点击还是 NotchPanelController 鼠标追踪，都走同一套交错逻辑。
        .onChange(of: presentation) { oldValue, newValue in
            handlePresentationChange(from: oldValue, to: newValue)
        }
    }

    // MARK: - 状态切换

    /// SwiftUI 内部调用（点击展开/收起）。
    /// 使用 withAnimation 显式驱动方向动画：收起用 closeMorph（高阻尼，减少下冲），
    /// 展开用 openMorph（略弹，形态变化更明显）。
    private func setPresentation(_ value: NotchPresentation) {
        guard presentation != value else { return }
        let anim = value == .collapsed ? closeMorph : openMorph
        withAnimation(anim) {
            model.presentation = value
        }
    }

    /// presentation 变化时驱动 contentVisible 交错动画（参考 codex-island onHover/onTapGesture）。
    /// 形状先变（由 setPresentation 中的 withAnimation 驱动），内容延迟渐入；
    /// 收起时内容先渐出，形状后收起。
    private func handlePresentationChange(from oldValue: NotchPresentation, to newValue: NotchPresentation) {
        if newValue == .expanded {
            // 展开：先隐藏旧内容，形状变大后新内容 220ms 渐入
            withAnimation(.easeOut(duration: 0.08)) { contentVisible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                guard model.presentation == .expanded else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    contentVisible = true
                }
            }
        } else if newValue == .peek {
            // peek：先隐藏旧内容，形状变化后新内容 60ms 渐入
            withAnimation(.easeOut(duration: 0.08)) { contentVisible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                guard model.presentation == .peek else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    contentVisible = true
                }
            }
        } else {
            // collapsed：内容先渐出
            withAnimation(.easeOut(duration: 0.08)) {
                contentVisible = false
            }
        }
    }
}

// MARK: - ChatGPTLogoOverlay

/// 右侧 ChatGPT 图标叠加：固定在 compact 右边缘位置。
/// 使用 stroke 而非 fill 保持花瓣间的负空间，参考 OpenAI 标志的六瓣花结。
private struct ChatGPTLogoOverlay: View {
    let notchHeight: CGFloat
    /// 图标距内容右边的固定内边距。
    private let trailingPadding: CGFloat = 9

    var body: some View {
        ChatGPTLogo()
            .stroke(.white, lineWidth: 1.2)
            .frame(width: 18, height: 18)
            .padding(.trailing, trailingPadding)
            .padding(.top, max(0, (notchHeight - 18) / 2))
            .accessibilityLabel("ChatGPT")
    }
}

// MARK: - PeekContent

/// peek 内容：刘海下方展示周限额与今日用量指标。
/// 两列水平排列，每列占一半宽度，避免互相挤压。
private struct PeekContent: View {
    let snapshot: UsageSnapshot
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // 顶部连接带与物理刘海融合
            Color.clear.frame(height: notchHeight)
            // 两列水平排列指标
            HStack(spacing: 16) {
                ForEach(Array(NotchLayoutPolicy.metrics(snapshot: snapshot).enumerated()), id: \.offset) { _, metric in
                    PeekMetricColumn(metric: metric)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(.white)
        }
        .accessibilityLabel("Codex 用量摘要")
    }
}

/// 单个 peek 指标列：标题在上，数值/进度条在下，垂直排列。
/// 每列等宽分配，避免长文本挤压其他列。
private struct PeekMetricColumn: View {
    let metric: PeekMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(metric.value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(metric.usesWarningTint ? .orange : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let progress = metric.progress {
                QuotaProgressBar(remaining: progress, height: 5)
            } else {
                Color.clear.frame(height: 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
