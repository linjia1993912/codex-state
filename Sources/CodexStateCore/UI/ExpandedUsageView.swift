import SwiftUI

@MainActor
struct ExpandedUsageView: View {
    @Bindable var store: UsageStore
    let notchHeight: CGFloat

    private var totalTokens: Int64 {
        store.snapshot.dailyUsage.reduce(0) { $0 + $1.tokens.total }
    }

    private var totalCost: Decimal? {
        let knownCosts = store.snapshot.dailyUsage.compactMap(\.estimatedCostUSD)
        return knownCosts.isEmpty ? nil : knownCosts.reduce(.zero, +)
    }

    private var accountSubtitle: String {
        guard let account = store.snapshot.account else { return "未连接账号 · —" }
        return "\(account.maskedEmail ?? "未知账号") · \(account.plan ?? "未知套餐")"
    }

    private var refreshedAtText: String {
        guard let refreshedAt = store.snapshot.refreshedAt else { return "—" }
        return refreshedAt.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 连接带不承载内容，避免文字和控件落入物理刘海遮挡区。
            Color.clear.frame(height: notchHeight)
            VStack(alignment: .leading, spacing: 12) {
                header
                quotas
                usageOverview
                models
                if let warning = store.snapshot.visibleWarnings.first {
                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(4)
                        .accessibilityLabel("警告：\(warning.message)")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("Codex 用量")
                    .font(.headline)
                Spacer(minLength: 2)
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("已同步 · \(refreshedAtText)", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            Text(accountSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(2)
    }

    // 所有额度窗口放入同一主卡，既突出剩余额度，也不会因窗口类型变化而遗漏信息。
    @ViewBuilder
    private var quotas: some View {
        if !store.snapshot.quotaWindows.isEmpty {
            VStack(spacing: 8) {
                ForEach(store.snapshot.quotaWindows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.remainingTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            if let resetsAt = window.resetsAt {
                                Text("重置：\(resetsAt, format: .dateTime.month().day().hour().minute())")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(window.remainingPercent, specifier: "%.0f")%")
                                .font(.title3.monospacedDigit().weight(.bold))
                            Text("剩余")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        QuotaProgressBar(remaining: window.remainingPercent / 100, height: 5)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(2)
        }
    }

    private var usageOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本地用量")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                ForEach(UsageRange.allCases, id: \.self) { range in
                    let isSelected = store.snapshot.selectedRange == range
                    Button {
                        store.selectRange(range)
                    } label: {
                        Text("\(range.rawValue) 天")
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            // 深色刘海上的系统 secondary 对比度不足，未选中项保留可见的白色层级。
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(isSelected ? .white.opacity(0.14) : .clear)
                            )
                            // plain 样式不提供默认按钮底板，显式定义整块分段区域为命中范围。
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            totals
        }
        .layoutPriority(2)
    }

    private var totals: some View {
        HStack(spacing: 8) {
            metric(title: "Token 总量", value: UsageFormat.tokens(totalTokens))
            metric(title: "估算成本", value: totalCost.map { UsageFormat.cost($0) } ?? "—")
        }
    }

    private var models: some View {
        let displayedModels = Array(store.snapshot.topModels.prefix(3))

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("常用模型")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("前 3 项")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            // 固定预留三行，避免所选日期的模型数变化时让展开面板产生跳动。
            ForEach(0..<3, id: \.self) { index in
                if index < displayedModels.count {
                    modelShare(displayedModels[index])
                } else {
                    Color.clear
                        .frame(height: 20)
                        .accessibilityHidden(true)
                }
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(3)
    }

    private func modelShare(_ model: ModelShare) -> some View {
        HStack {
                Text(model.model)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text(model.fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .fixedSize()
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background {
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.10))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.blue.opacity(0.8))
                            .frame(width: max(0, proxy.size.width * min(max(model.fraction, 0), 1)))
                    }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
