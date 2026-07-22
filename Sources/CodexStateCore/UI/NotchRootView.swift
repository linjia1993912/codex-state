import SwiftUI

@MainActor
public struct NotchRootView: View {
    @Bindable private var store: UsageStore
    @Binding private var presentation: NotchPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverTask: Task<Void, Never>?

    public init(store: UsageStore, presentation: Binding<NotchPresentation>) {
        self.store = store
        _presentation = presentation
    }

    public var body: some View {
        Group {
            switch presentation {
            case .collapsed:
                Color.black
                    .clipShape(Capsule())
                    .accessibilityLabel("Codex 用量")
            case .peek:
                PeekUsageView(snapshot: store.snapshot)
                    .contentShape(Rectangle())
                    .onTapGesture { setPresentation(.expanded) }
            case .expanded:
                ExpandedUsageView(store: store) {
                    setPresentation(.collapsed)
                }
            }
        }
        .frame(
            width: NotchPanelController.size(for: presentation).width,
            height: NotchPanelController.size(for: presentation).height
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: presentation)
        .onHover { hovering in
            switch (presentation, hovering) {
            case (.collapsed, true): schedule(.peek, after: .milliseconds(120))
            case (.peek, false): schedule(.collapsed, after: .milliseconds(250))
            default: hoverTask?.cancel()
            }
        }
        .onDisappear { hoverTask?.cancel() }
    }

    private func schedule(_ target: NotchPresentation, after delay: Duration) {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            setPresentation(target)
        }
    }

    private func setPresentation(_ value: NotchPresentation) {
        if reduceMotion {
            presentation = value
        } else {
            withAnimation(.easeInOut(duration: 0.18)) { presentation = value }
        }
    }
}
