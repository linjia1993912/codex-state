import SwiftUI

@MainActor
struct ExpandedUsageView: View {
    @Bindable var store: UsageStore
    let close: () -> Void

    private var totalTokens: Int64 {
        store.snapshot.dailyUsage.reduce(0) { $0 + $1.tokens.total }
    }

    private var totalCost: Decimal? {
        store.snapshot.dailyUsage.reduce(Decimal.zero as Decimal?) { total, day in
            guard let total, let cost = day.estimatedCostUSD else { return nil }
            return total + cost
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    account
                    quotas
                    rangePicker
                    totals
                    dailyBars
                    models
                    ForEach(Array(store.snapshot.visibleWarnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("警告：\(warning.message)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 22))
    }

    private var header: some View {
        HStack {
            Text("Codex 用量")
                .font(.headline)
            Spacer()
            if store.isRefreshing { ProgressView().controlSize(.small) }
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起")
        }
    }

    private var account: some View {
        let account = store.snapshot.account
        return HStack {
            Label(account.map { $0.maskedEmail ?? "未知账号" } ?? "未连接账号", systemImage: "person.crop.circle")
            Spacer()
            Text(account.map { $0.plan ?? "未知套餐" } ?? "—")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var quotas: some View {
        if !store.snapshot.quotaWindows.isEmpty {
            VStack(spacing: 8) {
                ForEach(store.snapshot.quotaWindows) { window in
                    VStack(spacing: 4) {
                        HStack {
                            Text(window.title)
                            Spacer()
                            Text("\(window.usedPercent, specifier: "%.0f")%")
                                .monospacedDigit()
                        }
                        ProgressView(value: min(max(window.usedPercent / 100, 0), 1))
                            .tint(window.usedPercent >= 90 ? .orange : .blue)
                        if let resetsAt = window.resetsAt {
                            Text("重置：\(resetsAt, format: .dateTime.month().day().hour().minute())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
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
    }

    private var totals: some View {
        HStack {
            metric(title: "Tokens", value: totalTokens.formatted())
            metric(title: "估算成本", value: totalCost.map { "$\($0)" } ?? "—")
        }
    }

    @ViewBuilder
    private var dailyBars: some View {
        let maximum = max(store.snapshot.dailyUsage.map(\.tokens.total).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text("每日用量").font(.caption).foregroundStyle(.secondary)
            ForEach(store.snapshot.dailyUsage) { day in
                HStack {
                    Text(day.date, format: .dateTime.month().day())
                        .frame(width: 44, alignment: .leading)
                    GeometryReader { geometry in
                        Capsule()
                            .fill(.blue)
                            .frame(width: geometry.size.width * Double(day.tokens.total) / Double(maximum))
                    }
                    .frame(height: 7)
                    Text(day.tokens.total.formatted())
                        .font(.caption.monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }
            if store.snapshot.dailyUsage.isEmpty {
                Text("暂无本地用量").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var models: some View {
        if !store.snapshot.topModels.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("常用模型").font(.caption).foregroundStyle(.secondary)
                ForEach(store.snapshot.topModels) { model in
                    HStack {
                        Text(model.model).lineLimit(1)
                        Spacer()
                        Text(model.fraction, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
