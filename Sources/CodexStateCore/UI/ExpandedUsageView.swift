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
        return refreshedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 连接带不承载内容，避免文字和控件落入物理刘海遮挡区。
            Color.clear.frame(height: notchHeight)
            VStack(alignment: .leading, spacing: 14) {
                header
                quotas
                rangePicker
                totals
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
            .background(.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Codex 用量")
                .font(.headline)
                .fixedSize()
            Text(accountSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            if store.isRefreshing { ProgressView().controlSize(.small) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(2)
    }

    // 展示所有额度窗口（包括每周额度及其重置时间）
    @ViewBuilder
    private var quotas: some View {
        if !store.snapshot.quotaWindows.isEmpty {
            VStack(spacing: 8) {
                ForEach(store.snapshot.quotaWindows) { window in
                    VStack(spacing: 4) {
                        HStack {
                            Text(window.remainingTitle).lineLimit(1)
                            Spacer()
                            Text("\(window.remainingPercent, specifier: "%.0f")%")
                                .monospacedDigit()
                                .fixedSize()
                        }
                        .font(.caption)
                        QuotaProgressBar(remaining: window.remainingPercent / 100, height: 6)
                        if let resetsAt = window.resetsAt {
                            Text("重置：\(resetsAt, format: .dateTime.month().day().hour().minute())")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(2)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(UsageRange.allCases, id: \.self) { range in
                let isSelected = store.snapshot.selectedRange == range
                Button {
                    store.selectRange(range)
                } label: {
                    Text("\(range.rawValue) 天")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? .white.opacity(0.22) : .white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 22)
        .layoutPriority(2)
    }

    private var totals: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                metric(title: "Tokens", value: UsageFormat.tokens(totalTokens))
                metric(
                    title: "估算成本",
                    value: totalCost.map { UsageFormat.cost($0) } ?? "—"
                )
            }
            // 最后统计刷新时间
            HStack(spacing: 4) {
                Text("最后刷新")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(refreshedAtText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var models: some View {
        if !store.snapshot.topModels.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("常用模型")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                // 只展示前 3 个模型，不再追加"其他"聚合项。
                ForEach(Array(store.snapshot.topModels.prefix(3))) { model in
                    HStack {
                        Text(model.model)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Text(model.fraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .fixedSize()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(3)
        }
    }

    private func metric(title: String, value: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
