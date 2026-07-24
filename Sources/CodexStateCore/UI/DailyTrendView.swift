import SwiftUI

enum DailyTrendSelection {
    static func index(for locationX: CGFloat, width: CGFloat, count: Int) -> Int? {
        guard width > 0, count > 0 else { return nil }

        // 将悬停横坐标按等宽柱分段，并把图表外的坐标稳定收敛到首尾柱。
        return min(max(Int((locationX / width * CGFloat(count)).rounded(.down)), 0), count - 1)
    }
}

struct DailyTrendView: View {
    let days: [DailyUsage]
    @State private var selectedIndex: Int?

    private var maximum: Int64 {
        max(days.map(\.tokens.total).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("每日趋势")
                .font(.caption)
                .foregroundStyle(.secondary)

            if days.isEmpty {
                Text("暂无本地用量")
                    .foregroundStyle(.secondary)
            } else {
                chart
            }
        }
    }

    private var chart: some View {
        GeometryReader { geometry in
            chartBars(geometry: geometry)
        }
        .frame(height: 56)
        .overlay(alignment: .topLeading) {
            if let selectedIndex, days.indices.contains(selectedIndex) {
                tooltip(for: days[selectedIndex])
            }
        }
    }

    private func chartBars(geometry: GeometryProxy) -> some View {
        // 固定柱宽上限，柱子多于可用宽度时自动收缩；少于时居中排列。
        let spacing: CGFloat = 3
        let count = max(days.count, 1)
        let availableWidth = geometry.size.width - CGFloat(max(days.count - 1, 0)) * spacing
        let barWidth = min(20.0, max(4.0, availableWidth / CGFloat(count)))

        return HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                barView(day: day, index: index, barWidth: barWidth, maxHeight: geometry.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                selectedIndex = DailyTrendSelection.index(
                    for: location.x,
                    width: geometry.size.width,
                    count: days.count
                )
            case .ended:
                selectedIndex = nil
            }
        }
    }

    private func barView(day: DailyUsage, index: Int, barWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let barHeight = maxHeight * CGFloat(day.tokens.total) / CGFloat(maximum)
        let label = "\(day.date.formatted(date: .abbreviated, time: .omitted))，\(UsageFormat.tokens(day.tokens.total)) 令牌，\(Self.costText(for: day))"

        return Capsule()
            .fill(.blue)
            .frame(width: barWidth)
            .frame(maxHeight: barHeight, alignment: .bottom)
            .overlay {
                if selectedIndex == index {
                    Capsule().stroke(.white.opacity(0.8), lineWidth: 1)
                }
            }
            .accessibilityLabel(label)
    }

    private func tooltip(for day: DailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.date, format: .dateTime.month().day())
            Text("\(UsageFormat.tokens(day.tokens.total)) 令牌")
            Text(Self.costText(for: day))
        }
        .font(.caption.monospacedDigit())
        .padding(6)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func costText(for day: DailyUsage) -> String {
        guard let cost = day.estimatedCostUSD else { return "估算成本：—" }
        return "估算成本：\(UsageFormat.cost(cost))"
    }
}
