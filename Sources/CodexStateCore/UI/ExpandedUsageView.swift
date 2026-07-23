import SwiftUI

@MainActor
struct ExpandedUsageView: View {
    @Bindable var store: UsageStore
    let close: () -> Void

    private var totalTokens: Int64 {
        store.snapshot.dailyUsage.reduce(0) { $0 + $1.tokens.total }
    }

    private var totalCost: Decimal? {
        let knownCosts = store.snapshot.dailyUsage.compactMap(\.estimatedCostUSD)
        return knownCosts.isEmpty ? nil : knownCosts.reduce(.zero, +)
    }

    private var unknownPriceModelCount: Int {
        // 同一未知模型可能跨多天出现，范围提示按模型去重而不是累计出现次数。
        Set(store.snapshot.dailyUsage.flatMap(\.unknownPriceModels)).count
    }

    private var accountSubtitle: String {
        guard let account = store.snapshot.account else { return "未连接账号 · —" }
        return "\(account.maskedEmail ?? "未知账号") · \(account.plan ?? "未知套餐")"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 连接带不承载内容，避免文字和控件落入物理刘海遮挡区。
            Color.clear.frame(height: 32)
            VStack(alignment: .leading, spacing: 4) {
                header
                quotas
                rangePicker
                totals
                DailyTrendView(days: store.snapshot.dailyUsage)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                models
                if let warning = store.snapshot.visibleWarnings.first {
                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(4)
                        .accessibilityLabel("警告：\(warning.message)")
                }
            }
            .padding(16)
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
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起")
        }
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(2)
    }

    @ViewBuilder
    private var quotas: some View {
        if !store.snapshot.quotaWindows.isEmpty {
            VStack(spacing: 2) {
                ForEach(store.snapshot.quotaWindows) { window in
                    VStack(spacing: 1) {
                        HStack {
                            Text(window.remainingTitle).lineLimit(1)
                            Spacer()
                            Text("\(window.remainingPercent, specifier: "%.0f")%")
                                .monospacedDigit()
                                .fixedSize()
                        }
                        .font(.caption2)
                        ProgressView(value: window.remainingPercent / 100)
                            .progressViewStyle(.linear)
                            .frame(height: 5)
                            .tint(window.remainingPercent <= 10 ? .orange : .blue)
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
        Picker("统计范围", selection: Binding(
            get: { store.snapshot.selectedRange },
            set: { store.selectRange($0) }
        )) {
            ForEach(UsageRange.allCases, id: \.self) { range in
                Text("\(range.rawValue) 天").tag(range)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.mini)
        .frame(height: 20)
        .layoutPriority(2)
    }

    private var totals: some View {
        HStack(spacing: 8) {
            metric(title: "Tokens", value: totalTokens.formatted())
            metric(
                title: "估算成本",
                value: totalCost.map { "$\($0)" } ?? "—",
                subtitle: unknownPriceModelCount > 0 ? "未含 \(unknownPriceModelCount) 个未知模型" : nil
            )
        }
        .frame(height: 58)
    }

    @ViewBuilder
    private var models: some View {
        if !store.snapshot.topModels.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text("常用模型")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ForEach(store.snapshot.topModels) { model in
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
        VStack(alignment: .leading, spacing: 1) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
