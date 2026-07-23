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
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Capsule()
                        .fill(.blue)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: geometry.size.height * CGFloat(day.tokens.total) / CGFloat(maximum),
                            alignment: .bottom
                        )
                        .overlay {
                            if selectedIndex == index {
                                Capsule().stroke(.white.opacity(0.8), lineWidth: 1)
                            }
                        }
                        .accessibilityLabel("\(day.date.formatted(date: .abbreviated, time: .omitted))，\(day.tokens.total.formatted()) 令牌，\(Self.costText(for: day))")
                }
            }
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
        .frame(height: 56)
        .overlay(alignment: .topLeading) {
            if let selectedIndex, days.indices.contains(selectedIndex) {
                tooltip(for: days[selectedIndex])
            }
        }
    }

    private func tooltip(for day: DailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.date, format: .dateTime.month().day())
            Text("\(day.tokens.total.formatted()) 令牌")
            Text(Self.costText(for: day))
        }
        .font(.caption.monospacedDigit())
        .padding(6)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func costText(for day: DailyUsage) -> String {
        let omission = day.unknownPriceModels.isEmpty
            ? ""
            : "（未含 \(day.unknownPriceModels.count) 个未知模型）"
        guard let cost = day.estimatedCostUSD else { return "估算成本：—\(omission)" }

        return "估算成本：$\(cost)\(omission)"
    }
}
