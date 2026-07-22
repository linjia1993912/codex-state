import AppKit
import QuartzCore
import SwiftUI

@MainActor
public final class NotchPanelController: NSObject {
    public private(set) var presentation: NotchPresentation = .collapsed

    private let store: UsageStore
    private let panel: NSPanel
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    public init(store: UsageStore) {
        self.store = store
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size(for: .collapsed)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = makeHostingView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public static func size(for presentation: NotchPresentation) -> CGSize {
        switch presentation {
        case .collapsed: CGSize(width: 150, height: 30)
        case .peek: CGSize(width: 300, height: 80)
        case .expanded: CGSize(width: 368, height: 410)
        }
    }

    public func show() {
        reposition(size: Self.size(for: presentation), animated: false)
        panel.orderFrontRegardless()
    }

    public func toggleExpanded() {
        setPresentation(presentation == .expanded ? .collapsed : .expanded)
    }

    public func stop() {
        removeClickMonitors()
        panel.orderOut(nil)
    }

    private func setPresentation(_ value: NotchPresentation) {
        guard presentation != value else { return }
        presentation = value
        panel.contentView = makeHostingView()
        reposition(
            size: Self.size(for: value),
            animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        updateClickMonitors()
    }

    private func makeHostingView() -> NSHostingView<NotchRootView> {
        NSHostingView(rootView: NotchRootView(
            store: store,
            presentation: Binding(
                get: { [weak self] in self?.presentation ?? .collapsed },
                set: { [weak self] in self?.setPresentation($0) }
            )
        ))
    }

    private func reposition(size: CGSize, animated: Bool) {
        guard let screen = Self.preferredScreen() else { return }
        let frame = NSRect(origin: ScreenPlacement.panelOrigin(screenFrame: screen.frame, panelSize: size), size: size)
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    @objc private func screenParametersDidChange(_: Notification) {
        reposition(size: Self.size(for: presentation), animated: false)
    }

    private func updateClickMonitors() {
        removeClickMonitors()
        guard presentation == .expanded else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor in self?.collapseIfClickIsOutside() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.collapseIfClickIsOutside()
            return event
        }
    }

    private func collapseIfClickIsOutside() {
        guard presentation == .expanded, !panel.frame.contains(NSEvent.mouseLocation) else { return }
        setPresentation(.collapsed)
    }

    private func removeClickMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        globalClickMonitor = nil
        localClickMonitor = nil
    }
}
