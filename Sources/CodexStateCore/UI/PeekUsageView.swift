import SwiftUI

struct PeekUsageView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(NotchLayoutPolicy.metrics(snapshot: snapshot).enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 5) {
                    Text(metric.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(.headline.monospacedDigit())
                    if let progress = metric.progress {
                        ProgressView(value: min(max(progress, 0), 1))
                            .tint(progress >= 0.9 ? .orange : .blue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        .foregroundStyle(.white)
        .background(.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityLabel("Codex 用量摘要")
    }
}
